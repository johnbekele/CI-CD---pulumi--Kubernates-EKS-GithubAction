# Phase 03: Storage Module (S3 + ECR)

Create S3 buckets and ECR repositories.

## Pulumi Reference

From `infra/pulumi/components/infrastructure.py`:
```python
self.uploads_bucket = aws.s3.Bucket("maia-uploads", ...)
self.backend_repo = aws.ecr.Repository("maia-backend-repo", ...)
```

## Step 1: Create Module Structure

```bash
mkdir -p infra/terraform/modules/storage
```

## Step 2: Create variables.tf

`modules/storage/variables.tf`:

```hcl
variable "environment" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "force_destroy" {
  description = "Allow deletion of non-empty buckets/repos (dev only)"
  type        = bool
  default     = false
}
```

## Step 3: Create main.tf

`modules/storage/main.tf`:

```hcl
locals {
  name_prefix = "maia-${lower(var.environment)}"
}

# Random suffix for globally unique bucket names
resource "random_id" "suffix" {
  byte_length = 4
}

# =============================================================================
# S3 Bucket - Uploads
# =============================================================================

resource "aws_s3_bucket" "uploads" {
  bucket        = "${local.name_prefix}-uploads-${random_id.suffix.hex}"
  force_destroy = var.force_destroy

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-uploads"
    Purpose = "User uploads"
  })
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket                  = aws_s3_bucket.uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# S3 Bucket - Logs
# =============================================================================

resource "aws_s3_bucket" "logs" {
  bucket        = "${local.name_prefix}-logs-${random_id.suffix.hex}"
  force_destroy = var.force_destroy

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-logs"
    Purpose = "Application logs"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter { prefix = "" }
    expiration { days = 30 }
  }
}

# =============================================================================
# ECR - Backend Repository
# =============================================================================

resource "aws_ecr_repository" "backend" {
  name                 = "${local.name_prefix}-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = var.force_destroy

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-backend"
    Service = "Backend"
  })
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# =============================================================================
# ECR - Frontend Repository
# =============================================================================

resource "aws_ecr_repository" "frontend" {
  name                 = "${local.name_prefix}-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = var.force_destroy

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-frontend"
    Service = "Frontend"
  })
}

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
```

## Step 4: Create outputs.tf

`modules/storage/outputs.tf`:

```hcl
# S3
output "uploads_bucket_name" {
  value = aws_s3_bucket.uploads.id
}

output "uploads_bucket_arn" {
  value = aws_s3_bucket.uploads.arn
}

output "logs_bucket_name" {
  value = aws_s3_bucket.logs.id
}

# ECR
output "backend_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "backend_repository_arn" {
  value = aws_ecr_repository.backend.arn
}

output "frontend_repository_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "frontend_repository_arn" {
  value = aws_ecr_repository.frontend.arn
}
```

## Step 5: Use in main.tf

Update `infra/terraform/main.tf`:

```hcl
module "storage" {
  source = "./modules/storage"

  environment   = var.environment
  tags          = module.tr_compliance.all_tags
  force_destroy = var.environment != "PROD"
}
```

## Step 6: Add Outputs

Update `infra/terraform/outputs.tf`:

```hcl
output "uploads_bucket_name" {
  value = module.storage.uploads_bucket_name
}

output "backend_repository_url" {
  value = module.storage.backend_repository_url
}

output "frontend_repository_url" {
  value = module.storage.frontend_repository_url
}
```

## Step 7: Test

```bash
terraform plan
terraform apply
```

## Push Images (After Apply)

```bash
# Get ECR login
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $(terraform output -raw backend_repository_url | cut -d'/' -f1)

# Build and push backend
docker build -t backend ./backend
docker tag backend:latest $(terraform output -raw backend_repository_url):latest
docker push $(terraform output -raw backend_repository_url):latest
```

---

**Next:** [Phase 04: ALB](./04-ALB.md)
