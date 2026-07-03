# Red-Team Plan Validation Caught 12 Defects Before Cook

**Date**: 2026-07-03 15:17
**Severity**: High (plan defects caught pre-implementation)
**Component**: Security scan remediation plan (5-phase parallel TDD)
**Status**: Resolved; plan corrected and ready for cook-phase with caveats

## What Happened

Created a 5-phase `--parallel --tdd` implementation plan (`plans/260703-1017-fix-remaining-security-scan-issues/`) to remediate 5 actionable findings from the 2026-07-03 full-repo security scan: fictional config keys in 3 templates, unpinned `curl|bash` NodeSource install, false Caddyfile comment, unpinned CI Action, and cron schedule/channel drift. Drafted research and all 5 phase files, then dispatched 3 parallel adversarial reviewers (`--red-team --auto --parallel`) paired with fact-checkers against the plan. All 3 reviewers independently caught 12 real defects in the drafted research and phases that would have shipped incorrect fixes if undetected.

## The Brutal Truth

The planner and initial research verified findings against the guide's own docs (codebase-summary, schemas, existing config samples). The red-team independently re-verified against live upstream source (`/home/ubuntu/workspace/hermes-agent` clone, actual `NousResearch/hermes-agent` repo) and caught systematic gaps:

The planner's confidence came from internally consistent evidence (all citations resolved, all grep patterns matched guide docs). But the guide's docs themselves were already proven stale in a prior session. Re-verifying against live upstream revealed gaps the planner never even looked for because they weren't documented in the guide. This is a structural hole: **verifying against your own docs doesn't catch what those docs got wrong.**

Worse: the adversarial process itself had the same problem. One reviewer (otherwise rigorous, used grep/GitHub API to verify) made a hallucination claim about `telegram-bot.yaml` lacking a `security:` block that independent fact-check disproved via direct file read. The lesson: even multi-reviewer red-team is not self-correcting; adjudication must independently re-verify findings before applying them, not just check that a citation exists.

## Technical Details

**The 12 defects found and corrected:**

1. **CI Action SHA pin** (Phase 2): Research mis-identified a git annotated-tag OBJECT sha as "the commit sha." GitHub API `/git/commits/{sha}` 404'd on the wrong value. Corrected via API roundtrip to find actual commit SHA.

2. **Hermes-agent webhook rate-limit claim** (Phase 1 false claim): Research stated "no rate limit or max_body_bytes config for webhooks." Actual config (`platforms.webhook.extra.rate_limit`, `max_body_bytes`) exists. Phase 1 planned to remove a false Caddyfile comment (correct) but would have replaced it with a different false claim (that the guide lacks the config entirely). Corrected to acknowledge both the false comment AND the actual config existence.

3. **security-hardened.yaml scaffold**: Research narrowed the fictional `security:` sub-key in `profiles:` but missed that the entire `profiles:` and `profile:` scaffold (the headline "quarantine mode" feature) was fabricated. Corrected scope to "all of profiles, not just nested security key."

4–7. **Sibling fictional keys left untouched** (4 defects): Research identified 8 fictional keys total but planned Phase 1–2 touch-ups only on the ones "flagged by research," creating logical inconsistency. Reviewers identified 4 more (`trust_label` appearing 8x, `tools_allowlist`, `allow_sampling`) that should have been removed if scope was "all fabrications." Corrected: explicit list of all fictional keys to remove, all phases.

8–10. **Regression gates false-passing** (3 defects): Phases 1–3's validation gates summed fictional-key occurrence counts across all files, printing "GATE PASS" even if incomplete removals left one file untouched. Corrected gates to check *each file individually* for residual fictional keys.

11. **Unenforced phase ordering**: Plan declared "no dependencies between phases" one paragraph, then prose-required "apply Phase 1 before Phase 5" later. Corrected: made ordering explicit or removed it; no contradictions.

12. **Hallucinated finding on telegram-bot.yaml** (rejected at adjudication): One reviewer claimed `telegram-bot.yaml` has zero `security:` block. Fact-check via `cat -n`, `wc -l`, `git status` confirmed the block exists. Rejected outright; lesson below.

## What We Tried

1. **Self-research against guide docs**: Drafted 5 phases, verified claims via grep on codebase-summary, existing config files, prior sessions' findings. All citations resolved; felt confident.

2. **Adversarial red-team** (3 parallel reviewers): Security Adversary, Failure Mode Analyst, Assumption Destroyer, each paired with a fact-checker (Fact Checker, Flow Tracer, Scope Auditor). All 3 independently re-verified against live upstream `hermes-agent` repo + GitHub API + NodeSource docs.

3. **Adjudication on conflicting findings**: When reviewers disagreed (e.g., telegram-bot.yaml claim), applied independent verification by direct read before accepting or rejecting the finding.

## Root Cause Analysis

**Verifying a plan against your own documentation doesn't catch what your documentation got wrong.** The planner had high confidence because the guide's own sources (codebase-summary, prior journals, repo structure) all aligned. But the 2026-07-03 security scan itself was prompted by discovering the guide's docs lag the actual config. The planner never looked upstream because the research phase was scoped to "cross-check with guide docs," not "cross-check with reality."

Second layer: **Multi-reviewer consensus is not self-correcting; hallucinations require independent fact-check.** The telegram-bot.yaml finding cited specific file structure and was internally coherent, making it plausible. Only independent re-check (actual file read) caught it as false. A process that says "three reviewers agree → apply" without re-verification would have shipped a false correction.

## Lessons Learned

1. **When planning config/schema fixes, verify against live upstream source, not guide docs.** The guide's docs are a convenience, not a ground truth. 5-minute `git clone` + grep is cheaper than building phases on stale documentation.

2. **Red-team findings are hypotheses, not conclusions.** A finding with a citation is more plausible than one without, but plausibility ≠ correctness. Adjudication must re-verify each finding independently before applying, regardless of how many reviewers converged on it.

3. **Scope-drift in fictional-key removal creates logical holes.** If the rationale is "remove all fabrications," then either scope them all upfront or explicitly defend why some stay. Leaving sibling keys untouched because they "weren't flagged by research" is circular reasoning (they weren't flagged because nobody checked them).

4. **Regression gates must validate at the granular level (per-file, per-key), not aggregated.** Summing counts across files masks incomplete removals. Each file must be checked for the absence of fictional keys, not just "total occurrences dropped from 47 to 0."

## Next Steps

**Completed:** Re-verified all 12 findings, applied corrections to research report and all 5 phase files. Ran full plan consistency sweep (renumbered unresolved judgment-calls 3→4, propagated "3 capability losses"→"5", corrected SHA everywhere it appears).

**Blocked on validation workflow:** Plan has 4 unresolved judgment-call questions (e.g., "keep the false Caddyfile comment or delete it?"). User was not at keyboard when `AskUserQuestion` was dispatched twice. Per user's explicit `--auto` flag on the original request, auto-selected the pre-marked "(Recommended)" lowest-risk option for all 4, logged as auto-defaults in plan's Validation Log. **User must revisit these before running `/ck:cook`.**

**Not yet implemented:** Plan is ready structurally but awaits user sign-off on the 4 auto-selected defaults before cook phase. All red-team defects are corrected; no blocker remains on plan side.

**For future sessions translating security scan findings into implementation plans:** (a) Add an explicit "verify against live upstream source, not docs" step to research scope. (b) In red-team adjudication, independently re-verify each finding (especially hallucinations) before applying, don't just check that a reviewer cited a file:line.
