---
description: Sub-Agent Execution Pipeline for running tasks in parallel via Codex CLI
---

# /run — Sub-Agent Execution Pipeline

// turbo-all-codex

```
 SCAN ──→ SPLIT ──→ EXECUTE ──→ VERIFY ──→ REPORT
                └──→ PARALLEL  ──┘
                     (Codex CLI)
```

---

## Core Policy (Do Not Skip)

1. Keep speed and plan fidelity.
2. Keep two-model safety:
   - Codex does implementation + Codex self-review.
   - Antigravity does lightweight cross-model audit from compact outputs.
3. Antigravity is orchestrator-first:
   - Antigravity handles gating, retries, reporting, and browser manipulation.
   - Antigravity does not do deep code analysis or code edits unless Codex fails the same task 2 times.
4. Browser work is Antigravity-only.
5. Any task with `PLAN_COMPLIANCE: NO` requires immediate human escalation.

---

## PHASE 1: SCAN

Find the plan. First match wins:

```powershell
$PLAN = @(
  "implementation_plan.md",
  "docs/PLAN.md",
  "task.md",
  "execution_plan.md"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $PLAN) { Write-Output "❌ No plan found. Run /plan or /triad first."; exit 1 }
Write-Output "📄 Plan: $PLAN"
```

Read the plan. Extract every task/checklist item (`- [ ]`, `- [/]`, `####`, numbered steps).

Session folder:

```powershell
$RUN_TS = Get-Date -Format 'yyyyMMdd-HHmmss'
$RUN_DIR = "run-results/$RUN_TS"
New-Item -ItemType Directory -Force -Path $RUN_DIR | Out-Null
```

Create manifest via Codex:

```powershell
codex --approval-mode full-auto exec @"
Read $PLAN and extract actionable tasks.
Return JSON only:
{
  "tasks":[
    {"id":"T1","text":"...","depends_on":[],"candidate_files":[],"status":"todo"}
  ]
}
"@ --output-last-message "$RUN_DIR/manifest.json"
```

---

## PHASE 2: SPLIT

Classify each task into one lane:

| Lane | Criteria | Executor |
|------|----------|----------|
| **SERIAL** | Depends on another task output, shared state/config/migration risk, same file overlap | Codex CLI (sequential) |
| **PARALLEL** | Independent file(s), no shared target files/import collisions, pure-add safe | Codex CLI (concurrent) |
| **BROWSER** | Requires Chrome/UI manipulation, HAR, screenshots, interactive auth flows | Antigravity |
| **SKIP** | Already `[x]` completed | — |

Codex proposes lanes:

```powershell
codex --approval-mode full-auto exec @"
Read $RUN_DIR/manifest.json and produce lane assignment.
Output JSON only:
{
  "execution":[{"id":"T1","lane":"SERIAL","files":["..."],"reason":"..."}],
  "parallel_batch":["T2","T4"],
  "serial_queue":["T1","T3"],
  "browser_queue":["T5"]
}
"@ --output-last-message "$RUN_DIR/lanes.json"
```

Output a table to user before executing:

```
┌─── EXECUTION PLAN ────────────────────────────┐
│ #  │ Task              │ Lane     │ Executor   │
│ 1  │ DB schema update  │ SERIAL   │ Codex CLI  │
│ 2  │ UserCard component│ PARALLEL │ Codex CLI  │
│ 3  │ API endpoint      │ SERIAL   │ Codex CLI  │
│ 4  │ Unit tests        │ PARALLEL │ Codex CLI  │
│ 5  │ OAuth browser flow│ BROWSER  │ Antigravity│
└───────────────────────────────────────────────┘
Parallel batch: [2, 4] → Codex CLI
Serial queue:   [1, 3] → Codex CLI
Browser queue:  [5]    → Antigravity
```

*Lanes assigned. Proceeding to execution...*

---

## PHASE 3: EXECUTE

### 3a. Serial Tasks -> Codex CLI (Implementer + Reviewer)

Execute serial queue in order.

Per task, run Implementer:

```powershell
codex --approval-mode full-auto exec @"
ROLE: IMPLEMENTER
TASK: {task_description}
FILES: {target_files}
CONSTRAINTS:
- Touch ONLY listed files
- Follow existing code style
- No new dependencies without 1-line justification
- Output compact format only
OUTPUT:
TASK_ID:
FILES_TOUCHED:
CHANGE_SUMMARY:
PLAN_COMPLIANCE: YES/NO + one line
"@ --output-last-message "$RUN_DIR/task-{N}.impl.md"
```

Then run Reviewer (independent Codex pass):

```powershell
codex --approval-mode full-auto exec @"
ROLE: REVIEWER
Read $PLAN and $RUN_DIR/task-{N}.impl.md.
Check: plan fidelity, scope creep, risk, missing edge cases.
OUTPUT:
TASK_ID:
VERDICT: APPROVE | RETRY | REJECT
ISSUES: up to 5 bullets
MIN_FIX:
"@ --output-last-message "$RUN_DIR/task-{N}.review.md"
```

Antigravity lightweight audit (no deep file read):
- Read only `TASK`, `FILES_TOUCHED`, `CHANGE_SUMMARY`, `PLAN_COMPLIANCE`, `VERDICT`, `ISSUES`.
- Decision: `ACCEPT | RETRY_ONCE | ESCALATE`.
- **Deviation Guard**: If `PLAN_COMPLIANCE` is `NO`, Antigravity MUST `ESCALATE` to human.
- If `RETRY_ONCE`, rerun Implementer once with `MIN_FIX`.

### 3b. Parallel Tasks -> Codex CLI Sub-Agents (paired)

Fire all parallel tasks simultaneously (max 4 at once), each with Implementer + Reviewer pair:

```powershell
# Implementer
codex --approval-mode full-auto exec @"
ROLE: IMPLEMENTER
TASK: {task_description}
FILES: {target_files}
CONSTRAINTS:
- Touch ONLY listed files
- Follow existing code style
- Output compact format only
"@ --output-last-message "$RUN_DIR/task-{N}.impl.md"

# Reviewer
codex --approval-mode full-auto exec @"
ROLE: REVIEWER
Read $PLAN and $RUN_DIR/task-{N}.impl.md.
Output compact verdict only.
"@ --output-last-message "$RUN_DIR/task-{N}.review.md"
```

Rules:
- Each Codex invocation = 1 task, 1 concern.
- Max 4 concurrent task pairs.
- Timeout: 3 min per Codex call. Hang -> kill -> retry once -> mark FAILED.
- If two tasks touch same file, stop both and move to SERIAL queue.

### 3c. Browser Tasks -> Antigravity (Codex-directed)

For each `BROWSER` task:
1. Codex writes exact browser steps + expected evidence.
2. Antigravity executes in Chrome.
3. Save artifacts in `$RUN_DIR/browser-task-{N}/`.
4. Codex analyzes artifacts and returns pass/fail + next action.

---

## PHASE 4: VERIFY

After all lanes complete, Codex runs verification:

```powershell
# Syntax/type/lint (choose relevant)
npx tsc --noEmit 2>&1 | Select-Object -First 20
# or
npx next lint 2>&1 | Select-Object -First 20
```

Per Codex result file in `$RUN_DIR/`:
1. Check real code result vs error/quota output.
2. If error -> mark FAILED.
3. Retry policy: Codex retries once; second failure escalates.

Gate:
- All tasks green -> PHASE 5.
- Any red -> fix via Codex serial repair, then re-verify.
- Same task fails verify 2x -> STOP -> ask user.

---

## PHASE 5: REPORT

```
┌─── /run COMPLETE ─────────────────────────────┐
│ Task              │ Lane     │ Status │ Time   │
│ DB schema update  │ SERIAL   │ ✅     │ 12s    │
│ UserCard component│ PARALLEL │ ✅     │ 45s    │
│ API endpoint      │ SERIAL   │ ✅     │ 30s    │
│ Unit tests        │ PARALLEL │ ✅     │ 38s    │
│ OAuth browser flow│ BROWSER  │ ✅     │ 22s    │
├───────────────────────────────────────────────┤
│ Total: 5 tasks │ Parallel saved: ~40s         │
│ Verify: ✅ lint ✅ types                      │
└───────────────────────────────────────────────┘
```

Update plan file: mark all completed tasks `[x]`.

---

## FAIL-SAFES

| Condition | Action |
|-----------|--------|
| Codex hangs > 3 min | Kill -> retry once -> Codex serial repair queue |
| Codex quota/rate-limit | Pause parallel -> continue SERIAL only |
| Merge/file-lock conflict | Move conflicting tasks to SERIAL |
| Reviewer REJECT 2x | STOP -> ask user |
| Any task fails verify 2x | STOP -> ask user |
| Plan Compliance NO | STOP -> ask user |
| Browser step required | Antigravity executes; Codex analyzes artifacts |

---

## Compact Output Contract (mandatory)

Every task artifact must be short and include only:
- `TASK_ID`
- `FILES_TOUCHED`
- `CHANGE_SUMMARY`
- `PLAN_COMPLIANCE`
- `VERDICT`
- `NEXT_ACTION`
