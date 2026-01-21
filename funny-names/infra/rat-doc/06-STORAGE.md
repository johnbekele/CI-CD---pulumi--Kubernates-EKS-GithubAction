# Phase 06: Storage (S3 & ECR)

## Learning Objectives

- Create S3 buckets with encryption and versioning
- Configure ECR repositories for container images
- Understand S3 bucket policies and access controls
- Use Terraform `for_each` for multiple similar resources

---

## 1. Storage Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          MAIA Storage Resources                              │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         S3 Buckets                                   │    │
│  │                                                                      │    │
│  │  ┌─────────────────────┐    ┌─────────────────────┐                 │    │
│  │  │   Uploads Bucket    │    │    Logs Bucket      │                 │    │
│  │  │                     │    │                     │                 │    │
│  │  │  • Versioning: ON   │    │  • Versioning: OFF  │                 │    │
│  │  │  • Encryption: AES  │    │  • Encryption: AES  │                 │    │
│  │  │  • Lifecycle: 90d   │    │  • Lifecycle: 30d   │                 │    │
│  │  └─────────────────────┘    └─────────────────────┘                 │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                       ECR Repositories                               │    │
│  │                                                                      │    │
│  │  ┌─────────────────────┐    ┌─────────────────────┐                 │    │
│  │  │   Backend Repo      │    │   Frontend Repo     │                 │    │
│  │  │                     │    │                     │                 │    │
│  │  │  • Scan on push     │    │  • Scan on push     │                 │    │
│  │  │  • Mutable tags     │    │  • Mutable tags     │                 │    │
│  │  │  • Force delete     │    │  • Force delete     │                 │    │
│  │  └─────────────────────┘    └─────────────────────┘                 │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Create Storage Module

### Directory Structure

```bash
mkdir -p infra/terraform/modules/storage
touch infra/terraform/modules/storage/{variables,main,outputs}.tf
```

### modules/storage/variables.tf

```hcl
# ============================================================================
# Storage Module - Variables
# ============================================================================

variable "environment" {
  description = "Environment name (DEV, QA, STAGING, PROD)"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "maia"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# S3 Configuration
# -----------------------------------------------------------------------------

variable "enable_versioning" {
  description = "Enable versioning on uploads bucket"
  type        = bool
  default     = true
}

variable "uploads_lifecycle_days" {
  description = "Days before uploads expire (0 to disable)"
  type        = number
  default     = 0  # No expiration by default
}

variable "logs_lifecycle_days" {
  description = "Days before logs expire"
  type        = number
  default     = 30
}

variable "force_destroy" {
  description = "Allow bucket deletion even with objects"
  type        = bool
  default     = false  # true for dev, false for prod
}

# -----------------------------------------------------------------------------
# ECR Configuration
# -----------------------------------------------------------------------------

variable "ecr_image_tag_mutability" {
  description = "Image tag mutability (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "MUTABLE"
  
  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "Must be MUTABLE or IMMUTABLE"
  }
}

variable "ecr_scan_on_push" {
  description = "Scan images when pushed"
  type        = bool
  default     = true
}

variable "ecr_force_delete" {
  description = "Allow repository deletion with images"
  type        = bool
  default     = false  # true for dev
}
```

### modules/storage/main.tf

```hcl
# ============================================================================
# Storage Module - Main
# ============================================================================

locals {
  # Generate unique bucket names
  bucket_prefix = "${var.name_prefix}-${lower(var.environment)}"
  
  # Determine if production
  is_production = var.environment == "PROD"
}

# =============================================================================
# Random Suffix (for unique bucket names)
# =============================================================================

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# =============================================================================
# Uploads S3 Bucket
# =============================================================================

resource "aws_s3_bucket" "uploads" {
  bucket = "${local.bucket_prefix}-uploads-${random_id.bucket_suffix.hex}"
  
  # Allow deletion in non-prod
  force_destroy = local.is_production ? false : var.force_destroy
  
  tags = merge(var.tags, {
    Name    = "${local.bucket_prefix}-uploads"
    Purpose = "User file uploads"
  })
}

# Versioning
resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rules (optional)
resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  count  = var.uploads_lifecycle_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.uploads.id
  
  rule {
    id     = "expire-old-uploads"
    status = "Enabled"
    
    expiration {
      days = var.uploads_lifecycle_days
    }
    
    # Also expire old versions
    noncurrent_version_expiration {
      noncurrent_days = var.uploads_lifecycle_days
    }
  }
}

# =============================================================================
# Logs S3 Bucket
# =============================================================================

resource "aws_s3_bucket" "logs" {
  bucket = "${local.bucket_prefix}-logs-${random_id.bucket_suffix.hex}"
  
  force_destroy = local.is_production ? false : var.force_destroy
  
  tags = merge(var.tags, {
    Name    = "${local.bucket_prefix}-logs"
    Purpose = "Application logs"
  })
}

# No versioning for logs (not needed)
resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  
  versioning_configuration {
    status = "Disabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rules - expire old logs
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    
    expiration {
      days = var.logs_lifecycle_days
    }
  }
}

# =============================================================================
# ECR Repository - Backend
# =============================================================================

resource "aws_ecr_repository" "backend" {
  name = "${local.bucket_prefix}-backend"
  
  image_tag_mutability = var.ecr_image_tag_mutability
  force_delete         = local.is_production ? false : var.ecr_force_delete
  
  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }
  
  # Enable encryption with AWS managed key
  encryption_configuration {
    encryption_type = "AES256"
  }
  
  tags = merge(var.tags, {
    Name    = "${local.bucket_prefix}-backend"
    Service = "Backend"
  })
}

# Lifecycle policy - keep only recent images
resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name
  
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# =============================================================================
# ECR Repository - Frontend
# =============================================================================

resource "aws_ecr_repository" "frontend" {
  name = "${local.bucket_prefix}-frontend"
  
  image_tag_mutability = var.ecr_image_tag_mutability
  force_delete         = local.is_production ? false : var.ecr_force_delete
  
  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }
  
  encryption_configuration {
    encryption_type = "AES256"
  }
  
  tags = merge(var.tags, {
    Name    = "${local.bucket_prefix}-frontend"
    Service = "Frontend"
  })
}

# Lifecycle policy
resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name
  
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
```

### modules/storage/outputs.tf

```hcl
# ============================================================================
# Storage Module - Outputs
# ============================================================================

# -----------------------------------------------------------------------------
# S3 Buckets
# -----------------------------------------------------------------------------

output "uploads_bucket_name" {
  description = "Name of the uploads S3 bucket"
  value       = aws_s3_bucket.uploads.id
}

output "uploads_bucket_arn" {
  description = "ARN of the uploads S3 bucket"
  value       = aws_s3_bucket.uploads.arn
}

output "uploads_bucket_domain_name" {
  description = "Domain name of the uploads bucket"
  value       = aws_s3_bucket.uploads.bucket_domain_name
}

output "logs_bucket_name" {
  description = "Name of the logs S3 bucket"
  value       = aws_s3_bucket.logs.id
}

output "logs_bucket_arn" {
  description = "ARN of the logs S3 bucket"
  value       = aws_s3_bucket.logs.arn
}

# -----------------------------------------------------------------------------
# ECR Repositories
# -----------------------------------------------------------------------------

output "backend_repository_url" {
  description = "URL of the backend ECR repository"
  value       = aws_ecr_repository.backend.repository_url
}

output "backend_repository_arn" {
  description = "ARN of the backend ECR repository"
  value       = aws_ecr_repository.backend.arn
}

output "backend_repository_name" {
  description = "Name of the backend ECR repository"
  value       = aws_ecr_repository.backend.name
}

output "frontend_repository_url" {
  description = "URL of the frontend ECR repository"
  value       = aws_ecr_repository.frontend.repository_url
}

output "frontend_repository_arn" {
  description = "ARN of the frontend ECR repository"
  value       = aws_ecr_repository.frontend.arn
}

output "frontend_repository_name" {
  description = "Name of the frontend ECR repository"
  value       = aws_ecr_repository.frontend.name
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

output "storage_summary" {
  description = "Summary of all storage resources"
  value = {
    s3 = {
      uploads = {
        name = aws_s3_bucket.uploads.id
        arn  = aws_s3_bucket.uploads.arn
      }
      logs = {
        name = aws_s3_bucket.logs.id
        arn  = aws_s3_bucket.logs.arn
      }
    }
    ecr = {
      backend = {
        name = aws_ecr_repository.backend.name
        url  = aws_ecr_repository.backend.repository_url
      }
      frontend = {
        name = aws_ecr_repository.frontend.name
        url  = aws_ecr_repository.frontend.repository_url
      }
    }
  }
}
```

---

## 3. Using `for_each` for Multiple Buckets (Alternative)

If you need many similar buckets, use `for_each`:

```hcl
# Define buckets in a map
variable "buckets" {
  default = {
    uploads = {
      versioning = true
      lifecycle_days = 90
    }
    logs = {
      versioning = false
      lifecycle_days = 30
    }
    backups = {
      versioning = true
      lifecycle_days = 365
    }
  }
}

# Create all buckets with for_each
resource "aws_s3_bucket" "buckets" {
  for_each = var.buckets
  
  bucket = "${local.bucket_prefix}-${each.key}-${random_id.suffix.hex}"
  
  tags = merge(var.tags, {
    Name    = "${local.bucket_prefix}-${each.key}"
    Purpose = each.key
  })
}

# Versioning for each bucket
resource "aws_s3_bucket_versioning" "buckets" {
  for_each = var.buckets
  
  bucket = aws_s3_bucket.buckets[each.key].id
  
  versioning_configuration {
    status = each.value.versioning ? "Enabled" : "Disabled"
  }
}

# Access buckets
output "bucket_names" {
  value = { for k, v in aws_s3_bucket.buckets : k => v.id }
}
# Output: { uploads = "maia-dev-uploads-abc123", logs = "maia-dev-logs-abc123", ... }
```

---

## 4. S3 Bucket Policy Example

For allowing ECS tasks to access the bucket:

```hcl
# Bucket policy for ECS task access
resource "aws_s3_bucket_policy" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowECSTaskAccess"
        Effect = "Allow"
        Principal = {
          AWS = var.ecs_task_role_arn
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.uploads.arn,
          "${aws_s3_bucket.uploads.arn}/*"
        ]
      }
    ]
  })
}
```

---

## 5. Using the Module

### Update main.tf

```hcl
# infra/terraform/main.tf

# TR Compliance
module "tr_compliance" {
  source = "./modules/tr_compliance"
  
  environment_type = var.environment
  resource_owner   = var.resource_owner
}

# Security Groups
module "security_groups" {
  source = "./modules/security_groups"
  
  vpc_id      = var.vpc_id
  environment = var.environment
  tags        = module.tr_compliance.all_tags
  
  enable_https              = var.alb_acm_certificate_arn != null
  create_rds_security_group = var.create_rds
}

# Storage
module "storage" {
  source = "./modules/storage"
  
  environment = var.environment
  tags        = module.tr_compliance.all_tags
  
  # S3 configuration
  enable_versioning      = true
  uploads_lifecycle_days = 0  # No expiration
  logs_lifecycle_days    = var.environment == "PROD" ? 90 : 30
  
  # Allow force destroy in dev
  force_destroy = var.environment != "PROD"
  
  # ECR configuration
  ecr_scan_on_push  = true
  ecr_force_delete  = var.environment != "PROD"
}
```

### Update outputs.tf

```hcl
# infra/terraform/outputs.tf

# Storage outputs
output "uploads_bucket_name" {
  description = "Uploads S3 bucket name"
  value       = module.storage.uploads_bucket_name
}

output "backend_repository_url" {
  description = "Backend ECR repository URL"
  value       = module.storage.backend_repository_url
}

output "frontend_repository_url" {
  description = "Frontend ECR repository URL"
  value       = module.storage.frontend_repository_url
}
```

---

## 6. Testing

### Plan

```bash
terraform plan \
  -var="vpc_id=vpc-xxx" \
  -var="public_subnet_ids=[\"subnet-1\",\"subnet-2\"]" \
  -var="private_subnet_ids=[\"subnet-3\"]" \
  -var="resource_owner=your.email@thomsonreuters.com"
```

### Expected Output

```
Terraform will perform the following actions:

  # module.storage.aws_ecr_repository.backend will be created
  + resource "aws_ecr_repository" "backend" {
      + name                 = "maia-dev-backend"
      + image_tag_mutability = "MUTABLE"
      ...
    }

  # module.storage.aws_s3_bucket.uploads will be created
  + resource "aws_s3_bucket" "uploads" {
      + bucket = "maia-dev-uploads-abc12345"
      ...
    }

Plan: 12 to add, 0 to change, 0 to destroy.
```

---

## 7. Working with ECR Images

After Terraform creates the ECR repositories, push images:

```bash
# Get ECR login
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 292899125550.dkr.ecr.us-east-1.amazonaws.com

# Tag your image
docker tag maia-backend:latest \
  292899125550.dkr.ecr.us-east-1.amazonaws.com/maia-dev-backend:latest

# Push
docker push 292899125550.dkr.ecr.us-east-1.amazonaws.com/maia-dev-backend:latest
```

---

## 8. Key Takeaways

1. **S3 configuration is split** - Bucket, versioning, encryption are separate resources
2. **Use `random_id`** - For globally unique bucket names
3. **Block public access** - Always enable public access blocks
4. **Enable encryption** - Use AES256 for all buckets
5. **Lifecycle policies** - Clean up old data automatically
6. **ECR lifecycle** - Keep only recent images to save storage

---

## Next Steps

Continue to [Phase 07: Load Balancer](./07-LOAD-BALANCER.md) to create the Application Load Balancer.
