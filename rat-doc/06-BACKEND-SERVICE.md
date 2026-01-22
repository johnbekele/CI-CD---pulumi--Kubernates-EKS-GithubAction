# Phase 06: Backend Service Module

Create ECS service and task definition for the backend.

## Pulumi Reference

From `infra/pulumi/components/backend_service.py`:
```python
class BackendServiceComponent(pulumi.ComponentResource):
    # Creates task definition, service, target group attachment
```

## Step 1: Create Module

```bash
mkdir -p infra/terraform/modules/backend_service
```

## Step 2: Create variables.tf

`modules/backend_service/variables.tf`:

```hcl
variable "environment" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ECS
variable "cluster_arn" {
  type = string
}

variable "task_execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

# Network
variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

# ALB
variable "target_group_arn" {
  type = string
}

# Container
variable "image_url" {
  type = string
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "container_port" {
  type    = number
  default = 8000
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 1
}

# Logging
variable "log_group" {
  type = string
}

variable "log_region" {
  type = string
}

# Environment variables
variable "environment_variables" {
  type    = map(string)
  default = {}
}

# Secrets (from Secrets Manager)
variable "secrets" {
  description = "Map of secret name to Secrets Manager ARN"
  type        = map(string)
  default     = {}
}
```

## Step 3: Create main.tf

`modules/backend_service/main.tf`:

```hcl
locals {
  name_prefix    = "maia-${lower(var.environment)}"
  container_name = "backend"
}

# =============================================================================
# Task Definition
# =============================================================================

resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.name_prefix}-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = "${var.image_url}:${var.image_tag}"
      essential = true

      portMappings = [{
        containerPort = var.container_port
        hostPort      = var.container_port
        protocol      = "tcp"
      }]

      environment = [
        for k, v in var.environment_variables : {
          name  = k
          value = v
        }
      ]

      secrets = [
        for k, v in var.secrets : {
          name      = k
          valueFrom = v
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group
          "awslogs-region"        = var.log_region
          "awslogs-stream-prefix" = "backend"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-backend-task"
    Service = "Backend"
  })
}

# =============================================================================
# ECS Service
# =============================================================================

resource "aws_ecs_service" "backend" {
  name            = "${local.name_prefix}-backend"
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  deployment_configuration {
    minimum_healthy_percent = 50
    maximum_percent         = 200
  }

  # Allow external changes to desired_count without Terraform drift
  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-backend-service"
    Service = "Backend"
  })
}
```

## Step 4: Create outputs.tf

`modules/backend_service/outputs.tf`:

```hcl
output "service_name" {
  value = aws_ecs_service.backend.name
}

output "service_arn" {
  value = aws_ecs_service.backend.id
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.backend.arn
}
```

## Step 5: Use in main.tf

```hcl
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

  # Example secrets (if you have them in Secrets Manager)
  # secrets = {
  #   DATABASE_URL = "arn:aws:secretsmanager:us-east-1:123456:secret:maia/db-url"
  # }
}
```

## Step 6: Test

```bash
terraform plan
terraform apply

# Check service status
aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services maia-dev-backend

# Check logs
aws logs tail /ecs/maia-dev-backend --follow
```

---

**Next:** [Phase 07: Frontend Service](./07-FRONTEND-SERVICE.md)
