# Phase 07: Application Load Balancer

## Learning Objectives

- Create an Application Load Balancer (ALB)
- Configure HTTP and HTTPS listeners
- Set up target groups for ECS services
- Understand listener rules and routing
- Use conditional resources for optional HTTPS

---

## 1. ALB Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Internet                                            │
│                              │                                              │
│                    ┌─────────┴─────────┐                                    │
│                    │    Route 53 /     │                                    │
│                    │    CloudFront     │                                    │
│                    └─────────┬─────────┘                                    │
│                              │                                              │
│  ┌───────────────────────────┼───────────────────────────────────────────┐  │
│  │                    Public Subnets                                      │  │
│  │                           │                                            │  │
│  │           ┌───────────────┴───────────────┐                           │  │
│  │           │    Application Load Balancer   │                           │  │
│  │           │                               │                           │  │
│  │           │  ┌─────────┐   ┌─────────┐   │                           │  │
│  │           │  │ HTTP:80 │   │HTTPS:443│   │                           │  │
│  │           │  │Listener │   │Listener │   │                           │  │
│  │           │  └────┬────┘   └────┬────┘   │                           │  │
│  │           └───────┼─────────────┼────────┘                           │  │
│  └───────────────────┼─────────────┼────────────────────────────────────┘  │
│                      │             │                                        │
│                      │    Listener Rules                                    │
│                      │    ┌────────────────────────────────────┐           │
│                      │    │ Path: /api/*  → Backend TG         │           │
│                      │    │ Path: /*      → Frontend TG        │           │
│                      │    └────────────────────────────────────┘           │
│                      │                                                      │
│  ┌───────────────────┼──────────────────────────────────────────────────┐  │
│  │              Private Subnets                                          │  │
│  │                   │                                                   │  │
│  │     ┌─────────────┴─────────────┐                                    │  │
│  │     │                           │                                    │  │
│  │  ┌──┴──────────┐    ┌───────────┴──┐                                │  │
│  │  │ Backend TG  │    │ Frontend TG  │                                │  │
│  │  │  Port 8000  │    │   Port 80    │                                │  │
│  │  └─────────────┘    └──────────────┘                                │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Create ALB Module

### Directory Structure

```bash
mkdir -p infra/terraform/modules/alb
touch infra/terraform/modules/alb/{variables,main,outputs}.tf
```

### modules/alb/variables.tf

```hcl
# ============================================================================
# ALB Module - Variables
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

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# HTTPS Configuration
# -----------------------------------------------------------------------------

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS (optional)"
  type        = string
  default     = null
}

variable "ssl_policy" {
  description = "SSL policy for HTTPS listener"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

# -----------------------------------------------------------------------------
# Target Group Configuration
# -----------------------------------------------------------------------------

variable "backend_container_port" {
  description = "Port for backend container"
  type        = number
  default     = 8000
}

variable "frontend_container_port" {
  description = "Port for frontend container"
  type        = number
  default     = 80
}

variable "health_check_path_backend" {
  description = "Health check path for backend"
  type        = string
  default     = "/health"
}

variable "health_check_path_frontend" {
  description = "Health check path for frontend"
  type        = string
  default     = "/"
}

# -----------------------------------------------------------------------------
# ALB Settings
# -----------------------------------------------------------------------------

variable "enable_deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false
}

variable "idle_timeout" {
  description = "Idle timeout in seconds"
  type        = number
  default     = 60
}

variable "access_logs_bucket" {
  description = "S3 bucket for access logs (optional)"
  type        = string
  default     = null
}
```

### modules/alb/main.tf

```hcl
# ============================================================================
# ALB Module - Main
# ============================================================================

locals {
  alb_name       = "${var.name_prefix}-alb-${lower(var.environment)}"
  enable_https   = var.certificate_arn != null
  is_production  = var.environment == "PROD"
}

# =============================================================================
# Application Load Balancer
# =============================================================================

resource "aws_lb" "main" {
  name               = local.alb_name
  load_balancer_type = "application"
  internal           = false
  
  subnets         = var.public_subnet_ids
  security_groups = [var.security_group_id]
  
  enable_deletion_protection = local.is_production ? true : var.enable_deletion_protection
  idle_timeout               = var.idle_timeout
  
  # Access logs (optional)
  dynamic "access_logs" {
    for_each = var.access_logs_bucket != null ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      prefix  = "alb/${local.alb_name}"
      enabled = true
    }
  }
  
  tags = merge(var.tags, {
    Name      = local.alb_name
    Component = "ALB"
  })
}

# =============================================================================
# Target Groups
# =============================================================================

# Backend Target Group
resource "aws_lb_target_group" "backend" {
  name        = "${var.name_prefix}-backend-tg-${lower(var.environment)}"
  port        = var.backend_container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"  # For Fargate
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = var.health_check_path_backend
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
  }
  
  # Slow start for new targets (gives time to warm up)
  slow_start = 30
  
  # Deregistration delay
  deregistration_delay = 30
  
  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-backend-tg"
    Component = "ALB"
    Service   = "Backend"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Frontend Target Group
resource "aws_lb_target_group" "frontend" {
  name        = "${var.name_prefix}-frontend-tg-${lower(var.environment)}"
  port        = var.frontend_container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = var.health_check_path_frontend
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
  }
  
  slow_start           = 30
  deregistration_delay = 30
  
  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-frontend-tg"
    Component = "ALB"
    Service   = "Frontend"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# HTTP Listener (Port 80)
# =============================================================================

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  
  # Default action - redirect to HTTPS if enabled, otherwise forward to frontend
  default_action {
    type = local.enable_https ? "redirect" : "forward"
    
    # Redirect to HTTPS
    dynamic "redirect" {
      for_each = local.enable_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    
    # Forward to frontend (if HTTPS not enabled)
    target_group_arn = local.enable_https ? null : aws_lb_target_group.frontend.arn
  }
  
  tags = merge(var.tags, {
    Name      = "${local.alb_name}-http-listener"
    Component = "ALB"
  })
}

# HTTP Listener Rule - Backend API (only if no HTTPS)
resource "aws_lb_listener_rule" "http_backend" {
  count = local.enable_https ? 0 : 1
  
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
  
  tags = merge(var.tags, { Name = "http-backend-rule" })
}

# =============================================================================
# HTTPS Listener (Port 443) - Optional
# =============================================================================

resource "aws_lb_listener" "https" {
  count = local.enable_https ? 1 : 0
  
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn
  
  # Default action - forward to frontend
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
  
  tags = merge(var.tags, {
    Name      = "${local.alb_name}-https-listener"
    Component = "ALB"
  })
}

# HTTPS Listener Rule - Backend API
resource "aws_lb_listener_rule" "https_backend" {
  count = local.enable_https ? 1 : 0
  
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
  
  tags = merge(var.tags, { Name = "https-backend-rule" })
}
```

### modules/alb/outputs.tf

```hcl
# ============================================================================
# ALB Module - Outputs
# ============================================================================

# -----------------------------------------------------------------------------
# Load Balancer
# -----------------------------------------------------------------------------

output "arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "zone_id" {
  description = "Zone ID of the ALB (for Route53 alias records)"
  value       = aws_lb.main.zone_id
}

output "id" {
  description = "ID of the ALB"
  value       = aws_lb.main.id
}

# -----------------------------------------------------------------------------
# Listeners
# -----------------------------------------------------------------------------

output "http_listener_arn" {
  description = "ARN of the HTTP listener"
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (if enabled)"
  value       = local.enable_https ? aws_lb_listener.https[0].arn : null
}

# -----------------------------------------------------------------------------
# Target Groups
# -----------------------------------------------------------------------------

output "backend_target_group_arn" {
  description = "ARN of the backend target group"
  value       = aws_lb_target_group.backend.arn
}

output "backend_target_group_name" {
  description = "Name of the backend target group"
  value       = aws_lb_target_group.backend.name
}

output "frontend_target_group_arn" {
  description = "ARN of the frontend target group"
  value       = aws_lb_target_group.frontend.arn
}

output "frontend_target_group_name" {
  description = "Name of the frontend target group"
  value       = aws_lb_target_group.frontend.name
}

# -----------------------------------------------------------------------------
# Convenience Outputs
# -----------------------------------------------------------------------------

output "application_url" {
  description = "URL to access the application"
  value       = local.enable_https ? "https://${aws_lb.main.dns_name}" : "http://${aws_lb.main.dns_name}"
}

output "https_enabled" {
  description = "Whether HTTPS is enabled"
  value       = local.enable_https
}
```

---

## 3. Understanding Key Concepts

### Dynamic Blocks

Used for optional nested blocks:

```hcl
# Dynamic access_logs block - only included if bucket is provided
dynamic "access_logs" {
  for_each = var.access_logs_bucket != null ? [1] : []
  content {
    bucket  = var.access_logs_bucket
    enabled = true
  }
}
```

### Conditional in default_action

```hcl
default_action {
  type = local.enable_https ? "redirect" : "forward"
  
  # Only include redirect block if HTTPS enabled
  dynamic "redirect" {
    for_each = local.enable_https ? [1] : []
    content {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
  
  # target_group_arn only when not redirecting
  target_group_arn = local.enable_https ? null : aws_lb_target_group.frontend.arn
}
```

### Target Types

- `ip` - For Fargate (awsvpc network mode)
- `instance` - For EC2 instances
- `lambda` - For Lambda functions

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
  
  enable_https = var.alb_acm_certificate_arn != null
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
  
  # HTTPS (optional)
  certificate_arn = var.alb_acm_certificate_arn
  
  # Target groups
  backend_container_port  = 8000
  frontend_container_port = 80
  
  # Access logs (optional)
  access_logs_bucket = module.storage.logs_bucket_name
}
```

### Update outputs.tf

```hcl
# infra/terraform/outputs.tf

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.dns_name
}

output "application_url" {
  description = "Application URL"
  value       = module.alb.application_url
}

output "backend_target_group_arn" {
  description = "Backend target group ARN (for ECS service)"
  value       = module.alb.backend_target_group_arn
}

output "frontend_target_group_arn" {
  description = "Frontend target group ARN (for ECS service)"
  value       = module.alb.frontend_target_group_arn
}
```

---

## 5. Listener Rules Deep Dive

### Priority

Lower number = higher priority:

```hcl
# Priority 100 - API routes (checked first)
resource "aws_lb_listener_rule" "api" {
  priority = 100
  ...
}

# Priority 200 - Static files
resource "aws_lb_listener_rule" "static" {
  priority = 200
  ...
}

# Default action (lowest priority) - Everything else
```

### Multiple Conditions

```hcl
resource "aws_lb_listener_rule" "api_authenticated" {
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 50
  
  # Must match BOTH conditions
  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
  
  condition {
    http_header {
      http_header_name = "X-Custom-Header"
      values           = ["expected-value"]
    }
  }
  
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}
```

### Weighted Target Groups

```hcl
# Blue-green or canary deployments
resource "aws_lb_listener_rule" "weighted" {
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 100
  
  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
  
  action {
    type = "forward"
    
    forward {
      target_group {
        arn    = aws_lb_target_group.backend_blue.arn
        weight = 90  # 90% to blue
      }
      target_group {
        arn    = aws_lb_target_group.backend_green.arn
        weight = 10  # 10% to green
      }
      
      stickiness {
        enabled  = true
        duration = 3600
      }
    }
  }
}
```

---

## 6. Testing

```bash
terraform plan \
  -var="vpc_id=vpc-xxx" \
  -var="public_subnet_ids=[\"subnet-1\",\"subnet-2\"]" \
  -var="private_subnet_ids=[\"subnet-3\"]" \
  -var="resource_owner=your.email@thomsonreuters.com"
```

### Expected Output

```
  # module.alb.aws_lb.main will be created
  + resource "aws_lb" "main" {
      + name               = "maia-alb-dev"
      + load_balancer_type = "application"
      ...
    }

  # module.alb.aws_lb_target_group.backend will be created
  # module.alb.aws_lb_target_group.frontend will be created
  # module.alb.aws_lb_listener.http will be created

Plan: 4 to add, 0 to change, 0 to destroy.
```

---

## 7. Key Takeaways

1. **ALB is internet-facing** - Placed in public subnets
2. **Target groups are IP-based** - Required for Fargate
3. **Listeners handle traffic** - HTTP (80), HTTPS (443)
4. **Listener rules route traffic** - Path-based routing to services
5. **Dynamic blocks** - For optional configuration
6. **Lifecycle create_before_destroy** - Prevent downtime

---

## Next Steps

Continue to [Phase 08: ECS Cluster](./08-ECS-CLUSTER.md) to create the ECS cluster and IAM roles.
