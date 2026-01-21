# Phase 04: TR Compliance Module

## Learning Objectives

- Understand Terraform modules and why they're useful
- Learn module structure and best practices
- Use your existing TR compliance module
- Create reusable infrastructure patterns

---

## 1. What is a Terraform Module?

A module is a **container for multiple resources** that are used together. Every Terraform configuration is technically a module (the "root module").

### Module Benefits

| Benefit | Description |
|---------|-------------|
| **Reusability** | Write once, use many times |
| **Abstraction** | Hide complexity behind simple interface |
| **Consistency** | Ensure standards (like TR tagging) are always applied |
| **Testing** | Test modules independently |
| **Versioning** | Track changes and maintain versions |

### Comparison with Pulumi

```python
# Pulumi - Python class
class TRCompliance:
    def __init__(self, environment, resource_owner):
        self.tags = {
            "tr:environment-type": environment,
            "tr:resource-owner": resource_owner
        }
    
    def get_tags(self, additional_tags={}):
        return {**self.tags, **additional_tags}
```

```hcl
# Terraform - Module
module "tr_compliance" {
  source = "./modules/tr_compliance"
  
  environment_type = var.environment
  resource_owner   = var.resource_owner
}

# Use tags
tags = module.tr_compliance.all_tags
```

---

## 2. Module Structure

A Terraform module has this structure:

```
modules/
└── tr_compliance/
    ├── variables.tf   # Input variables (like function parameters)
    ├── locals.tf      # Computed values (like private methods)
    ├── outputs.tf     # Output values (like return values)
    ├── main.tf        # Resources (if any)
    └── README.md      # Documentation
```

### You Already Have This!

Your existing TR compliance module:

```
infra/terraform/modules/tr_compliance/
├── variables.tf   # 126 lines - input variables
├── locals.tf      # 70 lines - tag computation
└── outputs.tf     # 61 lines - tag outputs
```

---

## 3. Review Your TR Compliance Module

### variables.tf - Inputs

```hcl
# Required inputs
variable "environment_type" {
  description = "Internal environment type (DEV, QA, STAGING, PROD)"
  type        = string
  validation {
    condition     = contains(["DEV", "QA", "STAGING", "PROD"], var.environment_type)
    error_message = "Environment type must be one of: DEV, QA, STAGING, PROD"
  }
}

variable "resource_owner" {
  description = "Email address of team responsible for the resource"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.resource_owner))
    error_message = "Resource owner must be a valid email address"
  }
}

# Optional inputs with defaults
variable "tr_account_id" {
  description = "TR AWS Account ID"
  type        = string
  default     = "292899125550"
}

variable "resource_name" {
  description = "Name of the resource"
  type        = string
  default     = null  # Will be computed if not provided
}
```

### locals.tf - Computations

```hcl
locals {
  # Map internal environment to TR standard
  tr_environment_type = {
    "DEV"     = "DEVELOPMENT"
    "QA"      = "QUALITY ASSURANCE"
    "STAGING" = "PRE-PRODUCTION"
    "PROD"    = "PRODUCTION"
  }[var.environment_type]

  # Mandatory tags (all AWS resources must have these)
  mandatory_tags = {
    "tr:application-asset-insight-id" = local.asset_id
    "tr:resource-owner"               = var.resource_owner
    "tr:environment-type"             = local.tr_environment_type
    "Name"                            = local.computed_resource_name
  }

  # Combine all tags
  all_tags = merge(
    local.mandatory_tags,
    local.recommended_tags,
    local.optional_tags,
    local.informational_tags,
    var.additional_tags
  )
}
```

### outputs.tf - Exports

```hcl
output "all_tags" {
  description = "All TR-compliant tags merged together"
  value       = local.all_tags
}

output "mandatory_tags" {
  description = "Only mandatory TR tags"
  value       = local.mandatory_tags
}

output "permission_boundary_arn" {
  description = "ARN of the TR permission boundary"
  value       = local.permission_boundary_arn
}
```

---

## 4. Using the Module

### In Your Root Module (main.tf)

```hcl
# infra/terraform/main.tf

# =============================================================================
# TR Compliance Module
# =============================================================================
# This module provides consistent tagging across all resources

module "tr_compliance" {
  source = "./modules/tr_compliance"
  
  # Required
  environment_type = var.environment
  resource_owner   = var.resource_owner
  
  # Optional customization
  resource_name       = "maia-${lower(var.environment)}"
  data_classification = "INTERNAL USE"
  service_name        = "maia-platform"
  
  # Extra tags
  additional_tags = merge(var.additional_tags, {
    "Application" = "MAIA"
  })
}

# =============================================================================
# Use Tags in Resources
# =============================================================================

resource "aws_s3_bucket" "uploads" {
  bucket = "maia-uploads-${lower(var.environment)}"
  
  # Use the module's tags
  tags = merge(module.tr_compliance.all_tags, {
    "Purpose" = "File uploads"
  })
}

resource "aws_ecs_cluster" "main" {
  name = "maia-cluster-${lower(var.environment)}"
  tags = module.tr_compliance.all_tags
}
```

---

## 5. Module Design Patterns

### Pattern 1: Tag-Only Module (What You Have)

Returns computed values, doesn't create resources.

```hcl
# Module only computes tags
module "tags" {
  source = "./modules/tr_compliance"
  ...
}

# Tags used by resources in root module
resource "aws_s3_bucket" "example" {
  tags = module.tags.all_tags
}
```

### Pattern 2: Resource Module

Creates and manages resources.

```hcl
# Module creates complete resources
module "alb" {
  source = "./modules/alb"
  
  name       = "maia-alb"
  vpc_id     = var.vpc_id
  subnet_ids = var.public_subnet_ids
  tags       = module.tr_compliance.all_tags
}

# Use outputs from module
output "alb_dns" {
  value = module.alb.dns_name
}
```

### Pattern 3: Composed Modules

Modules that use other modules.

```hcl
# modules/infrastructure/main.tf
module "tags" {
  source = "../tr_compliance"
  ...
}

module "security_groups" {
  source = "../security_groups"
  tags   = module.tags.all_tags
}

module "alb" {
  source             = "../alb"
  security_group_ids = [module.security_groups.alb_sg_id]
  tags               = module.tags.all_tags
}
```

---

## 6. Creating a New Module: Security Groups

Let's create a security groups module step by step.

### Directory Structure

```bash
mkdir -p infra/terraform/modules/security_groups
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
  description = "Environment name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_https" {
  description = "Enable HTTPS ingress on ALB security group"
  type        = bool
  default     = false
}

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
```

### modules/security_groups/main.tf

```hcl
# ============================================================================
# Security Groups Module - Main
# ============================================================================

locals {
  name_prefix = "maia-${lower(var.environment)}"
}

# -----------------------------------------------------------------------------
# ALB Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id
  
  tags = merge(var.tags, {
    Name      = "${local.name_prefix}-alb-sg"
    Component = "ALB"
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
  
  tags = { Name = "HTTP" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count = var.enable_https ? 1 : 0
  
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from anywhere"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
  
  tags = { Name = "HTTPS" }
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  
  tags = { Name = "All-Outbound" }
}

# -----------------------------------------------------------------------------
# Backend ECS Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "backend_ecs" {
  name        = "${local.name_prefix}-backend-ecs-sg"
  description = "Security group for Backend ECS tasks"
  vpc_id      = var.vpc_id
  
  tags = merge(var.tags, {
    Name      = "${local.name_prefix}-backend-ecs-sg"
    Component = "Backend"
  })
}

resource "aws_vpc_security_group_ingress_rule" "backend_from_alb" {
  security_group_id            = aws_security_group.backend_ecs.id
  description                  = "Traffic from ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.backend_container_port
  to_port                      = var.backend_container_port
  referenced_security_group_id = aws_security_group.alb.id
  
  tags = { Name = "From-ALB" }
}

resource "aws_vpc_security_group_egress_rule" "backend_all" {
  security_group_id = aws_security_group.backend_ecs.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  
  tags = { Name = "All-Outbound" }
}

# -----------------------------------------------------------------------------
# Frontend ECS Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "frontend_ecs" {
  name        = "${local.name_prefix}-frontend-ecs-sg"
  description = "Security group for Frontend ECS tasks"
  vpc_id      = var.vpc_id
  
  tags = merge(var.tags, {
    Name      = "${local.name_prefix}-frontend-ecs-sg"
    Component = "Frontend"
  })
}

resource "aws_vpc_security_group_ingress_rule" "frontend_from_alb" {
  security_group_id            = aws_security_group.frontend_ecs.id
  description                  = "Traffic from ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.frontend_container_port
  to_port                      = var.frontend_container_port
  referenced_security_group_id = aws_security_group.alb.id
  
  tags = { Name = "From-ALB" }
}

resource "aws_vpc_security_group_egress_rule" "frontend_all" {
  security_group_id = aws_security_group.frontend_ecs.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  
  tags = { Name = "All-Outbound" }
}
```

### modules/security_groups/outputs.tf

```hcl
# ============================================================================
# Security Groups Module - Outputs
# ============================================================================

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "backend_ecs_security_group_id" {
  description = "ID of the backend ECS security group"
  value       = aws_security_group.backend_ecs.id
}

output "frontend_ecs_security_group_id" {
  description = "ID of the frontend ECS security group"
  value       = aws_security_group.frontend_ecs.id
}

output "all_security_group_ids" {
  description = "Map of all security group IDs"
  value = {
    alb          = aws_security_group.alb.id
    backend_ecs  = aws_security_group.backend_ecs.id
    frontend_ecs = aws_security_group.frontend_ecs.id
  }
}
```

---

## 7. Using the New Module

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
  
  enable_https            = var.alb_acm_certificate_arn != null
  backend_container_port  = 8000
  frontend_container_port = 80
}

# Use in ALB
resource "aws_lb" "main" {
  name            = "maia-alb-${lower(var.environment)}"
  security_groups = [module.security_groups.alb_security_group_id]
  subnets         = var.public_subnet_ids
  tags            = module.tr_compliance.all_tags
}
```

---

## 8. Module Best Practices

### 1. Keep Modules Focused

```hcl
# GOOD - Single responsibility
module "security_groups" { ... }
module "alb" { ... }
module "ecs" { ... }

# BAD - Module does too much
module "everything" { ... }
```

### 2. Use Consistent Naming

```hcl
# Variables: snake_case
variable "vpc_id" {}
variable "subnet_ids" {}

# Outputs: snake_case
output "security_group_id" {}

# Resources: snake_case with prefix
resource "aws_security_group" "alb" {}
```

### 3. Document with README

```markdown
# Security Groups Module

Creates security groups for MAIA application.

## Usage

```hcl
module "security_groups" {
  source      = "./modules/security_groups"
  vpc_id      = "vpc-123"
  environment = "DEV"
  tags        = { "Owner" = "team@example.com" }
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| vpc_id | VPC ID | string | yes |

## Outputs

| Name | Description |
|------|-------------|
| alb_security_group_id | ALB security group ID |
```

### 4. Version Your Modules

For shared modules, use Git tags:

```hcl
module "tr_compliance" {
  source = "git::https://github.com/org/terraform-modules.git//tr_compliance?ref=v1.2.0"
}
```

---

## 9. Key Takeaways

1. **Modules = Reusable containers** for related resources
2. **Structure**: variables.tf → locals.tf → main.tf → outputs.tf
3. **Use your TR compliance module** for consistent tagging
4. **Pass tags as input** to other modules
5. **Keep modules focused** on single responsibility
6. **Document** your modules with README.md

---

## Next Steps

Continue to [Phase 05: Security Groups](./05-SECURITY-GROUPS.md) to implement the security groups module for real.
