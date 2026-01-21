# Terraform Learning Guide for MAIA Project

## Overview

This guide teaches Terraform by building the MAIA infrastructure step-by-step. Each phase builds on the previous one, introducing new concepts while creating real AWS resources.

## Learning Phases

| Phase | Topic | What You'll Build | Key Concepts |
|-------|-------|-------------------|--------------|
| 01 | [Basics & Setup](./01-BASICS-AND-SETUP.md) | Terraform installation & project structure | HCL syntax, providers, init |
| 02 | [State & Backend](./02-STATE-AND-BACKEND.md) | Remote state with S3 | State management, locking |
| 03 | [Variables & Outputs](./03-VARIABLES-AND-OUTPUTS.md) | Configuration system | Variables, locals, outputs, tfvars |
| 04 | [TR Compliance Module](./04-TR-COMPLIANCE-MODULE.md) | Tagging standards | Modules, reusable code |
| 05 | [Security Groups](./05-SECURITY-GROUPS.md) | Network security | Resources, references, dependencies |
| 06 | [Storage (S3 & ECR)](./06-STORAGE.md) | Buckets & container registry | Multiple resources, encryption |
| 07 | [Load Balancer](./07-LOAD-BALANCER.md) | ALB with listeners | Complex resources, conditionals |
| 08 | [ECS Cluster](./08-ECS-CLUSTER.md) | Container orchestration | IAM roles, policies |
| 09 | [RDS Database](./09-RDS-DATABASE.md) | PostgreSQL instance | Secrets, subnet groups |
| 10 | [CI/CD Integration](./10-CICD-INTEGRATION.md) | GitHub Actions workflow | Automation, deployment |

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud                                       │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                          VPC (Existing)                                │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                    Public Subnets                                │  │  │
│  │  │   ┌─────────────────────────────────────────────────────────┐   │  │  │
│  │  │   │            Application Load Balancer                     │   │  │  │
│  │  │   │         (HTTP:80 / HTTPS:443)                           │   │  │  │
│  │  │   └───────────────────────┬─────────────────────────────────┘   │  │  │
│  │  └───────────────────────────┼─────────────────────────────────────┘  │  │
│  │                              │                                         │  │
│  │  ┌───────────────────────────┼─────────────────────────────────────┐  │  │
│  │  │                    Private Subnets                              │  │  │
│  │  │         ┌─────────────────┴─────────────────┐                   │  │  │
│  │  │         │                                   │                   │  │  │
│  │  │   ┌─────┴─────┐                     ┌──────┴──────┐            │  │  │
│  │  │   │  Frontend │                     │   Backend   │            │  │  │
│  │  │   │   ECS     │                     │    ECS      │            │  │  │
│  │  │   │  Service  │                     │   Service   │            │  │  │
│  │  │   └───────────┘                     └──────┬──────┘            │  │  │
│  │  │                                            │                    │  │  │
│  │  │                                    ┌───────┴───────┐            │  │  │
│  │  │                                    │      RDS      │            │  │  │
│  │  │                                    │   PostgreSQL  │            │  │  │
│  │  │                                    └───────────────┘            │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                       │
│  │     ECR      │  │      S3      │  │   Secrets    │                       │
│  │ Repositories │  │   Buckets    │  │   Manager    │                       │
│  └──────────────┘  └──────────────┘  └──────────────┘                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- AWS CLI installed and configured
- Terraform >= 1.0.0 installed
- Access to TR AWS account (292899125550)
- Basic understanding of AWS services
- Git for version control

## Directory Structure (Final)

```
infra/terraform/
├── main.tf                    # Root module - calls other modules
├── provider.tf                # AWS provider & backend configuration
├── variables.tf               # Input variables
├── outputs.tf                 # Output values
├── terraform.tfvars           # Variable values (gitignored)
├── terraform.tfvars.example   # Example variable values
│
├── modules/
│   ├── tr_compliance/         # TR tagging standards (already exists)
│   │   ├── variables.tf
│   │   ├── locals.tf
│   │   └── outputs.tf
│   │
│   ├── security_groups/       # Network security
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── storage/               # S3 & ECR
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── alb/                   # Application Load Balancer
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── ecs/                   # ECS Cluster & IAM
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── rds/                   # PostgreSQL database
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
```

## Comparison: Pulumi vs Terraform

| Aspect | Pulumi (Current) | Terraform (Learning) |
|--------|------------------|---------------------|
| Language | Python | HCL (HashiCorp Configuration Language) |
| State | S3 + Passphrase | S3 + DynamoDB (locking) |
| Config | `pulumi config set` | `terraform.tfvars` or `-var` |
| Apply | `pulumi up` | `terraform apply` |
| Preview | `pulumi preview` | `terraform plan` |
| Destroy | `pulumi destroy` | `terraform destroy` |

## Quick Reference Commands

```bash
# Initialize (download providers)
terraform init

# Format code
terraform fmt

# Validate configuration
terraform validate

# Preview changes
terraform plan

# Apply changes
terraform apply

# Destroy resources
terraform destroy

# Show current state
terraform state list

# Import existing resource
terraform import aws_instance.example i-1234567890abcdef0
```

## Getting Started

Start with [Phase 01: Basics & Setup](./01-BASICS-AND-SETUP.md) to begin your Terraform learning journey.
