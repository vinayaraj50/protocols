---
description: Safe, repeatable protocol to migrate Firestore, Auth, Storage, and Functions between ANY two Firebase projects.
---

# Firebase Migration Protocol v2 (Pipeline)

> **Architecture:** 6 self-verifying scripts. Each stage does ONE thing, verifies itself, and exits with PASS/FAIL before the next stage runs. This prevents context overload and ensures each step is independently reliable.

> **⚠️ SAFETY:** Source project is always READ-ONLY. Scripts only READ from source, WRITE to destination.

---

## Prerequisites

- [ ] `gcloud` CLI installed and authenticated
- [ ] `firebase` CLI installed and authenticated
- [ ] **Blaze Plan** on both projects
- [ ] Access to both Firebase Consoles

## Configuration

```powershell
$SRC = "<YOUR-SOURCE-PROJECT-ID>"     # Source (READ-ONLY)
$DST = "<YOUR-DESTINATION-PROJECT-ID>"  # Destination
$REGION = "us-central1"
$SCRIPTS = "./scripts"
```

---

## Pipeline

Run each stage **one at a time**. Do NOT proceed to the next stage until the current one exits with `✅ COMPLETE`.

### Stage 1 → Baseline Audit
```powershell
# Captures before-state of both projects (file counts, sizes, users, apps)
# Auto-discovers correct storage bucket names
& "$SCRIPTS/01-baseline-audit.ps1" -SrcProject $SRC -DstProject $DST
```

### Stage 2 → Firestore
```powershell
# Exports Firestore from source, imports to destination
& "$SCRIPTS/02-firestore-migrate.ps1" -SrcProject $SRC -DstProject $DST -Region $REGION
```

### Stage 3 → Auth Users
```powershell
# Get hash params from: Source Firebase Console > Auth > Users > ⋮ > Password hash parameters
& "$SCRIPTS/03-auth-migrate.ps1" -SrcProject $SRC -DstProject $DST `
    -HashRounds "<ROUNDS>" `
    -HashMemCost "<MEM_COST>" `
    -HashSaltSeparator "<SALT_SEP>" `
    -HashSignerKey "<SIGNER_KEY>"
```

### Stage 4 → Storage
```powershell
# Rsync with --checksums and --delete-unmatched-destination-objects
# Auto-discovers bucket names. Verifies count + size match after sync.
& "$SCRIPTS/04-storage-migrate.ps1" -SrcProject $SRC -DstProject $DST
```

### Stage 5 → Functions & Rules
```powershell
# Deploy functions, Firestore rules, indexes, storage rules
& "$SCRIPTS/05-functions-deploy.ps1" -DstProject $DST -ProjectDir "."
```

### Stage 6 → Final Verification
```powershell
# Comprehensive parity check: apps, auth, storage (count+size), functions
& "$SCRIPTS/06-verify-all.ps1" -SrcProject $SRC -DstProject $DST
```

---

## Re-sync (After Initial Migration)

To re-sync after the source has accumulated new data:

```powershell
# Only re-run the stages that need updating:
& "$SCRIPTS/04-storage-migrate.ps1" -SrcProject $SRC -DstProject $DST
& "$SCRIPTS/06-verify-all.ps1" -SrcProject $SRC -DstProject $DST
```

---

## Scripts Reference

| Script | Purpose | Key Fix |
|--------|---------|---------|
| `01-baseline-audit.ps1` | Pre-migration snapshot | Auto-discovers bucket names (not hardcoded) |
| `02-firestore-migrate.ps1` | Firestore export/import | Self-verifies after import |
| `03-auth-migrate.ps1` | Auth user migration | Validates user count immediately |
| `04-storage-migrate.ps1` | Storage rsync | `--checksums` + `--delete-unmatched` + size verification |
| `05-functions-deploy.ps1` | Functions & rules | Lists deployed functions to confirm |
| `06-verify-all.ps1` | Final parity check | Checks count AND total size (not just count) |

## Rollback Plan

Source project is never modified. If issues arise, point the app config back to the source project.
