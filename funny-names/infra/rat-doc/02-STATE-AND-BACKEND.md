# Phase 02: State & Backend Configuration

## Learning Objectives

- Understand what Terraform state is and why it matters
- Configure S3 backend for remote state storage
- Set up DynamoDB for state locking
- Learn state management commands

---

## 1. What is Terraform State?

Terraform state is a **JSON file** that maps your configuration to real-world resources. It's how Terraform knows:

- What resources it manages
- Current configuration of those resources
- Dependencies between resources

### Local State (Default)

By default, state is stored locally in `terraform.tfstate`:

```
infra/terraform/
├── main.tf
├── terraform.tfstate      # State file (contains sensitive data!)
└── terraform.tfstate.backup
```

**Problems with local state:**
- ❌ Can't collaborate with team members
- ❌ State contains secrets (passwords, keys)
- ❌ No locking - concurrent runs can corrupt state
- ❌ Easy to lose (not backed up)

### Remote State (Recommended)

Store state in S3 with DynamoDB for locking:

```
┌─────────────────┐         ┌─────────────────┐
│  Your Machine   │         │      AWS        │
│                 │         │                 │
│  terraform.tf   │◄───────▶│  S3 Bucket      │
│                 │         │  (state file)   │
│                 │         │                 │
│                 │◄───────▶│  DynamoDB       │
│                 │         │  (lock table)   │
└─────────────────┘         └─────────────────┘
```

**Benefits:**
- ✅ Team collaboration
- ✅ State encryption at rest
- ✅ Locking prevents concurrent modifications
- ✅ Automatic backups via S3 versioning

---

## 2. Comparison: Pulumi vs Terraform State

| Aspect | Pulumi (Your Current Setup) | Terraform |
|--------|----------------------------|-----------|
| State Location | `s3://a209309-maia-pulumi-state-*` | S3 bucket (we'll create) |
| Encryption | Passphrase | S3 SSE (at rest) |
| Locking | Built into Pulumi | DynamoDB table |
| State Command | `pulumi stack export` | `terraform state list` |

---

## 3. Create State Backend Resources

Before configuring the backend, we need to create the S3 bucket and DynamoDB table. This is a **chicken-and-egg problem** - we'll create them manually first.

### Option A: Using AWS CLI (Recommended for Learning)

```bash
# Set variables
ACCOUNT_ID="292899125550"
REGION="us-east-1"
BUCKET_NAME="a209309-maia-terraform-state"
DYNAMODB_TABLE="maia-terraform-locks"

# Create S3 bucket for state
aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region $REGION

# Enable versioning (important for state recovery)
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration '{
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
  }'

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name $DYNAMODB_TABLE \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $REGION

# Add tags (TR compliance)
aws s3api put-bucket-tagging \
  --bucket $BUCKET_NAME \
  --tagging '{
    "TagSet": [
      {"Key": "tr:application-asset-insight-id", "Value": "209191"},
      {"Key": "tr:resource-owner", "Value": "yohans.bekele@thomsonreuters.com"},
      {"Key": "tr:environment-type", "Value": "DEVELOPMENT"},
      {"Key": "Name", "Value": "maia-terraform-state"},
      {"Key": "ManagedBy", "Value": "Manual"}
    ]
  }'

aws dynamodb tag-resource \
  --resource-arn "arn:aws:dynamodb:$REGION:$ACCOUNT_ID:table/$DYNAMODB_TABLE" \
  --tags Key=tr:application-asset-insight-id,Value=209191 \
         Key=tr:resource-owner,Value=yohans.bekele@thomsonreuters.com \
         Key=tr:environment-type,Value=DEVELOPMENT \
         Key=Name,Value=maia-terraform-locks \
         Key=ManagedBy,Value=Manual
```

### Option B: Using Terraform (Bootstrap Pattern)

Create a separate bootstrap directory:

```bash
mkdir -p infra/terraform-bootstrap
```

Create `infra/terraform-bootstrap/main.tf`:

```hcl
# Bootstrap configuration - creates state backend resources
# Run this ONCE manually, then configure backend in main terraform

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  bucket_name    = "a209309-maia-terraform-state"
  dynamodb_table = "maia-terraform-locks"
  
  tags = {
    "tr:application-asset-insight-id" = "209191"
    "tr:resource-owner"               = "yohans.bekele@thomsonreuters.com"
    "tr:environment-type"             = "DEVELOPMENT"
    "ManagedBy"                       = "Terraform-Bootstrap"
  }
}

# S3 Bucket for Terraform State
resource "aws_s3_bucket" "terraform_state" {
  bucket = local.bucket_name
  tags   = merge(local.tags, { Name = local.bucket_name })
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB Table for State Locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = local.dynamodb_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  
  attribute {
    name = "LockID"
    type = "S"
  }
  
  tags = merge(local.tags, { Name = local.dynamodb_table })
}

# Outputs
output "state_bucket_name" {
  value = aws_s3_bucket.terraform_state.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.terraform_locks.name
}

output "backend_config" {
  value = <<-EOT
    
    # Add this to your provider.tf:
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.terraform_state.id}"
        key            = "maia/terraform.tfstate"
        region         = "us-east-1"
        encrypt        = true
        dynamodb_table = "${aws_dynamodb_table.terraform_locks.name}"
      }
    }
  EOT
}
```

Run the bootstrap:

```bash
cd infra/terraform-bootstrap
terraform init
terraform apply
```

---

## 4. Configure Backend in Main Terraform

Now update your main `provider.tf`:

```hcl
# infra/terraform/provider.tf

terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  # Remote backend configuration
  backend "s3" {
    bucket         = "a209309-maia-terraform-state"
    key            = "maia/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "maia-terraform-locks"
  }
}

provider "aws" {
  region = var.region
  
  # Default tags applied to all resources
  default_tags {
    tags = {
      "tr:application-asset-insight-id" = "209191"
      "ManagedBy"                       = "Terraform"
    }
  }
}
```

### Initialize with New Backend

```bash
cd infra/terraform
terraform init
```

If you had existing local state, Terraform will ask to migrate it:

```
Initializing the backend...
Do you want to copy existing state to the new backend?
  Enter a value: yes
```

---

## 5. State Management Commands

### List Resources in State

```bash
terraform state list
```

Output:
```
aws_s3_bucket.uploads
aws_security_group.alb
aws_lb.main
...
```

### Show Resource Details

```bash
terraform state show aws_s3_bucket.uploads
```

### Move Resource (Rename)

```bash
terraform state mv aws_s3_bucket.old_name aws_s3_bucket.new_name
```

### Remove from State (Without Destroying)

```bash
# Terraform will "forget" this resource but won't delete it
terraform state rm aws_s3_bucket.example
```

### Import Existing Resource

```bash
# Import an existing S3 bucket into Terraform management
terraform import aws_s3_bucket.uploads my-existing-bucket-name
```

---

## 6. Understanding State Locking

When you run `terraform apply`, it acquires a lock:

```
Acquiring state lock. This may take a few moments...
```

### What Happens with Locking

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  User A     │     │  DynamoDB   │     │  User B     │
│             │     │             │     │             │
│  terraform  │────▶│  Lock: A    │◀────│  terraform  │
│  apply      │     │             │     │  apply      │
│             │     │             │     │             │
│  ✅ Gets    │     │             │     │  ❌ Waits   │
│    lock     │     │             │     │    or fails │
└─────────────┘     └─────────────┘     └─────────────┘
```

### Force Unlock (Emergency Only!)

```bash
# Only use if lock is stuck and you're SURE no one else is running
terraform force-unlock LOCK_ID
```

---

## 7. Best Practices

### 1. Use Separate State Per Environment

```hcl
# DEV environment
backend "s3" {
  bucket = "a209309-maia-terraform-state"
  key    = "maia/dev/terraform.tfstate"  # Different key
  ...
}

# PROD environment
backend "s3" {
  bucket = "a209309-maia-terraform-state"
  key    = "maia/prod/terraform.tfstate"  # Different key
  ...
}
```

### 2. Enable S3 Versioning

Allows recovery from corrupted state:

```bash
# List state versions
aws s3api list-object-versions \
  --bucket a209309-maia-terraform-state \
  --prefix maia/terraform.tfstate

# Recover previous version
aws s3api get-object \
  --bucket a209309-maia-terraform-state \
  --key maia/terraform.tfstate \
  --version-id VERSION_ID \
  terraform.tfstate.backup
```

### 3. Never Edit State Manually

Use `terraform state` commands instead of editing the JSON directly.

### 4. Backup Before Major Changes

```bash
terraform state pull > backup-$(date +%Y%m%d).tfstate
```

---

## 8. Hands-On Exercise

### Verify Backend Configuration

```bash
cd infra/terraform

# Reinitialize with backend
terraform init

# Check where state is stored
terraform state list

# Pull state and examine
terraform state pull | head -50
```

### Test Locking

Open two terminals and try to run `terraform plan` simultaneously:

**Terminal 1:**
```bash
terraform plan -var-file=terraform.tfvars
```

**Terminal 2 (while Terminal 1 is running):**
```bash
terraform plan -var-file=terraform.tfvars
# Should wait or show "Error acquiring the state lock"
```

---

## 9. Key Takeaways

1. **State = Source of Truth** - Terraform uses state to track managed resources
2. **Remote State = Collaboration** - S3 backend enables team work
3. **Locking = Safety** - DynamoDB prevents concurrent modifications
4. **Versioning = Recovery** - S3 versioning allows state recovery
5. **Never Edit State Manually** - Use `terraform state` commands

---

## Next Steps

Continue to [Phase 03: Variables & Outputs](./03-VARIABLES-AND-OUTPUTS.md) to learn about parameterizing your configuration.
