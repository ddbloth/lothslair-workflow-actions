# Priority 1 (Security):
1. Replace bash-embedded tokens with GitHub credential helpers
2. Add input validation and sanitization
3. Add secrets filtering to prevent accidental logging

# Priority 2 (Reliability):
4. Extract retry logic into a reusable helper
5. Standardize error handling across all actions
6. Add workspace/region awareness to artifact naming

# Priority 3 (Maintainability):
7. Fix input descriptions and naming conventions
8. Add more detailed output information
9. Create action tests/verification workflow
10. Add versioning and changelog documentation


# Current: ~50 lines of retry logic in init, ~40 in plan
# Better: Create a shared _retry action or script

Strengths ✅
Composable/Modular Design: Excellent separation of concerns - each action does one thing well
Reusability: Perfect for creating DRY workflows across multiple repositories
Environment Parameterization: Good support for multi-environment deployments (dev/staging/prod)
Artifact Strategy: Smart use of publish/download for multi-job approval workflows
Drift Detection: Nice addition for compliance and observability
Error Handling: Includes retry logic for transient failures
Concerns & Areas for Improvement ⚠️
1. Secret Management Issues 🔴
The init action exposes GitHub token in bash script: Git config via CLI embeds credentials in environment/history
Better approach: Use SSH keys or Git credential helpers instead
Risk: Token could leak in logs or process history

# Current (risky):
git config --global url."https://oauth2:${{inputs.github_token}}@github.com"

# Better:
# Use SSH keys or GitHub's credential helper

2. Incomplete Descriptions & Input Naming 🟡
init action's backend_sa_key input has a mismatched description: "Specify Terraform plan command extra arguments" (copy-paste error)
Input names are slightly awkward: tf_actions_working_dir could be working_dir or terraform_dir
Missing descriptions on several inputs
3. Bash Script Complexity 🟡
Heavy bash logic in composite actions reduces maintainability
Retry logic is duplicated between init and plan actions
Better: Extract shared retry logic into a separate action or use external scripts
4. Exit Code Handling 🟡
plan-destroy doesn't match plan behavior (less forgiving retry logic)
Inconsistency could cause workflows to fail unexpectedly
Should standardize error handling across all plan-type actions
5. Plan File Naming Convention 🟡
Using {environment}.plan.tfplan assumes unique environments per run
If multiple regions/workspaces exist, this will collide
Better: {environment}-{workspace}.plan.tfplan or include run ID
6. Missing Security Best Practices 🔴
No input validation: Actions don't validate that backends/environments exist
No error output sanitization: Backend secrets could appear in logs
No RBAC considerations: All actions assume same permission level
7. Artifact Naming Collision Risk 🟡
publish/download use {environment}{github.run_id}
If same workflow runs multiple times with different matrices, this could collide
Better: Include branch name or additional context
8. Missing Output Descriptions 🟡
plan returns exitcode but no output for apply
Should output resource counts, drift summary, etc. for better reporting
9. Terraform Wrapper Disabled 🟡
setup disables wrapper but doesn't document why
Wrapper provides better output formatting, could be beneficial
Should be a configurable option
10. No Action Versioning Strategy 🟡
Repository structure suggests semantic versioning via git tags
But no guidance on how consumers should pin versions
No changelog or migration guide