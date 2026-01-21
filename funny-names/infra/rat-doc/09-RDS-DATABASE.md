# Phase 09: RDS Database (Optional)

## Learning Objectives

- Create an RDS PostgreSQL instance
- Configure DB subnet groups
- Store credentials in Secrets Manager
- Understand RDS parameter groups
- Handle sensitive data in Terraform

---

## 1. RDS Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          RDS Architecture                                    │
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                      Private Subnets                                   │  │
│  │                                                                        │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                     DB Subnet Group                              │  │  │
│  │  │              (spans multiple AZs)                               │  │  │
│  │  │                                                                  │  │  │
│  │  │   ┌─────────────────┐        ┌─────────────────┐               │  │  │
│  │  │   │   AZ-1          │        │   AZ-2          │               │  │  │
│  │  │   │                 │        │                 │               │  │  │
│  │  │   │  ┌───────────┐  │        │  ┌───────────┐  │               │  │  │
│  │  │   │  │    RDS    │  │        │  │   RDS     │  │               │  │  │
│  │  │   │  │  Primary  │◀─┼────────┼─▶│  Standby  │  │               │  │  │
│  │  │   │  │           │  │ Sync   │  │ (Multi-AZ)│  │               │  │  │
│  │  │   │  └───────────┘  │        │  └───────────┘  │               │  │  │
│  │  │   └─────────────────┘        └─────────────────┘               │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  │                           │                                            │  │
│  │                   ┌───────┴───────┐                                   │  │
│  │                   │   Security    │                                   │  │
│  │                   │    Group      │                                   │  │
│  │                   │               │                                   │  │
│  │                   │ Allow: 5432   │                                   │  │
│  │                   │ From: ECS SG  │                                   │  │
│  │                   └───────────────┘                                   │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                    Secrets Manager                                     │  │
│  │                                                                        │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │  Secret: maia/rds/credentials                                   │  │  │
│  │  │                                                                  │  │  │
│  │  │  {                                                               │  │  │
│  │  │    "username": "maia_admin",                                     │  │  │
│  │  │    "password": "...",                                            │  │  │
│  │  │    "host": "maia-db.xxx.us-east-1.rds.amazonaws.com",           │  │  │
│  │  │    "port": 5432,                                                 │  │  │
│  │  │    "database": "maia"                                            │  │  │
│  │  │  }                                                               │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Create RDS Module

### Directory Structure

```bash
mkdir -p infra/terraform/modules/rds
touch infra/terraform/modules/rds/{variables,main,outputs}.tf
```

### modules/rds/variables.tf

```hcl
# ============================================================================
# RDS Module - Variables
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
# Network Configuration
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for RDS"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for RDS"
  type        = string
}

# -----------------------------------------------------------------------------
# Database Configuration
# -----------------------------------------------------------------------------

variable "database_name" {
  description = "Name of the database to create"
  type        = string
  default     = "maia"
}

variable "master_username" {
  description = "Master username for RDS"
  type        = string
  default     = "maia_admin"
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum storage for autoscaling (0 to disable)"
  type        = number
  default     = 100
}

# -----------------------------------------------------------------------------
# High Availability
# -----------------------------------------------------------------------------

variable "multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Backup & Maintenance
# -----------------------------------------------------------------------------

variable "backup_retention_period" {
  description = "Days to retain backups (0 to disable)"
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "Preferred backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "Mon:04:00-Mon:05:00"
}

# -----------------------------------------------------------------------------
# Security
# -----------------------------------------------------------------------------

variable "storage_encrypted" {
  description = "Enable storage encryption"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when deleting"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Performance
# -----------------------------------------------------------------------------

variable "performance_insights_enabled" {
  description = "Enable Performance Insights"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention (7 for free tier)"
  type        = number
  default     = 7
}
```

### modules/rds/main.tf

```hcl
# ============================================================================
# RDS Module - Main
# ============================================================================

locals {
  db_identifier  = "${var.name_prefix}-db-${lower(var.environment)}"
  is_production  = var.environment == "PROD"
}

# =============================================================================
# Random Password Generation
# =============================================================================

resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# =============================================================================
# DB Subnet Group
# =============================================================================

resource "aws_db_subnet_group" "main" {
  name        = "${local.db_identifier}-subnet-group"
  description = "Subnet group for ${local.db_identifier}"
  subnet_ids  = var.private_subnet_ids
  
  tags = merge(var.tags, {
    Name      = "${local.db_identifier}-subnet-group"
    Component = "RDS"
  })
}

# =============================================================================
# DB Parameter Group
# =============================================================================

resource "aws_db_parameter_group" "main" {
  name        = "${local.db_identifier}-params"
  family      = "postgres15"
  description = "Parameter group for ${local.db_identifier}"
  
  # PostgreSQL optimizations
  parameter {
    name  = "log_statement"
    value = "ddl"
  }
  
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"  # Log queries taking > 1 second
  }
  
  # Connection settings
  parameter {
    name  = "max_connections"
    value = "100"
  }
  
  tags = merge(var.tags, {
    Name      = "${local.db_identifier}-params"
    Component = "RDS"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# RDS Instance
# =============================================================================

resource "aws_db_instance" "main" {
  identifier = local.db_identifier
  
  # Engine
  engine               = "postgres"
  engine_version       = var.engine_version
  instance_class       = var.instance_class
  
  # Storage
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage > 0 ? var.max_allocated_storage : null
  storage_type          = "gp3"
  storage_encrypted     = var.storage_encrypted
  
  # Database
  db_name  = var.database_name
  username = var.master_username
  password = random_password.master.result
  port     = 5432
  
  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false
  
  # Parameter group
  parameter_group_name = aws_db_parameter_group.main.name
  
  # High availability
  multi_az = local.is_production ? true : var.multi_az
  
  # Backup
  backup_retention_period = local.is_production ? max(7, var.backup_retention_period) : var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  
  # Protection
  deletion_protection = local.is_production ? true : var.deletion_protection
  skip_final_snapshot = local.is_production ? false : var.skip_final_snapshot
  final_snapshot_identifier = local.is_production ? "${local.db_identifier}-final-snapshot" : null
  
  # Monitoring
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period
  
  # Updates
  auto_minor_version_upgrade = true
  apply_immediately          = !local.is_production
  
  tags = merge(var.tags, {
    Name      = local.db_identifier
    Component = "RDS"
    Service   = "Database"
  })
  
  lifecycle {
    prevent_destroy = false  # Set to true in production
  }
}

# =============================================================================
# Secrets Manager - Store Credentials
# =============================================================================

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.name_prefix}/rds/credentials-${lower(var.environment)}"
  description = "RDS credentials for ${local.db_identifier}"
  
  # Allow recovery for 7 days in production
  recovery_window_in_days = local.is_production ? 7 : 0
  
  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-rds-credentials"
    Component = "Secrets"
  })
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    database = var.database_name
    engine   = "postgres"
    # Connection URL format for applications
    url      = "postgresql://${var.master_username}:${random_password.master.result}@${aws_db_instance.main.endpoint}/${var.database_name}"
  })
}

# =============================================================================
# CloudWatch Alarms (Optional)
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.db_identifier}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU utilization is high"
  
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
  
  tags = merge(var.tags, {
    Name = "${local.db_identifier}-cpu-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "storage_low" {
  alarm_name          = "${local.db_identifier}-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5000000000  # 5 GB in bytes
  alarm_description   = "RDS free storage space is low"
  
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
  
  tags = merge(var.tags, {
    Name = "${local.db_identifier}-storage-alarm"
  })
}
```

### modules/rds/outputs.tf

```hcl
# ============================================================================
# RDS Module - Outputs
# ============================================================================

# -----------------------------------------------------------------------------
# Instance
# -----------------------------------------------------------------------------

output "id" {
  description = "ID of the RDS instance"
  value       = aws_db_instance.main.id
}

output "arn" {
  description = "ARN of the RDS instance"
  value       = aws_db_instance.main.arn
}

output "identifier" {
  description = "Identifier of the RDS instance"
  value       = aws_db_instance.main.identifier
}

# -----------------------------------------------------------------------------
# Connection
# -----------------------------------------------------------------------------

output "endpoint" {
  description = "Connection endpoint (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "address" {
  description = "Hostname of the RDS instance"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "Port of the RDS instance"
  value       = aws_db_instance.main.port
}

output "database_name" {
  description = "Name of the database"
  value       = aws_db_instance.main.db_name
}

# -----------------------------------------------------------------------------
# Secrets
# -----------------------------------------------------------------------------

output "secret_arn" {
  description = "ARN of the Secrets Manager secret containing credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.db_credentials.name
}

# -----------------------------------------------------------------------------
# Connection URL (for ECS task definition)
# -----------------------------------------------------------------------------

output "connection_url_secret_ref" {
  description = "Reference for ECS to get connection URL from Secrets Manager"
  value       = "${aws_secretsmanager_secret.db_credentials.arn}:url::"
}

# -----------------------------------------------------------------------------
# Subnet Group
# -----------------------------------------------------------------------------

output "subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.main.name
}
```

---

## 3. Using the Module

### Update variables.tf

Add RDS-related variables:

```hcl
# infra/terraform/variables.tf

variable "create_rds" {
  description = "Create RDS PostgreSQL instance"
  type        = bool
  default     = false
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ for RDS"
  type        = bool
  default     = false
}
```

### Update main.tf

```hcl
# infra/terraform/main.tf

# ... previous modules ...

# RDS Database (Optional)
module "rds" {
  count  = var.create_rds ? 1 : 0
  source = "./modules/rds"
  
  environment        = var.environment
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  security_group_id  = module.security_groups.rds_security_group_id
  tags               = module.tr_compliance.all_tags
  
  # Database configuration
  database_name     = "maia"
  master_username   = "maia_admin"
  instance_class    = var.rds_instance_class
  allocated_storage = var.rds_allocated_storage
  multi_az          = var.rds_multi_az
  
  # Protection settings based on environment
  deletion_protection = var.environment == "PROD"
  skip_final_snapshot = var.environment != "PROD"
  
  # Backup
  backup_retention_period = var.environment == "PROD" ? 7 : 1
}
```

### Update outputs.tf

```hcl
# infra/terraform/outputs.tf

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = var.create_rds ? module.rds[0].endpoint : null
}

output "rds_secret_arn" {
  description = "RDS credentials secret ARN"
  value       = var.create_rds ? module.rds[0].secret_arn : null
  sensitive   = true
}
```

---

## 4. Accessing RDS from ECS

### In ECS Task Definition

```hcl
# Reference secret in ECS task definition
resource "aws_ecs_task_definition" "backend" {
  # ...
  
  container_definitions = jsonencode([
    {
      name  = "backend"
      image = "${module.storage.backend_repository_url}:latest"
      
      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = module.rds[0].connection_url_secret_ref
        }
      ]
      
      # ...
    }
  ])
}
```

---

## 5. Handling Sensitive Data

### Don't Commit tfvars with Secrets

```bash
# .gitignore
*.tfvars
!terraform.tfvars.example
```

### Use `sensitive = true`

```hcl
output "rds_secret_arn" {
  value     = aws_secretsmanager_secret.db_credentials.arn
  sensitive = true  # Won't show in logs
}
```

### State Contains Secrets

Remember: Terraform state contains the password! That's why remote state with encryption is critical.

---

## 6. Testing

```bash
# With RDS enabled
terraform plan \
  -var="vpc_id=vpc-xxx" \
  -var="public_subnet_ids=[\"subnet-1\",\"subnet-2\"]" \
  -var="private_subnet_ids=[\"subnet-3\",\"subnet-4\"]" \
  -var="resource_owner=your.email@thomsonreuters.com" \
  -var="create_rds=true"
```

---

## 7. Key Takeaways

1. **DB Subnet Group** spans multiple AZs for high availability
2. **Parameter Groups** configure PostgreSQL settings
3. **Secrets Manager** stores credentials securely
4. **Multi-AZ** provides automatic failover in production
5. **sensitive = true** prevents secrets in logs
6. **State contains secrets** - use encrypted remote state

---

## Next Steps

Continue to [Phase 10: CI/CD Integration](./10-CICD-INTEGRATION.md) to automate Terraform deployments with GitHub Actions.
