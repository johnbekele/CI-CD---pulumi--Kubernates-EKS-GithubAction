# Phase 01: Setup Variables

Configure the root module variables for the MAIA deployment.

## Step 1: Create variables.tf

```bash
# We'll create this file
touch infra/terraform/variables.tf
```

Create `infra/terraform/variables.tf`:

```hcl
# =============================================================================
# MAIA Infrastructure Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment (DEV, QA, STAGING, PROD)"
  type        = string
  default     = "DEV"
}

variable "resource_owner" {
  description = "TR resource owner email"
  type        = string
}

# -----------------------------------------------------------------------------
# Network (from SSM at runtime)
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS"
  type        = list(string)
}

# -----------------------------------------------------------------------------
# Feature Flags (match your Pulumi config)
# -----------------------------------------------------------------------------

variable "create_rds" {
  description = "Create RDS PostgreSQL"
  type        = bool
  default     = false
}

variable "create_redis" {
  description = "Create ElastiCache Redis"
  type        = bool
  default     = false
}

variable "create_cloudfront" {
  description = "Create CloudFront distribution"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Container Configuration
# -----------------------------------------------------------------------------

variable "backend_image_tag" {
  description = "Backend container image tag"
  type        = string
  default     = "latest"
}

variable "frontend_image_tag" {
  description = "Frontend container image tag"
  type        = string
  default     = "latest"
}

# -----------------------------------------------------------------------------
# Optional: ALB Certificate
# -----------------------------------------------------------------------------

variable "alb_certificate_arn" {
  description = "ACM certificate ARN for HTTPS"
  type        = string
  default     = null
}
```

## Step 2: Create terraform.tfvars

Create `infra/terraform/terraform.tfvars`:

```hcl
# =============================================================================
# MAIA Terraform Variables
# =============================================================================

region         = "us-east-1"
environment    = "DEV"
resource_owner = "yohans.bekele@thomsonreuters.com"

# Feature flags
create_rds        = false
create_redis      = false
create_cloudfront = false

# Container tags (updated by CI/CD)
backend_image_tag  = "latest"
frontend_image_tag = "latest"

# Network values - set at runtime via TF_VAR_* environment variables
# vpc_id             = "vpc-xxx"
# public_subnet_ids  = ["subnet-1", "subnet-2"]
# private_subnet_ids = ["subnet-3", "subnet-4"]
```

## Step 3: Create main.tf Skeleton

Create `infra/terraform/main.tf`:

```hcl
# =============================================================================
# MAIA Infrastructure - Main
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

# module "security_groups" {
#   source = "./modules/security_groups"
#   ... (Phase 02)
# }

# -----------------------------------------------------------------------------
# Storage (S3 + ECR)
# -----------------------------------------------------------------------------

# module "storage" {
#   source = "./modules/storage"
#   ... (Phase 03)
# }

# -----------------------------------------------------------------------------
# Application Load Balancer
# -----------------------------------------------------------------------------

# module "alb" {
#   source = "./modules/alb"
#   ... (Phase 04)
# }

# -----------------------------------------------------------------------------
# ECS Cluster
# -----------------------------------------------------------------------------

# module "ecs" {
#   source = "./modules/ecs"
#   ... (Phase 05)
# }
```

## Step 4: Update outputs.tf

Create `infra/terraform/outputs.tf`:

```hcl
# =============================================================================
# MAIA Infrastructure - Outputs
# =============================================================================

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}

# Uncomment as modules are added:

# output "alb_dns_name" {
#   value = module.alb.dns_name
# }

# output "backend_repository_url" {
#   value = module.storage.backend_repository_url
# }

# output "frontend_repository_url" {
#   value = module.storage.frontend_repository_url
# }
```

## Step 5: Test Configuration

```bash
cd infra/terraform

# Set network variables (get from SSM or hardcode for testing)
export TF_VAR_vpc_id="vpc-0abc123"  # Replace with actual
export TF_VAR_public_subnet_ids='["subnet-pub1","subnet-pub2"]'
export TF_VAR_private_subnet_ids='["subnet-priv1","subnet-priv2"]'

# Or get from SSM (like Pulumi workflow)
export TF_VAR_vpc_id=$(aws ssm get-parameter --name "/a205257/cicd/tr-vpc-1-id" --query "Parameter.Value" --output text)

# Initialize and validate
terraform init
terraform validate
terraform plan
```

## Equivalent Pulumi Config

Your Pulumi workflow does:
```bash
pulumi config set maia-deployment:environment DEV
pulumi config set maia-deployment:vpcId "$VPC_ID"
```

In Terraform, this becomes:
```bash
# In terraform.tfvars
environment = "DEV"

# Or via environment variables
export TF_VAR_vpc_id="$VPC_ID"
```

---

**Next:** [Phase 02: Security Groups](./02-SECURITY-GROUPS.md)
