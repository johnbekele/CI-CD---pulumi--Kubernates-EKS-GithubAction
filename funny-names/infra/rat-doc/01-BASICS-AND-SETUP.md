# Phase 01: Terraform Basics & Setup

## Learning Objectives

- Understand what Terraform is and how it works
- Install Terraform
- Learn HCL (HashiCorp Configuration Language) syntax
- Create your first Terraform configuration
- Understand the Terraform workflow

---

## 1. What is Terraform?

Terraform is an **Infrastructure as Code (IaC)** tool that lets you define cloud resources in human-readable configuration files. Unlike Pulumi (which uses Python), Terraform uses its own language called **HCL** (HashiCorp Configuration Language).

### Key Concepts

| Concept | Description | Pulumi Equivalent |
|---------|-------------|-------------------|
| **Provider** | Plugin that talks to cloud APIs | `pulumi_aws` package |
| **Resource** | A single infrastructure object | `aws.s3.Bucket()` |
| **Module** | Reusable group of resources | Python class/function |
| **State** | Record of managed infrastructure | Pulumi state file |
| **Plan** | Preview of changes | `pulumi preview` |
| **Apply** | Execute changes | `pulumi up` |

---

## 2. Install Terraform

### Linux (Ubuntu/Debian)

```bash
# Add HashiCorp GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Add repository
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Install
sudo apt update && sudo apt install terraform
```

### macOS

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

### Verify Installation

```bash
terraform version
# Output: Terraform v1.x.x
```

---

## 3. HCL Syntax Basics

HCL is declarative - you describe **what** you want, not **how** to create it.

### Basic Structure

```hcl
# This is a comment

# Block type with label(s)
resource "aws_s3_bucket" "my_bucket" {
  # Arguments
  bucket = "my-unique-bucket-name"
  
  # Nested block
  tags = {
    Name        = "My Bucket"
    Environment = "dev"
  }
}
```

### Comparison with Pulumi Python

```python
# Pulumi (Python)
bucket = aws.s3.Bucket(
    "my_bucket",
    bucket="my-unique-bucket-name",
    tags={
        "Name": "My Bucket",
        "Environment": "dev"
    }
)
```

```hcl
# Terraform (HCL)
resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-unique-bucket-name"
  
  tags = {
    Name        = "My Bucket"
    Environment = "dev"
  }
}
```

### Data Types

```hcl
# String
name = "hello"

# Number
count = 42

# Boolean
enabled = true

# List
subnets = ["subnet-1", "subnet-2", "subnet-3"]

# Map (object)
tags = {
  Name = "example"
  Env  = "dev"
}
```

### References

```hcl
# Reference another resource
resource "aws_security_group" "alb" {
  name   = "alb-sg"
  vpc_id = var.vpc_id  # Reference a variable
}

resource "aws_lb" "main" {
  name            = "my-alb"
  security_groups = [aws_security_group.alb.id]  # Reference the SG above
  subnets         = var.public_subnet_ids
}
```

---

## 4. Project Setup

### Create the Directory Structure

```bash
cd /home/john/MAIA/maia/infra/terraform

# You should already have:
# - provider.tf
# - main.tf
# - modules/tr_compliance/
```

### Current provider.tf (Review)

Your existing `provider.tf`:

```hcl
terraform {
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.region
}
```

### Create variables.tf

Create the main variables file:

```hcl
# infra/terraform/variables.tf

# ============================================================================
# Core Variables
# ============================================================================

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (DEV, QA, STAGING, PROD)"
  type        = string
  default     = "DEV"
  
  validation {
    condition     = contains(["DEV", "QA", "STAGING", "PROD"], var.environment)
    error_message = "Environment must be one of: DEV, QA, STAGING, PROD"
  }
}

variable "resource_owner" {
  description = "Email of the resource owner (TR requirement)"
  type        = string
}

# ============================================================================
# Network Variables (from SSM at runtime)
# ============================================================================

variable "vpc_id" {
  description = "VPC ID where resources will be created"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}
```

### Create terraform.tfvars.example

```hcl
# infra/terraform/terraform.tfvars.example
# Copy this to terraform.tfvars and fill in your values

region         = "us-east-1"
environment    = "DEV"
resource_owner = "your.email@thomsonreuters.com"

# These will be set at runtime from SSM parameters
# vpc_id             = "vpc-xxx"
# public_subnet_ids  = ["subnet-xxx", "subnet-yyy"]
# private_subnet_ids = ["subnet-aaa", "subnet-bbb"]
```

---

## 5. The Terraform Workflow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Write     │────▶│    Init     │────▶│    Plan     │────▶│   Apply     │
│   Code      │     │             │     │             │     │             │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
     │                    │                   │                   │
     │                    │                   │                   │
     ▼                    ▼                   ▼                   ▼
  .tf files          Downloads           Shows what         Creates/
                     providers           will change        updates
                                                           resources
```

### Step 1: Initialize

```bash
cd infra/terraform
terraform init
```

This downloads the AWS provider and initializes the backend.

**Output:**
```
Initializing the backend...
Initializing provider plugins...
- Finding latest version of hashicorp/aws...
- Installing hashicorp/aws v5.x.x...

Terraform has been successfully initialized!
```

### Step 2: Format (Optional but Recommended)

```bash
terraform fmt
```

Auto-formats your `.tf` files to canonical style.

### Step 3: Validate

```bash
terraform validate
```

Checks syntax and configuration validity.

### Step 4: Plan

```bash
terraform plan
```

Shows what changes Terraform will make. **Always review before applying!**

### Step 5: Apply

```bash
terraform apply
```

Executes the changes. Type `yes` to confirm.

---

## 6. Hands-On Exercise

Let's create a simple S3 bucket to verify everything works.

### Create a test file

Create `infra/terraform/test_bucket.tf`:

```hcl
# Temporary test file - DELETE after testing
resource "aws_s3_bucket" "test" {
  bucket = "maia-terraform-test-${random_id.suffix.hex}"
  
  tags = {
    Name        = "Terraform Test Bucket"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

output "test_bucket_name" {
  value = aws_s3_bucket.test.id
}
```

### Run Terraform

```bash
# Initialize (downloads random provider)
terraform init

# See what will be created
terraform plan -var="vpc_id=vpc-placeholder" -var='public_subnet_ids=["subnet-1"]' -var='private_subnet_ids=["subnet-1"]' -var="resource_owner=your.email@thomsonreuters.com"

# Create the bucket
terraform apply -var="vpc_id=vpc-placeholder" -var='public_subnet_ids=["subnet-1"]' -var='private_subnet_ids=["subnet-1"]' -var="resource_owner=your.email@thomsonreuters.com"

# Verify in AWS Console or CLI
aws s3 ls | grep maia-terraform-test

# Clean up
terraform destroy -var="vpc_id=vpc-placeholder" -var='public_subnet_ids=["subnet-1"]' -var='private_subnet_ids=["subnet-1"]' -var="resource_owner=your.email@thomsonreuters.com"

# Delete test file
rm test_bucket.tf
```

---

## 7. Common Mistakes & Tips

### Mistake 1: Forgetting to Initialize

```bash
# Error: "Provider registry.terraform.io/hashicorp/aws is not available"
# Solution: Run terraform init
```

### Mistake 2: Hardcoding Values

```hcl
# BAD - hardcoded
bucket = "my-bucket-dev"

# GOOD - using variables
bucket = "my-bucket-${var.environment}"
```

### Mistake 3: Not Using terraform plan

Always run `terraform plan` before `terraform apply` to avoid surprises!

### Tip: Enable Tab Completion

```bash
terraform -install-autocomplete
```

---

## 8. Key Takeaways

1. **Terraform uses HCL** - declarative language similar to JSON/YAML
2. **Workflow**: Write → Init → Plan → Apply
3. **Always plan first** - review changes before applying
4. **State is important** - Terraform tracks what it manages (more in Phase 02)
5. **Use variables** - don't hardcode values

---

## Next Steps

Continue to [Phase 02: State & Backend](./02-STATE-AND-BACKEND.md) to learn about Terraform state management and setting up a remote backend.
