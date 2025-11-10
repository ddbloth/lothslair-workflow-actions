# Workflow Architecture & Data Flow

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     GitHub Actions Workflow                             │
└─────────────────────────────────────────────────────────────────────────┘

   Manual Trigger
   (workflow_dispatch)
           │
           ▼
    ┌──────────────┐
    │   INPUTS     │
    ├──────────────┤
    │ environment  │ (dev, staging, prod)
    │ deployment   │ (core, networking, etc.)
    └──────────────┘
           │
           ▼
    ╔═════════════════════════════════════════════════════════════════════╗
    ║                      7-STAGE DEPLOYMENT                            ║
    ╠═════════════════════════════════════════════════════════════════════╣
    ║                                                                     ║
    ║  ┌─ Stage 1: SETUP & VALIDATE ────────────────────────────────┐  ║
    ║  │ • Setup Terraform                                          │  ║
    ║  │ • Validate configuration syntax                            │  ║
    ║  │ • Check code formatting                                    │  ║
    ║  │ • Set output variables                                     │  ║
    ║  │ ✓ All parallel, no state ops                               │  ║
    ║  └────────────────────────────────────────────────────────────┘  ║
    ║           │                                                       ║
    ║           ▼                                                       ║
    ║  ┌─ Stage 2: INITIALIZE BACKEND ──────────────────────────────┐  ║
    ║  │ • Authenticate with Azure                                  │  ║
    ║  │ • Configure Terraform backend                              │  ║
    ║  │ • Lock state file                                          │  ║
    ║  │ • Initialize working directory                             │  ║
    ║  │ ✓ Required for plan/apply stages                           │  ║
    ║  └────────────────────────────────────────────────────────────┘  ║
    ║           │                                                       ║
    ║           ▼                                                       ║
    ║  ┌─ Stage 3: PLAN ─────────────────────────────────────────────┐  ║
    ║  │ • Read Terraform code                                      │  ║
    ║  │ • Load environment variables                                │  ║
    ║  │ • Compare against current state                            │  ║
    ║  │ • Generate .tfplan file                                    │  ║
    ║  │ • Create human-readable summary                            │  ║
    ║  │ Output: exit_code (0=no-change, 2=change, 1=error)        │  ║
    ║  └────────────────────────────────────────────────────────────┘  ║
    ║           │                                                       ║
    ║           ├─ No Changes (exit_code=0) ────┐                      ║
    ║           │                                │                      ║
    ║           │                      SKIP APPLY & CONTINUE            ║
    ║           │                                │                      ║
    ║           │                       (Drift Detection)               ║
    ║           │                                │                      ║
    ║           └────────────┬───────────────────┘                      ║
    ║                        │                                          ║
    ║           Changes Detected (exit_code=2)                          ║
    ║                        │                                          ║
    ║                        ▼                                          ║
    ║  ┌─ Stage 4: APPROVAL GATE ────────────────────────────────────┐  ║
    ║  │ • Create GitHub Issue                                      │  ║
    ║  │ • Request team approval                                    │  ║
    ║  │ • BLOCK: Wait for /approve comment                         │  ║
    ║  │ • Manual gate before production changes                    │  ║
    ║  └────────────────────────────────────────────────────────────┘  ║
    ║           │                                                       ║
    ║           ▼                                                       ║
    ║  ┌─ Stage 5: APPLY ─────────────────────────────────────────────┐  ║
    ║  │ • Download plan artifact (.tfplan)                          │  ║
    ║  │ • Execute terraform apply -plan-file=...                    │  ║
    ║  │ • Update infrastructure state                               │  ║
    ║  │ • Update state in Azure Storage backend                     │  ║
    ║  │ • Generate post-apply summary                               │  ║
    ║  │ ✓ Only if plan had changes                                 │  ║
    ║  └────────────────────────────────────────────────────────────┘  ║
    ║           │                                                       ║
    ║           ▼                                                       ║
    ║  ┌─ Stage 6: DRIFT DETECTION ──────────────────────────────────┐  ║
    ║  │ • Run terraform plan (read-only)                            │  ║
    ║  │ • Compare actual vs desired infrastructure                  │  ║
    ║  │ • Detect manual changes to resources                        │  ║
    ║  │ • Alert on configuration drift                              │  ║
    ║  │ ✓ Optional, runs after apply (or independently)             │  ║
    ║  └────────────────────────────────────────────────────────────┘  ║
    ║           │                                                       ║
    ║           ▼                                                       ║
    ║  ┌─ Stage 7: SUMMARY ───────────────────────────────────────────┐  ║
    ║  │ • Collect stage results                                     │  ║
    ║  │ • Create GitHub Step Summary                                │  ║
    ║  │ • Report success/failure                                    │  ║
    ║  │ • Log audit trail                                           │  ║
    ║  └────────────────────────────────────────────────────────────┘  ║
    ║                                                                     ║
    ╚═════════════════════════════════════════════════════════════════════╝
           │
           ▼
    ┌──────────────────┐
    │  DEPLOYMENT      │
    │  COMPLETE        │
    └──────────────────┘
```

---

## Data Flow Diagram

```
GitHub Repository
│
├─ Code
│  ├─ terraform/
│  │  ├─ main.tf
│  │  ├─ variables.tf
│  │  └─ environments/
│  │     ├─ dev-variables.tfvars
│  │     ├─ staging-variables.tfvars
│  │     └─ prod-variables.tfvars
│  │
│  └─ .github/workflows/
│     └─ deploy.yml
│
└─ Secrets (GitHub Settings)
   ├─ BACKEND_RG
   ├─ BACKEND_SA
   ├─ BACKEND_CONTAINER
   ├─ AZURE_AD_CLIENT_ID
   └─ AZURE_AD_TENANT_ID

        │
        ▼
   ┌─────────────────────────────────┐
   │   GitHub Actions Runtime        │
   ├─────────────────────────────────┤
   │ 1. Checkout repository          │
   │ 2. Setup Terraform              │
   │ 3. Load secrets → env vars      │
   │ 4. Authenticate with Azure      │
   └─────────────────────────────────┘
        │
        ▼
   ┌──────────────────────────────────────────────────────┐
   │       Terraform Working Directory                    │
   ├──────────────────────────────────────────────────────┤
   │ .terraform/                                          │
   │ ├─ lock.hcl                                          │
   │ └─ backend-config/                                   │
   │    └─ (Azure Storage credentials)                   │
   │                                                      │
   │ Working files (generated):                           │
   │ ├─ terraform.tfstate.d/                              │
   │ ├─ plan files (.tfplan)                              │
   │ └─ temp files                                        │
   └──────────────────────────────────────────────────────┘
        │
        ▼
   ┌──────────────────────────────────────────────────────┐
   │    Azure Storage Account (State Backend)             │
   ├──────────────────────────────────────────────────────┤
   │ Resource Group: BACKEND_RG                           │
   │ Storage Account: BACKEND_SA                          │
   │ Container: BACKEND_CONTAINER                         │
   │                                                      │
   │ State Files:                                         │
   │ ├─ dev.tfstate                                       │
   │ ├─ staging.tfstate                                   │
   │ └─ prod.tfstate                                      │
   │                                                      │
   │ Locks:                                               │
   │ ├─ dev.tfstate.lock                                  │
   │ ├─ staging.tfstate.lock                              │
   │ └─ prod.tfstate.lock                                 │
   └──────────────────────────────────────────────────────┘
        │
        ▼
   ┌──────────────────────────────────────────────────────┐
   │         Azure Infrastructure                         │
   ├──────────────────────────────────────────────────────┤
   │ • Resource Groups                                    │
   │ • Virtual Networks                                   │
   │ • Compute Resources                                  │
   │ • Storage Accounts                                   │
   │ • Databases                                          │
   │ (Managed by Terraform)                               │
   └──────────────────────────────────────────────────────┘
```

---

## Artifact & File Flow

```
┌─ Stage 1: Setup & Validate
│
│  Generated Artifacts:
│  ├─ Output variables (plan_file, summary_file)
│  └─ Validation reports (logs only)
│
├─ Stage 2: Initialize
│
│  Azure Storage → Downloads:
│  ├─ Current state file
│  ├─ Lock file
│  └─ Backend config
│
│  Uploads back:
│  └─ Lock file (state is locked during plan/apply)
│
├─ Stage 3: Plan
│
│  Generated:
│  ├─ terraform.tfplan (binary plan file)
│  ├─ prod-prod.tfplan (published to artifacts)
│  └─ prod-prod.summary (human-readable text)
│
│  Published Artifacts:
│  ├─ Workflow run artifacts (90-day retention)
│  ├─ GitHub Step Summary (inline)
│  └─ Plan file for download in apply stage
│
├─ Stage 4: Approval Gate
│
│  Generated:
│  └─ GitHub Issue (#123)
│     - Title: "[Approval] Terraform Deploy prod: prod"
│     - Body: Deployment details, links to plan
│     - Status: Awaiting /approve comment
│
├─ Stage 5: Apply
│
│  Downloaded:
│  └─ prod-prod.tfplan (from workflow artifacts)
│
│  Azure Storage:
│  └─ Current prod.tfstate
│
│  Executes:
│  └─ terraform apply -no-input -plan-file=prod.tfplan
│
│  Uploads:
│  └─ Updated prod.tfstate (with new resources)
│
│  Generated:
│  ├─ Apply logs
│  ├─ Post-apply summary
│  └─ Resource IDs and outputs
│
├─ Stage 6: Drift Detection
│
│  Reads:
│  ├─ Current infrastructure (AWS, Azure, GCP)
│  ├─ Terraform state (from backend)
│  └─ Terraform code
│
│  Generated:
│  └─ Drift report
│     - No drift detected
│     - OR: Manual changes detected (alert!)
│
└─ Stage 7: Summary
   
   Aggregates:
   ├─ All stage results
   ├─ Exit codes
   └─ Execution times
   
   Published to:
   ├─ GitHub Step Summary
   ├─ Workflow logs
   └─ Job summary
```

---

## Decision Tree

```
START: workflow_dispatch triggered
│
▼
Input Validation ─[FAIL]─────────────────────────── ERROR STOP
│
├─ environment: dev, staging, prod? ✓
└─ deployment_name: non-empty? ✓
│
▼
Stage 1: Setup & Validate ─[FAIL]────────────────── ERROR STOP
│
├─ Checkout code? ✓
├─ Setup Terraform? ✓
├─ Validate syntax? ✓
└─ Check formatting? ✓
│
▼
Stage 2: Initialize ─[FAIL]───────────────────────── ERROR STOP
│
├─ Azure authentication? ✓
├─ Backend accessible? ✓
└─ State lockable? ✓
│
▼
Stage 3: Plan ─[FAIL]─────────────────────────────── ERROR STOP
│
├─ Terraform plan executed? ✓
│
└─ exit_code?
   │
   ├─ exit_code = 0 (No changes)
   │  │
   │  └─────────────► Drift Detection
   │                   │
   │                   └─► Summary ──► COMPLETE
   │
   ├─ exit_code = 1 (Error)
   │  │
   │  └─────────────► ERROR STOP
   │
   └─ exit_code = 2 (Changes)
      │
      ▼
      Stage 4: Approval Gate
      │
      ├─ Create approval issue
      │
      └─ [WAIT FOR /approve COMMENT]
         │
         ├─ [/approve commented] ──► Continue
         │
         └─ [/deny commented] ────► CANCELLED
      
      ▼
      Stage 5: Apply
      │
      ├─ Download plan? ✓
      ├─ Execute apply? ✓
      ├─ Update state? ✓
      │
      └─ [FAIL]──────────────────── ROLLBACK (optional)
      │
      ▼
      Stage 6: Drift Detection
      │
      ├─ Check for drift? ✓
      │
      └─ [Drift detected?]
         │
         ├─ [No] ──► Continue
         │
         └─ [Yes] ─► ALERT (recoverable)
      │
      ▼
      Stage 7: Summary
      │
      ├─ Report results
      └─ Close approval issue
      
      ▼
      COMPLETE ✅
```

---

## Communication Channels

```
GitHub Actions Workflow
│
├─ ::error:: annotations
│  └─ Critical failures (appear in workflow summary)
│
├─ ::warning:: annotations
│  └─ Warnings (production changes detected)
│
├─ ::notice:: annotations
│  └─ Informational (stage completions)
│
├─ Step Summary
│  └─ $GITHUB_STEP_SUMMARY (inline status table)
│
├─ GitHub Issues
│  └─ Approval gate issues
│
├─ Artifacts
│  └─ Plan files, summaries (downloadable)
│
└─ Job Logs
   └─ Detailed execution logs (searchable)

        │
        ▼
   ┌─────────────────────────────┐
   │   Team Notifications        │
   ├─────────────────────────────┤
   │ • GitHub email notifications│
   │ • GitHub web dashboard      │
   │ • CI/CD status checks       │
   │ • Slack (optional)          │
   │ • Email (optional)          │
   │ • PagerDuty (optional)      │
   └─────────────────────────────┘
```

---

## Concurrency & Locking

```
┌─────────────────────────────────────────────┐
│         GitHub Concurrency Control          │
├─────────────────────────────────────────────┤
│                                             │
│ concurrency:                                │
│   group: terraform-deploy-${{ env }}        │
│   cancel-in-progress: false                 │
│                                             │
│ ✓ One deploy per environment at a time      │
│ ✓ Prevents simultaneous state modifications │
│ ✓ No cancellation of in-flight deploys      │
│                                             │
└─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────┐
│      Terraform State File Locking           │
├─────────────────────────────────────────────┤
│                                             │
│ Stage 2: Initialize                         │
│   └─ CREATE lock: dev.tfstate.lock          │
│                                             │
│ Stage 3: Plan                               │
│   └─ HOLD lock: dev.tfstate.lock            │
│      (Read-only operations allowed)         │
│                                             │
│ Stage 5: Apply                              │
│   └─ HOLD lock: dev.tfstate.lock            │
│      (Write operations proceed)             │
│                                             │
│ Stage Exit                                  │
│   └─ RELEASE lock: dev.tfstate.lock         │
│      (Lock expires)                         │
│                                             │
│ ✓ Prevents concurrent modifications         │
│ ✓ Automatic lock expiration (15 min)        │
│ ✓ Recoverable if workflow crashes           │
│                                             │
└─────────────────────────────────────────────┘
```

---

## Security Boundary

```
┌──────────────────────────────────────────────┐
│    GitHub Repository (Public/Private)        │
├──────────────────────────────────────────────┤
│                                              │
│  Code Layer (Git-tracked):                   │
│  ├─ Terraform configurations                 │
│  ├─ Workflow definitions                     │
│  └─ NOT: Secrets, credentials                │
│                                              │
│  Environment Protection:                     │
│  └─ Prod environment requires approval       │
│     rules and/or specific branch             │
│                                              │
│  Secrets Layer (NOT Git-tracked):            │
│  ├─ BACKEND_RG                               │
│  ├─ BACKEND_SA                               │
│  ├─ BACKEND_CONTAINER                        │
│  ├─ AZURE_AD_CLIENT_ID                       │
│  └─ AZURE_AD_TENANT_ID                       │
│                                              │
└──────────────────────────────────────────────┘
         │
         │ (Encrypted in transit)
         │
         ▼
┌──────────────────────────────────────────────┐
│    GitHub Actions Runner (Ephemeral)         │
├──────────────────────────────────────────────┤
│                                              │
│  Secrets injected as environment variables   │
│  (NOT visible in logs or process listings)   │
│                                              │
│  Authentication:                             │
│  ├─ GitHub CLI (secure token handling)       │
│  ├─ Azure CLI (OIDC federation)              │
│  └─ ARM_USE_CLI=true (no embedded creds)     │
│                                              │
│  Execution (Isolated):                       │
│  ├─ Temporary workspace                      │
│  ├─ No persistence between runs               │
│  └─ Automatic cleanup on exit                │
│                                              │
└──────────────────────────────────────────────┘
         │
         │ (Authenticated connection)
         │
         ▼
┌──────────────────────────────────────────────┐
│      Azure Cloud (Infrastructure)            │
├──────────────────────────────────────────────┤
│                                              │
│  Storage Account (State Backend)             │
│  ├─ Access restricted to service principal   │
│  ├─ Encrypted at rest                        │
│  ├─ Access logs maintained                   │
│  └─ Point-in-time recovery enabled           │
│                                              │
│  Infrastructure Resources                   │
│  ├─ Deployed by authenticated principal      │
│  ├─ RBAC permissions validated               │
│  ├─ Resource locks (optional)                │
│  └─ Audit trail in Activity Log              │
│                                              │
└──────────────────────────────────────────────┘
```

---

## Resource Cleanup

```
Workflow Artifacts (GitHub)
├─ Terraform plans (.tfplan)
├─ Summaries
├─ Logs
│
└─ Retention Policy:
   ├─ Default: 90 days
   ├─ Configurable per workflow
   └─ Auto-deleted after retention expires

State Files (Azure Storage)
├─ Current state (.tfstate)
├─ Lock files (.tfstate.lock)
│
└─ Retention Policy:
   ├─ Indefinite (production data)
   ├─ Versioning: 7 versions retained
   └─ Manual cleanup only (CAUTION!)

GitHub Issues (Approval Gate)
├─ Approval issues
│
└─ Lifecycle:
   ├─ Created during planning
   ├─ Auto-closed after apply
   └─ Manual cleanup if cancelled
```

---

## Failure Recovery

```
If Setup & Validate Fails:
├─ ❌ No state modifications attempted
├─ ✓ Fix configuration and retry
└─ ✓ No manual cleanup needed

If Initialize Fails:
├─ ⚠️ State file locked (15 min timeout)
├─ Manual unlock available:
│  └─ terraform force-unlock <LOCK_ID>
└─ ✓ Retry after fix

If Plan Fails:
├─ ❌ No apply will execute
├─ ✓ Review error message
├─ ✓ Fix Terraform code
└─ ✓ Retry plan

If Apply Fails:
├─ ⚠️ Infrastructure partially deployed
├─ State file in consistent state
├─ Options:
│  ├─ Manual correction + state fix-up
│  ├─ Destroy & retry (if safe)
│  └─ Contact infrastructure team
└─ ✓ Review logs carefully

If Approval Gate Fails:
├─ ❌ Apply never executes
├─ ✓ Manual cleanup: Close issue
├─ ✓ Lock state file if stuck
└─ ✓ Retry approval/deployment
```

---

## Performance Characteristics

```
Typical Execution Times:

Stage 1: Setup & Validate
├─ Checkout: 5-10s
├─ Setup Terraform: 10-15s
├─ Validation: 5-10s
└─ Total: ~30s

Stage 2: Initialize
├─ Authentication: 5-10s
├─ Backend download: 5-10s
└─ Total: ~20s

Stage 3: Plan
├─ Terraform plan execution: 30s - 5min (depends on resources)
├─ Artifact publishing: 5-10s
└─ Total: 40s - 5.5min

[Approval Gate: Manual (1min - ∞)]

Stage 5: Apply
├─ Artifact download: 5-10s
├─ Terraform apply execution: 1min - 30min (depends on resources)
└─ Total: 1min - 30.5min

Stage 6: Drift Detection
├─ Terraform plan (read-only): 30s - 5min
└─ Total: ~30s - 5min

Stage 7: Summary
├─ Aggregation: 5-10s
└─ Total: ~10s

Overall (No Changes):
├─ Setup → Plan → Summary: ~3-5 minutes

Overall (With Changes):
├─ Setup → Plan → Approval → Apply → Drift → Summary: 3-40 minutes
```
