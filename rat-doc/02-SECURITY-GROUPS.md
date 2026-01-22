# Phase 02: Security Groups Module

Create security groups for ALB, ECS services, and databases.

## Pulumi Reference

From `infra/pulumi/modules/security_groups.py`:
```python
def create_alb_security_group(name, vpc_id, allow_https, tags, opts):
    # Creates SG with HTTP/HTTPS ingress
```

## Step 1: Create Module Structure

```bash
mkdir -p infra/terraform/modules/security_groups
```

## Step 2: Create variables.tf

`modules/security_groups/variables.tf`:

```hcl
variable "vpc_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "enable_https" {
  type    = bool
  default = false
}

variable "backend_port" {
  type    = number
  default = 8000
}

variable "frontend_port" {
  type    = number
  default = 80
}

variable "create_rds_sg" {
  type    = bool
  default = false
}

variable "create_redis_sg" {
  type    = bool
  default = false
}
```

## Step 3: Create main.tf

`modules/security_groups/main.tf`:

```hcl
locals {
  name_prefix = "maia-${lower(var.environment)}"
}

# =============================================================================
# ALB Security Group
# =============================================================================

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB security group"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-alb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count             = var.enable_https ? 1 : 0
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# =============================================================================
# Backend ECS Security Group
# =============================================================================

resource "aws_security_group" "backend" {
  name        = "${local.name_prefix}-backend-sg"
  description = "Backend ECS security group"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-backend-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "backend_from_alb" {
  security_group_id            = aws_security_group.backend.id
  description                  = "From ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.backend_port
  to_port                      = var.backend_port
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "backend_all" {
  security_group_id = aws_security_group.backend.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# =============================================================================
# Frontend ECS Security Group
# =============================================================================

resource "aws_security_group" "frontend" {
  name        = "${local.name_prefix}-frontend-sg"
  description = "Frontend ECS security group"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-frontend-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "frontend_from_alb" {
  security_group_id            = aws_security_group.frontend.id
  description                  = "From ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.frontend_port
  to_port                      = var.frontend_port
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "frontend_all" {
  security_group_id = aws_security_group.frontend.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# =============================================================================
# RDS Security Group (Optional)
# =============================================================================

resource "aws_security_group" "rds" {
  count       = var.create_rds_sg ? 1 : 0
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS security group"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_backend" {
  count                        = var.create_rds_sg ? 1 : 0
  security_group_id            = aws_security_group.rds[0].id
  description                  = "PostgreSQL from backend"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.backend.id
}

resource "aws_vpc_security_group_egress_rule" "rds_all" {
  count             = var.create_rds_sg ? 1 : 0
  security_group_id = aws_security_group.rds[0].id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
```

## Step 4: Create outputs.tf

`modules/security_groups/outputs.tf`:

```hcl
output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "backend_sg_id" {
  value = aws_security_group.backend.id
}

output "frontend_sg_id" {
  value = aws_security_group.frontend.id
}

output "rds_sg_id" {
  value = var.create_rds_sg ? aws_security_group.rds[0].id : null
}
```

## Step 5: Use in main.tf

Update `infra/terraform/main.tf`:

```hcl
module "security_groups" {
  source = "./modules/security_groups"

  vpc_id       = var.vpc_id
  environment  = var.environment
  tags         = module.tr_compliance.all_tags
  enable_https = var.alb_certificate_arn != null
  create_rds_sg = var.create_rds
}
```

## Step 6: Test

```bash
terraform plan
# Should show security groups to create
```

---

**Next:** [Phase 03: Storage](./03-STORAGE.md)
