# Phase 08: Full Deployment & CI/CD

Complete deployment guide and CI/CD setup.

## Complete main.tf

Here's the full `infra/terraform/main.tf`:

```hcl
# =============================================================================
# MAIA Infrastructure
# =============================================================================

# -----------------------------------------------------------------------------
# TR Compliance Tags
# -----------------------------------------------------------------------------

module "tr_compliance" {
  source = "./modules/tr_compliance"

  environment_type = var.environment
  resource_owner   = var.resource_owner
  resource_name    = "maia-${lower(var.environment)}"
  service_name     = "maia"
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------

module "security_groups" {
  source = "./modules/security_groups"

  vpc_id        = var.vpc_id
  environment   = var.environment
  tags          = module.tr_compliance.all_tags
  enable_https  = var.alb_certificate_arn != null
  create_rds_sg = var.create_rds
}

# -----------------------------------------------------------------------------
# Storage (S3 + ECR)
# -----------------------------------------------------------------------------

module "storage" {
  source = "./modules/storage"

  environment   = var.environment
  tags          = module.tr_compliance.all_tags
  force_destroy = var.environment != "PROD"
}

# -----------------------------------------------------------------------------
# Application Load Balancer
# -----------------------------------------------------------------------------

module "alb" {
  source = "./modules/alb"

  environment       = var.environment
  vpc_id            = var.vpc_id
  public_subnet_ids = var.public_subnet_ids
  security_group_id = module.security_groups.alb_sg_id
  tags              = module.tr_compliance.all_tags
  certificate_arn   = var.alb_certificate_arn
}

# -----------------------------------------------------------------------------
# ECS Cluster
# -----------------------------------------------------------------------------

module "ecs" {
  source = "./modules/ecs"

  environment        = var.environment
  tags               = module.tr_compliance.all_tags
  uploads_bucket_arn = module.storage.uploads_bucket_arn
  log_retention_days = var.environment == "PROD" ? 90 : 30
}

# -----------------------------------------------------------------------------
# Backend Service
# -----------------------------------------------------------------------------

module "backend_service" {
  source = "./modules/backend_service"

  environment             = var.environment
  tags                    = module.tr_compliance.all_tags
  cluster_arn             = module.ecs.cluster_arn
  task_execution_role_arn = module.ecs.task_execution_role_arn
  task_role_arn           = module.ecs.task_role_arn
  vpc_id                  = var.vpc_id
  private_subnet_ids      = var.private_subnet_ids
  security_group_id       = module.security_groups.backend_sg_id
  target_group_arn        = module.alb.backend_target_group_arn
  image_url               = module.storage.backend_repository_url
  image_tag               = var.backend_image_tag
  log_group               = module.ecs.backend_log_group
  log_region              = module.ecs.log_region

  environment_variables = {
    ENVIRONMENT = var.environment
    PORT        = "8000"
  }
}

# -----------------------------------------------------------------------------
# Frontend Service
# -----------------------------------------------------------------------------

module "frontend_service" {
  source = "./modules/frontend_service"

  environment             = var.environment
  tags                    = module.tr_compliance.all_tags
  cluster_arn             = module.ecs.cluster_arn
  task_execution_role_arn = module.ecs.task_execution_role_arn
  task_role_arn           = module.ecs.task_role_arn
  vpc_id                  = var.vpc_id
  private_subnet_ids      = var.private_subnet_ids
  security_group_id       = module.security_groups.frontend_sg_id
  target_group_arn        = module.alb.frontend_target_group_arn
  image_url               = module.storage.frontend_repository_url
  image_tag               = var.frontend_image_tag
  log_group               = module.ecs.frontend_log_group
  log_region              = module.ecs.log_region

  environment_variables = {
    REACT_APP_API_URL = "/api"
  }
}
```

## Complete outputs.tf

```hcl
# =============================================================================
# Outputs
# =============================================================================

output "environment" {
  value = var.environment
}

# ALB
output "alb_dns_name" {
  value = module.alb.dns_name
}

output "application_url" {
  value = "http://${module.alb.dns_name}"
}

# ECR
output "backend_repository_url" {
  value = module.storage.backend_repository_url
}

output "frontend_repository_url" {
  value = module.storage.frontend_repository_url
}

# ECS
output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

# S3
output "uploads_bucket_name" {
  value = module.storage.uploads_bucket_name
}
```

## Deploy Commands

```bash
cd infra/terraform

# 1. Login and export credentials
cloud-tool login
export AWS_PROFILE=tr-acoe-aicoe-preprod
export AWS_DEFAULT_REGION=us-east-1

# 2. Get VPC config from SSM
export TF_VAR_vpc_id=$(aws ssm get-parameter --name "/a205257/cicd/tr-vpc-1-id" --query "Parameter.Value" --output text)
export TF_VAR_public_subnet_ids=$(aws ssm get-parameter --name "/a205257/cicd/tr-vpc-1-public-subnets" --query "Parameter.Value" --output text | sed 's/, /","/g' | sed 's/^/["/' | sed 's/$/"]/')
export TF_VAR_private_subnet_ids=$(aws ssm get-parameter --name "/a205257/cicd/tr-vpc-1-private-subnets" --query "Parameter.Value" --output text | sed 's/, /","/g' | sed 's/^/["/' | sed 's/$/"]/')

# 3. Initialize
terraform init

# 4. Plan
terraform plan

# 5. Apply
terraform apply

# 6. Build and push images
./script/build-and-push.sh

# 7. Update image tags and redeploy
terraform apply -var="backend_image_tag=$(git rev-parse --short HEAD)"
```

## GitHub Actions Workflow

Create `.github/workflows/terraform.yml`:

```yaml
name: Terraform Deploy

on:
  push:
    branches: [main]
    paths: ['infra/terraform/**']
  workflow_dispatch:
    inputs:
      action:
        type: choice
        options: [plan, apply, destroy]
        default: plan

env:
  AWS_REGION: us-east-1
  TF_DIR: infra/terraform

jobs:
  terraform:
    runs-on: codebuild-a209309-MAIA-Runner-${{ github.run_id }}
    
    steps:
      - uses: actions/checkout@v4
      
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.6.0
      
      - name: Get VPC Config
        id: vpc
        run: |
          echo "TF_VAR_vpc_id=$(aws ssm get-parameter --name '/a205257/cicd/tr-vpc-1-id' --query 'Parameter.Value' --output text)" >> $GITHUB_ENV
          
          PRIVATE=$(aws ssm get-parameter --name '/a205257/cicd/tr-vpc-1-private-subnets' --query 'Parameter.Value' --output text)
          echo "TF_VAR_private_subnet_ids=$(echo $PRIVATE | sed 's/, /\",\"/g' | sed 's/^/[\"/' | sed 's/$/\"]/')" >> $GITHUB_ENV
          
          PUBLIC=$(aws ssm get-parameter --name '/a205257/cicd/tr-vpc-1-public-subnets' --query 'Parameter.Value' --output text)
          echo "TF_VAR_public_subnet_ids=$(echo $PUBLIC | sed 's/, /\",\"/g' | sed 's/^/[\"/' | sed 's/$/\"]/')" >> $GITHUB_ENV
      
      - name: Terraform Init
        working-directory: ${{ env.TF_DIR }}
        run: terraform init
      
      - name: Terraform Plan
        working-directory: ${{ env.TF_DIR }}
        run: terraform plan -out=tfplan
      
      - name: Terraform Apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        working-directory: ${{ env.TF_DIR }}
        run: terraform apply -auto-approve tfplan
```

## Useful Commands

```bash
# View state
terraform state list

# Show specific resource
terraform state show module.alb.aws_lb.main

# Refresh state
terraform refresh

# Destroy specific module
terraform destroy -target=module.backend_service

# Import existing resource
terraform import module.storage.aws_s3_bucket.uploads existing-bucket-name

# Format code
terraform fmt -recursive

# Validate
terraform validate
```

## Comparison: Pulumi vs Terraform Workflow

| Step | Pulumi | Terraform |
|------|--------|-----------|
| Login | `pulumi login s3://...` | `terraform init` (backend in provider.tf) |
| Config | `pulumi config set` | `TF_VAR_*` or tfvars |
| Preview | `pulumi preview` | `terraform plan` |
| Deploy | `pulumi up` | `terraform apply` |
| Destroy | `pulumi destroy` | `terraform destroy` |

## Next Steps

1. **Add RDS module** - If you need database
2. **Add CloudFront** - For CDN
3. **Add auto-scaling** - For ECS services
4. **Set up multiple environments** - Use workspaces or separate state files

---

**Congratulations!** You've deployed MAIA using Terraform! 🎉
