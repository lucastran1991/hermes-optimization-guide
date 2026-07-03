---
phase: 5
title: "Cron Drift Reconciliation"
status: completed
effort: "1h"
---

# Phase 5: Cron Drift Reconciliation

## Context Links

- Research (ground truth): `research/researcher-real-hermes-schema-and-fix-verification-report.md` (§ "LOW #7")
- Scan finding: `plans/reports/security-scan-260703-1005-full-repo-secrets-code-config-audit-report.md` (LOW #7)

## Overview

**Priority:** LOW (finding #7). **Status:** Pending.

`templates/cron/production-crons.yaml` and the embedded `cron:` block in `templates/config/production.yaml` (~289-302) are two independently-maintained job lists that drifted: different `notify` channel (`telegram_private` vs `telegram_dm`), different schedule times on overlapping jobs, and different job sets. `production.yaml`'s block is the more current source of truth (received today's curator/journey reminder additions, commit `f8948a8`). Sync `production-crons.yaml` to it. No security impact — content/consistency fix.

## Key Insights

- `production-crons.yaml` is a **legitimate separate modular-cron artifact** (its header: "Paste into ~/.hermes/cron.yaml or include via `cron_files:`") — NOT a pure duplicate to delete.
- It holds 3 jobs `production.yaml` lacks that are worth keeping: `weekly-bypass-audit`, `daily-injection-sweep`, `disk-watchdog` (no_agent). A naive "make the two files identical" would **delete these** — do not do that silently.
- `production.yaml` holds 2 reminder jobs `production-crons.yaml` lacks: `monthly-skill-curator-reminder`, `monthly-journey-reminder`.
- Overlapping jobs differ on schedule/name: `weekly-mcp-audit` (9am vs 10am), `weekly-cost-report` (11am vs 9am), `weekly-dep-audit` (12pm vs 9am), `monthly-secret-rotation` vs `monthly-rotate` (name drift, same schedule/task), `nightly-backup` bucket path differs (illustrative placeholder).
- `security-hardened.yaml` also has its own `cron:` block — **out of scope** for this phase (not part of finding #7's two-file drift; leave untouched).
- **Red-team correction (2026-07-03):** the commented-out `morning-digest` example block (`production-crons.yaml:54`, `#   notify: telegram_private`) is a **9th occurrence** of the drifted channel name beyond the 8 active jobs. A literal reading of "replace every `notify: telegram_private`" that skips comments (reasonable — comments aren't live config) leaves this one behind and fails a strict `== 0` gate. Must be included in scope explicitly (see Refactor step 1).
- **Red-team correction (2026-07-03): this reconciliation creates 2 new same-time cron collisions**, both pre-existing in the "source of truth" or introduced by the alignment itself: (a) `production.yaml`'s own cron block already schedules `weekly-dep-audit` and `weekly-cost-report` both at `"0 9 * * 1"` — reconciling `production-crons.yaml`'s copies to match propagates this collision; (b) aligning `weekly-mcp-audit` to `"0 10 * * 1"` (per `production.yaml`) collides with `production-crons.yaml`'s own `weekly-bypass-audit`, already at `"0 10 * * 1"` and kept unchanged as one of the 3 unique jobs. Not a security issue (no shared-mutable-state proof found), but flag it — see Risk Assessment and unresolved question 4.

## Requirements

**Functional (recommended reconciliation policy = union, source-of-truth wins on overlap):**
- `notify` channel: all entries in `production-crons.yaml` → `telegram_dm` (match source of truth).
- Overlapping jobs: align schedule/task/name to `production.yaml` (weekly-mcp-audit→10am Mon, weekly-cost-report→9am Mon, weekly-dep-audit→9am Mon, rename `monthly-secret-rotation`→`monthly-rotate`).
- Add `production.yaml`'s 2 reminder jobs to `production-crons.yaml`.
- **Keep** `production-crons.yaml`'s 3 unique jobs (`weekly-bypass-audit`, `daily-injection-sweep`, `disk-watchdog`).
- Add a one-line "keep both files in sync" comment to each file.

**Non-functional**
- Both files remain valid YAML (yamllint clean via CI's `templates/` sweep).

## Architecture

Two schedule sources feed hermes-agent's cron scheduler independently (`config.yaml` embedded `cron:` and any `cron_files:`-included modular file). Drift means an operator copying the modular file gets different behavior than the embedded block. Reconciliation makes the modular file a **superset-consistent** view: identical channel, matching schedules for shared jobs, plus its own no-agent/security jobs.

**Recommended (default): union + source-of-truth-wins.** Preserves all real jobs, resolves the reported drift (channel + overlapping schedules).
**Alternative (needs user OK): strict mirror** — make `production-crons.yaml` an exact copy of `production.yaml`'s block; this DELETES the 3 unique jobs. Folded into unresolved question 4 — do not apply without confirmation.

## Related Code Files

**Modify:**
- `templates/cron/production-crons.yaml` — whole file: channel → `telegram_dm`, align overlapping schedules/names, add 2 reminder jobs, keep 3 unique jobs, add sync-warning header comment.
- `templates/config/production.yaml` — **`cron:` block (~289-302) ONLY**: add a single sync-warning comment line. **Do NOT touch `security:`/`mcp_servers` (Phase 1 territory).** Use a scoped `Edit`, never a full-file `Write`. If parallelizing with Phase 1, apply after Phase 1's production.yaml edits.

**Create / Delete:** none.

## Implementation Steps

### Tests Before (baseline)

```sh
grep -c 'telegram_private' templates/cron/production-crons.yaml            # expect >0 (drifted channel)
grep -Ec 'monthly-skill-curator-reminder|monthly-journey-reminder' templates/cron/production-crons.yaml  # expect 0 (missing)
grep -Ec 'weekly-bypass-audit|daily-injection-sweep|disk-watchdog' templates/cron/production-crons.yaml   # expect 3 (unique jobs to preserve)
yamllint -c .github/yamllint.yml templates/cron/production-crons.yaml templates/config/production.yaml    # start green
```

### Refactor

1. In `production-crons.yaml`: replace every `notify: telegram_private` with `notify: telegram_dm` — **including the commented-out example at line ~54** (`#   notify: telegram_private` in the `morning-digest` block), not just the 8 active job entries. Skipping the comment leaves 1 hit and fails the Regression Gate's strict `== 0` check.
2. Align overlapping-job schedules/names to `production.yaml` (see Requirements).
3. Append the 2 reminder jobs from `production.yaml` (`monthly-skill-curator-reminder`, `monthly-journey-reminder`).
4. Leave the 3 unique jobs (`weekly-bypass-audit`, `daily-injection-sweep`, `disk-watchdog`) in place.
5. Add a header comment to `production-crons.yaml` and a one-line comment above `production.yaml`'s `cron:` block noting both lists must be updated together (describe the invariant, no phase/finding refs).

### Tests After

```sh
grep -c 'telegram_private' templates/cron/production-crons.yaml            # expect 0 (incl. the commented example)
grep -Ec 'monthly-skill-curator-reminder|monthly-journey-reminder' templates/cron/production-crons.yaml  # expect 2
grep -Ec 'weekly-bypass-audit|daily-injection-sweep|disk-watchdog' templates/cron/production-crons.yaml   # expect 3 (still there)
# Schedule/name realignment — the actual point of "drift reconciliation" (red-team correction:
# the original gate never checked this, so a channel-only fix could false-pass):
grep -A1 'name: weekly-mcp-audit' templates/cron/production-crons.yaml | grep -q '0 10 \* \* 1'
grep -A1 'name: weekly-cost-report' templates/cron/production-crons.yaml | grep -q '0 9 \* \* 1'
grep -A1 'name: weekly-dep-audit' templates/cron/production-crons.yaml | grep -q '0 9 \* \* 1'
grep -c 'monthly-secret-rotation' templates/cron/production-crons.yaml     # expect 0 (renamed away)
grep -c 'monthly-rotate' templates/cron/production-crons.yaml             # expect 1 (renamed to match production.yaml)
yamllint -c .github/yamllint.yml templates/cron/production-crons.yaml templates/config/production.yaml    # valid
```

### Regression Gate

```sh
yamllint -c .github/yamllint.yml templates/cron/production-crons.yaml templates/config/production.yaml \
  && test "$(grep -c 'telegram_private' templates/cron/production-crons.yaml)" = "0" \
  && test "$(grep -Ec 'monthly-skill-curator-reminder|monthly-journey-reminder' templates/cron/production-crons.yaml)" = "2" \
  && test "$(grep -Ec 'weekly-bypass-audit|daily-injection-sweep|disk-watchdog' templates/cron/production-crons.yaml)" = "3" \
  && grep -A1 'name: weekly-mcp-audit' templates/cron/production-crons.yaml | grep -q '0 10 \* \* 1' \
  && grep -A1 'name: weekly-cost-report' templates/cron/production-crons.yaml | grep -q '0 9 \* \* 1' \
  && grep -A1 'name: weekly-dep-audit' templates/cron/production-crons.yaml | grep -q '0 9 \* \* 1' \
  && test "$(grep -c 'monthly-secret-rotation' templates/cron/production-crons.yaml)" = "0" \
  && echo "PHASE 5 GATE PASS"
```

## Todo List

- [x] production-crons.yaml: channel → `telegram_dm` (all 8 active entries + the 1 commented example)
- [x] production-crons.yaml: align overlapping schedules/names to production.yaml (incl. `monthly-secret-rotation`→`monthly-rotate` rename)
- [x] production-crons.yaml: add 2 reminder jobs
- [x] production-crons.yaml: keep 3 unique jobs (bypass-audit, injection-sweep, disk-watchdog)
- [x] Add sync-warning comment to both files (scoped Edit on production.yaml cron block)
- [x] Note the 2 same-time cron collisions the alignment creates (weekly-dep-audit/weekly-cost-report both 9am; weekly-mcp-audit/weekly-bypass-audit both 10am) in a comment — accept-as-is per default policy, revisit if unresolved question 4 says stagger
- [x] Run Regression Gate → `PHASE 5 GATE PASS`

## Success Criteria

- `production-crons.yaml` uses `telegram_dm` everywhere; overlapping jobs match `production.yaml` schedules; 2 reminder jobs added; 3 unique jobs retained.
- Both files yamllint-clean.
- No data silently dropped (the 3 unique jobs verified present post-edit).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Strict-mirror interpretation deletes 3 legit security jobs | Med | Med | Default policy is union+preserve; gate asserts the 3 jobs remain; strict-mirror deferred to unresolved question 4. |
| production.yaml cron edit collides with Phase 1's security edit | Med | Med | Scoped `Edit` on cron block only; `telemetry:` block separates it from Phase 1's region; apply after Phase 1. |
| Sync doesn't prevent future re-drift | High | Low | Sync-warning comment added to both; structural dedup deferred to unresolved question 4. |
| Reconciliation itself creates 2 new same-time cron collisions (confirmed by red-team, 2026-07-03): weekly-dep-audit/weekly-cost-report both `0 9 * * 1`; weekly-mcp-audit/weekly-bypass-audit both `0 10 * * 1` | Confirmed | Low (no shared-mutable-state proof found; possible cost/rate-limit spike from 2 concurrent cron LLM sessions) | Default: accept as-is (mirrors production.yaml's own pre-existing collision) and note in a comment; staggering is a possible alternative, deferred to unresolved question 4. |
| Naive "replace notify: telegram_private" skips the 1 commented-out example occurrence, leaving the gate's `== 0` check failing | Confirmed by red-team reproduction | Low | Refactor step 1 now explicitly includes the commented line. |

## Security Considerations

- No security impact (schedule/channel consistency). Preserving `weekly-bypass-audit` / `daily-injection-sweep` keeps the operator's security-audit crons intact.
- No secrets; `notify` channels are logical labels, not credentials.
- The 2 same-time collisions this reconciliation creates (see Risk Assessment) are an operational concern (concurrent cron-triggered LLM sessions), not a security one — no shared-mutable-state race was found in scope for this repo's docs/templates.

## Next Steps

- `production-crons.yaml` edit is fully independent (start anytime). Coordinate the small `production.yaml` cron-block comment with Phase 1 (apply after Phase 1, scoped Edit).
- Unresolved question 4 (sync-only vs structural dedup, AND stagger-vs-accept the 2 new collisions) decided at validate-workflow determines whether a follow-up "one file includes/generates the other" task or a schedule-stagger edit is needed.
