# Phase 05: Security Groups

## Learning Objectives

- Understand AWS security groups in Terraform
- Create security groups with proper rules
- Use security group references for service-to-service communication
- Implement conditional resources with `count`

---

## 1. Security Groups Overview

Security groups act as **virtual firewalls** for your AWS resources. They control inbound and outbound traffic.

### MAIA Security Group Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Internet                                        │
│                                  │                                          │
│                          HTTP/HTTPS (80, 443)                               │
│                                  │                                          │
│                                  ▼                                          │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                    ALB Security Group                                 │  │
│  │  Ingress: 0.0.0.0/0 → 80, 443                                        │  │
│  │  Egress: All → Anywhere                                               │  │
│  └───────────────────────────┬───────────────────────────────────────────┘  │
│                              │                                              │
│              ┌───────────────┼───────────────┐                              │
│              │               │               │                              │
│              ▼               │               ▼                              │
│  ┌───────────────────┐       │   ┌───────────────────┐                      │
│  │   Frontend ECS    │       │   │   Backend ECS     │                      │
│  │  Security Group   │       │   │  Security Group   │                      │
│  │                   │       │   │                   │                      │
│  │  Ingress: ALB→80  │       │   │  Ingress: ALB→8000│                      │
│  │  Egress: All      │       │   │  Egress: All      │                      │
│  └───────────────────┘       │   └─────────┬─────────┘                      │
│                              │             │                                │
│                              │             ▼                                │
│                              │   ┌───────────────────┐                      │
│                              │   │   RDS Security    │                      │
│                              │   │      Group        │                      │
│                              │   │                   │                      │
│                              │   │  Ingress:         │                      │
│                              │   │  Backend ECS→5432 │                      │
│                              │   └───────────────────┘                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Terraform Security Group Resources

### AWS Provider v5+ (Recommended)

AWS provider v5+ uses separate resources for rules:

```hcl
# Security Group (container)
resource "aws_security_group" "alb" {
  name        = "maia-alb-sg"
  description = "ALB security group"
  vpc_id      = var.vpc_id
  
  tags = var.tags
}

# Ingress Rule (separate resource)
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.alb.id
  
  description = "HTTP from internet"
  ip_protocol = "tcp"
  from_port   = 80
  to_port     = 80
  cidr_ipv4   = "0.0.0.0/0"
}

# Egress Rule (separate resource)
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.alb.id
  
  description = "All outbound"
  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}
```

### Why Separate Resources?

1. **Clearer diffs** - See exactly which rules changed
2. **Individual tagging** - Tag each rule separately
3. **Better lifecycle** - Rules can be added/removed independently
4. **Avoid conflicts** - Multiple sources can manage different rules

---

## 3. Create the Security Groups Module

### File Structure

```bash
mkdir -p infra/terraform/modules/security_groups
touch infra/terraform/modules/security_groups/{variables,main,outputs}.tf
```

### modules/security_groups/variables.tf

```hcl
# ============================================================================
# Security Groups Module - Variables
# ============================================================================

variable "vpc_id" {
  description = "VPC ID where security groups will be created"
  type        = string
}

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
# ALB Configuration
# -----------------------------------------------------------------------------

variable "enable_https" {
  description = "Enable HTTPS (port 443) on ALB"
  type        = bool
  default     = false
}

variable "restrict_alb_to_cloudfront" {
  description = "Restrict ALB to only accept traffic from CloudFront"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# ECS Configuration
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

# -----------------------------------------------------------------------------
# Database Configuration (Optional)
# -----------------------------------------------------------------------------

variable "create_rds_security_group" {
  description = "Create security group for RDS"
  type        = bool
  default     = false
}

variable "rds_port" {
  description = "RDS PostgreSQL port"
  type        = number
  default     = 5432
}

# -----------------------------------------------------------------------------
# Redis Configuration (Optional)
# -----------------------------------------------------------------------------

variable "create_redis_security_group" {
  description = "Create security group for Redis"
  type        = bool
  default     = false
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}
```

### modules/security_groups/main.tf

```hcl
# ============================================================================
# Security Groups Module - Main
# ============================================================================

locals {
  # Consistent naming
  sg_name_prefix = "${var.name_prefix}-${lower(var.environment)}"
  
  # CloudFront prefix list for restricting ALB access
  # This is the AWS managed prefix list for CloudFront
  cloudfront_prefix_list_id = "pl-3b927c52"  # us-east-1
}

# =============================================================================
# ALB Security Group
# =============================================================================

resource "aws_security_group" "alb" {
  name        = "${local.sg_name_prefix}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id
  
  tags = merge(var.tags, {
    Name      = "${local.sg_name_prefix}-alb-sg"
    Component = "ALB"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# HTTP Ingress - Public (when not restricted to CloudFront)
resource "aws_vpc_security_group_ingress_rule" "alb_http_public" {
  count = var.restrict_alb_to_cloudfront ? 0 : 1
  
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
  
  tags = merge(var.tags, { Name = "HTTP-Public" })
}

# HTTP Ingress - CloudFront only
resource "aws_vpc_security_group_ingress_rule" "alb_http_cloudfront" {
  count = var.restrict_alb_to_cloudfront ? 1 : 0
  
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from CloudFront only"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = local.cloudfront_prefix_list_id
  
  tags = merge(var.tags, { Name = "HTTP-CloudFront" })
}

# HTTPS Ingress - Public (when not restricted to CloudFront)
resource "aws_vpc_security_group_ingress_rule" "alb_https_public" {
  count = var.enable_https && !var.restrict_alb_to_cloudfront ? 1 : 0
  
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
  
  tags = merge(var.tags, { Name = "HTTPS-Public" })
}

# HTTPS Ingress - CloudFront only
resource "aws_vpc_security_group_ingress_rule" "alb_https_cloudfront" {
  count = var.enable_https && var.restrict_alb_to_cloudfront ? 1 : 0
  
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from CloudFront only"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = local.cloudfront_prefix_list_id
  
  tags = merge(var.tags, { Name = "HTTPS-CloudFront" })
}

# Egress - All outbound
resource "aws_vpc_security_group_egress_rule" "alb_all_outbound" {
  security_group_id = aws_security_group.alb.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  
  tags = merge(var.tags, { Name = "All-Outbound" })
}

# =============================================================================
# Backend ECS Security Group
# =============================================================================

resource "aws_security_group" "backend_ecs" {
  name        = "${local.sg_name_prefix}-backend-ecs-sg"
  description = "Security group for Backend ECS tasks"
  vpc_id      = var.vpc_id
  
  tags = merge(var.tags, {
    Name      = "${local.sg_name_prefix}-backend-ecs-sg"
    Component = "Backend"
    Service   = "ECS"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Ingress from ALB
resource "aws_vpc_security_group_ingress_rule" "backend_from_alb" {
  security_group_id            = aws_security_group.backend_ecs.id
  description                  = "Traffic from ALB on container port"
  ip_protocol                  = "tcp"
  from_port                    = var.backend_container_port
  to_port                      = var.backend_container_port
  referenced_security_group_id = aws_security_group.alb.id
  
  tags = merge(var.tags, { Name = "From-ALB" })
}

# Egress - All outbound
resource "aws_vpc_security_group_egress_rule" "backend_all_outbound" {
  security_group_id = aws_security_group.backend_ecs.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  
  tags = merge(var.tags, { Name = "All-Outbound" })
}

# =============================================================================
# Frontend ECS Security Group
# =============================================================================

resource "aws_security_group" "frontend_ecs" {
  name        = "${local.sg_name_prefix}-frontend-ecs-sg"
  description = "Security group for Frontend ECS tasks"
  vpc_id      = var.vpc_id
  
  tags = merge(var.tags, {
    Name      = "${local.sg_name_prefix}-frontend-ecs-sg"
    Component = "Frontend"
    Service   = "ECS"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Ingress from ALB
resource "aws_vpc_security_group_ingress_rule" "frontend_from_alb" {
  security_group_id            = aws_security_group.frontend_ecs.id
  description                  = "Traffic from ALB on container port"
  ip_protocol                  = "tcp"
  from_port                    = var.frontend_container_port
  to_port                      = var.frontend_container_port
  referenced_security_group_id = aws_security_group.alb.id
  
  tags = merge(var.tags, { Name = "From-ALB" })
}

# Egress - All outbound
resource "aws_vpc_security_group_egress_rule" "frontend_all_outbound" {
  security_group_id = aws_security_group.frontend_ecs.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  
  tags = merge(var.tags, { Name = "All-Outbound" })
}

# =============================================================================
# RDS Security Group (Optional)
# =============================================================================

resource "aws_security_group" "rds" {
  count = var.create_rds_security_group ? 1 : 0
  
  name        = "${local.sg_name_prefix}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id
  
  tags = merge(var.tags, {
    Name      = "${local.sg_name_prefix}-rds-sg"
    Component = "RDS"
    Service   = "Database"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Ingress from Backend ECS
resource "aws_vpc_security_group_ingress_rule" "rds_from_backend" {
  count = var.create_rds_security_group ? 1 : 0
  
  security_group_id            = aws_security_group.rds[0].id
  description                  = "PostgreSQL from Backend ECS"
  ip_protocol                  = "tcp"
  from_port                    = var.rds_port
  to_port                      = var.rds_port
  referenced_security_group_id = aws_security_group.backend_ecs.id
  
  tags = merge(var.tags, { Name = "From-Backend" })
}

# Egress - All outbound (required for RDS)
resource "aws_vpc_security_group_egress_rule" "rds_all_outbound" {
  count = var.create_rds_security_group ? 1 : 0
  
  security_group_id = aws_security_group.rds[0].id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  
  tags = merge(var.tags, { Name = "All-Outbound" })
}

# =============================================================================
# Redis Security Group (Optional)
# =============================================================================

resource "aws_security_group" "redis" {
  count = var.create_redis_security_group ? 1 : 0
  
  name        = "${local.sg_name_prefix}-redis-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = var.vpc_id
  
  tags = merge(var.tags, {
    Name      = "${local.sg_name_prefix}-redis-sg"
    Component = "Redis"
    Service   = "Cache"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Ingress from Backend ECS
resource "aws_vpc_security_group_ingress_rule" "redis_from_backend" {
  count = var.create_redis_security_group ? 1 : 0
  
  security_group_id            = aws_security_group.redis[0].id
  description                  = "Redis from Backend ECS"
  ip_protocol                  = "tcp"
  from_port                    = var.redis_port
  to_port                      = var.redis_port
  referenced_security_group_id = aws_security_group.backend_ecs.id
  
  tags = merge(var.tags, { Name = "From-Backend" })
}

# Egress - All outbound
resource "aws_vpc_security_group_egress_rule" "redis_all_outbound" {
  count = var.create_redis_security_group ? 1 : 0
  
  security_group_id = aws_security_group.redis[0].id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  
  tags = merge(var.tags, { Name = "All-Outbound" })
}
```

### modules/security_groups/outputs.tf

```hcl
# ============================================================================
# Security Groups Module - Outputs
# ============================================================================

# -----------------------------------------------------------------------------
# ALB
# -----------------------------------------------------------------------------

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "alb_security_group_arn" {
  description = "ARN of the ALB security group"
  value       = aws_security_group.alb.arn
}

# -----------------------------------------------------------------------------
# Backend ECS
# -----------------------------------------------------------------------------

output "backend_ecs_security_group_id" {
  description = "ID of the backend ECS security group"
  value       = aws_security_group.backend_ecs.id
}

output "backend_ecs_security_group_arn" {
  description = "ARN of the backend ECS security group"
  value       = aws_security_group.backend_ecs.arn
}

# -----------------------------------------------------------------------------
# Frontend ECS
# -----------------------------------------------------------------------------

output "frontend_ecs_security_group_id" {
  description = "ID of the frontend ECS security group"
  value       = aws_security_group.frontend_ecs.id
}

output "frontend_ecs_security_group_arn" {
  description = "ARN of the frontend ECS security group"
  value       = aws_security_group.frontend_ecs.arn
}

# -----------------------------------------------------------------------------
# RDS (Optional)
# -----------------------------------------------------------------------------

output "rds_security_group_id" {
  description = "ID of the RDS security group (if created)"
  value       = var.create_rds_security_group ? aws_security_group.rds[0].id : null
}

output "rds_security_group_arn" {
  description = "ARN of the RDS security group (if created)"
  value       = var.create_rds_security_group ? aws_security_group.rds[0].arn : null
}

# -----------------------------------------------------------------------------
# Redis (Optional)
# -----------------------------------------------------------------------------

output "redis_security_group_id" {
  description = "ID of the Redis security group (if created)"
  value       = var.create_redis_security_group ? aws_security_group.redis[0].id : null
}

output "redis_security_group_arn" {
  description = "ARN of the Redis security group (if created)"
  value       = var.create_redis_security_group ? aws_security_group.redis[0].arn : null
}

# -----------------------------------------------------------------------------
# All Security Groups (for convenience)
# -----------------------------------------------------------------------------

output "all_security_group_ids" {
  description = "Map of all security group IDs"
  value = {
    alb          = aws_security_group.alb.id
    backend_ecs  = aws_security_group.backend_ecs.id
    frontend_ecs = aws_security_group.frontend_ecs.id
    rds          = var.create_rds_security_group ? aws_security_group.rds[0].id : null
    redis        = var.create_redis_security_group ? aws_security_group.redis[0].id : null
  }
}
```

---

## 4. Understanding Key Concepts

### Conditional Resources with `count`

```hcl
# Create resource only if condition is true
resource "aws_security_group" "rds" {
  count = var.create_rds_security_group ? 1 : 0  # 1 = create, 0 = skip
  ...
}

# Accessing conditional resource (must use index)
output "rds_sg_id" {
  value = var.create_rds_security_group ? aws_security_group.rds[0].id : null
}
```

### Security Group References

Instead of hardcoding IPs, reference other security groups:

```hcl
# Reference another security group as source
resource "aws_vpc_security_group_ingress_rule" "backend_from_alb" {
  security_group_id            = aws_security_group.backend_ecs.id
  referenced_security_group_id = aws_security_group.alb.id  # Source SG
  ...
}
```

This is more secure and maintainable than CIDR blocks.

### Lifecycle Rules

```hcl
resource "aws_security_group" "alb" {
  ...
  lifecycle {
    create_before_destroy = true  # Create new SG before destroying old one
  }
}
```

Prevents downtime during updates.

---

## 5. Using the Module

### In main.tf

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
  
  # ALB configuration
  enable_https               = var.alb_acm_certificate_arn != null
  restrict_alb_to_cloudfront = var.restrict_alb_to_cloudfront
  
  # ECS ports
  backend_container_port  = 8000
  frontend_container_port = 80
  
  # Optional databases
  create_rds_security_group   = var.create_rds
  create_redis_security_group = var.create_redis
}
```

---

## 6. Testing

### Plan the Changes

```bash
cd infra/terraform

terraform plan \
  -var="vpc_id=vpc-xxx" \
  -var="public_subnet_ids=[\"subnet-1\",\"subnet-2\"]" \
  -var="private_subnet_ids=[\"subnet-3\",\"subnet-4\"]" \
  -var="resource_owner=your.email@thomsonreuters.com"
```

### Expected Output

```
Terraform will perform the following actions:

  # module.security_groups.aws_security_group.alb will be created
  + resource "aws_security_group" "alb" {
      + name   = "maia-dev-alb-sg"
      + vpc_id = "vpc-xxx"
      ...
    }

  # module.security_groups.aws_vpc_security_group_ingress_rule.alb_http_public[0] will be created
  ...

Plan: 10 to add, 0 to change, 0 to destroy.
```

---

## 7. Key Takeaways

1. **Use separate rule resources** - Clearer diffs and better management
2. **Reference security groups** - More secure than CIDR blocks
3. **Use `count` for conditionals** - Create resources only when needed
4. **Use `lifecycle` rules** - Prevent downtime during updates
5. **Tag everything** - TR compliance and visibility
6. **Module outputs** - Make security group IDs available to other resources

---

## Next Steps

Continue to [Phase 06: Storage (S3 & ECR)](./06-STORAGE.md) to create storage resources for the application.
