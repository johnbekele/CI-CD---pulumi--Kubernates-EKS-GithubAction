# Phase 10: CI/CD Integration

## Learning Objectives

- Integrate Terraform with GitHub Actions
- Set up automated planning and applying
- Configure environment-based deployments
- Use SSM parameters for dynamic configuration
- Implement approval workflows

---

## 1. CI/CD Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       GitHub Actions Workflow                                │
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                        Push to main                                    │  │
│  └───────────────────────────────┬───────────────────────────────────────┘  │
│                                  │                                          │
│                                  ▼                                          │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                      Get VPC Config from SSM                          │  │
│  │                                                                        │  │
│  │  • VPC ID                                                             │  │
│  │  • Private Subnets                                                    │  │
│  │  • Public Subnets                                                     │  │
│  └───────────────────────────────┬───────────────────────────────────────┘  │
│                                  │                                          │
│                                  ▼                                          │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                        Terraform Init                                  │  │
│  │                                                                        │  │
│  │  • Download providers                                                 │  │
│  │  • Configure S3 backend                                               │  │
│  └───────────────────────────────┬───────────────────────────────────────┘  │
│                                  │                                          │
│                                  ▼                                          │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                        Terraform Plan                                  │  │
│  │                                                                        │  │
│  │  • Show what will change                                              │  │
│  │  • Save plan to file                                                  │  │
│  │  • Post summary to PR                                                 │  │
│  └───────────────────────────────┬───────────────────────────────────────┘  │
│                                  │                                          │
│                    ┌─────────────┴─────────────┐                           │
│                    │     Environment Check      │                           │
│                    └─────────────┬─────────────┘                           │
│                                  │                                          │
│            ┌─────────────────────┼─────────────────────┐                   │
│            │                     │                     │                   │
│            ▼                     ▼                     ▼                   │
│    ┌───────────────┐    ┌───────────────┐    ┌───────────────┐           │
│    │     DEV       │    │      QA       │    │     PROD      │           │
│    │               │    │               │    │               │           │
│    │  Auto Apply   │    │  Auto Apply   │    │   Manual      │           │
│    │               │    │               │    │   Approval    │           │
│    └───────────────┘    └───────────────┘    └───────┬───────┘           │
│                                                      │                    │
│                                                      ▼                    │
│                                              ┌───────────────┐           │
│                                              │    Apply      │           │
│                                              └───────────────┘           │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. GitHub Actions Workflow

### Create `.github/workflows/terraform.yml`

```yaml
name: Terraform Deploy

on:
  push:
    branches:
      - main
    paths:
      - 'infra/terraform/**'
  pull_request:
    branches:
      - main
    paths:
      - 'infra/terraform/**'
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy'
        required: true
        default: 'DEV'
        type: choice
        options:
          - DEV
          - QA
          - PROD
      action:
        description: 'Terraform action'
        required: true
        default: 'plan'
        type: choice
        options:
          - plan
          - apply
          - destroy

env:
  AWS_REGION: us-east-1
  TF_DIR: infra/terraform
  # Terraform version
  TF_VERSION: 1.6.0

jobs:
  # ==========================================================================
  # Plan Job - Always runs
  # ==========================================================================
  plan:
    name: Terraform Plan
    runs-on:
      - codebuild-a209309-MAIA-Runner-${{ github.run_id }}-${{ github.run_attempt }}
    
    outputs:
      plan_exitcode: ${{ steps.plan.outputs.exitcode }}
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}
      
      # ========================================================================
      # Get VPC Configuration from SSM
      # ========================================================================
      - name: Get VPC Configuration
        id: vpc-config
        run: |
          echo "Getting VPC configuration from SSM..."
          
          VPC_ID=$(aws ssm get-parameter \
            --name "/a205257/cicd/tr-vpc-1-id" \
            --region ${{ env.AWS_REGION }} \
            --query "Parameter.Value" \
            --output text)
          echo "VPC_ID=$VPC_ID" >> $GITHUB_OUTPUT
          
          # Get subnets and convert to JSON array
          PRIVATE_SUBNETS_RAW=$(aws ssm get-parameter \
            --name "/a205257/cicd/tr-vpc-1-private-subnets" \
            --region ${{ env.AWS_REGION }} \
            --query "Parameter.Value" \
            --output text)
          # Convert "subnet-1, subnet-2" to '["subnet-1","subnet-2"]'
          PRIVATE_SUBNETS=$(echo "$PRIVATE_SUBNETS_RAW" | sed 's/, /","/g' | sed 's/^/["/' | sed 's/$/"]/')
          echo "PRIVATE_SUBNETS=$PRIVATE_SUBNETS" >> $GITHUB_OUTPUT
          
          PUBLIC_SUBNETS_RAW=$(aws ssm get-parameter \
            --name "/a205257/cicd/tr-vpc-1-public-subnets" \
            --region ${{ env.AWS_REGION }} \
            --query "Parameter.Value" \
            --output text)
          PUBLIC_SUBNETS=$(echo "$PUBLIC_SUBNETS_RAW" | sed 's/, /","/g' | sed 's/^/["/' | sed 's/$/"]/')
          echo "PUBLIC_SUBNETS=$PUBLIC_SUBNETS" >> $GITHUB_OUTPUT
          
          echo "✅ VPC Configuration retrieved"
      
      # ========================================================================
      # Set Environment Variables
      # ========================================================================
      - name: Set Terraform Variables
        run: |
          # Determine environment
          if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
            ENVIRONMENT="${{ github.event.inputs.environment }}"
          else
            ENVIRONMENT="DEV"
          fi
          
          echo "TF_VAR_environment=$ENVIRONMENT" >> $GITHUB_ENV
          echo "TF_VAR_vpc_id=${{ steps.vpc-config.outputs.VPC_ID }}" >> $GITHUB_ENV
          echo "TF_VAR_public_subnet_ids=${{ steps.vpc-config.outputs.PUBLIC_SUBNETS }}" >> $GITHUB_ENV
          echo "TF_VAR_private_subnet_ids=${{ steps.vpc-config.outputs.PRIVATE_SUBNETS }}" >> $GITHUB_ENV
          echo "TF_VAR_resource_owner=yohans.bekele@thomsonreuters.com" >> $GITHUB_ENV
          
          echo "📋 Environment: $ENVIRONMENT"
      
      # ========================================================================
      # Terraform Init
      # ========================================================================
      - name: Terraform Init
        working-directory: ${{ env.TF_DIR }}
        run: |
          terraform init \
            -backend-config="bucket=a209309-maia-terraform-state" \
            -backend-config="key=maia/${TF_VAR_environment}/terraform.tfstate" \
            -backend-config="region=${{ env.AWS_REGION }}" \
            -backend-config="encrypt=true" \
            -backend-config="dynamodb_table=maia-terraform-locks"
      
      # ========================================================================
      # Terraform Validate
      # ========================================================================
      - name: Terraform Validate
        working-directory: ${{ env.TF_DIR }}
        run: terraform validate
      
      # ========================================================================
      # Terraform Plan
      # ========================================================================
      - name: Terraform Plan
        id: plan
        working-directory: ${{ env.TF_DIR }}
        run: |
          set +e
          terraform plan \
            -detailed-exitcode \
            -out=tfplan \
            -no-color 2>&1 | tee plan_output.txt
          EXITCODE=$?
          set -e
          
          echo "exitcode=$EXITCODE" >> $GITHUB_OUTPUT
          
          # Exit codes:
          # 0 = No changes
          # 1 = Error
          # 2 = Changes present
          
          if [ $EXITCODE -eq 1 ]; then
            echo "❌ Terraform plan failed"
            exit 1
          elif [ $EXITCODE -eq 0 ]; then
            echo "✅ No changes needed"
          else
            echo "📝 Changes detected"
          fi
      
      # ========================================================================
      # Post Plan to PR
      # ========================================================================
      - name: Post Plan to PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const plan = fs.readFileSync('${{ env.TF_DIR }}/plan_output.txt', 'utf8');
            
            // Truncate if too long
            const maxLength = 65000;
            const truncatedPlan = plan.length > maxLength 
              ? plan.substring(0, maxLength) + '\n\n... (truncated)'
              : plan;
            
            const output = `### Terraform Plan Results
            
            \`\`\`
            ${truncatedPlan}
            \`\`\`
            
            *Environment: ${{ env.TF_VAR_environment }}*
            *Triggered by: @${{ github.actor }}*`;
            
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output
            });
      
      # ========================================================================
      # Upload Plan Artifact
      # ========================================================================
      - name: Upload Plan
        uses: actions/upload-artifact@v4
        with:
          name: tfplan-${{ env.TF_VAR_environment }}
          path: ${{ env.TF_DIR }}/tfplan
          retention-days: 5

  # ==========================================================================
  # Apply Job - Only on main branch or manual trigger
  # ==========================================================================
  apply:
    name: Terraform Apply
    needs: plan
    runs-on:
      - codebuild-a209309-MAIA-Runner-${{ github.run_id }}-${{ github.run_attempt }}
    
    # Only run if:
    # 1. Push to main with changes (exitcode=2)
    # 2. Manual trigger with action=apply
    if: |
      (github.event_name == 'push' && github.ref == 'refs/heads/main' && needs.plan.outputs.plan_exitcode == '2') ||
      (github.event_name == 'workflow_dispatch' && github.event.inputs.action == 'apply')
    
    # PROD requires manual approval
    environment: ${{ github.event.inputs.environment || 'DEV' }}
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}
      
      - name: Get VPC Configuration
        id: vpc-config
        run: |
          VPC_ID=$(aws ssm get-parameter --name "/a205257/cicd/tr-vpc-1-id" --region ${{ env.AWS_REGION }} --query "Parameter.Value" --output text)
          echo "VPC_ID=$VPC_ID" >> $GITHUB_OUTPUT
          
          PRIVATE_SUBNETS_RAW=$(aws ssm get-parameter --name "/a205257/cicd/tr-vpc-1-private-subnets" --region ${{ env.AWS_REGION }} --query "Parameter.Value" --output text)
          PRIVATE_SUBNETS=$(echo "$PRIVATE_SUBNETS_RAW" | sed 's/, /","/g' | sed 's/^/["/' | sed 's/$/"]/')
          echo "PRIVATE_SUBNETS=$PRIVATE_SUBNETS" >> $GITHUB_OUTPUT
          
          PUBLIC_SUBNETS_RAW=$(aws ssm get-parameter --name "/a205257/cicd/tr-vpc-1-public-subnets" --region ${{ env.AWS_REGION }} --query "Parameter.Value" --output text)
          PUBLIC_SUBNETS=$(echo "$PUBLIC_SUBNETS_RAW" | sed 's/, /","/g' | sed 's/^/["/' | sed 's/$/"]/')
          echo "PUBLIC_SUBNETS=$PUBLIC_SUBNETS" >> $GITHUB_OUTPUT
      
      - name: Set Terraform Variables
        run: |
          if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
            ENVIRONMENT="${{ github.event.inputs.environment }}"
          else
            ENVIRONMENT="DEV"
          fi
          
          echo "TF_VAR_environment=$ENVIRONMENT" >> $GITHUB_ENV
          echo "TF_VAR_vpc_id=${{ steps.vpc-config.outputs.VPC_ID }}" >> $GITHUB_ENV
          echo "TF_VAR_public_subnet_ids=${{ steps.vpc-config.outputs.PUBLIC_SUBNETS }}" >> $GITHUB_ENV
          echo "TF_VAR_private_subnet_ids=${{ steps.vpc-config.outputs.PRIVATE_SUBNETS }}" >> $GITHUB_ENV
          echo "TF_VAR_resource_owner=yohans.bekele@thomsonreuters.com" >> $GITHUB_ENV
      
      - name: Download Plan
        uses: actions/download-artifact@v4
        with:
          name: tfplan-${{ env.TF_VAR_environment }}
          path: ${{ env.TF_DIR }}
      
      - name: Terraform Init
        working-directory: ${{ env.TF_DIR }}
        run: |
          terraform init \
            -backend-config="bucket=a209309-maia-terraform-state" \
            -backend-config="key=maia/${TF_VAR_environment}/terraform.tfstate" \
            -backend-config="region=${{ env.AWS_REGION }}" \
            -backend-config="encrypt=true" \
            -backend-config="dynamodb_table=maia-terraform-locks"
      
      - name: Terraform Apply
        working-directory: ${{ env.TF_DIR }}
        run: |
          echo "🚀 Applying Terraform changes..."
          terraform apply -auto-approve tfplan
          echo "✅ Apply complete!"
      
      - name: Show Outputs
        working-directory: ${{ env.TF_DIR }}
        run: |
          echo "📋 Terraform Outputs:"
          terraform output -json | jq '.'

  # ==========================================================================
  # Destroy Job - Manual only
  # ==========================================================================
  destroy:
    name: Terraform Destroy
    runs-on:
      - codebuild-a209309-MAIA-Runner-${{ github.run_id }}-${{ github.run_attempt }}
    
    if: github.event_name == 'workflow_dispatch' && github.event.inputs.action == 'destroy'
    
    # Always require approval for destroy
    environment: ${{ github.event.inputs.environment }}-destroy
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}
      
      - name: Get VPC Configuration
        id: vpc-config
        run: |
          VPC_ID=$(aws ssm get-parameter --name "/a205257/cicd/tr-vpc-1-id" --region ${{ env.AWS_REGION }} --query "Parameter.Value" --output text)
          echo "VPC_ID=$VPC_ID" >> $GITHUB_OUTPUT
          
          PRIVATE_SUBNETS_RAW=$(aws ssm get-parameter --name "/a205257/cicd/tr-vpc-1-private-subnets" --region ${{ env.AWS_REGION }} --query "Parameter.Value" --output text)
          PRIVATE_SUBNETS=$(echo "$PRIVATE_SUBNETS_RAW" | sed 's/, /","/g' | sed 's/^/["/' | sed 's/$/"]/')
          echo "PRIVATE_SUBNETS=$PRIVATE_SUBNETS" >> $GITHUB_OUTPUT
          
          PUBLIC_SUBNETS_RAW=$(aws ssm get-parameter --name "/a205257/cicd/tr-vpc-1-public-subnets" --region ${{ env.AWS_REGION }} --query "Parameter.Value" --output text)
          PUBLIC_SUBNETS=$(echo "$PUBLIC_SUBNETS_RAW" | sed 's/, /","/g' | sed 's/^/["/' | sed 's/$/"]/')
          echo "PUBLIC_SUBNETS=$PUBLIC_SUBNETS" >> $GITHUB_OUTPUT
      
      - name: Set Terraform Variables
        run: |
          echo "TF_VAR_environment=${{ github.event.inputs.environment }}" >> $GITHUB_ENV
          echo "TF_VAR_vpc_id=${{ steps.vpc-config.outputs.VPC_ID }}" >> $GITHUB_ENV
          echo "TF_VAR_public_subnet_ids=${{ steps.vpc-config.outputs.PUBLIC_SUBNETS }}" >> $GITHUB_ENV
          echo "TF_VAR_private_subnet_ids=${{ steps.vpc-config.outputs.PRIVATE_SUBNETS }}" >> $GITHUB_ENV
          echo "TF_VAR_resource_owner=yohans.bekele@thomsonreuters.com" >> $GITHUB_ENV
      
      - name: Terraform Init
        working-directory: ${{ env.TF_DIR }}
        run: |
          terraform init \
            -backend-config="bucket=a209309-maia-terraform-state" \
            -backend-config="key=maia/${TF_VAR_environment}/terraform.tfstate" \
            -backend-config="region=${{ env.AWS_REGION }}" \
            -backend-config="encrypt=true" \
            -backend-config="dynamodb_table=maia-terraform-locks"
      
      - name: Terraform Destroy
        working-directory: ${{ env.TF_DIR }}
        run: |
          echo "⚠️  DESTROYING resources in ${{ github.event.inputs.environment }}..."
          terraform destroy -auto-approve
          echo "✅ Destroy complete!"
```

---

## 3. GitHub Environments for Approvals

### Configure in Repository Settings

1. Go to **Settings** → **Environments**
2. Create environments:
   - `DEV` - No protection rules
   - `QA` - No protection rules  
   - `PROD` - **Required reviewers** enabled
   - `PROD-destroy` - **Required reviewers** enabled

---

## 4. Backend Configuration with Dynamic Key

### provider.tf (Updated)

```hcl
# infra/terraform/provider.tf

terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  
  # Backend is configured via -backend-config in CI/CD
  # This allows different state files per environment
  backend "s3" {
    # These values are provided via -backend-config:
    # bucket         = "a209309-maia-terraform-state"
    # key            = "maia/${environment}/terraform.tfstate"
    # region         = "us-east-1"
    # encrypt        = true
    # dynamodb_table = "maia-terraform-locks"
  }
}

provider "aws" {
  region = var.region
  
  default_tags {
    tags = {
      "tr:application-asset-insight-id" = "209191"
      "ManagedBy"                       = "Terraform"
    }
  }
}
```

---

## 5. Local Development Workflow

### Create a Makefile

```makefile
# infra/terraform/Makefile

.PHONY: init plan apply destroy fmt validate

# Variables
ENV ?= DEV
AWS_REGION ?= us-east-1

# Get VPC config from SSM (requires AWS credentials)
define get_vpc_config
	$(eval VPC_ID := $(shell aws ssm get-parameter --name "/a205257/cicd/tr-vpc-1-id" --region $(AWS_REGION) --query "Parameter.Value" --output text))
	$(eval PRIVATE_SUBNETS := $(shell aws ssm get-parameter --name "/a205257/cicd/tr-vpc-1-private-subnets" --region $(AWS_REGION) --query "Parameter.Value" --output text | sed 's/, /","/g' | sed 's/^/["/' | sed 's/$$/"]/' ))
	$(eval PUBLIC_SUBNETS := $(shell aws ssm get-parameter --name "/a205257/cicd/tr-vpc-1-public-subnets" --region $(AWS_REGION) --query "Parameter.Value" --output text | sed 's/, /","/g' | sed 's/^/["/' | sed 's/$$/"]/' ))
endef

# Common TF vars
TF_VARS = -var="environment=$(ENV)" \
          -var="vpc_id=$(VPC_ID)" \
          -var="public_subnet_ids=$(PUBLIC_SUBNETS)" \
          -var="private_subnet_ids=$(PRIVATE_SUBNETS)" \
          -var="resource_owner=yohans.bekele@thomsonreuters.com"

# Initialize
init:
	terraform init \
		-backend-config="bucket=a209309-maia-terraform-state" \
		-backend-config="key=maia/$(ENV)/terraform.tfstate" \
		-backend-config="region=$(AWS_REGION)" \
		-backend-config="encrypt=true" \
		-backend-config="dynamodb_table=maia-terraform-locks"

# Format
fmt:
	terraform fmt -recursive

# Validate
validate: init
	terraform validate

# Plan
plan: init
	$(call get_vpc_config)
	terraform plan $(TF_VARS) -out=tfplan

# Apply
apply: init
	$(call get_vpc_config)
	terraform apply $(TF_VARS) -auto-approve

# Apply from saved plan
apply-plan:
	terraform apply tfplan

# Destroy
destroy: init
	$(call get_vpc_config)
	terraform destroy $(TF_VARS)

# Show outputs
output:
	terraform output -json | jq '.'

# Usage examples
help:
	@echo "Usage:"
	@echo "  make init ENV=DEV          # Initialize for DEV"
	@echo "  make plan ENV=DEV          # Plan for DEV"
	@echo "  make apply ENV=QA          # Apply for QA"
	@echo "  make destroy ENV=DEV       # Destroy DEV"
```

### Usage

```bash
cd infra/terraform

# Initialize for DEV
make init ENV=DEV

# Plan changes
make plan ENV=DEV

# Apply changes
make apply ENV=DEV

# Or apply from saved plan
make apply-plan
```

---

## 6. Workflow Triggers

| Trigger | Plan | Apply | Notes |
|---------|------|-------|-------|
| Push to main (terraform changes) | ✅ | ✅ (if changes) | Auto-deploys to DEV |
| PR to main | ✅ | ❌ | Comments plan on PR |
| Manual (plan) | ✅ | ❌ | Any environment |
| Manual (apply) | ✅ | ✅ | Requires approval for PROD |
| Manual (destroy) | ❌ | ✅ (destroy) | Always requires approval |

---

## 7. Key Takeaways

1. **Plan on every PR** - Review changes before merging
2. **Auto-apply on main** - DEV deployments are automatic
3. **PROD requires approval** - Use GitHub Environments
4. **State per environment** - Different state files prevent conflicts
5. **SSM for dynamic config** - VPC/subnet IDs from central source
6. **Artifacts for plans** - Ensure applied plan matches reviewed plan

---

## Congratulations! 🎉

You've completed the Terraform learning guide. You now know how to:

- Set up Terraform with proper state management
- Create modular, reusable infrastructure code
- Implement TR-compliant tagging and IAM
- Deploy core AWS resources (Security Groups, S3, ECR, ALB, ECS, RDS)
- Automate deployments with GitHub Actions

### Next Steps

1. **Deploy to DEV** - Run the workflow and verify resources
2. **Test the application** - Deploy your containers to ECS
3. **Add more features** - CloudFront, Redis, SageMaker
4. **Improve monitoring** - Add more CloudWatch alarms
5. **Document your infrastructure** - Keep the README updated
