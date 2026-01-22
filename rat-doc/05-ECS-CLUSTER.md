# Phase 05: ECS Cluster Module

Create ECS cluster and IAM roles.

## Pulumi Reference

From `infra/pulumi/components/infrastructure.py`:
```python
self.ecs_cluster = aws.ecs.Cluster("maia-ecs-cluster", ...)
```

## Step 1: Create Module

```bash
mkdir -p infra/terraform/modules/ecs
```

## Step 2: Create variables.tf

`modules/ecs/variables.tf`:

```hcl
variable "environment" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "uploads_bucket_arn" {
  description = "S3 bucket ARN for task role access"
  type        = string
  default     = null
}

variable "log_retention_days" {
  type    = number
  default = 30
}

# TR Compliance
variable "tr_account_id" {
  type    = string
  default = "292899125550"
}

variable "tr_permission_boundary" {
  type    = string
  default = "tr-permission-boundary"
}

variable "tr_iam_path" {
  type    = string
  default = "/service-role/"
}
```

## Step 3: Create main.tf

`modules/ecs/main.tf`:

```hcl
locals {
  name_prefix             = "maia-${lower(var.environment)}"
  permission_boundary_arn = "arn:aws:iam::${var.tr_account_id}:policy/${var.tr_permission_boundary}"
  role_prefix             = "a209671-"  # TR asset ID prefix
}

data "aws_region" "current" {}

# =============================================================================
# ECS Cluster
# =============================================================================

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-cluster"
  })
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# =============================================================================
# CloudWatch Log Groups
# =============================================================================

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.name_prefix}-backend"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-backend-logs"
    Service = "Backend"
  })
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${local.name_prefix}-frontend"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-frontend-logs"
    Service = "Frontend"
  })
}

# =============================================================================
# Task Execution Role (used by ECS agent)
# =============================================================================

resource "aws_iam_role" "task_execution" {
  name                 = "${local.role_prefix}${local.name_prefix}-task-exec"
  path                 = var.tr_iam_path
  permissions_boundary = local.permission_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-task-execution-role"
  })
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Secrets Manager access
resource "aws_iam_role_policy" "task_execution_secrets" {
  name = "secrets-access"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:*:${var.tr_account_id}:secret:maia/*"
    }]
  })
}

# =============================================================================
# Task Role (used by application)
# =============================================================================

resource "aws_iam_role" "task" {
  name                 = "${local.role_prefix}${local.name_prefix}-task"
  path                 = var.tr_iam_path
  permissions_boundary = local.permission_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-task-role"
  })
}

# S3 access for task role
resource "aws_iam_role_policy" "task_s3" {
  count = var.uploads_bucket_arn != null ? 1 : 0
  name  = "s3-access"
  role  = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        var.uploads_bucket_arn,
        "${var.uploads_bucket_arn}/*"
      ]
    }]
  })
}
```

## Step 4: Create outputs.tf

`modules/ecs/outputs.tf`:

```hcl
output "cluster_id" {
  value = aws_ecs_cluster.main.id
}

output "cluster_arn" {
  value = aws_ecs_cluster.main.arn
}

output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "task_execution_role_arn" {
  value = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "backend_log_group" {
  value = aws_cloudwatch_log_group.backend.name
}

output "frontend_log_group" {
  value = aws_cloudwatch_log_group.frontend.name
}

output "log_region" {
  value = data.aws_region.current.name
}
```

## Step 5: Use in main.tf

```hcl
module "ecs" {
  source = "./modules/ecs"

  environment        = var.environment
  tags               = module.tr_compliance.all_tags
  uploads_bucket_arn = module.storage.uploads_bucket_arn
  log_retention_days = var.environment == "PROD" ? 90 : 30
}
```

## Step 6: Add Outputs

```hcl
output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}
```

## Step 7: Test

```bash
terraform plan
terraform apply

# Verify cluster
aws ecs describe-clusters --clusters $(terraform output -raw ecs_cluster_name)
```

---

**Next:** [Phase 06: Backend Service](./06-BACKEND-SERVICE.md)
