# Terraform Deployment Workflow Example

This guide demonstrates how to orchestrate the `lothslair-workflow-actions` to build a complete, production-ready Terraform deployment workflow from initialization through application.

## Table of Contents

1. [Complete Workflow](#complete-workflow)
2. [Workflow Breakdown](#workflow-breakdown)
3. [Step-by-Step Explanation](#step-by-step-explanation)
4. [Implementation Patterns](#implementation-patterns)
5. [Error Handling](#error-handling)
6. [Best Practices](#best-practices)

---

## Complete Workflow

Below is a production-ready workflow that implements the full Terraform deployment lifecycle:

```yaml
name: Terraform Deploy - Init to Apply

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Deployment environment'
        required: true
        type: choice
        options:
          - dev
          - staging
          - prod
      deployment_name:
        description: 'Deployment identifier'
        required: true
        type: string

permissions:
  contents: read
  id-token: write
  pull-requests: write

env:
  # Azure Authentication (uses GitHub OIDC + Azure CLI)
  ARM_USE_CLI: 'true'
  # TF_VAR_* environment variables loaded from secrets
  TF_LOG: INFO

jobs:
  # ============================================================================
  # STAGE 1: SETUP & VALIDATION
  # ============================================================================

  setup-and-validate:
    name: Setup & Validate Configuration
    runs-on: ubuntu-latest
    outputs:
      plan_file: ${{ steps.set-vars.outputs.plan_file }}
      params_file: ${{ steps.set-vars.outputs.params_file }}
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      # Setup Terraform runtime
      - name: Setup Terraform
        uses: lothslair/lothslair-workflow-actions/setup@main

      # Setup Node.js (required for some workflow tooling)
      - name: Setup Node.js
        uses: lothslair/lothslair-workflow-actions/node@main

      # Set standard output variables
      - name: Set Output Variables
        id: set-vars
        run: |
          echo "plan_file=${{ inputs.environment }}-${{ inputs.deployment_name }}.tfplan" >> $GITHUB_OUTPUT
          echo "params_file=terraform/environments/${{ inputs.environment }}-variables.tfvars" >> $GITHUB_OUTPUT
          echo "::notice::Environment: ${{ inputs.environment }}, Deployment: ${{ inputs.deployment_name }}"

      # Validate Terraform syntax
      - name: Validate Terraform Configuration
        uses: lothslair/lothslair-workflow-actions/validate@main
        with:
          working_dir: 'terraform/'

      # Check Terraform code formatting
      - name: Check Terraform Format
        uses: lothslair/lothslair-workflow-actions/format@main
        with:
          working_dir: 'terraform/'
          check_only: 'true'

  # ============================================================================
  # STAGE 2: INITIALIZATION
  # ============================================================================

  terraform-init:
    name: Initialize Terraform Backend
    needs: setup-and-validate
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: lothslair/lothslair-workflow-actions/setup@main

      # Initialize Terraform with Azure Storage backend
      - name: Terraform Init
        uses: lothslair/lothslair-workflow-actions/init@main
        with:
          backend_rg: ${{ secrets.TERRAFORM_BACKEND_RG }}
          backend_sa: ${{ secrets.TERRAFORM_BACKEND_SA }}
          backend_sa_container: ${{ secrets.TERRAFORM_BACKEND_CONTAINER }}
          backend_sa_key: ${{ inputs.environment }}-${{ inputs.deployment_name }}.tfstate
          working_dir: 'terraform/'
          github_token: ${{ secrets.GITHUB_TOKEN }}

  # ============================================================================
  # STAGE 3: PLANNING
  # ============================================================================

  terraform-plan:
    name: Plan Infrastructure Changes
    needs: [setup-and-validate, terraform-init]
    runs-on: ubuntu-latest
    outputs:
      exit_code: ${{ steps.plan.outputs.exitcode }}
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: lothslair/lothslair-workflow-actions/setup@main

      # Generate Terraform execution plan
      - name: Terraform Plan
        id: plan
        uses: lothslair/lothslair-workflow-actions/plan@main
        with:
          environment: ${{ inputs.environment }}
          working_dir: 'terraform/'
          params_dir: 'terraform/environments'

      - name: Publish Terraform Plan
        uses: lothslair/lothslair-workflow-actions/publish@main
        with:
          environment: ${{ inputs.environment }}
          working_dir: 'terraform/'

      # Generate human-readable plan summary
      - name: Generate Plan Summary
        uses: lothslair/lothslair-workflow-actions/summary@main
        with:
          environment: ${{ inputs.environment }}
          working_dir: 'terraform/'

      # Fail if plan had errors
      - name: Check Plan Exit Code
        run: |
          EXIT_CODE=${{ steps.plan.outputs.exitcode }}
          if [ $EXIT_CODE -eq 1 ]; then
            echo "::error::Terraform plan failed with error (exit code: 1)"
            exit 1
          fi
          if [ $EXIT_CODE -eq 0 ]; then
            echo "::notice::No infrastructure changes detected"
          fi
          if [ $EXIT_CODE -eq 2 ]; then
            echo "::warning::Infrastructure changes detected - review required"
          fi

  # ============================================================================
  # STAGE 4: APPROVAL (Manual Gate)
  # ============================================================================

  approval-gate:
    name: Request Manual Approval
    needs: terraform-plan
    runs-on: ubuntu-latest
    if: ${{ needs.terraform-plan.outputs.exit_code == 2 }}
    steps:
      - name: Announce Plan Changes
        run: |
          echo "::warning::Infrastructure changes detected and require approval"
          echo ""
          echo "Deployment Details:"
          echo "  Environment: ${{ inputs.environment }}"
          echo "  Deployment: ${{ inputs.deployment_name }}"
          echo "  Branch: ${{ github.ref }}"
          echo ""
          echo "Please review the plan artifact and approve to continue."

      - name: Create Approval Issue
        if: github.event_name == 'workflow_dispatch'
        uses: actions/github-script@v7
        with:
          script: |
            const issue = await github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: `Approval Required: Terraform Deploy to ${{ inputs.environment }}`,
              body: `
## Deployment Approval Required

**Deployment Details:**
- Environment: \`${{ inputs.environment }}\`
- Deployment: \`${{ inputs.deployment_name }}\`
- Triggered by: @${{ github.actor }}
- Ref: ${{ github.ref }}

**Plan artifacts available:** Download from the workflow run

**Actions:**
- ✅ Approve by commenting \`/approve\`
- ❌ Deny by commenting \`/deny\`

**Next steps after approval:** The workflow will automatically proceed to apply the plan.
              `,
              labels: ['terraform', 'approval-required']
            });
            console.log('Approval issue created: ' + issue.data.html_url);

  # ============================================================================
  # STAGE 5: APPLICATION
  # ============================================================================

  terraform-apply:
    name: Apply Infrastructure Changes
    needs: [setup-and-validate, terraform-plan]
    runs-on: ubuntu-latest
    # Only apply if plan showed changes AND approval completed
    if: ${{ needs.terraform-plan.outputs.exit_code == 2 && (github.event_name == 'workflow_dispatch' || github.ref == 'refs/heads/main') }}
    environment: ${{ inputs.environment }}
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: lothslair/lothslair-workflow-actions/setup@main

      # Download the plan created in the planning stage
      - name: Download Plan Artifact
        uses: lothslair/lothslair-workflow-actions/download@main
        with:
          environment: ${{ inputs.environment }}
          working_dir: 'terraform/'

      # Apply the plan to infrastructure
      - name: Terraform Apply
        uses: lothslair/lothslair-workflow-actions/apply@main
        with:
          environment: ${{ inputs.environment }}
          working_dir: 'terraform/'
          plan_exit_code: ${{ needs.terraform-plan.outputs.exit_code }}

      - name: Publish Post-Apply Summary
        uses: lothslair/lothslair-workflow-actions/summary@main
        with:
          environment: ${{ inputs.environment }}
          working_dir: 'terraform/'

      - name: Report Success
        run: |
          echo "::notice::✅ Infrastructure successfully deployed to ${{ inputs.environment }}"

  # ============================================================================
  # STAGE 6: DRIFT DETECTION (Optional, runs separately)
  # ============================================================================

  drift-detection:
    name: Detect Configuration Drift
    needs: terraform-apply
    runs-on: ubuntu-latest
    if: always() # Run even if apply was skipped
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: lothslair/lothslair-workflow-actions/setup@main

      # Check for configuration drift
      - name: Detect Drift
        uses: lothslair/lothslair-workflow-actions/drift@main
        with:
          environment: ${{ inputs.environment }}
          working_dir: 'terraform/'
          params_dir: 'terraform/environments'

  # ============================================================================
  # STAGE 7: CLEANUP & NOTIFICATIONS
  # ============================================================================

  workflow-summary:
    name: Workflow Summary
    runs-on: ubuntu-latest
    if: always()
    needs: [setup-and-validate, terraform-init, terraform-plan, terraform-apply]
    steps:
      - name: Report Workflow Status
        run: |
          echo "# Terraform Deployment Summary" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "| Stage | Status |" >> $GITHUB_STEP_SUMMARY
          echo "|-------|--------|" >> $GITHUB_STEP_SUMMARY
          echo "| Setup & Validate | ✅ |" >> $GITHUB_STEP_SUMMARY
          echo "| Initialize | ✅ |" >> $GITHUB_STEP_SUMMARY
          echo "| Plan | ✅ |" >> $GITHUB_STEP_SUMMARY
          echo "| Apply | ${{ needs.terraform-apply.result == 'success' && '✅' || '⏭️' }} |" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "**Environment:** ${{ inputs.environment }}" >> $GITHUB_STEP_SUMMARY
          echo "**Deployment:** ${{ inputs.deployment_name }}" >> $GITHUB_STEP_SUMMARY
```

---

## Workflow Breakdown

### Stage 1: Setup & Validation
**Purpose**: Prepare environment and validate Terraform configuration before any state operations

```yaml
setup-and-validate:
  - Checkout code
  - Setup Terraform
  - Setup Node.js
  - Set output variables for later stages
  - Validate Terraform syntax (terraform validate)
  - Check code formatting (terraform fmt --check)
```

**Why this matters**:
- Catches syntax errors early before touching infrastructure state
- Ensures consistent code formatting across the team
- Outputs variables available to all downstream jobs

---

### Stage 2: Initialization
**Purpose**: Configure Terraform backend and initialize working directory

```yaml
terraform-init:
  - Checkout code
  - Setup Terraform
  - Initialize backend with Azure Storage:
    - backend_rg: Resource group containing storage account
    - backend_sa: Storage account name
    - backend_sa_container: Container for state files
    - backend_sa_key: State file name
    - working_dir: Terraform root module
    - github_token: Secure git authentication
```

**Key Security Features**:
- Uses GitHub CLI for credential management (no embedded tokens)
- Azure CLI authentication via ARM_USE_CLI=true
- Secrets for backend configuration

**Example Configuration**:
```yaml
backend_rg: 'terraform-state-rg'
backend_sa: 'tfstagingsa123'
backend_sa_container: 'tfstate'
backend_sa_key: 'prod-production.tfstate'
```

---

### Stage 3: Planning
**Purpose**: Generate and validate infrastructure changes

```yaml
terraform-plan:
  - Checkout code
  - Setup Terraform
  - Generate plan (terraform plan):
    - Reads environment-specific variables
    - Generates .tfplan file
    - Returns exit code (0=no changes, 2=changes, 1=error)
  - Publish plan artifact
  - Generate human-readable summary
  - Check exit code and report status
```

**Exit Code Interpretation**:
- `0`: No infrastructure changes detected → ✅ Safe to apply
- `1`: Error occurred → ❌ Deployment blocked
- `2`: Changes detected → ⚠️ Requires review/approval

---

### Stage 4: Approval Gate (Manual)
**Purpose**: Require human review before applying infrastructure changes

```yaml
approval-gate:
  runs-on: ubuntu-latest
  if: ${{ needs.terraform-plan.outputs.exit_code == 2 }}
  steps:
    - Create GitHub issue for approval
    - Include plan summary and deployment details
    - Block apply until approved
```

**Why this pattern**:
- Prevents accidental infrastructure changes
- Creates audit trail of approvals
- Allows team review of proposed changes
- Automatic for production, optional for development

---

### Stage 5: Application
**Purpose**: Apply approved infrastructure changes

```yaml
terraform-apply:
  - Checkout code
  - Setup Terraform
  - Download plan artifact from plan stage
  - Execute terraform apply:
    - Uses downloaded .tfplan file
    - Applies changes to infrastructure
    - Updates state in Azure Storage backend
  - Publish post-apply summary
```

**Safety Mechanisms**:
- Only runs if plan showed changes (exit code 2)
- Requires explicit environment protection for prod
- Uses plan artifact (prevents plan-apply drift)
- Validates plan_exit_code before applying

---

### Stage 6: Drift Detection (Optional)
**Purpose**: Detect configuration drift after deployment

```yaml
drift-detection:
  - Runs after apply (or independently)
  - Compares current infrastructure state with code
  - Reports any manual changes or drift
  - Can create issues for drift resolution
```

---

### Stage 7: Workflow Summary
**Purpose**: Report overall deployment status

```yaml
workflow-summary:
  - Create GitHub Step Summary with status table
  - Report environment and deployment details
  - Log success/failure for audit
```

---

## Step-by-Step Explanation

### Scenario: Deploying to Production

#### Step 1: Trigger Workflow
```bash
# Manual trigger with parameters
Environment: prod
Deployment Name: core-infrastructure-update
```

#### Step 2: Setup & Validate (Parallel Execution)
```
✅ Checkout code from main branch
✅ Setup Terraform 1.x
✅ Validate Terraform syntax
✅ Check code formatting
📊 Output: plan_file, params_file variables set
```

#### Step 3: Initialize Backend
```
✅ Authenticate with Azure using ARM_USE_CLI
✅ Configure git authentication using GitHub CLI
✅ Initialize Terraform backend:
   - backend_rg: terraform-state-rg
   - backend_sa: prodtfstate123
   - backend_sa_container: tfstate
   - backend_sa_key: prod-core-infrastructure-update.tfstate
✅ Lock state file (automatic)
```

#### Step 4: Generate Plan
```
✅ Run terraform plan with prod-variables.tfvars
✅ Generate prod-core-infrastructure-update.tfplan
✅ Publish artifact to workflow run
✅ Create human-readable summary

Output:
  Terraform will perform these actions:
    # module.network.azurerm_virtual_network.main will be created
    + resource "azurerm_virtual_network" "main" {
        + name = "prod-vnet"
        + ...
      }
  
  Plan: 3 to add, 2 to modify, 0 to destroy
```

#### Step 5: Request Approval
```
⚠️ GitHub Issue Created:
   Title: "Approval Required: Terraform Deploy to prod"
   Body: Includes deployment details and plan summary
   Status: Awaiting team review

Team lead reviews and comments: "/approve"
```

#### Step 6: Apply Changes
```
✅ Download prod-core-infrastructure-update.tfplan
✅ Execute terraform apply with downloaded plan
✅ Output:
   Apply complete! Resources: 3 added, 2 changed, 0 destroyed
✅ State updated in Azure Storage backend
✅ Publish post-apply summary to step summary
```

#### Step 7: Detect Drift (Independent)
```
✅ Verify no manual changes to infrastructure
✅ Report configuration drift status
```

#### Step 8: Workflow Complete
```
📊 Step Summary:
   | Stage | Status |
   | Setup | ✅ |
   | Init  | ✅ |
   | Plan  | ✅ |
   | Apply | ✅ |
```

---

## Implementation Patterns

### Pattern 1: Multi-Environment Deployment

Deploy to dev, staging, and prod in sequence with different approval requirements:

```yaml
name: Multi-Environment Deployment

on:
  push:
    branches: [main]

jobs:
  deploy-dev:
    uses: ./.github/workflows/deploy.yml
    with:
      environment: dev
      deployment_name: auto-deploy-dev
    secrets: inherit

  deploy-staging:
    needs: deploy-dev
    uses: ./.github/workflows/deploy.yml
    with:
      environment: staging
      deployment_name: auto-deploy-staging
    secrets: inherit

  deploy-prod:
    needs: deploy-staging
    uses: ./.github/workflows/deploy.yml
    with:
      environment: prod
      deployment_name: manual-deploy-prod
      # Note: prod requires manual approval via approval-gate job
    secrets: inherit
```

### Pattern 2: Matrix Deployments

Deploy to multiple regions or configurations:

```yaml
terraform-apply:
  strategy:
    matrix:
      region: [us-east-1, us-west-2, eu-west-1]
      node_count: [3, 5]
  with:
    environment: prod
    working_dir: terraform/regions/${{ matrix.region }}/
    plan_exit_code: ${{ needs.terraform-plan.outputs.exit_code }}
```

### Pattern 3: Conditional Apply

Only apply changes in specific conditions:

```yaml
terraform-apply:
  if: |
    always() && 
    needs.terraform-plan.outputs.exit_code == 2 &&
    github.event_name == 'push' &&
    github.ref == 'refs/heads/main'
```

### Pattern 4: Plan-Only Mode

Generate plans without applying changes (for reviews):

```yaml
plan-only:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: lothslair/lothslair-workflow-actions/setup@main
    - uses: lothslair/lothslair-workflow-actions/init@main
      with:
        backend_rg: ${{ secrets.TF_BACKEND_RG }}
        backend_sa: ${{ secrets.TF_BACKEND_SA }}
        backend_sa_container: ${{ secrets.TF_BACKEND_CONTAINER }}
        backend_sa_key: ${{ inputs.environment }}.tfstate
        working_dir: terraform/
    - uses: lothslair/lothslair-workflow-actions/plan@main
      with:
        environment: ${{ inputs.environment }}
        working_dir: terraform/
        params_dir: terraform/environments
    - uses: lothslair/lothslair-workflow-actions/summary@main
      with:
        environment: ${{ inputs.environment }}
        working_dir: terraform/
```

---

## Error Handling

### Input Validation Errors

If invalid inputs are provided, actions will fail early with clear messages:

```bash
::error::Invalid environment name 'prod!'. Use alphanumeric characters and hyphens only
::notice::Expected format: [a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]
```

### Terraform Validation Errors

Caught in Stage 1 before any state operations:

```bash
::error::Terraform configuration validation failed:
Error: Missing required argument

  on main.tf line 12, in resource "azurerm_resource_group" "rg":
   12: resource "azurerm_resource_group" "rg" {

An argument named "location" is required here.
```

### Authentication Errors

Clear messaging for credential/authentication issues:

```bash
::error::Azure authentication failed: AADSTS700016 - Application not found in directory
::notice::Verify ARM_CLIENT_ID, ARM_TENANT_ID, and GITHUB_TOKEN secrets are configured
```

### Plan Errors

Terraform plan failures block progression to apply:

```bash
::error::Terraform plan failed with error (exit code: 1)
✗ Failed to read variables from prod-variables.tfvars
```

### Apply Errors

If apply fails, state is left in a safe, recoverable state:

```bash
::error::Terraform apply failed: resource creation timed out
::notice::Infrastructure is partially deployed. Review state and retry.
```

---

## Best Practices

### 1. **Use Separate Secrets for Each Environment**

```yaml
env:
  # Different Azure credentials per environment
  PROD_ARM_CLIENT_ID: ${{ secrets.PROD_AZURE_CLIENT_ID }}
  STAGING_ARM_CLIENT_ID: ${{ secrets.STAGING_AZURE_CLIENT_ID }}
```

### 2. **Lock Production Environments**

```yaml
terraform-apply:
  environment: ${{ inputs.environment }}
  if: inputs.environment != 'prod'  # Require manual triggering for prod
```

### 3. **Archive Plans for Audit Trail**

```yaml
- name: Archive Plan Artifacts
  uses: actions/upload-artifact@v3
  with:
    name: terraform-plans-${{ inputs.environment }}
    path: terraform/*.tfplan
    retention-days: 90
```

### 4. **Use Concurrency to Prevent Simultaneous Deployments**

```yaml
concurrency:
  group: terraform-deploy-${{ inputs.environment }}
  cancel-in-progress: false  # Don't cancel ongoing deployments
```

### 5. **Implement Proper Rollback Strategy**

```yaml
# On failure, automatically plan and apply previous state
on-failure:
  - name: Rollback Plan
    if: failure()
    uses: lothslair/lothslair-workflow-actions/plan@main
    with:
      environment: ${{ inputs.environment }}-rollback
```

### 6. **Monitor Drift After Deployment**

```yaml
drift-detection:
  schedule:
    - cron: '0 2 * * *'  # Run daily at 2 AM
  # Alerts on manual infrastructure changes
```

### 7. **Tag Deployments for Traceability**

```yaml
- name: Tag Deployment
  run: |
    git tag -a "deploy-${{ inputs.environment }}-$(date +%Y%m%d-%H%M%S)" \
      -m "Deployment to ${{ inputs.environment }} by ${{ github.actor }}" \
      ${{ github.sha }}
    git push origin --tags
```

---

## Integration with External Tools

### Slack Notifications

```yaml
- name: Notify Slack on Success
  uses: slackapi/slack-github-action@v1
  with:
    payload: |
      {
        "text": "✅ Terraform deployment to ${{ inputs.environment }} complete",
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "*Terraform Deployment Complete*\nEnvironment: ${{ inputs.environment }}\nTriggered by: @${{ github.actor }}"
            }
          }
        ]
      }
  if: success()
```

### PagerDuty Alerts

```yaml
- name: Alert PagerDuty on Failure
  uses: morrissimo/pagerduty-action@v1
  with:
    event_action: trigger
    dedup_key: terraform-deploy-${{ inputs.environment }}
    description: Terraform deployment to ${{ inputs.environment }} failed
  if: failure()
```

### Email Notifications

```yaml
- name: Send Email Report
  uses: dawidd6/action-send-mail@v3
  with:
    server_address: ${{ secrets.MAIL_SERVER }}
    server_port: ${{ secrets.MAIL_PORT }}
    username: ${{ secrets.MAIL_USERNAME }}
    password: ${{ secrets.MAIL_PASSWORD }}
    subject: Terraform Deployment Report - ${{ inputs.environment }}
    to: ${{ secrets.DEPLOY_NOTIFY_EMAIL }}
    body: Deployment to ${{ inputs.environment }} completed successfully
  if: always()
```

---

## Conclusion

This workflow pattern provides:

✅ **Safety**: Multi-stage validation and approval gating
✅ **Transparency**: Clear logging and summaries at each stage
✅ **Security**: No embedded credentials, GitHub CLI authentication
✅ **Auditability**: Issue creation, tagging, and notifications
✅ **Scalability**: Supports multi-environment and matrix deployments
✅ **Reliability**: Error handling at each stage with clear messages

The modular design allows you to customize each stage for your specific needs while maintaining security and best practices.
