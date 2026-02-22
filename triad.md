---
description: Generator→Critic→Verifier triad review. Uses Codex CLI as Generator, Antigravity agents as Critic & Verifier. Produces a consensus implementation plan.
---

# 🛑 ABSOLUTE RULE — READ FIRST

> **This workflow produces a PLAN ONLY. It does NOT implement code.**
> **DO NOT edit, modify, or touch ANY source code file during this workflow.**
> **DO NOT skip the Human Gate (Phase 5). The user MUST explicitly say "Y" or "yes" before ANY implementation begins.**
> **"APPROVED" from the Verifier means the PLAN is approved for HUMAN REVIEW — NOT for implementation.**
> **Violating this rule = CRITICAL FAILURE.**

---

# Triad Review — Checkpoint Pipeline

**Trigger:** `/triad [task description]`

> Codex (OpenAI) ↔ Antigravity (Gemini/Claude) — cross-model review.
> **Rule:** Smallest correct change wins. Complexity is a defect.
> **Rule:** PLAN ONLY. Zero source code changes until human says "Y".

---

## 🔒 Session Isolation (MANDATORY FIRST STEP)

Each Triad invocation gets a **unique timestamped folder** to prevent conflicts when multiple windows run concurrently. All phases use `$TRIAD_DIR` instead of a hardcoded path.

// turbo
```powershell
# 1. Generate unique session folder
$TRIAD_TS = Get-Date -Format 'yyyyMMdd-HHmmss'
$TRIAD_DIR = "docs/triad-session-$TRIAD_TS"

# 2. Auto-clean stale sessions (older than 5 hours)
Get-ChildItem -Path "docs" -Directory -Filter "triad-session-*" -ErrorAction SilentlyContinue | ForEach-Object {
    $folderAge = (Get-Date) - $_.CreationTime
    if ($folderAge.TotalHours -gt 5) {
        Remove-Item $_.FullName -Recurse -Force
        Write-Output "🧹 Cleaned stale session: $($_.Name)"
    }
}

# 3. Create isolated session folder
New-Item -ItemType Directory -Force -Path $TRIAD_DIR | Out-Null
Write-Output "📂 Session: $TRIAD_DIR"
```

> ⚠️ **All subsequent phases MUST use `$TRIAD_DIR` for file paths.** Never hardcode `docs/triad-session/`.

---

## Pipeline Overview

```
PHASE 0 ──→ GATE 0 ──→ PHASE 1 ──→ GATE 1 ──→ PHASE 2 ──→ GATE 2
 (Brief)    (check)    (Generate)   (check)    (Critique)   (check)
                                                    │
              ┌────────────────────────────────────  │
              ▼                                      │
          PHASE 3 ──→ GATE 3 ──→ PHASE 4 ──→ GATE 4 ──→ PHASE 5
          (Revise)    (check)    (Verify)    (check)    (Human Gate)
```

---

## PHASE 0: Task Brief (Antigravity)

Write `$TRIAD_DIR/TASK_BRIEF.md`.

**OUTPUT CONTRACT:**
```
Required sections (all mandatory):
□ **What:** — 1 sentence
□ **Where:** — file path(s)
□ **Size:** — 1-line / small / moderate / large
□ **Don't break:** — existing behavior to preserve
□ **Out of scope:** — what NOT to do
```

**GATE 0:** Verify all 5 sections exist. If any missing → rewrite before proceeding.

---

## PHASE 1: Generator (Codex CLI)

Search web first. Then produce the MINIMAL change.

```powershell
codex -a never exec "Read $TRIAD_DIR/TASK_BRIEF.md. Search the web for the simplest approach. Write the minimal code change. If 1-line fix, output 1 line. Do NOT add state, hooks, or abstractions unless required. Show the exact diff." --output-last-message "$TRIAD_DIR/GENERATOR_PLAN.md"
```

> ⚠️ **Model:** `gpt-5.3-codex high` is the ONLY acceptable model. If unavailable → STOP and report to user. Allow up to 10 min for web-search-heavy tasks.

**OUTPUT CONTRACT:**
```
Required in GENERATOR_PLAN.md:
□ Diff or exact code change
□ Which file(s) and line(s)
□ 1-sentence rationale for the approach
```

**GATE 1:**
// turbo
```powershell
$f = "$TRIAD_DIR/GENERATOR_PLAN.md"
if (Test-Path $f) {
    $c = Get-Content $f -Raw
    if ($c -match 'rate.?limit|quota|429|exceeded|too many requests|billing|usage limit') {
        Write-Output "🔴 QUOTA EXHAUSTED. Run 'codex login' with a different account."
    } elseif ($c.Length -gt 100) { Write-Output "✅ GATE 1 PASS ($($c.Length) bytes)" }
    else { Write-Output "❌ GATE 1 FAIL — too small ($($c.Length) bytes). Retry." }
} else { Write-Output "❌ GATE 1 FAIL — file missing" }
```

Antigravity also quick-scans: is it an error message or real plan? If error → retry.

---

## PHASE 2: Critic (Antigravity)

Search web (last 30 days). Review for simplicity and correctness.

**PROMPT:**
```
Read $TRIAD_DIR/TASK_BRIEF.md and GENERATOR_PLAN.md.
Search the web for current best practices for this change.
Write $TRIAD_DIR/CRITIC_REVIEW.md.
```

**OUTPUT CONTRACT:**
```
Required sections (all mandatory):
□ **Too complex?** — YES/NO. If YES: show simpler diff.
□ **Real bugs?** — list only genuine issues, or "None". Zero is valid.
□ **Scope drift?** — YES/NO. If YES: what to remove.
□ **Verdict:** — ✅ APPROVE | 🔄 SIMPLIFY | ❌ REJECT
```

**GATE 2:** Verify all 4 sections exist. Verdict must be one of the 3 options. If missing → rewrite.

---

## PHASE 3: Reviser (Codex CLI)

**Only runs if Critic said 🔄 or ❌.** If ✅ APPROVE → skip to Phase 4.

```powershell
codex -a never exec "Read TASK_BRIEF.md, GENERATOR_PLAN.md, CRITIC_REVIEW.md in $TRIAD_DIR/. Search web for simpler approaches. If Critic said SIMPLIFY: make it smaller. Never add complexity. Output: ## Response then ## Revised Plan with exact diff." --output-last-message "$TRIAD_DIR/REVISED_PLAN.md"
```

**OUTPUT CONTRACT:**
```
Required in REVISED_PLAN.md:
□ Point-by-point response to Critic
□ Revised diff (must be same size or smaller than original)
```

**GATE 3:** File exists + > 100 bytes + quota check. Same as Gate 1 pattern.

---

## PHASE 4: Verifier (Antigravity)

Search web (last 30 days). Final gate: correctness AND simplicity.

**PROMPT:**
```
Read all files in $TRIAD_DIR/.
Search web for best practices.
Write $TRIAD_DIR/VERIFIER_VERDICT.md.
```

**OUTPUT CONTRACT:**
```
Required sections (all mandatory):
□ **Simplicity (1-10):** — 10=minimal, 1=bloated. < 7 = auto REVISE.
□ **Correct?** — YES/NO
□ **Scope clean?** — YES/NO
□ **Verdict:** — ✅ APPROVED | 🔄 REVISE | ❌ REJECTED

🛑 APPROVED means: plan is ready for HUMAN REVIEW.
🛑 DO NOT implement any code. Present to user in Phase 5 and WAIT.
```

**GATE 4:** All 4 sections present. Simplicity score must be a number. If REVISE → loop to Phase 3 (max 2 iterations, then force Phase 5). **After this gate → go to Phase 5. DO NOT implement.**

---

## PHASE 5: Human Gate

> 🛑 **This phase is MANDATORY. You MUST present the summary and WAIT for user to say "Y". DO NOT implement code before this.**

**OUTPUT CONTRACT (MANDATORY — block if any section missing):**

```markdown
## 🔺 Summary with Rationale
[≤60 words, layman terms: what changes and WHY this approach was chosen over alternatives]

- **File:** [which file(s)]
- **Change:** [what the diff does]
- **Untouched:** [what stays the same]
- **Why this way:** [1-sentence rationale]

---

## Full Report

| Phase | Artifact | Verdict |
|-------|----------|---------|
| Brief | TASK_BRIEF.md | — |
| Generator | GENERATOR_PLAN.md | — |
| Critic | CRITIC_REVIEW.md | [verdict] |
| Reviser | REVISED_PLAN.md | (if ran) |
| Verifier | VERIFIER_VERDICT.md | [verdict] |

**Simplicity:** X/10 · **Iterations:** X/2
**Session:** $TRIAD_DIR

Approve to implement? (Y/N)
```

**GATE 5 (self-check before presenting to user):**
```
□ "Summary with Rationale" section exists and is ≤60 words?
□ File/Change/Untouched/Why bullets all present?
□ Full Report table present?
□ Simplicity score present?
If ANY missing → DO NOT present. Fix first.
```

---

## Fail-Safes

1. **Model:** `gpt-5.3-codex high` is the ONLY acceptable model. If model is unavailable or wrong → STOP and report to user.
2. **Timeout:** > 10 min → kill and report to user. Do NOT retry with a different model.
3. **Empty:** < 100 bytes → retry (same model)
4. **Max loops:** 2, then human gate
5. **Quota:** rate-limit detected → stop → report to user → `codex login` with different account → resume

---

## Cleanup

```powershell
New-Item -ItemType Directory -Force -Path "docs/triad-archive"
Move-Item $TRIAD_DIR "docs/triad-archive/session-$TRIAD_TS"
```
