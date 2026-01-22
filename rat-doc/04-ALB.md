# Phase 04: Application Load Balancer Module

Create ALB with listeners and target groups.

## Pulumi Reference

From `infra/pulumi/components/infrastructure.py`:
```python
self.alb = aws.lb.LoadBalancer("maia-alb", ...)
self.http_listener = aws.lb.Listener("maia-http-listener", ...)
```

## Step 1: Create Module

```bash
mkdir -p infra/terraform/modules/alb
```

## Step 2: Create variables.tf

`modules/alb/variables.tf`:

```hcl
variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "certificate_arn" {
  type    = string
  default = null
}

variable "backend_port" {
  type    = number
  default = 8000
}

variable "frontend_port" {
  type    = number
  default = 80
}

variable "health_check_path_backend" {
  type    = string
  default = "/health"
}

variable "health_check_path_frontend" {
  type    = string
  default = "/"
}
```

## Step 3: Create main.tf

`modules/alb/main.tf`:

```hcl
locals {
  name_prefix  = "maia-${lower(var.environment)}"
  enable_https = var.certificate_arn != null
}

# =============================================================================
# Application Load Balancer
# =============================================================================

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [var.security_group_id]

  enable_deletion_protection = var.environment == "PROD"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-alb"
  })
}

# =============================================================================
# Target Groups
# =============================================================================

resource "aws_lb_target_group" "backend" {
  name        = "${local.name_prefix}-backend-tg"
  port        = var.backend_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.health_check_path_backend
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-backend-tg"
    Service = "Backend"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "frontend" {
  name        = "${local.name_prefix}-frontend-tg"
  port        = var.frontend_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.health_check_path_frontend
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-frontend-tg"
    Service = "Frontend"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# HTTP Listener
# =============================================================================

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = local.enable_https ? "redirect" : "forward"

    # Redirect to HTTPS if certificate provided
    dynamic "redirect" {
      for_each = local.enable_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    # Forward to frontend if no HTTPS
    target_group_arn = local.enable_https ? null : aws_lb_target_group.frontend.arn
  }
}

# HTTP Backend rule (only if no HTTPS)
resource "aws_lb_listener_rule" "http_backend" {
  count        = local.enable_https ? 0 : 1
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["/api/*", "/health"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

# =============================================================================
# HTTPS Listener (Optional)
# =============================================================================

resource "aws_lb_listener" "https" {
  count             = local.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "https_backend" {
  count        = local.enable_https ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 100

  condition {
    path_pattern {
      values = ["/api/*", "/health"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}
```

## Step 4: Create outputs.tf

`modules/alb/outputs.tf`:

```hcl
output "arn" {
  value = aws_lb.main.arn
}

output "dns_name" {
  value = aws_lb.main.dns_name
}

output "zone_id" {
  value = aws_lb.main.zone_id
}

output "http_listener_arn" {
  value = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  value = local.enable_https ? aws_lb_listener.https[0].arn : null
}

output "backend_target_group_arn" {
  value = aws_lb_target_group.backend.arn
}

output "frontend_target_group_arn" {
  value = aws_lb_target_group.frontend.arn
}
```

## Step 5: Use in main.tf

```hcl
module "alb" {
  source = "./modules/alb"

  environment       = var.environment
  vpc_id            = var.vpc_id
  public_subnet_ids = var.public_subnet_ids
  security_group_id = module.security_groups.alb_sg_id
  tags              = module.tr_compliance.all_tags
  certificate_arn   = var.alb_certificate_arn
}
```

## Step 6: Add Output

```hcl
output "alb_dns_name" {
  value = module.alb.dns_name
}

output "application_url" {
  value = "http://${module.alb.dns_name}"
}
```

## Step 7: Test

```bash
terraform plan
terraform apply

# Test the ALB
curl http://$(terraform output -raw alb_dns_name)/health
```

---

**Next:** [Phase 05: ECS Cluster](./05-ECS-CLUSTER.md)
