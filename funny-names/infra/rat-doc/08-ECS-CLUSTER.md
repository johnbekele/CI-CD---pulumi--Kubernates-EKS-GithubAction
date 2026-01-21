# Phase 08: ECS Cluster & IAM Roles

## Learning Objectives

- Create an ECS cluster for container orchestration
- Configure IAM roles for ECS tasks
- Understand task execution role vs task role
- Create CloudWatch log groups for container logs
- Prepare for ECS service deployment

---

## 1. ECS Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          ECS Architecture                                    │
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                        ECS Cluster                                     │  │
│  │                    (maia-cluster-dev)                                  │  │
│  │                                                                        │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                     ECS Services                                 │  │  │
│  │  │                                                                  │  │  │
│  │  │  ┌──────────────────┐        ┌──────────────────┐              │  │  │
│  │  │  │  Backend Service │        │ Frontend Service │              │  │  │
│  │  │  │                  │        │                  │              │  │  │
│  │  │  │  ┌────────────┐  │        │  ┌────────────┐  │              │  │  │
│  │  │  │  │   Task     │  │        │  │   Task     │  │              │  │  │
│  │  │  │  │ Definition │  │        │  │ Definition │  │              │  │  │
│  │  │  │  └─────┬──────┘  │        │  └─────┬──────┘  │              │  │  │
│  │  │  │        │         │        │        │         │              │  │  │
│  │  │  │  ┌─────┴──────┐  │        │  ┌─────┴──────┐  │              │  │  │
│  │  │  │  │ Container  │  │        │  │ Container  │  │              │  │  │
│  │  │  │  │ (Fargate)  │  │        │  │ (Fargate)  │  │              │  │  │
│  │  │  │  └────────────┘  │        │  └────────────┘  │              │  │  │
│  │  │  └──────────────────┘        └──────────────────┘              │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                        IAM Roles                                       │  │
│  │                                                                        │  │
│  │  ┌─────────────────────────┐  ┌─────────────────────────┐            │  │
│  │  │   Task Execution Role   │  │      Task Role          │            │  │
│  │  │                         │  │                         │            │  │
│  │  │  • Pull ECR images      │  │  • Access S3 buckets    │            │  │
│  │  │  • Write CloudWatch logs│  │  • Call AWS APIs        │            │  │
│  │  │  • Get Secrets Manager  │  │  • Application needs    │            │  │
│  │  └─────────────────────────┘  └─────────────────────────┘            │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. IAM Roles Explained

### Task Execution Role vs Task Role

| Aspect | Task Execution Role | Task Role |
|--------|--------------------| ----------|
| **Used by** | ECS Agent | Your application |
| **Purpose** | Infrastructure tasks | Application tasks |
| **Permissions** | Pull images, write logs, get secrets | Access S3, DynamoDB, etc. |
| **When used** | Task startup | Runtime |

---

## 3. Create ECS Module

### Directory Structure

```bash
mkdir -p infra/terraform/modules/ecs
touch infra/terraform/modules/ecs/{variables,main,outputs}.tf
```

### modules/ecs/variables.tf

```hcl
# ============================================================================
# ECS Module - Variables
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
# TR Compliance
# -----------------------------------------------------------------------------

variable "tr_account_id" {
  description = "TR AWS Account ID"
  type        = string
  default     = "292899125550"
}

variable "tr_iam_role_path" {
  description = "IAM role path for TR compliance"
  type        = string
  default     = "/service-role/"
}

variable "tr_permission_boundary_name" {
  description = "Name of TR permission boundary"
  type        = string
  default     = "tr-permission-boundary"
}

# -----------------------------------------------------------------------------
# S3 Access (for Task Role)
# -----------------------------------------------------------------------------

variable "uploads_bucket_arn" {
  description = "ARN of uploads S3 bucket (for task role access)"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}
```

### modules/ecs/main.tf

```hcl
# ============================================================================
# ECS Module - Main
# ============================================================================

locals {
  cluster_name             = "${var.name_prefix}-cluster-${lower(var.environment)}"
  permission_boundary_arn  = "arn:aws:iam::${var.tr_account_id}:policy/${var.tr_permission_boundary_name}"
  
  # TR-compliant role name prefix
  role_name_prefix = "a209191-"
}

# =============================================================================
# ECS Cluster
# =============================================================================

resource "aws_ecs_cluster" "main" {
  name = local.cluster_name
  
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  
  tags = merge(var.tags, {
    Name      = local.cluster_name
    Component = "ECS"
  })
}

# Cluster capacity providers (Fargate)
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name
  
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
  name              = "/ecs/${var.name_prefix}-backend-${lower(var.environment)}"
  retention_in_days = var.log_retention_days
  
  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-backend-logs"
    Service   = "Backend"
    Component = "Logging"
  })
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${var.name_prefix}-frontend-${lower(var.environment)}"
  retention_in_days = var.log_retention_days
  
  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-frontend-logs"
    Service   = "Frontend"
    Component = "Logging"
  })
}

# =============================================================================
# Task Execution Role
# =============================================================================
# This role is used by ECS to:
# - Pull container images from ECR
# - Write logs to CloudWatch
# - Retrieve secrets from Secrets Manager

resource "aws_iam_role" "task_execution" {
  name = "${local.role_name_prefix}${var.name_prefix}-task-execution-${lower(var.environment)}"
  path = var.tr_iam_role_path
  
  # TR compliance: permission boundary
  permissions_boundary = local.permission_boundary_arn
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-task-execution-role"
    Component = "IAM"
    Purpose   = "ECS Task Execution"
  })
}

# Attach AWS managed policy for basic ECS task execution
resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for Secrets Manager access
resource "aws_iam_role_policy" "task_execution_secrets" {
  name = "secrets-manager-access"
  role = aws_iam_role.task_execution.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:*:${var.tr_account_id}:secret:${var.name_prefix}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.*.amazonaws.com"
          }
        }
      }
    ]
  })
}

# =============================================================================
# Task Role
# =============================================================================
# This role is assumed by the running container to access AWS services

resource "aws_iam_role" "task" {
  name = "${local.role_name_prefix}${var.name_prefix}-task-${lower(var.environment)}"
  path = var.tr_iam_role_path
  
  permissions_boundary = local.permission_boundary_arn
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-task-role"
    Component = "IAM"
    Purpose   = "ECS Task"
  })
}

# S3 access for task role (if bucket provided)
resource "aws_iam_role_policy" "task_s3" {
  count = var.uploads_bucket_arn != null ? 1 : 0
  
  name = "s3-access"
  role = aws_iam_role.task.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
      }
    ]
  })
}

# CloudWatch access for custom metrics
resource "aws_iam_role_policy" "task_cloudwatch" {
  name = "cloudwatch-access"
  role = aws_iam_role.task.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "${var.name_prefix}/${var.environment}"
          }
        }
      }
    ]
  })
}
```

### modules/ecs/outputs.tf

```hcl
# ============================================================================
# ECS Module - Outputs
# ============================================================================

# -----------------------------------------------------------------------------
# Cluster
# -----------------------------------------------------------------------------

output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

# -----------------------------------------------------------------------------
# IAM Roles
# -----------------------------------------------------------------------------

output "task_execution_role_arn" {
  description = "ARN of the task execution role"
  value       = aws_iam_role.task_execution.arn
}

output "task_execution_role_name" {
  description = "Name of the task execution role"
  value       = aws_iam_role.task_execution.name
}

output "task_role_arn" {
  description = "ARN of the task role"
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "Name of the task role"
  value       = aws_iam_role.task.name
}

# -----------------------------------------------------------------------------
# CloudWatch Log Groups
# -----------------------------------------------------------------------------

output "backend_log_group_name" {
  description = "Name of the backend CloudWatch log group"
  value       = aws_cloudwatch_log_group.backend.name
}

output "backend_log_group_arn" {
  description = "ARN of the backend CloudWatch log group"
  value       = aws_cloudwatch_log_group.backend.arn
}

output "frontend_log_group_name" {
  description = "Name of the frontend CloudWatch log group"
  value       = aws_cloudwatch_log_group.frontend.name
}

output "frontend_log_group_arn" {
  description = "ARN of the frontend CloudWatch log group"
  value       = aws_cloudwatch_log_group.frontend.arn
}

# -----------------------------------------------------------------------------
# For Task Definition Use
# -----------------------------------------------------------------------------

output "task_definition_requirements" {
  description = "Values needed for ECS task definitions"
  value = {
    cluster_arn            = aws_ecs_cluster.main.arn
    task_execution_role_arn = aws_iam_role.task_execution.arn
    task_role_arn          = aws_iam_role.task.arn
    backend_log_group      = aws_cloudwatch_log_group.backend.name
    frontend_log_group     = aws_cloudwatch_log_group.frontend.name
    log_region             = data.aws_region.current.name
  }
}

# Get current region
data "aws_region" "current" {}
```

---

## 4. Using the Module

### Update main.tf

```hcl
# infra/terraform/main.tf

module "tr_compliance" {
  source = "./modules/tr_compliance"
  
  environment_type = var.environment
  resource_owner   = var.resource_owner
}

module "security_groups" {
  source = "./modules/security_groups"
  
  vpc_id      = var.vpc_id
  environment = var.environment
  tags        = module.tr_compliance.all_tags
}

module "storage" {
  source = "./modules/storage"
  
  environment   = var.environment
  tags          = module.tr_compliance.all_tags
  force_destroy = var.environment != "PROD"
}

module "alb" {
  source = "./modules/alb"
  
  environment       = var.environment
  vpc_id            = var.vpc_id
  public_subnet_ids = var.public_subnet_ids
  security_group_id = module.security_groups.alb_security_group_id
  tags              = module.tr_compliance.all_tags
}

module "ecs" {
  source = "./modules/ecs"
  
  environment = var.environment
  tags        = module.tr_compliance.all_tags
  
  # TR compliance
  tr_account_id               = "292899125550"
  tr_iam_role_path            = "/service-role/"
  tr_permission_boundary_name = "tr-permission-boundary"
  
  # S3 access for task role
  uploads_bucket_arn = module.storage.uploads_bucket_arn
  
  # Logging
  log_retention_days = var.environment == "PROD" ? 90 : 30
}
```

### Update outputs.tf

```hcl
# infra/terraform/outputs.tf

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = module.ecs.cluster_arn
}

output "task_execution_role_arn" {
  description = "Task execution role ARN"
  value       = module.ecs.task_execution_role_arn
}

output "task_role_arn" {
  description = "Task role ARN"
  value       = module.ecs.task_role_arn
}
```

---

## 5. ECS Service (Reference)

After this module, you'd create ECS services. Here's a preview:

```hcl
# This would be in a separate module or the root module
resource "aws_ecs_service" "backend" {
  name            = "maia-backend"
  cluster         = module.ecs.cluster_arn
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 2
  launch_type     = "FARGATE"
  
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [module.security_groups.backend_ecs_security_group_id]
    assign_public_ip = false
  }
  
  load_balancer {
    target_group_arn = module.alb.backend_target_group_arn
    container_name   = "backend"
    container_port   = 8000
  }
}
```

---

## 6. TR Compliance Notes

### Permission Boundary

All IAM roles must have the TR permission boundary:

```hcl
resource "aws_iam_role" "example" {
  name = "a209191-my-role"
  path = "/service-role/"
  
  # Required for TR compliance
  permissions_boundary = "arn:aws:iam::292899125550:policy/tr-permission-boundary"
}
```

### Role Naming

Roles must start with the asset ID prefix:

```hcl
# Good
name = "a209191-maia-task-execution-dev"

# Bad (will be rejected)
name = "maia-task-execution-dev"
```

---

## 7. Testing

```bash
terraform plan \
  -var="vpc_id=vpc-xxx" \
  -var="public_subnet_ids=[\"subnet-1\",\"subnet-2\"]" \
  -var="private_subnet_ids=[\"subnet-3\"]" \
  -var="resource_owner=your.email@thomsonreuters.com"
```

### Expected Output

```
  # module.ecs.aws_ecs_cluster.main will be created
  + resource "aws_ecs_cluster" "main" {
      + name = "maia-cluster-dev"
      ...
    }

  # module.ecs.aws_iam_role.task_execution will be created
  + resource "aws_iam_role" "task_execution" {
      + name                 = "a209191-maia-task-execution-dev"
      + path                 = "/service-role/"
      + permissions_boundary = "arn:aws:iam::292899125550:policy/tr-permission-boundary"
      ...
    }

Plan: 8 to add, 0 to change, 0 to destroy.
```

---

## 8. Key Takeaways

1. **ECS Cluster** is the logical grouping of services
2. **Task Execution Role** is used by ECS infrastructure
3. **Task Role** is used by your application code
4. **Permission Boundary** is required for TR compliance
5. **Container Insights** provides monitoring
6. **Fargate** removes need to manage EC2 instances

---

## Next Steps

Continue to [Phase 09: RDS Database](./09-RDS-DATABASE.md) to create the PostgreSQL database (optional component).
