#!/bin/bash
# validate-inputs.sh
# Provides reusable input validation functions for GitHub Actions
# Source this script in action steps to validate inputs

set -euo pipefail

# Color output for better readability
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Validate that a required input is not empty
# Usage: validate_required "input_name" "$input_value"
validate_required() {
    local input_name="$1"
    local input_value="$2"
    
    if [ -z "$input_value" ]; then
        echo "::error::Required input '$input_name' is empty or not provided"
        return 1
    fi
    return 0
}

# Validate that a directory exists
# Usage: validate_directory "working_dir" "${{ inputs.working_dir }}"
validate_directory() {
    local input_name="$1"
    local directory="$2"
    
    if [ ! -d "$directory" ]; then
        echo "::error::Directory '$directory' specified in '$input_name' does not exist"
        return 1
    fi
    
    if [ ! -r "$directory" ]; then
        echo "::error::Directory '$directory' is not readable"
        return 1
    fi
    
    echo "::notice::✓ Directory validation passed: $directory"
    return 0
}

# Validate that a file exists
# Usage: validate_file "params_dir" "${{ github.workspace }}/terraform/environments"
validate_file() {
    local input_name="$1"
    local file_path="$2"
    
    if [ ! -f "$file_path" ]; then
        echo "::error::File '$file_path' specified in '$input_name' does not exist"
        return 1
    fi
    
    if [ ! -r "$file_path" ]; then
        echo "::error::File '$file_path' is not readable"
        return 1
    fi
    
    echo "::notice::✓ File validation passed: $file_path"
    return 0
}

# Validate that a directory contains specific files matching a pattern
# Usage: validate_files_in_dir "params_dir" "/path/to/dir" "prod-variables.tfvars"
validate_files_in_dir() {
    local input_name="$1"
    local directory="$2"
    local pattern="$3"
    
    if [ ! -d "$directory" ]; then
        echo "::error::Directory '$directory' does not exist"
        return 1
    fi
    
    local file_count
    file_count=$(find "$directory" -maxdepth 1 -name "$pattern" 2>/dev/null | wc -l)
    
    if [ "$file_count" -eq 0 ]; then
        echo "::error::No files matching pattern '$pattern' found in '$directory'"
        echo "::notice::Expected file format: {environment}-variables.tfvars"
        return 1
    fi
    
    echo "::notice::✓ Files validation passed: Found $file_count file(s) matching '$pattern'"
    return 0
}

# Validate environment name format (alphanumeric, hyphens allowed)
# Usage: validate_environment_name "prod"
validate_environment_name() {
    local env_name="$1"
    
    if ! [[ "$env_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$|^[a-zA-Z0-9]$ ]]; then
        echo "::error::Invalid environment name '$env_name'. Use alphanumeric characters and hyphens only"
        return 1
    fi
    
    echo "::notice::✓ Environment name validation passed: $env_name"
    return 0
}

# Validate that Terraform is installed
# Usage: validate_terraform_installed
validate_terraform_installed() {
    if ! command -v terraform &> /dev/null; then
        echo "::error::Terraform is not installed or not in PATH"
        return 1
    fi
    
    local tf_version
    tf_version=$(terraform version | head -n1)
    echo "::notice::✓ Terraform found: $tf_version"
    return 0
}

# Validate that a working directory contains Terraform files
# Usage: validate_terraform_dir "/path/to/terraform"
validate_terraform_dir() {
    local working_dir="$1"
    
    if [ ! -d "$working_dir" ]; then
        echo "::error::Working directory '$working_dir' does not exist"
        return 1
    fi
    
    # Check for .tf files
    local tf_files
    tf_files=$(find "$working_dir" -maxdepth 1 -name "*.tf" 2>/dev/null | wc -l)
    
    if [ "$tf_files" -eq 0 ]; then
        echo "::error::No Terraform files (*.tf) found in '$working_dir'"
        return 1
    fi
    
    echo "::notice::✓ Terraform directory validation passed: Found $tf_files Terraform file(s)"
    return 0
}

# Validate backend parameters for Azure Storage
# Usage: validate_azure_backend "my-rg" "mystorageaccount" "tfstate" "prod.tfstate"
validate_azure_backend() {
    local backend_rg="$1"
    local backend_sa="$2"
    local backend_sa_container="$3"
    local backend_sa_key="$4"
    
    # Validate required fields
    validate_required "backend_rg" "$backend_rg" || return 1
    validate_required "backend_sa" "$backend_sa" || return 1
    validate_required "backend_sa_container" "$backend_sa_container" || return 1
    validate_required "backend_sa_key" "$backend_sa_key" || return 1
    
    # Validate format of storage account name (3-24 chars, lowercase alphanumeric)
    if ! [[ "$backend_sa" =~ ^[a-z0-9]{3,24}$ ]]; then
        echo "::error::Invalid storage account name '$backend_sa'. Must be 3-24 lowercase alphanumeric characters"
        return 1
    fi
    
    # Validate resource group name format (1-90 chars, alphanumeric, dash, underscore, period)
    if ! [[ "$backend_rg" =~ ^[a-zA-Z0-9._-]{1,90}$ ]]; then
        echo "::error::Invalid resource group name '$backend_rg'"
        return 1
    fi
    
    echo "::notice::✓ Azure backend parameters validation passed"
    return 0
}

# Validate exit code is numeric
# Usage: validate_exit_code "2"
validate_exit_code() {
    local exit_code="$1"
    
    if ! [[ "$exit_code" =~ ^[0-9]+$ ]]; then
        echo "::error::Exit code must be numeric, got: '$exit_code'"
        return 1
    fi
    
    if [ "$exit_code" -gt 255 ]; then
        echo "::error::Exit code must be between 0 and 255, got: $exit_code"
        return 1
    fi
    
    echo "::notice::✓ Exit code validation passed: $exit_code"
    return 0
}

# Validate that output summary is not empty
# Usage: validate_summary "summary text..."
validate_summary() {
    local summary="$1"
    
    if [ -z "$summary" ]; then
        echo "::error::Output summary is empty"
        return 1
    fi
    
    if [ ${#summary} -lt 10 ]; then
        echo "::warning::Output summary is very short (${#summary} characters)"
    fi
    
    echo "::notice::✓ Summary validation passed"
    return 0
}

# Comprehensive validation for plan action inputs
# Usage: validate_plan_inputs "prod" "terraform/" "terraform/environments" "${{ github.workspace }}"
validate_plan_inputs() {
    local environment="$1"
    local working_dir="$2"
    local params_dir="$3"
    local workspace="$4"
    
    echo "::group::Validating plan action inputs"
    
    validate_required "environment" "$environment" || return 1
    validate_required "working_dir" "$working_dir" || return 1
    validate_required "params_dir" "$params_dir" || return 1
    
    validate_environment_name "$environment" || return 1
    validate_directory "working_dir" "$working_dir" || return 1
    validate_terraform_dir "$working_dir" || return 1
    validate_files_in_dir "params_dir" "$workspace/$params_dir" "$environment-variables.tfvars" || return 1
    
    echo "::endgroup::"
    echo "::notice::All plan action inputs validated successfully ✓"
    return 0
}

# Comprehensive validation for init action inputs
# Usage: validate_init_inputs "my-rg" "mystorageaccount" "tfstate" "prod.tfstate" "terraform/"
validate_init_inputs() {
    local backend_rg="$1"
    local backend_sa="$2"
    local backend_sa_container="$3"
    local backend_sa_key="$4"
    local working_dir="$5"
    
    echo "::group::Validating init action inputs"
    
    validate_azure_backend "$backend_rg" "$backend_sa" "$backend_sa_container" "$backend_sa_key" || return 1
    validate_required "working_dir" "$working_dir" || return 1
    validate_directory "working_dir" "$working_dir" || return 1
    
    echo "::endgroup::"
    echo "::notice::All init action inputs validated successfully ✓"
    return 0
}

# Error handler for use with 'trap'
# Captures line number and exit code
on_error() {
    local line_number=$1
    local exit_code=$2
    echo "::error::Action failed at line $line_number with exit code $exit_code"
    return "$exit_code"
}

# Export functions so they can be used in sourced scripts
export -f validate_required
export -f validate_directory
export -f validate_file
export -f validate_files_in_dir
export -f validate_environment_name
export -f validate_terraform_installed
export -f validate_terraform_dir
export -f validate_azure_backend
export -f validate_exit_code
export -f validate_summary
export -f validate_plan_inputs
export -f validate_init_inputs
export -f on_error

echo "::notice::Validation helper script loaded successfully"
