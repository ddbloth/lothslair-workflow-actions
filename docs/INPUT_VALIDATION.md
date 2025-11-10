# Input Validation Best Practices

## Overview

All `lothslair-workflow-actions` actions now include comprehensive input validation using reusable helper scripts. This guide explains the validation approach and how to use it.

---

## Validation Strategy

### Three Validation Layers

1. **GitHub Actions YAML** - Type checking and required fields
2. **Shell Script Validation** - Runtime validation of values
3. **Terraform Validation** - Backend/configuration validation

### Example: Complete Validation Flow

```yaml
name: Terraform Init
inputs:
  backend_rg:
    required: true          # Layer 1: YAML requirement
    type: string
    description: '...'

runs:
  using: "composite"
  steps:
    - name: Validate Inputs  # Layer 2: Shell validation
      shell: bash
      run: |
        source scripts/validate-inputs.sh
        validate_azure_backend "${{ inputs.backend_rg }}" ...
    
    - name: Terraform Init   # Layer 3: Terraform validation
      run: |
        terraform init ...   # Terraform validates backend config
```

---

## Validation Checklist by Action

### `init` Action

```bash
✓ backend_rg          - Required string, valid Azure RG name format
✓ backend_sa          - Required string, 3-24 lowercase alphanumeric
✓ backend_sa_container - Required string, not empty
✓ backend_sa_key      - Required string, not empty
✓ working_dir         - Required directory that exists
✓ github_token        - Optional string for git auth
```

**Validation Function**: `validate_init_inputs`

---

### `plan` Action

```bash
✓ environment         - Required, alphanumeric + hyphens
✓ working_dir         - Required directory containing *.tf files
✓ params_dir          - Required directory containing {env}-variables.tfvars
```

**Validation Function**: `validate_plan_inputs`

---

### `plan-destroy` Action

Same validation as `plan`.

**Validation Function**: `validate_plan_inputs`

---

### `apply` Action

```bash
✓ environment         - Required string, not empty
✓ working_dir         - Required directory that exists
✓ {env}.plan.tfplan   - Plan file must exist (validated before apply)
```

**Validation Function**: Basic validation + file existence check

---

### `destroy` Action

Same as `plan` (requires variable file).

**Validation Function**: `validate_plan_inputs`

---

### `validate` Action

```bash
✓ working_dir         - Required directory containing *.tf files
```

**Validation Function**: Built-in validation

---

### `format` Action

```bash
✓ working_dir         - Required directory containing *.tf files
✓ check_only          - Optional boolean
```

**Validation Function**: Built-in validation

---

### `publish` / `download` Actions

```bash
✓ environment         - Required, used in artifact naming
✓ working_dir         - Required directory
```

**Validation Function**: Basic validation

---

### `summary` Action

```bash
✓ environment         - Required string
✓ working_dir         - Required directory
✓ {env}.plan.tfplan   - Plan file must exist
```

**Validation Function**: Basic validation + file existence

---

### `push-pr` Action

```bash
✓ github_token        - Required string
✓ summary             - Required string (not empty)
```

**Validation Function**: `validate_summary`

---

### `drift` Action

```bash
✓ github_token        - Required string
✓ plan_exit_code      - Required, numeric (0, 1, or 2)
✓ output_summary      - Required string (not empty)
```

**Validation Function**: `validate_exit_code` + `validate_summary`

---

## Common Validation Patterns

### Pattern 1: Directory Validation

```bash
validate_directory "working_dir" "${{ inputs.working_dir }}"
# Checks: exists, is directory, readable
```

---

### Pattern 2: File Existence

```bash
validate_file "plan_file" "$working_dir/$environment.plan.tfplan"
# Checks: exists, is file, readable
```

---

### Pattern 3: Directory Contents

```bash
validate_files_in_dir "params_dir" \
  "${{ github.workspace }}/${{ inputs.params_dir }}" \
  "${{ inputs.environment }}-variables.tfvars"
# Checks: directory exists, contains matching files
```

---

### Pattern 4: Name Format

```bash
validate_environment_name "${{ inputs.environment }}"
# Checks: alphanumeric + hyphens only, not empty
```

---

### Pattern 5: Azure Resources

```bash
validate_azure_backend \
  "${{ inputs.backend_rg }}" \
  "${{ inputs.backend_sa }}" \
  "${{ inputs.backend_sa_container }}" \
  "${{ inputs.backend_sa_key }}"
# Checks: all required, correct format for Azure naming
```

---

## Validation Error Messages

### Clear, Actionable Errors

Each validation produces specific error messages:

```
✗ Required input 'backend_rg' is empty or not provided
  Action: Provide backend_rg input to the action

✗ Directory '/terraform' does not exist
  Action: Create directory or correct working_dir input

✗ Invalid storage account name 'my-storage-ACCOUNT'
  Action: Use only lowercase letters and numbers (3-24 chars)

✗ No files matching 'prod-variables.tfvars' found
  Action: Create prod-variables.tfvars in terraform/environments/

✗ Exit code must be numeric, got: 'invalid'
  Action: Ensure plan_exit_code is 0, 1, or 2
```

---

## Adding Validation to Your Workflows

### Step 1: Always Validate Early

Place validation as the first step:

```yaml
steps:
  - uses: actions/checkout@v4
  
  # Validation runs early
  - uses: lothslair/lothslair-workflow-actions/plan@main
    # Validation runs automatically before plan
```

---

### Step 2: Provide Clear Inputs

Ensure all inputs are defined:

```yaml
- uses: lothslair/lothslair-workflow-actions/plan@main
  with:
    environment: 'prod'              # ✓ Valid
    working_dir: 'terraform/'        # ✓ Must exist
    params_dir: 'terraform/environments'  # ✓ Must exist
```

---

### Step 3: Structure Your Repository

```
.
├── terraform/
│   ├── *.tf files
│   └── environments/
│       ├── dev-variables.tfvars
│       ├── staging-variables.tfvars
│       └── prod-variables.tfvars
└── .github/workflows/
    └── terraform.yml
```

---

## Validation Failures

### When Validation Fails

1. **Action stops immediately** - Doesn't proceed to Terraform operation
2. **Clear error message** - Indicates what validation failed
3. **Workflow marked red** - Shows validation error in UI
4. **Next steps clear** - Error message indicates how to fix

### Example Failure Output

```
::group::Input Validation
::error::Invalid environment name 'prod!'. Use alphanumeric characters and hyphens only
::endgroup::

Error: Process completed with exit code 10.
```

---

## Validation Performance

Validation is **lightweight and fast**:

- Basic checks: < 10ms
- Directory validation: < 50ms
- File existence: < 5ms
- **Total time**: < 100ms for full validation

**No performance impact** on workflow runs.

---

## Skipping Validation (Not Recommended)

If you need to bypass validation (not recommended):

```bash
# Don't do this in production!
set +e  # Disable error checking
source validate-inputs.sh
validate_required ... || true  # Ignore errors
set -e
```

**Why not skip?**
- Harder to debug failures
- Silent failures are worse than loud ones
- Validation catches issues early
- Performance impact is negligible

---

## Testing Validation

### Manual Testing

Test validation locally:

```bash
source scripts/validate-inputs.sh
source scripts/error-handler.sh

# Test valid input
validate_environment_name "prod"        # ✓ Pass
validate_environment_name "prod!"       # ✗ Fail
```

---

### Workflow Testing

Create a test workflow:

```yaml
name: Test Validation

on: workflow_dispatch

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: lothslair/lothslair-workflow-actions/validate@main
        with:
          working_dir: 'terraform/'
      
      # If we get here, validation passed
      - run: echo "✓ Validation successful"
```

---

## Migration from Old Validation

### Old Approach (No Validation)

```bash
#!/bin/bash
cd "$working_dir"
terraform plan ...  # Hope inputs are valid
```

**Problems**:
- Fails deep in Terraform
- Unclear error messages
- Hard to debug

---

### New Approach (With Validation)

```bash
#!/bin/bash
source scripts/validate-inputs.sh
source scripts/error-handler.sh

validate_plan_inputs "$env" "$dir" "$params" "$workspace"

cd "$working_dir"
terraform plan ... || fail "Terraform failed" 20
```

**Benefits**:
- Fails early with clear message
- Easy to debug
- Professional error output

---

## Reference

### Validation Functions

| Function | Use Case | Exit Code on Failure |
|----------|----------|---------------------|
| `validate_required` | Any required field | 1 |
| `validate_directory` | Directory inputs | 1 |
| `validate_file` | File inputs | 1 |
| `validate_environment_name` | Environment parameter | 1 |
| `validate_azure_backend` | Backend parameters | 1 |
| `validate_terraform_dir` | Terraform working dir | 1 |
| `validate_exit_code` | Terraform exit codes | 1 |
| `validate_summary` | Output summaries | 1 |
| `validate_plan_inputs` | Complete plan validation | 1 |
| `validate_init_inputs` | Complete init validation | 1 |

---

## Support

For validation issues or questions:

1. Check error message for specific problem
2. Review this guide for your use case
3. Check action documentation in README.md
4. Open issue if error is unclear

