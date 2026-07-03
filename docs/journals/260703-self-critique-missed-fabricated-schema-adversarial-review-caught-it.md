# Self-Critique Missed Fabricated Schema; Adversarial Review Caught It

**Date**: 2026-07-03 14:30
**Severity**: Critical (caught and fixed before shipping)
**Component**: Config schema design for Part 5/7 integration
**Status**: Resolved

## What Happened

Applied Part 5 (Curator skill-hygiene) and Part 7 (memory three-tier system) guide chapters to the repo's shipped config and docs. Started with a single-pass self-critique, which found invented scoring weights (RT-1) and cut them. Then user requested adversarial red-team review (`--red-team --auto --parallel` with 3 hostile reviewers). All 3 reviewers independently converged on a Critical finding the self-critique missed: the entire `curator:` and `memory_audit:` top-level YAML config blocks were **fabricated**. The source guide documents Curator and `/journey` only as interactive CLI/TUI commands (`hermes curator run`, `hermes curator enable`, `/journey` opened by human), never as YAML-configurable or headless automated features.

## The Brutal Truth

The planner and self-critique caught invented **values** inside a proposed schema (scoring weights like 0.20, 0.25) but completely missed that the **schema itself didn't exist**. This is the insidious kind of false confidence: a well-reasoned config design with pruned weights, that would have shipped silently inert while operators believed automation was active. Grep for "curator:" in part*.md returns zero matches. That should have been the first check before inventing YAML blocks.

Three days of work on phases 1–3, a planner, two researchers, and a self-critique session — all focused on *refining* a configuration mechanism that didn't exist in the source material. A single hostile reviewer from a different discipline would have caught it in two minutes.

## Technical Details

- **Self-critique session (session 1):** Ran through 8 findings via grep/read verification. RT-1 correctly identified fabricated scoring weights (0.20/0.25/…) at `part5:137` (names 5 dimensions but zero weights shipped). Accepted and cut them. Missed that the parent block itself (`curator:` and `memory_audit:`) was also fabricated.
- **Adversarial red-team session (session 2):** Spawned 3 parallel hostile reviewers (Security Adversary, Assumption Destroyer, Failure Mode Analyst). All 3 independently converged on RT2-1/RT2-2:
  - RT2-1: `memory_audit:` premise (`scheduled /journey` with regex pattern scanning) — fabricated. `/journey` documented at `part7:120-123`, `part26:98,101,168` as interactive-only. Zero headless mode exists.
  - RT2-2: `curator:` top-level block — fabricated. `grep -rn "curator:"` across part*.md = zero. Only CLI forms exist: `hermes curator run`, `hermes curator enable`, `hermes curator status`.
- **Convergence pattern:** Security Adversary found RT2-1 via config-safety (missing approval gate for automated archival). Assumption Destroyer found RT2-2 via first-principles check (does the config-mode even exist?). Failure Mode Analyst found both via tracing the claim to the actual mechanism. Three different lenses, one root issue.

## What We Tried

1. **Self-critique alone:** Filtered invented *values* but accepted the invented *abstraction* (automated config-driven Curator and `/journey` audit). Checked citations, ran grep on line ranges in the phase files, but never checked whether the feature class itself existed. The trap: a well-formed config proposal with good citations to *part* of a feature (`part5:137` names dimensions, part5 mentions archive at 139) looks credible even when the automation mechanism doesn't exist.

2. **Independent verification (ad-hoc):** Session 1 ran "do all cited line ranges resolve?" — they do, but that proved the *pieces* are documented, not that they're assembled into a YAML automation. Lesson: "all citations valid" ≠ "the schema exists."

## Root Cause Analysis

**The planner designed for a feature that doesn't exist, and the self-critique focused on pruning fabrications *within the design* rather than validating the design's premise.** Specifically:

- No explicit "verify this feature class (automated YAML-driven Curator) exists in the source" step before drafting Phase 1's YAML shape.
- Self-critique had 8 findings; 3 of them (RT-1, RT-4, RT-7) were validations/corrections *inside the schema*. None checked "does this schema itself exist?"
- Scoring weights were an easy target (clearly invented; `part5:137` names but doesn't weight). The parent schema was harder to spot as invented because parts of it *do* exist in the guide (Curator is real, archive is real, `/journey` is real) — just not in YAML-configurable form.
- **The confidence trap:** Citing `part5` and `part7` line ranges, passing grep checks on individual keywords, and trimming weights made the overall design *feel* verified when it wasn't.

## Lessons Learned

1. **Self-critique is for refinement, not discovery.** Self-critique found and fixed invented weights (good). It cannot reliably catch fabricated abstraction layers (schema), because the same person who designed the schema also checks it — confirmation bias is structural. Single-reviewer verification works well for "is this value invented?" (binary, fact-checkable), poorly for "does this feature class exist?" (requires stepping outside the designed scope to question the premise).

2. **Adversarial multi-reviewer with different disciplines catches fabrication that self-critique misses.** The three reviewers came from different threat models:
   - Security Adversary: "What's the attack surface of automated archival?"
   - Assumption Destroyer: "Does this feature actually exist or are we assuming it?"
   - Failure Mode Analyst: "Where's the failure if the automation doesn't exist?"
   
   Their convergence on the same two Critical findings (RT2-1, RT2-2) signals high confidence. If they'd disagreed, one finding might be a false alarm. All three saying "fabricated schema" is strong.

3. **When translating prose guides into config, verify the **mechanism** before inventing the **shape.** Specifically:
   - For Curator: check "is there a documented YAML configuration mode?" (answer: no, only CLI).
   - For `/journey`: check "is there a documented headless or cron-callable mode?" (answer: no, only interactive).
   - Before Phase 1: `grep -rn "curator:" part*.md` (result: 0 hits = schema doesn't exist).
   - This check is micro (5 minutes), cheap, and blocks hours of follow-up work on invented features.

4. **"All citations valid" is not the same as "the feature exists."** Session 1 verified that `part5:137` exists, `part5:139` exists, `part7:64` exists — all true. But those cite *dimensions* (what Curator scores), *archive* (a feature), and *180d* (a number), not *a YAML schema* (what doesn't exist). Lesson: distinguish between "this artifact (line, section) is real" and "this system abstraction (config-driven automation) is real."

## Next Steps

**Implemented:** Redesigned Phase 1 — replaced fabricated `curator:` and `memory_audit:` blocks with two entries appended to the existing, already-proven `cron:` list: `monthly-skill-curator-reminder` and `monthly-journey-reminder`. These are static text reminders pointing operators to the real interactive CLI commands. No invented automation, no fabricated schema, no silent inertness. Also fixed Phase 2's insertion-point citation (was after Procedure; should be after Triggering section). All 3 phases code-reviewed and marked complete.

**No follow-up needed:** The fabricated schema was caught before merge. The fix is minimal (2 cron entries reusing existing infrastructure). Config validation uses the same `cron:` list format already in production use.

**For future plans translating prose into config:** Add an explicit "verify mechanism exists" step before designing the YAML shape. Cost is 5-10 minutes per feature class; return is preventing hours of work on non-existent automation.
