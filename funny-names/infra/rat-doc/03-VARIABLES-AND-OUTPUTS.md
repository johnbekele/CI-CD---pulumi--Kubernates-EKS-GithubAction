# Phase 03: Variables, Locals & Outputs

## Learning Objectives

- Master Terraform variable types and validation
- Use locals for computed values
- Define outputs for sharing information
- Work with tfvars files and environment variables
- Understand variable precedence

---

## 1. Variable Types Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Terraform Configuration                             │
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                   │
│  │  Variables   │───▶│    Locals    │───▶│  Resources   │                   │
│  │   (inputs)   │    │  (computed)  │    │   (infra)    │                   │
│  └──────────────┘    └──────────────┘    └──────────────┘                   │
│         │                                       │                            │
│         │                                       ▼                            │
│         │                               ┌──────────────┐                    │
│         │                               │   Outputs    │                    │
│         │                               │  (exports)   │                    │
│         │                               └──────────────┘                    │
│         │                                       │                            │
│  ┌──────┴──────────────────────────────────────┴─────────────────────────┐  │
│  │                     Ways to Set Variables                              │  │
│  │  • terraform.tfvars      (auto-loaded)                                │  │
│  │  • *.auto.tfvars         (auto-loaded)                                │  │
│  │  • -var="name=value"     (command line)                               │  │
│  │  • -var-file="file.tfvars"                                            │  │
│  │  • TF_VAR_name           (environment variable)                       │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Defining Variables

### Basic Variable

```hcl
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "DEV"
}
```

### Variable with Validation

```hcl
variable "environment" {
  description = "Environment name (DEV, QA, STAGING, PROD)"
  type        = string
  default     = "DEV"
  
  validation {
    condition     = contains(["DEV", "QA", "STAGING", "PROD"], var.environment)
    error_message = "Environment must be one of: DEV, QA, STAGING, PROD"
  }
}

variable "resource_owner" {
  description = "Email of the resource owner (TR requirement)"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.resource_owner))
    error_message = "Resource owner must be a valid email address"
  }
}
```

### Variable Types

```hcl
# String
variable "region" {
  type    = string
  default = "us-east-1"
}

# Number
variable "instance_count" {
  type    = number
  default = 2
}

# Boolean
variable "enable_deletion_protection" {
  type    = bool
  default = false
}

# List of strings
variable "public_subnet_ids" {
  type = list(string)
}

# List of numbers
variable "allowed_ports" {
  type    = list(number)
  default = [80, 443]
}

# Map (key-value pairs)
variable "additional_tags" {
  type    = map(string)
  default = {}
}

# Object (structured data)
variable "rds_config" {
  type = object({
    instance_class    = string
    allocated_storage = number
    multi_az          = bool
  })
  default = {
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    multi_az          = false
  }
}

# Tuple (fixed-length, typed list)
variable "cidr_blocks" {
  type = tuple([string, string])
}
```

### Sensitive Variables

```hcl
variable "database_password" {
  description = "Database master password"
  type        = string
  sensitive   = true  # Won't show in logs or plan output
}
```

---

## 3. Setting Variable Values

### Method 1: terraform.tfvars (Auto-loaded)

```hcl
# terraform.tfvars
region         = "us-east-1"
environment    = "DEV"
resource_owner = "yohans.bekele@thomsonreuters.com"

# Lists
public_subnet_ids  = ["subnet-abc123", "subnet-def456"]
private_subnet_ids = ["subnet-111222", "subnet-333444"]

# Maps
additional_tags = {
  "Team"    = "Platform"
  "Project" = "MAIA"
}
```

### Method 2: *.auto.tfvars (Auto-loaded)

```hcl
# dev.auto.tfvars - automatically loaded
environment = "DEV"
```

### Method 3: Command Line -var

```bash
terraform apply -var="environment=DEV" -var="region=us-east-1"
```

### Method 4: Environment Variables (TF_VAR_*)

```bash
# Set in shell
export TF_VAR_vpc_id="vpc-12345"
export TF_VAR_environment="DEV"

# Or in GitHub Actions workflow
- name: Set Terraform Variables
  run: |
    echo "TF_VAR_vpc_id=${{ steps.vpc.outputs.VPC_ID }}" >> $GITHUB_ENV
    echo "TF_VAR_environment=DEV" >> $GITHUB_ENV
```

### Method 5: -var-file

```bash
terraform apply -var-file="environments/dev.tfvars"
```

### Variable Precedence (Lowest to Highest)

1. Default value in variable definition
2. Environment variables (TF_VAR_*)
3. terraform.tfvars
4. *.auto.tfvars (alphabetical order)
5. -var-file (in order specified)
6. -var (in order specified)

---

## 4. Using Locals

Locals are computed values - think of them as helper variables.

### Basic Locals

```hcl
locals {
  # Simple value
  project_name = "maia"
  
  # Computed from variables
  name_prefix = "${local.project_name}-${lower(var.environment)}"
  
  # Conditional
  is_production = var.environment == "PROD"
  
  # Complex computation
  common_tags = {
    "tr:application-asset-insight-id" = "209191"
    "tr:resource-owner"               = var.resource_owner
    "tr:environment-type"             = local.tr_environment_type
    "ManagedBy"                       = "Terraform"
  }
}
```

### Environment Mapping (From Your TR Compliance Module)

```hcl
locals {
  # Map internal env to TR standard
  tr_environment_type = {
    "DEV"     = "DEVELOPMENT"
    "QA"      = "QUALITY ASSURANCE"
    "STAGING" = "PRE-PRODUCTION"
    "PROD"    = "PRODUCTION"
  }[var.environment]
}
```

### Using Locals in Resources

```hcl
resource "aws_s3_bucket" "uploads" {
  bucket = "${local.name_prefix}-uploads"
  
  tags = merge(local.common_tags, {
    "Name"    = "${local.name_prefix}-uploads"
    "Purpose" = "File uploads"
  })
}
```

---

## 5. Outputs

Outputs export values for:
- Display after `terraform apply`
- Use by other Terraform configurations
- CI/CD pipelines

### Basic Outputs

```hcl
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}
```

### Conditional Outputs

```hcl
output "rds_endpoint" {
  description = "RDS endpoint (if created)"
  value       = var.create_rds ? aws_db_instance.main[0].endpoint : null
}
```

### Sensitive Outputs

```hcl
output "database_password" {
  description = "Database password"
  value       = aws_secretsmanager_secret_version.db_password.secret_string
  sensitive   = true  # Won't show in terminal, but stored in state
}
```

### Complex Outputs

```hcl
output "infrastructure" {
  description = "All infrastructure details"
  value = {
    alb = {
      dns_name = aws_lb.main.dns_name
      arn      = aws_lb.main.arn
    }
    ecs = {
      cluster_name = aws_ecs_cluster.main.name
      cluster_arn  = aws_ecs_cluster.main.arn
    }
    buckets = {
      uploads = aws_s3_bucket.uploads.id
      logs    = aws_s3_bucket.logs.id
    }
  }
}
```

---

## 6. Practical Example: MAIA Variables File

Create `infra/terraform/variables.tf`:

```hcl
# ============================================================================
# MAIA Infrastructure - Variables
# ============================================================================

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment type (DEV, QA, STAGING, PROD)"
  type        = string
  default     = "DEV"
  
  validation {
    condition     = contains(["DEV", "QA", "STAGING", "PROD"], var.environment)
    error_message = "Environment must be one of: DEV, QA, STAGING, PROD"
  }
}

variable "resource_owner" {
  description = "Email of the resource owner (TR requirement)"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.resource_owner))
    error_message = "Resource owner must be a valid email address"
  }
}

# -----------------------------------------------------------------------------
# Network Configuration (Set at Runtime)
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID where resources will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
  
  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "At least 2 public subnets required for ALB"
  }
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS services"
  type        = list(string)
  
  validation {
    condition     = length(var.private_subnet_ids) >= 1
    error_message = "At least 1 private subnet required"
  }
}

# -----------------------------------------------------------------------------
# Feature Flags
# -----------------------------------------------------------------------------

variable "create_rds" {
  description = "Create RDS PostgreSQL instance"
  type        = bool
  default     = false
}

variable "create_redis" {
  description = "Create ElastiCache Redis cluster"
  type        = bool
  default     = false
}

variable "create_cloudfront" {
  description = "Create CloudFront distribution"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# RDS Configuration (if create_rds = true)
# -----------------------------------------------------------------------------

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "RDS storage in GB"
  type        = number
  default     = 20
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ for RDS"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# ALB Configuration
# -----------------------------------------------------------------------------

variable "alb_acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener (optional)"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Additional Tags
# -----------------------------------------------------------------------------

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
```

---

## 7. Practical Example: MAIA Outputs File

Create `infra/terraform/outputs.tf`:

```hcl
# ============================================================================
# MAIA Infrastructure - Outputs
# ============================================================================

# -----------------------------------------------------------------------------
# Load Balancer
# -----------------------------------------------------------------------------

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.alb.arn
}

output "alb_zone_id" {
  description = "Zone ID of the ALB (for Route53)"
  value       = module.alb.zone_id
}

# -----------------------------------------------------------------------------
# ECS
# -----------------------------------------------------------------------------

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ecs.cluster_arn
}

# -----------------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------------

output "uploads_bucket_name" {
  description = "Name of the uploads S3 bucket"
  value       = module.storage.uploads_bucket_name
}

output "backend_repository_url" {
  description = "ECR repository URL for backend"
  value       = module.storage.backend_repository_url
}

output "frontend_repository_url" {
  description = "ECR repository URL for frontend"
  value       = module.storage.frontend_repository_url
}

# -----------------------------------------------------------------------------
# Database (Conditional)
# -----------------------------------------------------------------------------

output "rds_endpoint" {
  description = "RDS endpoint (if created)"
  value       = var.create_rds ? module.rds[0].endpoint : null
}

output "rds_secret_arn" {
  description = "ARN of the RDS credentials secret (if created)"
  value       = var.create_rds ? module.rds[0].secret_arn : null
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Connection URLs for CI/CD
# -----------------------------------------------------------------------------

output "application_url" {
  description = "URL to access the application"
  value       = "http://${module.alb.dns_name}"
}
```

---

## 8. Runtime Variables in CI/CD

### GitHub Actions Example (Similar to Your Pulumi Workflow)

```yaml
- name: Get VPC Configuration
  id: vpc-config
  run: |
    VPC_ID=$(aws ssm get-parameter --name "/a205257/cicd/tr-vpc-1-id" --query "Parameter.Value" --output text)
    echo "TF_VAR_vpc_id=$VPC_ID" >> $GITHUB_ENV
    
    # For lists, create JSON array
    PRIVATE_SUBNETS=$(aws ssm get-parameter --name "/a205257/cicd/tr-vpc-1-private-subnets" --query "Parameter.Value" --output text)
    # Convert "subnet-1, subnet-2" to '["subnet-1","subnet-2"]'
    PRIVATE_SUBNETS_JSON=$(echo "$PRIVATE_SUBNETS" | sed 's/, /","/g' | sed 's/^/["/' | sed 's/$/"]/')
    echo "TF_VAR_private_subnet_ids=$PRIVATE_SUBNETS_JSON" >> $GITHUB_ENV

- name: Terraform Apply
  run: |
    cd infra/terraform
    terraform init
    terraform apply -auto-approve
```

---

## 9. Key Takeaways

1. **Variables** = Inputs to your configuration (like function parameters)
2. **Locals** = Computed/derived values (like local variables in a function)
3. **Outputs** = Exports from your configuration (like return values)
4. **Use validation** = Catch errors early with variable validation
5. **Multiple ways to set variables** = tfvars, CLI, env vars, files
6. **Sensitive** = Mark secrets to prevent accidental exposure

---

## Next Steps

Continue to [Phase 04: TR Compliance Module](./04-TR-COMPLIANCE-MODULE.md) to learn about creating reusable modules for Thomson Reuters compliance.
