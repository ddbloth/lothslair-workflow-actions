# Error Handling & Input Validation Guide

## Overview

This document describes the standardized error handling and input validation approach used across all `lothslair-workflow-actions` actions.

---

## Validation Architecture

### Helper Scripts

Two reusable bash scripts provide validation and error handling:

1. **`scripts/validate-inputs.sh`** - Input validation functions
2. **`scripts/error-handler.sh`** - Error handling and logging patterns

### When Validation Occurs

Every action follows this pattern:

```yaml
steps:
  - name: Validate Inputs  # Step 1: Validate all inputs
    shell: bash
    run: |
      source "${{ github.action_path }}/../scripts/validate-inputs.sh"
      validate_plan_inputs ...
  
  - name: Main Operation  # Step 2: Perform the action
    # Uses validated inputs...
```

---

## Input Validation Functions

### Basic Validation

#### `validate_required`
Ensures a required input is not empty.

```bash
validate_required "environment" "${{ inputs.environment }}"
# Fails if environment is empty
```

**Exit Code**: 1 on failure

---

#### `validate_directory`
Ensures a directory exists and is readable.

```bash
validate_directory "working_dir" "${{ inputs.working_dir }}"
# Checks: exists, is directory, is readable
```

**Checks**:
- ✓ Directory exists
- ✓ Is readable
- ✓ Is actually a directory

---

#### `validate_file`
Ensures a file exists and is readable.

```bash
validate_file "params_file" "$workspace/$params_dir/prod-variables.tfvars"
```

---

### Specialized Validation

#### `validate_environment_name`
Validates environment name format (alphanumeric + hyphens).

```bash
validate_environment_name "prod"      # ✓ Valid
validate_environment_name "dev-us-1"  # ✓ Valid
validate_environment_name "prod!"     # ✗ Invalid
```

**Pattern**: `^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$|^[a-zA-Z0-9]$`

---

#### `validate_azure_backend`
Validates Azure Storage backend parameters.

```bash
validate_azure_backend "my-rg" "mystorageaccount" "tfstate" "prod.tfstate"
```

**Checks**:
- ✓ All parameters required
- ✓ Storage account name: 3-24 lowercase alphanumeric
- ✓ Resource group name: 1-90 chars, alphanumeric + dash/underscore/period

---

#### `validate_terraform_dir`
Ensures directory contains `.tf` files.

```bash
validate_terraform_dir "${{ inputs.working_dir }}"
```

**Checks**:
- ✓ Directory exists
- ✓ Contains at least one `*.tf` file

---

### Composite Validation

#### `validate_plan_inputs`
Comprehensive validation for plan-type actions.

```bash
validate_plan_inputs \
  "${{ inputs.environment }}" \
  "${{ inputs.working_dir }}" \
  "${{ inputs.params_dir }}" \
  "${{ github.workspace }}"
```

**Validates**:
- ✓ Environment name format
- ✓ Working directory exists and contains Terraform files
- ✓ Variable file exists: `{environment}-variables.tfvars`

---

#### `validate_init_inputs`
Comprehensive validation for init action.

```bash
validate_init_inputs \
  "${{ inputs.backend_rg }}" \
  "${{ inputs.backend_sa }}" \
  "${{ inputs.backend_sa_container }}" \
  "${{ inputs.backend_sa_key }}" \
  "${{ inputs.working_dir }}"
```

**Validates**:
- ✓ Azure backend parameters
- ✓ Working directory exists

---

## Error Handling Functions

### Basic Error Logging

#### `log_error`
Log an error with GitHub annotation.

```bash
log_error "Something went wrong"
# Output: ::error::Something went wrong
```

---

#### `log_warning`
Log a warning with GitHub annotation.

```bash
log_warning "This operation is dangerous"
# Output: ::warning::This operation is dangerous
```

---

#### `log_notice`
Log a notice/info message.

```bash
log_notice "Operation completed successfully"
# Output: ::notice::Operation completed successfully
```

---

### Advanced Error Handling

#### `fail`
Log error and exit with code.

```bash
fail "Validation failed" 10
# Logs error and exits with code 10
```

**Exit Codes** (conventional):
- 10: Validation failed
- 20: Terraform operation failed
- 30: Execution failed
- 40: Authentication failed
- 50: Timeout
- 60: Resource not found

---

#### `handle_terraform_error`
Handle Terraform-specific exit codes.

```bash
handle_terraform_error "plan" $? "/path/to/log"
```

**Interprets**:
- Exit 0 → Success
- Exit 1 → Error (logs last 20 lines of output)
- Exit 2 → Success with changes
- Other → Unexpected exit code

---

#### `handle_auth_error`
Handle authentication failures.

```bash
handle_auth_error "Azure" "arm_use_cli"
# Logs helpful error message about Azure auth
```

---

### Control Flow

#### `warn_destructive`
Warn before destructive operations.

```bash
warn_destructive "destroy" "production"
# Output: ::warning::DESTRUCTIVE OPERATION: About to destroy production...
```

---

#### `require_command`
Fail if required command not found.

```bash
require_command "terraform"
# Checks terraform exists in PATH
```

---

#### `require_env_var`
Fail if environment variable not set.

```bash
require_env_var "GITHUB_TOKEN"
# Checks GITHUB_TOKEN is set
```

---

### Logging Organization

#### `log_group` / `log_group_end`
Group related log lines for better visibility.

```bash
log_group "Terraform Initialization"
log_notice "Backend: my-storage"
log_notice "Region: eastus"
log_group_end
```

**Output**:
```
::group::Terraform Initialization
::notice::Backend: my-storage
::notice::Region: eastus
::endgroup::
```

---

## Error Handling Patterns

### Pattern 1: Validation Then Execute

```bash
#!/bin/bash
source "${{ github.action_path }}/../scripts/error-handler.sh"
source "${{ github.action_path }}/../scripts/validate-inputs.sh"

# Validate
log_group "Input Validation"
validate_plan_inputs "$env" "$dir" "$params" "$workspace"
log_group_end

# Execute
log_group "Terraform Execution"
terraform plan || fail "Plan failed" 20
log_group_end
```

---

### Pattern 2: Terraform-Specific Error Handling

```bash
source "${{ github.action_path }}/../scripts/error-handler.sh"

exitcode=0
terraform plan ... || exitcode=$?

echo "exitcode=$exitcode" >> $GITHUB_OUTPUT
handle_terraform_error "plan" "$exitcode"
```

---

### Pattern 3: Destructive Operations

```bash
source "${{ github.action_path }}/../scripts/error-handler.sh"

log_group "Terraform Destroy"
warn_destructive "destroy" "production"

terraform apply -destroy ... || fail "Destroy failed" 20

log_notice "✓ Terraform destroy completed"
log_group_end
```

---

### Pattern 4: Multi-Step Validation

```bash
source "${{ github.action_path }}/../scripts/error-handler.sh"
source "${{ github.action_path }}/../scripts/validate-inputs.sh"

# Validate multiple things
validate_required "param1" "$param1"
validate_directory "param2" "$param2"
validate_environment_name "$param3"

# All passed, continue
log_notice "All validations passed"
```

---

## GitHub Action Annotations

### Integration with GitHub UI

Errors, warnings, and notices appear in:

1. **Workflow Run Summary** - Grouped by step
2. **Annotations** - In pull request code review
3. **Job Logs** - Inline with command output
4. **Workflow Failure Status** - Errors mark workflow as failed

### Examples

**::error::**
```
::error::Terraform plan failed
```
Result: Red X, workflow fails

**::warning::**
```
::warning::Destructive operation: destroy
```
Result: Yellow triangle, workflow continues

**::notice::**
```
::notice::✓ Terraform initialized successfully
```
Result: Blue info, workflow continues

---

## Exit Codes

### Standard Exit Codes

| Code | Meaning | Typical Cause |
|------|---------|---------------|
| 0 | Success | Operation completed successfully |
| 1 | General error | Unspecified failure |
| 10 | Validation failed | Input validation error |
| 20 | Terraform failed | `terraform` command failed |
| 30 | Execution failed | Script/command execution error |
| 40 | Auth failed | Authentication/credential error |
| 50 | Timeout | Operation timed out |
| 60 | Not found | Required resource/file not found |

---

## Troubleshooting

### Issue: "Plan file not found"

```
::error::Plan file not found: prod.plan.tfplan
```

**Causes**:
- Plan action didn't run
- Plan action failed
- Different working directory between jobs
- Artifact download failed

**Solution**:
1. Check plan action logs
2. Verify working directories match
3. Confirm publish/download artifact names match

---

### Issue: "Validation failed: Invalid environment name"

```
::error::Invalid environment name 'prod!'. Use alphanumeric characters and hyphens only
```

**Cause**: Environment name contains invalid characters

**Solution**: Use only `[a-zA-Z0-9-]` in environment names

---

### Issue: "Required command 'terraform' not found in PATH"

```
::error::Required command 'terraform' not found in PATH
```

**Cause**: `setup` action didn't run or failed

**Solution**:
1. Ensure `setup` action runs before other actions
2. Check setup action logs for errors
3. Verify runner has bash available

---

## Best Practices

1. **Always Validate Early** - Validate all inputs before expensive operations
2. **Group Related Operations** - Use `log_group` for better readability
3. **Clear Error Messages** - Include expected vs. actual values
4. **Document Requirements** - Comment non-obvious validation rules
5. **Test Edge Cases** - Invalid names, missing files, etc.
6. **Use Consistent Patterns** - Maintain consistency across actions
7. **Fail Fast** - Return early on validation failures
8. **Provide Context** - Include file paths, environment names in errors

---

## Examples

### Example 1: Complete Validation

```bash
#!/bin/bash
set -euo pipefail

source "${{ github.action_path }}/../scripts/error-handler.sh"
source "${{ github.action_path }}/../scripts/validate-inputs.sh"

# Validate all inputs
log_group "Input Validation"
validate_required "environment" "${{ inputs.environment }}"
validate_directory "working_dir" "${{ inputs.working_dir }}"
validate_terraform_dir "${{ inputs.working_dir }}"
validate_files_in_dir "params_dir" \
  "${{ github.workspace }}/${{ inputs.params_dir }}" \
  "${{ inputs.environment }}-variables.tfvars"
log_group_end

# Execute
log_group "Terraform Plan"
cd "${{ inputs.working_dir }}"
terraform plan \
  -var-file="${{ github.workspace }}/${{ inputs.params_dir }}/${{ inputs.environment }}-variables.tfvars" \
  -out plan.tfplan || fail "Terraform plan failed" 20
log_group_end

log_notice "✓ All steps completed successfully"
```

---

## Migration Guide

### For Existing Actions

To add validation to an action:

1. Add validation step at the beginning
2. Source helper scripts
3. Call appropriate validation function
4. Update main step to use error handlers

**Before**:
```bash
terraform plan ... || exit 1
```

**After**:
```bash
source "${{ github.action_path }}/../scripts/error-handler.sh"
terraform plan ... || fail "Terraform plan failed" 20
```

---

