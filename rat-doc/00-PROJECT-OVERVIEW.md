# MAIA Terraform Deployment Guide

A hands-on guide to deploying the MAIA application infrastructure using Terraform.

## What We're Building

The same infrastructure you have in Pulumi, but in Terraform:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              MAIA Infrastructure                             │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Security Groups (ALB, Backend ECS, Frontend ECS, RDS)              │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                      │                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Storage: S3 (uploads, logs) + ECR (backend, frontend)              │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                      │                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  ALB → Target Groups → ECS Services (Fargate)                       │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                      │                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Optional: RDS PostgreSQL, ElastiCache Redis, CloudFront            │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
infra/terraform/
├── main.tf                 # Root module - orchestrates everything
├── provider.tf             # AWS provider + S3 backend (done ✓)
├── variables.tf            # Input variables
├── outputs.tf              # Output values
├── terraform.tfvars        # Variable values
│
├── modules/
│   ├── tr_compliance/      # TR tagging (exists ✓)
│   ├── security_groups/    # Network security
│   ├── storage/            # S3 + ECR
│   ├── alb/                # Load balancer
│   ├── ecs/                # ECS cluster + IAM
│   ├── backend_service/    # Backend ECS service
│   └── frontend_service/   # Frontend ECS service
│
└── script/
    ├── create-tf-backend.py  # Backend setup (done ✓)
    └── aws-export.sh         # AWS credential helper
```

## Deployment Phases

| Phase | Module | Description |
|-------|--------|-------------|
| [01](./01-SETUP-VARIABLES.md) | Root | Variables and runtime config |
| [02](./02-SECURITY-GROUPS.md) | security_groups | Network security rules |
| [03](./03-STORAGE.md) | storage | S3 buckets + ECR repos |
| [04](./04-ALB.md) | alb | Load balancer + listeners |
| [05](./05-ECS-CLUSTER.md) | ecs | ECS cluster + IAM roles |
| [06](./06-BACKEND-SERVICE.md) | backend_service | Backend ECS service |
| [07](./07-FRONTEND-SERVICE.md) | frontend_service | Frontend ECS service |
| [08](./08-DEPLOY.md) | - | Full deployment + CI/CD |

## Prerequisites

- [x] Terraform installed
- [x] AWS credentials configured (cloud-tool)
- [x] S3 backend created (`a209671-maia-terraform-state`)
- [x] TR compliance module exists
- [ ] VPC/Subnets (we'll get from SSM)

## Quick Commands

```bash
# Export AWS credentials after cloud-tool login
export AWS_PROFILE=tr-acoe-aicoe-preprod
export AWS_DEFAULT_REGION=us-east-1

# Initialize
terraform init

# Plan
terraform plan

# Apply
terraform apply

# Destroy
terraform destroy
```

## Pulumi → Terraform Reference

| Pulumi | Terraform |
|--------|-----------|
| `pulumi up` | `terraform apply` |
| `pulumi preview` | `terraform plan` |
| `pulumi destroy` | `terraform destroy` |
| `pulumi config set x y` | `TF_VAR_x=y` or `-var="x=y"` |
| `Pulumi.yaml` stack config | `terraform.tfvars` |
| Python class | Module |
| `pulumi.export()` | `output` block |

## Start Here

Go to [Phase 01: Setup Variables](./01-SETUP-VARIABLES.md)
