# Phase 07: Frontend Service Module

Create ECS service for the frontend (similar to backend).

## Step 1: Create Module

```bash
mkdir -p infra/terraform/modules/frontend_service
```

## Step 2: Create variables.tf

`modules/frontend_service/variables.tf`:

```hcl
variable "environment" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "cluster_arn" {
  type = string
}

variable "task_execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "image_url" {
  type = string
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "container_port" {
  type    = number
  default = 80
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

variable "log_group" {
  type = string
}

variable "log_region" {
  type = string
}

variable "environment_variables" {
  type    = map(string)
  default = {}
}
```

## Step 3: Create main.tf

`modules/frontend_service/main.tf`:

```hcl
locals {
  name_prefix    = "maia-${lower(var.environment)}"
  container_name = "frontend"
}

# =============================================================================
# Task Definition
# =============================================================================

resource "aws_ecs_task_definition" "frontend" {
  family                   = "${local.name_prefix}-frontend"
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

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group
          "awslogs-region"        = var.log_region
          "awslogs-stream-prefix" = "frontend"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/ || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-frontend-task"
    Service = "Frontend"
  })
}

# =============================================================================
# ECS Service
# =============================================================================

resource "aws_ecs_service" "frontend" {
  name            = "${local.name_prefix}-frontend"
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.frontend.arn
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

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-frontend-service"
    Service = "Frontend"
  })
}
```

## Step 4: Create outputs.tf

`modules/frontend_service/outputs.tf`:

```hcl
output "service_name" {
  value = aws_ecs_service.frontend.name
}

output "service_arn" {
  value = aws_ecs_service.frontend.id
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.frontend.arn
}
```

## Step 5: Use in main.tf

```hcl
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
    REACT_APP_API_URL = "http://${module.alb.dns_name}/api"
  }
}
```

## Step 6: Test

```bash
terraform plan
terraform apply

# Check both services
aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services maia-dev-backend maia-dev-frontend

# Access the app
curl http://$(terraform output -raw alb_dns_name)
```

---

**Next:** [Phase 08: Full Deployment](./08-DEPLOY.md)
