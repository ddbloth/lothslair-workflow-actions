#!/bin/bash
# error-handler.sh
# Provides standardized error handling patterns for GitHub Actions
# Source this script to use consistent error, warning, and notice patterns

set -euo pipefail

# Error levels and their GitHub Action annotations
readonly ERROR_LEVEL_ERROR="::error::"
readonly ERROR_LEVEL_WARNING="::warning::"
readonly ERROR_LEVEL_NOTICE="::notice::"

# Standard error codes
readonly ERROR_VALIDATION_FAILED=10
readonly ERROR_TERRAFORM_FAILED=20
readonly ERROR_EXECUTION_FAILED=30
readonly ERROR_AUTHENTICATION_FAILED=40
readonly ERROR_TIMEOUT=50
readonly ERROR_RESOURCE_NOT_FOUND=60

# Log an error message with GitHub annotation
# Usage: log_error "Something went wrong"
log_error() {
    local message="$1"
    echo "${ERROR_LEVEL_ERROR}${message}"
}

# Log a warning message with GitHub annotation
# Usage: log_warning "Something might be wrong"
log_warning() {
    local message="$1"
    echo "${ERROR_LEVEL_WARNING}${message}"
}

# Log a notice message with GitHub annotation
# Usage: log_notice "Operation completed"
log_notice() {
    local message="$1"
    echo "${ERROR_LEVEL_NOTICE}${message}"
}

# Log an error and exit with code
# Usage: fail "Validation failed" 10
fail() {
    local message="$1"
    local exit_code="${2:-1}"
    log_error "$message"
    exit "$exit_code"
}

# Log a warning for potentially destructive operations
# Usage: warn_destructive "destroy" "production"
warn_destructive() {
    local operation="$1"
    local target="${2:-infrastructure}"
    log_warning "DESTRUCTIVE OPERATION: About to $operation $target. This cannot be undone."
}

# Handle Terraform-specific errors
# Usage: handle_terraform_error "plan" "$?" "/path/to/log"
handle_terraform_error() {
    local terraform_operation="$1"
    local exit_code="$2"
    local log_file="${3:-}"
    
    case "$exit_code" in
        0)
            log_notice "Terraform $terraform_operation succeeded"
            return 0
            ;;
        1)
            log_error "Terraform $terraform_operation failed with errors"
            if [ -n "$log_file" ] && [ -f "$log_file" ]; then
                log_error "Last 20 lines of logs:"
                tail -20 "$log_file" | sed 's/^/  /'
            fi
            return "$ERROR_TERRAFORM_FAILED"
            ;;
        2)
            log_notice "Terraform $terraform_operation succeeded with changes detected"
            return 0
            ;;
        *)
            log_error "Terraform $terraform_operation exited with unexpected code: $exit_code"
            return "$ERROR_EXECUTION_FAILED"
            ;;
    esac
}

# Handle authentication errors
# Usage: handle_auth_error "Azure" "arm_use_cli"
handle_auth_error() {
    local service="$1"
    local method="${2:-}"
    log_error "Authentication failed for $service"
    if [ -n "$method" ]; then
        log_error "Attempted method: $method"
        log_error "Verify credentials are configured correctly in GitHub Actions environment"
    fi
    return "$ERROR_AUTHENTICATION_FAILED"
}

# Validate command exists in PATH
# Usage: require_command "terraform"
require_command() {
    local command="$1"
    
    if ! command -v "$command" &> /dev/null; then
        fail "Required command '$command' not found in PATH" "$ERROR_EXECUTION_FAILED"
    fi
    
    log_notice "✓ Command found: $command"
}

# Validate environment variable is set
# Usage: require_env_var "GITHUB_TOKEN"
require_env_var() {
    local var_name="$1"
    
    if [ -z "${!var_name:-}" ]; then
        fail "Required environment variable '$var_name' is not set" "$ERROR_VALIDATION_FAILED"
    fi
    
    log_notice "✓ Environment variable set: $var_name"
}

# Retry a command with exponential backoff
# Usage: retry_with_backoff "terraform apply" 3 2
retry_with_backoff() {
    local command="$1"
    local max_attempts="${2:-3}"
    local initial_delay="${3:-2}"
    
    local attempt=1
    local delay=$initial_delay
    
    while [ $attempt -le $max_attempts ]; do
        log_notice "Attempt $attempt/$max_attempts: $command"
        
        if eval "$command"; then
            log_notice "✓ Command succeeded on attempt $attempt"
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_warning "Command failed on attempt $attempt, retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "Command failed after $max_attempts attempts"
    return 1
}

# Create a stack trace of where an error occurred
# Usage: print_stack_trace (typically called from trap handler)
print_stack_trace() {
    local frame=0
    log_error "Stack trace:"
    while caller $frame 2>/dev/null; do
        frame=$((frame + 1))
    done | sed 's/^/  /'
}

# Set up error trap to log stack trace on error
# Usage: setup_error_trap
setup_error_trap() {
    trap 'log_error "Error occurred in script"; print_stack_trace; exit 1' ERR
}

# Validate exit code and handle accordingly
# Usage: check_exit_code $? "terraform plan"
check_exit_code() {
    local exit_code="$1"
    local operation="${2:-Command}"
    
    if [ "$exit_code" -ne 0 ]; then
        log_error "$operation failed with exit code $exit_code"
        return "$exit_code"
    fi
    
    log_notice "✓ $operation completed successfully"
    return 0
}

# Output grouped logs for better visibility
# Usage: log_group "Initialization" "terraform init"
log_group() {
    local group_name="$1"
    local message="${2:-}"
    
    echo "::group::$group_name"
    if [ -n "$message" ]; then
        log_notice "$message"
    fi
}

# Close a log group
# Usage: log_group_end
log_group_end() {
    echo "::endgroup::"
}

# Format a duration in seconds to human-readable format
# Usage: format_duration 125
format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    printf "%02d:%02d:%02d" "$hours" "$minutes" "$secs"
}

# Log operation timing
# Usage: log_duration "Terraform plan" 125
log_duration() {
    local operation="$1"
    local duration="$2"
    local formatted
    formatted=$(format_duration "$duration")
    log_notice "$operation completed in $formatted"
}

# Create a debug dump for troubleshooting
# Usage: debug_dump "plan" "/path/to/planfile"
debug_dump() {
    local operation="$1"
    local file_path="${2:-}"
    
    log_group "Debug Information"
    
    log_notice "Operation: $operation"
    log_notice "Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    log_notice "Working directory: $(pwd)"
    log_notice "User: $(whoami)"
    
    if [ -n "$file_path" ] && [ -f "$file_path" ]; then
        log_notice "File: $file_path"
        log_notice "File size: $(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo 'unknown')"
    fi
    
    log_group_end
}

# Sanitize output to prevent secret leakage
# Usage: sanitize_output "my secret password"
sanitize_output() {
    local output="$1"
    # Remove common patterns that might contain secrets
    echo "$output" | sed 's/oauth2:[^@]*@/oauth2:***@/g' | sed 's/Bearer [^ ]*/Bearer ***/g'
}

# Export functions
export -f log_error
export -f log_warning
export -f log_notice
export -f fail
export -f warn_destructive
export -f handle_terraform_error
export -f handle_auth_error
export -f require_command
export -f require_env_var
export -f retry_with_backoff
export -f print_stack_trace
export -f setup_error_trap
export -f check_exit_code
export -f log_group
export -f log_group_end
export -f format_duration
export -f log_duration
export -f debug_dump
export -f sanitize_output

log_notice "Error handling helper script loaded successfully"
