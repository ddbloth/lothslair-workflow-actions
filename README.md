# lothslair-workflow-actions

A comprehensive collection of reusable GitHub Actions for Terraform automation workflows. This repository provides composable actions that enable infrastructure-as-code (IaC) teams to automate provisioning, planning, applying, and managing Terraform-based infrastructure through GitHub Actions.

## Quick Links

**New to this project?** Start here:
- 📖 [QUICK_START.md](docs/QUICK_START.md) - Get deploying in 7 minutes
- 🏗️ [WORKFLOW_IMPLEMENTATION_SUMMARY.md](WORKFLOW_IMPLEMENTATION_SUMMARY.md) - Complete overview of what's new
- 📚 [Documentation Index](#documentation) - All guides and resources

**Implementation Summary**: See [WORKFLOW_IMPLEMENTATION_SUMMARY.md](WORKFLOW_IMPLEMENTATION_SUMMARY.md) for a complete overview of the new 7-stage deployment workflow layer.

## Overview

`lothslair-workflow-actions` is a modular action library designed to streamline Terraform operations in CI/CD pipelines. Each action is a self-contained, composable component that can be orchestrated to build powerful infrastructure automation workflows.

## Features

- **Terraform Automation**: Complete lifecycle management from initialization to destruction
- **Multi-Environment Support**: Parameterized environments (dev, staging, production, etc.)
- **Azure Backend Integration**: Seamless integration with Azure Storage for Terraform state management
- **Plan Artifacts**: Automatic publishing and downloading of Terraform plans for approval workflows
- **GitHub Integration**: Native PR comments, issue creation for drift detection, and step summaries
- **Secure Credential Handling**: GitHub CLI-based authentication without embedding credentials
- **Code Quality**: Format validation, plan validation, and configuration drift detection
- **Input Validation**: Comprehensive validation of all action inputs with clear error messages
- **Standardized Error Handling**: Consistent error handling patterns across all actions
- **GitHub Annotations**: Structured logging with error, warning, and notice annotations

## Security & Best Practices

### 🔐 Token & Credential Handling

This version implements security best practices:

1. **Secure Git Authentication**: The `init` action uses GitHub CLI (`gh auth login`) which securely manages credentials
2. **No Embedded Credentials**: Credentials are passed via environment variables, not embedded in git config
3. **Azure CLI Integration**: Leverages `ARM_USE_CLI=true` for Azure authentication using pre-authenticated CLI credentials

### 📝 Naming Conventions

All actions use consistent, clear input naming:
- `working_dir` - Working directory for Terraform operations (replaces `tf_actions_working_dir`)
- `plan_exit_code` - Terraform plan exit code (replaces `planExitCode`)
- `output_summary` - Terraform plan summary/output (replaces `outputSummary`)

Variable files now use `-variables.tfvars` suffix (e.g., `prod-variables.tfvars`) instead of `-ado-variables.tfvars` for portability.

### 📊 Improved Logging

Actions include structured logging with GitHub annotations:
- `::error::` - Critical failures
- `::warning::` - Potentially destructive operations
- `::notice::` - Successful operations

---

## Input Validation & Error Handling

All actions include comprehensive input validation and standardized error handling to catch configuration issues early:

### Automatic Input Validation

Each action validates its inputs before executing Terraform:
- ✓ Required fields are not empty
- ✓ Directories exist and contain required files
- ✓ Files exist when expected
- ✓ Environment names follow correct format (alphanumeric with hyphens)
- ✓ Azure resource names follow Azure naming conventions

**Example**: The `plan` action validates:
```yaml
- uses: lothslair/lothslair-workflow-actions/plan@main
  with:
    environment: 'prod'              # ✓ Validated format
    working_dir: 'terraform/'        # ✓ Validated directory exists
    params_dir: 'terraform/environments'  # ✓ Validated contains prod-variables.tfvars
```

### Clear Error Messages

Failed validations produce actionable error messages:
```
::error::Invalid environment name 'prod!'. Use alphanumeric characters and hyphens only
::notice::Expected format: [a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]
```

### Helper Scripts

Two reusable helper scripts provide validation and error handling:

- **`scripts/validate-inputs.sh`** - 14 validation functions for comprehensive input checking
- **`scripts/error-handler.sh`** - 20 error handling and logging functions

### Documentation

For detailed validation and error handling patterns, see:
- **[ERROR_HANDLING.md](docs/ERROR_HANDLING.md)** - Complete error handling guide with exit codes and patterns
- **[INPUT_VALIDATION.md](docs/INPUT_VALIDATION.md)** - Input validation strategies and best practices

### Workflow Orchestration Layer

Complete guides for building production-ready Terraform deployment workflows:
- **[WORKFLOW_LAYER_SUMMARY.md](docs/WORKFLOW_LAYER_SUMMARY.md)** - Overview of the 7-stage deployment pattern
- **[QUICK_START.md](docs/QUICK_START.md)** - Quick reference and copy-paste template (7 min read)
- **[DEPLOYMENT_WORKFLOW_EXAMPLE.md](docs/DEPLOYMENT_WORKFLOW_EXAMPLE.md)** - Complete 7-stage workflow guide (30 min read)
- **[WORKFLOW_ARCHITECTURE.md](docs/WORKFLOW_ARCHITECTURE.md)** - Visual architecture, data flow, and system design

### Example Workflows

Production-ready workflow templates:
- **[terraform-complete-deployment.yml](.github/workflows/terraform-complete-deployment.yml)** - Full init-to-apply workflow with approval gating and drift detection

---

## Available Actions

### Setup & Initialization

#### `setup`
Sets up Terraform in your GitHub Actions runner.

**Inputs**: None

**Functionality**:
- Installs and configures Terraform using HashiCorp's official setup action
- Disables Terraform wrapper for better output control

**Usage Example**:
```yaml
- uses: lothslair/lothslair-workflow-actions/setup@main
```

---

#### `node`
Sets up Node.js 20.x environment for GitHub Actions.

**Inputs**: None

**Functionality**:
- Configures Node.js 20.x runtime
- Useful for actions that require Node.js tooling

**Usage Example**:
```yaml
- uses: lothslair/lothslair-workflow-actions/node@main
```

---

#### `init`
Initializes Terraform with Azure backend configuration.

**Inputs**:
- `backend_rg` (required, string): Azure Resource Group containing the state storage account
- `backend_sa` (required, string): Azure Storage Account name for Terraform state
- `backend_sa_container` (required, string): Container name in the storage account
- `backend_sa_key` (required, string): Key/blob name for the state file
- `working_dir` (required, string): Working directory for Terraform operations
- `github_token` (optional, string): GitHub token for git authentication (uses GitHub CLI for secure handling)

**Functionality**:
- Securely configures GitHub authentication using GitHub CLI
- Initializes Terraform with Azure Storage backend
- Sets `ARM_USE_CLI=true` for Azure authentication
- Leverages pre-authenticated Azure CLI in GitHub Actions runner

**Usage Example**:
```yaml
- uses: lothslair/lothslair-workflow-actions/init@main
  with:
    backend_rg: 'my-rg'
    backend_sa: 'mystorageaccount'
    backend_sa_container: 'tfstate'
    backend_sa_key: 'prod.tfstate'
    working_dir: 'terraform/'
    github_token: ${{ secrets.GITHUB_TOKEN }}
```

---

### Code Quality & Validation

#### `format`
Validates and formats Terraform code.

**Inputs**:
- `working_dir` (required, string): Working directory for Terraform operations
- `check_only` (optional, boolean): Only check formatting without applying changes (default: false)

**Functionality**:
- Recursively checks Terraform formatting across the working directory
- Displays formatting differences using `-diff` flag
- Optional check-only mode for CI validation

**Usage Example**:
```yaml
# Apply formatting
- uses: lothslair/lothslair-workflow-actions/format@main
  with:
    working_dir: 'terraform/'

# Check only (for CI)
- uses: lothslair/lothslair-workflow-actions/format@main
  with:
    working_dir: 'terraform/'
    check_only: 'true'
```

---

#### `validate`
Validates Terraform configuration syntax and consistency.

**Inputs**:
- `working_dir` (required, string): Working directory for Terraform operations

**Functionality**:
- Runs `terraform validate` to check configuration files for syntax errors
- Ensures all required variables are defined
- Verifies resource references and variable dependencies

**Usage Example**:
```yaml
- uses: lothslair/lothslair-workflow-actions/validate@main
  with:
    working_dir: 'terraform/'
```

---

### Planning & Drift Detection

#### `plan`
Executes a Terraform plan and detects infrastructure changes.

**Inputs**:
- `environment` (required, string): Environment name (e.g., 'dev', 'staging', 'prod')
- `working_dir` (required, string): Working directory for Terraform operations
- `params_dir` (required, string): Directory containing variable files

**Outputs**:
- `exitcode`: Plan exit code (0 = no changes, 2 = changes detected, 1 = error)

**Functionality**:
- Generates detailed execution plan for infrastructure changes
- Uses detailed exit codes to indicate plan status
- Reads variables from `{environment}-variables.tfvars` file
- Outputs plan to `{environment}.plan.tfplan` file
- Sets `TF_IN_AUTOMATION=true` for better CI/CD integration

**Usage Example**:
```yaml
- uses: lothslair/lothslair-workflow-actions/plan@main
  id: terraform-plan
  with:
    environment: 'prod'
    working_dir: 'terraform/'
    params_dir: 'terraform/environments'
```

---

#### `plan-destroy`
Generates a Terraform destroy plan (preview resource removal).

**Inputs**:
- `environment` (required, string): Environment name
- `working_dir` (required, string): Working directory for Terraform operations
- `params_dir` (required, string): Directory containing variable files

**Outputs**:
- `exitcode`: Plan exit code (0 = no changes, 2 = changes detected, 1 = error)

**Functionality**:
- Creates a plan for destroying all infrastructure
- Uses `terraform plan -destroy` to preview resource removal
- Outputs plan to `{environment}.plan.tfplan` file
- Useful for controlled infrastructure teardown and disaster recovery scenarios
- Includes warning annotation in logs

**Usage Example**:
```yaml
- uses: lothslair/lothslair-workflow-actions/plan-destroy@main
  with:
    environment: 'staging'
    working_dir: 'terraform/'
    params_dir: 'terraform/environments'
```

---

#### `drift`
Detects and reports Terraform configuration drift.

**Inputs**:
- `github_token` (required, string): GitHub token for API access
- `plan_exit_code` (required, string): Exit code from plan execution (0 or 2)
- `output_summary` (required, string): Terraform plan summary/output for issue body

**Functionality**:
- Creates or updates GitHub issues when drift is detected (exit code 2)
- Automatically closes issues when drift is resolved (exit code 0)
- Adds labels for easy filtering ('terraform', 'drift')
- Prevents duplicate issues by searching for existing ones
- Marks workflow as failed if drift detected for visibility

**Usage Example**:
```yaml
- uses: lothslair/lothslair-workflow-actions/drift@main
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    plan_exit_code: ${{ steps.terraform-plan.outputs.exitcode }}
    output_summary: ${{ steps.summary.outputs.summary }}
```

---

### Artifact Management

#### `publish`
Uploads Terraform plan artifacts to GitHub Actions.

**Inputs**:
- `environment` (required, string): Environment name
- `working_dir` (required, string): Working directory for Terraform operations

**Functionality**:
- Publishes `.plan.tfplan` files as GitHub Actions artifacts
- Uses unique artifact naming: `tfplan-{environment}-{run_id}` for collision prevention
- Sets 7-day retention policy
- Fails if plan file not found
- Essential for approval workflows where planning and applying happen in separate jobs

**Usage Example**:
```yaml
- uses: lothslair/lothslair-workflow-actions/publish@main
  with:
    environment: 'prod'
    working_dir: 'terraform/'
```

---

#### `download`
Downloads Terraform plan artifacts from GitHub Actions.

**Inputs**:
- `environment` (required, string): Environment name
- `working_dir` (required, string): Working directory for Terraform operations

**Functionality**:
- Downloads previously published plan artifacts
- Restores plans to the specified working directory
- Uses the same naming convention as `publish` action
- Enables multi-job workflows where applying happens after planning

**Usage Example**:
```yaml
- uses: lothslair/lothslair-workflow-actions/download@main
  with:
    environment: 'prod'
    working_dir: 'terraform/'
```

---

### Execution & Reporting

#### `apply`
Applies a Terraform plan to infrastructure.

**Inputs**:
- `environment` (required, string): Environment name
- `working_dir` (required, string): Working directory for Terraform operations

**Functionality**:
- Executes `terraform apply` with auto-approval flag
- Uses pre-generated plan file (`{environment}.plan.tfplan`)
- Validates plan file exists before applying
- Implements infrastructure changes as specified in the plan
- Typically used after manual approval of the plan

**Usage Example**:
```yaml
- uses: lothslair/lothslair-workflow-actions/apply@main
  with:
    environment: 'prod'
    working_dir: 'terraform/'
```

---

#### `destroy`
Destroys infrastructure managed by Terraform.

**Inputs**:
- `environment` (required, string): Environment name
- `working_dir` (required, string): Working directory for Terraform operations
- `params_dir` (required, string): Directory containing variable files

**Functionality**:
- Executes `terraform apply -destroy` for infrastructure teardown
- Requires environment-specific variable file
- Auto-approves destruction (use with caution!)
- Includes warning annotation for safety
- Useful for ephemeral environments and cleanup operations

**Usage Example**:
```yaml
- uses: lothslair/lothslair-workflow-actions/destroy@main
  with:
    environment: 'staging'
    working_dir: 'terraform/'
    params_dir: 'terraform/environments'
```

---

#### `summary`
Generates formatted Terraform plan summaries for reporting.

**Inputs**:
- `environment` (required, string): Environment name
- `working_dir` (required, string): Working directory for Terraform operations

**Outputs**:
- `summary`: Formatted Terraform plan output suitable for PR comments and step summaries

**Functionality**:
- Converts Terraform plan to human-readable format
- Creates collapsible HTML details section for better readability
- Includes emoji indicators for visual scanning (📋)
- Validates plan file exists before reading
- Publishes to GitHub Actions step summary (`$GITHUB_STEP_SUMMARY`)
- Outputs formatted summary for use in PR comments or reporting

**Usage Example**:
```yaml
- uses: lothslair/lothslair-workflow-actions/summary@main
  id: terraform-summary
  with:
    environment: 'prod'
    working_dir: 'terraform/'
```

---

#### `push-pr`
Posts Terraform plan output as a comment on pull requests.

**Inputs**:
- `github_token` (required, string): GitHub token for API access
- `summary` (required, string): Terraform plan summary/output to post

**Functionality**:
- Automatically comments on PRs with Terraform plan details
- Only runs during pull request events (checks `github.event_name`)
- Provides visibility into planned changes during code review process
- Posts full summary output as a collapsed comment

**Usage Example**:
```yaml
- uses: lothslair/lothslair-workflow-actions/push-pr@main
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    summary: ${{ steps.summary.outputs.summary }}
```

---

## Example Workflows

### Complete PR Planning Workflow

```yaml
name: Terraform Plan on PR

on:
  pull_request:
    paths:
      - 'terraform/**'

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: lothslair/lothslair-workflow-actions/setup@main
      
      - uses: lothslair/lothslair-workflow-actions/init@main
        with:
          backend_rg: ${{ secrets.BACKEND_RG }}
          backend_sa: ${{ secrets.BACKEND_SA }}
          backend_sa_container: 'tfstate'
          backend_sa_key: 'dev.tfstate'
          working_dir: 'terraform/'
          github_token: ${{ secrets.GITHUB_TOKEN }}
      
      - uses: lothslair/lothslair-workflow-actions/validate@main
        with:
          working_dir: 'terraform/'
      
      - uses: lothslair/lothslair-workflow-actions/format@main
        with:
          working_dir: 'terraform/'
      
      - uses: lothslair/lothslair-workflow-actions/plan@main
        id: plan
        with:
          environment: 'dev'
          working_dir: 'terraform/'
          params_dir: 'terraform/environments'
      
      - uses: lothslair/lothslair-workflow-actions/summary@main
        id: summary
        with:
          environment: 'dev'
          working_dir: 'terraform/'
      
      - uses: lothslair/lothslair-workflow-actions/push-pr@main
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          summary: ${{ steps.summary.outputs.summary }}
```

### Production Apply Workflow (with Approval Gate)

```yaml
name: Terraform Apply to Production

on:
  push:
    branches:
      - main
    paths:
      - 'terraform/**'

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: lothslair/lothslair-workflow-actions/setup@main
      
      - uses: lothslair/lothslair-workflow-actions/init@main
        with:
          backend_rg: ${{ secrets.BACKEND_RG }}
          backend_sa: ${{ secrets.BACKEND_SA }}
          backend_sa_container: 'tfstate'
          backend_sa_key: 'prod.tfstate'
          working_dir: 'terraform/'
          github_token: ${{ secrets.GITHUB_TOKEN }}
      
      - uses: lothslair/lothslair-workflow-actions/validate@main
        with:
          working_dir: 'terraform/'
      
      - uses: lothslair/lothslair-workflow-actions/plan@main
        id: plan
        with:
          environment: 'prod'
          working_dir: 'terraform/'
          params_dir: 'terraform/environments'
      
      - uses: lothslair/lothslair-workflow-actions/publish@main
        with:
          environment: 'prod'
          working_dir: 'terraform/'

  apply:
    needs: plan
    runs-on: ubuntu-latest
    environment:
      name: production
    steps:
      - uses: actions/checkout@v4
      
      - uses: lothslair/lothslair-workflow-actions/setup@main
      
      - uses: lothslair/lothslair-workflow-actions/init@main
        with:
          backend_rg: ${{ secrets.BACKEND_RG }}
          backend_sa: ${{ secrets.BACKEND_SA }}
          backend_sa_container: 'tfstate'
          backend_sa_key: 'prod.tfstate'
          working_dir: 'terraform/'
          github_token: ${{ secrets.GITHUB_TOKEN }}
      
      - uses: lothslair/lothslair-workflow-actions/download@main
        with:
          environment: 'prod'
          working_dir: 'terraform/'
      
      - uses: lothslair/lothslair-workflow-actions/apply@main
        with:
          environment: 'prod'
          working_dir: 'terraform/'
```

### Drift Detection Workflow

```yaml
name: Terraform Drift Detection

on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM UTC

jobs:
  drift-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: lothslair/lothslair-workflow-actions/setup@main
      
      - uses: lothslair/lothslair-workflow-actions/init@main
        with:
          backend_rg: ${{ secrets.BACKEND_RG }}
          backend_sa: ${{ secrets.BACKEND_SA }}
          backend_sa_container: 'tfstate'
          backend_sa_key: 'prod.tfstate'
          working_dir: 'terraform/'
          github_token: ${{ secrets.GITHUB_TOKEN }}
      
      - uses: lothslair/lothslair-workflow-actions/plan@main
        id: plan
        with:
          environment: 'prod'
          working_dir: 'terraform/'
          params_dir: 'terraform/environments'
      
      - uses: lothslair/lothslair-workflow-actions/summary@main
        id: summary
        with:
          environment: 'prod'
          working_dir: 'terraform/'
      
      - uses: lothslair/lothslair-workflow-actions/drift@main
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          plan_exit_code: ${{ steps.plan.outputs.exitcode }}
          output_summary: ${{ steps.summary.outputs.summary }}
```

---

## Variable File Convention

Actions expect environment-specific variable files in the following format:

```
terraform/environments/
├── dev-variables.tfvars
├── staging-variables.tfvars
└── prod-variables.tfvars
```

Example `prod-variables.tfvars`:
```hcl
region = "eastus"
environment = "prod"

tags = {
  Environment = "Production"
  ManagedBy   = "Terraform"
  CostCenter  = "Infrastructure"
}

# Azure-specific settings
resource_group_location = "eastus"
enable_monitoring       = true
```

---

## State Management

These actions are configured for Azure Storage backend. Set up your Terraform backend configuration:

```hcl
terraform {
  backend "azurerm" {
    # These values are configured via init action inputs
    # resource_group_name  = ""
    # storage_account_name = ""
    # container_name       = ""
    # key                  = ""
  }
}
```

### Azure Storage Setup

1. Create a Storage Account to hold Terraform state
2. Create a blob container within the storage account
3. Grant appropriate RBAC permissions:
   - GitHub Actions service principal/identity needs `Storage Blob Data Contributor` role
4. Configure GitHub secrets:
   - `BACKEND_RG`: Resource group name
   - `BACKEND_SA`: Storage account name
   - (Container name and key can be hardcoded in workflows)

---

## Prerequisites

- **GitHub Actions Runner**: ubuntu-latest or compatible Linux
- **Terraform**: >= 1.0
- **Azure CLI**: Pre-installed in GitHub-hosted runners
- **Git**: Pre-installed in GitHub-hosted runners
- **Bash**: Available on runner
- **Credentials**:
  - GitHub token (for git operations)
  - Azure credentials (already authenticated in GitHub Actions runners via `azure/login@v1`)
  - GitHub Actions secrets for backend configuration

---

## Exit Codes Reference

Terraform plan exit codes used throughout these actions:

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success, no changes | Workflow continues normally |
| 1 | Error | Workflow fails, retries not performed |
| 2 | Success, changes detected | Workflow continues, drift detection triggers |

---

## Best Practices

1. **Always validate before planning**: Use `validate` action before `plan` to catch configuration errors early
2. **Format code in CI**: Use `format` action with `check_only: 'true'` in PR workflows to enforce standards
3. **Multi-job approval gates**: Use `publish` and `download` for multi-job workflows with manual approval steps
4. **Monitor infrastructure drift**: Schedule regular drift detection checks using the `drift` action
5. **Secure your secrets**: Store backend credentials and tokens in GitHub repository secrets
6. **Version your actions**: Pin actions to specific versions or tags, not `@main` in production
7. **Tag all resources**: Use the `tags` variable in your `.tfvars` files for cost allocation and governance
8. **Use environment-specific state files**: Each environment (dev/staging/prod) should have its own state file key
9. **Review plans before apply**: Implement GitHub environments with required reviewers for production deployments
10. **Automate drift remediation**: Consider complementing drift detection with automated remediation workflows

---

## Contributing

Contributions are welcome! Please ensure any changes:
- Maintain backward compatibility
- Follow the established action patterns
- Include updated documentation
- Test with real GitHub workflows
- Add appropriate error handling

---

## License

This repository is licensed under the MIT License. See the LICENSE file for details.

---

## Troubleshooting

### Common Issues

**Plan file not found during apply**
- Ensure `publish` step completed successfully
- Verify artifact retention period hasn't expired
- Check environment and run_id match between jobs

**Azure authentication fails in init**
- Ensure Azure CLI is pre-authenticated in the runner
- Verify service principal/identity has required permissions
- Check `ARM_USE_CLI=true` is being set

**Git authentication errors**
- Verify GitHub token is correctly passed to init action
- Ensure token has appropriate `repo` scope
- Check for rate limiting on GitHub API

**Drift detection not creating issues**
- Verify GitHub token has permission to create issues
- Check repository allows issues (not disabled)
- Ensure `plan_exit_code` is correctly passed as string

---

## Support

For issues, questions, or contributions, please:
1. Open an issue in the repository
2. Provide workflow logs and error messages
3. Include relevant action versions
4. Contact the maintainers

