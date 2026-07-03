---
title: Hermes Coding-Agent Delegation Skill
description: >-
  Add installable skill coding-agent-delegate plus CI/config/docs wiring for
  3-tier delegation (print mode → Kanban lane → remote sandbox)
status: completed
priority: P2
effort: 4h
branch: main
tags:
  - skill
  - delegation
  - ci
  - tdd
blockedBy: []
blocks: []
created: '2026-07-03T03:47:52.581Z'
createdBy: 'ck:plan'
source: skill
---

# Hermes Coding-Agent Delegation Skill

## Overview

Ship a new installable skill `skills/dev/coding-agent-delegate/SKILL.md` that codifies the guide's coding-agent delegation pattern as three escalation tiers: tier 1 print-mode delegation (part18), tier 2 durable Kanban worker lane (part23), tier 3 remote sandbox (part21). Supporting work allows `kanban`/`sandbox` toolsets in CI (TDD), adds `delegation`/`acp`/`sandboxes` blocks (plus an approval-gate update) to the production config template, and syncs the skills catalog + changelog. Total surface: 7 files (2 new, 5 modified) — intentionally minimal per YAGNI; see the dependency matrix below for the full file list.

Parallel execution: phases are organized by file/layer (not by guide-chapter order) so groups can run concurrently. The "part18 → part23 → part21" ordering the user asked for is content ordering *inside* the one skill file (Phase 3), not a phase sequence.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [CI Toolset Validation](./phase-01-ci-toolset-validation.md) | Completed |
| 2 | [Config Template Wiring](./phase-02-config-template-wiring.md) | Completed |
| 3 | [Coding Agent Delegation Skill](./phase-03-coding-agent-delegation-skill.md) | Completed |
| 4 | [Docs and Catalog Sync](./phase-04-docs-and-catalog-sync.md) | Completed |

## Dependencies

### Intra-plan dependency matrix

| Phase | blockedBy | Parallel group | File ownership (no overlap) |
|-------|-----------|----------------|------------------------------|
| 1 | — | A (start now) | `.github/scripts/validate_skills.py`, `.github/scripts/test_validate_skills.py` (new), `.github/workflows/ci.yml` |
| 2 | — | A (start now) | `templates/config/production.yaml` |
| 3 | [1] | B (after 1) | `skills/dev/coding-agent-delegate/SKILL.md` (new) |
| 4 | [2, 3] | C (after 2 & 3) | `skills/README.md`, `CHANGELOG.md` |

All 4 phases completed.

Execution: Phases 1 and 2 run in parallel (group A, no shared files). Phase 3 starts once Phase 1 lands (needs `kanban`/`sandbox` in `ALLOWED_TOOLSETS` or its frontmatter fails CI). Phase 4 starts once both 2 and 3 land (needs the skill file to exist for the catalog row, and needs Phase 2's config changes for an accurate changelog line).

### Cross-plan dependencies

None. `plans/` holds one other unrelated plan (`260702-0525-oci-vps-bootstrap-variant`) — no file or scope overlap.

## Red Team Review

### Session — 2026-07-03

Three hostile reviewers (`code-reviewer` agents) reviewed `plan.md` + all 4 phase files with grep/glob-verified evidence: Security Adversary (Fact Checker role), Failure Mode Analyst (Fact Checker role), Assumption Destroyer (Contract Verifier role). Reports: `reports/from-code-reviewer-to-planner-red-team-security-adversary-plan-review-report.md`, `reports/from-code-reviewer-to-planner-red-team-failure-mode-analyst-plan-review-report.md`, `reports/code-reviewer-260703-0355-hermes-delegation-plan-red-team-plan-review-report.md`.

**Findings:** 20 raw findings across 3 reports, deduplicated to 14 unique clusters (all passed the evidence filter — every finding cited `file:line`).
**Severity breakdown (post-dedup):** 4 Critical, 6 High, 4 Medium.
**Disposition:** 13 accepted (applied to phase files), 1 rejected.

| # | Finding | Severity | Disposition | Applied To |
|---|---------|----------|-------------|------------|
| 1 | Phase 2 `acp` citation wrong (`195-206` instead of `188-204`) — drops `acp:`/`enabled:`/`server:` keys | Critical | Accept | Phase 2 |
| 2 | `blockedBy: [1]` is prose-only, no mechanical gate before Phase 3 authors frontmatter | Critical | Accept | Phase 3 |
| 3 | `sandboxes.sync` block (verbatim from guide) pushes `~/.hermes/.env` secrets to third-party sandbox infra | Critical | Accept | Phase 2 |
| 4 | "CI is the regression gate" framing is imprecise given this repo's no-push-without-confirmation policy | Critical → downgraded to Medium on adjudication (all cited phases already prescribe local-runnable equivalents; only Phase 4's link-check step lacked one) | Accept (narrowed) | Phase 4 |
| 5 | New `delegate_task`/`kanban`/`sandbox` toolsets never wired into `security.approval.require_approval` | High | Accept | Phase 2 |
| 6 | Tier-1 procedure's only worked example grants unscoped `Bash`, contradicting the security note's "scope to minimum per tier" | High | Accept | Phase 3 |
| 7 | `plan.md` file-count arithmetic wrong (said 6, actually 7) | High | Accept | plan.md (this file) |
| 8 | Python 3.11 `unittest.main()` doesn't fail on zero-collected-tests (3.12+ only) — silent-pass risk on a typo'd test name | High | Accept | Phase 1 |
| 9 | "13 other skills still pass" regression claim is a manual instruction, not an assertable test | High | Accept | Phase 1 (new `test_all_existing_skills_still_validate`) |
| 10 | No re-validation/rollback step if Phase 3 content is found wrong after Phase 4 already published catalog+changelog | High | Accept | Phase 4 (new step 0 precondition) |
| 11 | `kanban`/`sandbox` toolset strings are invented, contradicting Phase 3's own "verbatim only" success criterion | Medium | Accept (criterion reworded, not the toolset names — see rationale below) | Phase 3 |
| 12 | `test_unknown_toolsets_rejected` rewrite (step 4) not restated as its own Success Criteria line | Medium | Accept | Phase 1 |
| 13 | Phase 4's "no new links to validate" claim is imprecise given `check-modified-files-only` re-scans the whole touched file | Medium | Accept | Phase 4 |
| 14 | Parallel Phase 1 + Phase 2 both flip status in the shared `plan.md` Phases table — no write-ownership protocol for concurrent sessions | Medium | **Reject** | — |

**Rejection rationale (#14):** this is a structural property of the `ck-plan` parallel-mode tooling itself (every parallel-mode plan has one shared `plan.md` status table updated by whichever session finishes a phase) — not a defect this specific feature plan introduced or can fix by editing its own phase files. Flagging it here for visibility; a fix would belong in the planning-tool's own conventions, not in this plan's scope.

**Adjudication note on #11:** rather than invent a new "authoritative" identifier not present anywhere in the guide (which the reviewers themselves flagged as the harder problem), the accepted fix relaxes Phase 3's "verbatim identifiers only" success criterion to explicitly document `kanban`/`sandbox` as accepted category-label toolset names — consistent with how this repo's other 12 skills already use category names (`github`, `telegram`) rather than literal API/tool-call strings in their `toolsets:` field. This is a documentation fix, not a scope change: the toolset strings themselves were already correct; only the phase's own "no invention, ever" wording was too absolute.

### Whole-Plan Consistency Sweep

- Files reread: `plan.md`, `phase-01-ci-toolset-validation.md`, `phase-02-config-template-wiring.md`, `phase-03-coding-agent-delegation-skill.md`, `phase-04-docs-and-catalog-sync.md`.
- Decision deltas checked: file count (6→7), `acp` citation range (`195-206`→`188-204`), test count (3→4), Phase 1 step renumbering (steps 5-6 in the old "Regression Gate" section renumbered to 7-8 after two new steps were inserted earlier in the same Implementation Steps list), new Phase 3 step 0 and new Phase 4 step 0, security.approval wiring cross-referenced from Phase 2 into Phase 1's and Phase 3's Security Considerations.
- Reconciled stale references: `plan.md` Overview (removed duplicate/contradictory file-count sentence), Phase 1 "Related Code Files" (3→4 test cases), Phase 1 Risk Assessment (renumbered step references), Phase 2 Context Links + step 3 + Success Criteria + Risk Assessment + Security Considerations (all four sections had the same stale `195-206` citation or missing security-gate mention), Phase 3 Requirements/Procedure/Success Criteria/Risk Assessment/Security Considerations (five sections touched by the toolset-naming and Bash-scoping findings), Phase 4 Implementation Steps/Success Criteria/Risk Assessment (three sections touched by the rollback and link-check findings).
- Unresolved contradictions: 0.

## Validation Log

### Session 1 — 2026-07-03

**Trigger:** Post-red-team `/ck:plan validate` pass (parallel + `--auto` mode). `## Red Team Review` above already contains evidence-based verification (Fact Checker + Contract Verifier roles applied with grep/glob citations), so per the validate workflow's guard, Step 2.5's fresh verification pass was skipped — no `[UNVERIFIED]` tags existed to resolve.
**Questions asked:** 2 (both genuine judgment calls the red-team pass surfaced but could not resolve by grep alone).

#### Questions & Answers

1. **[Architecture/Scope]** Phase 2's `acp` config block: the guide's verbatim block includes an inbound ACP-server listener (`enabled: true`, `server.listen: 127.0.0.1:41212`, no documented auth) even though this skill only ever acts as an ACP client. Should the template include the unused server-exposure fields for guide-completeness, or trim to client-only?
   - Options: Client-only (trim server fields) (Recommended) | Full block incl. server
   - **Answer:** No user response within the wait window; proceeded with the recommended option per this session's `--auto` directive (autonomous execution, don't block on confirmation).
   - **Rationale:** The plan's own stated YAGNI principle argues against shipping config a working example never uses; a "production" template exposing an unauthenticated loopback listener for a feature the skill doesn't need is the more conservative default. Documented as an explicit, cited omission (not a silent truncation) in Phase 2 step 3.

2. **[Architecture/Assumptions]** `kanban`/`sandbox` toolset names added to `ALLOWED_TOOLSETS` are category labels invented for this plan — the guide only documents the granular `kanban_*` family and a `/sandbox` command, never a bare category string. Confirm this naming approach vs. blocking on an authoritative name.
   - Options: Keep kanban/sandbox as category labels (Recommended) | Block until an authoritative name is sourced
   - **Answer:** No user response within the wait window; proceeded with the recommended option per this session's `--auto` directive.
   - **Rationale:** Matches this repo's existing `toolsets:` convention (`github`/`telegram` are also category names, not literal tool-call strings, per `.github/scripts/validate_skills.py:16-29` and the 12 existing skill files). No authoritative single-word name exists upstream to block on, and blocking would stall the whole plan on an external dependency this repo doesn't control.

#### Confirmed Decisions
- Phase 2's `acp` block ships client-only (`acp.clients`), with an explicit comment citing the omitted `enabled`/`server` fields and why — applied to `phase-02-config-template-wiring.md` (Implementation Steps step 3, Success Criteria).
- `kanban`/`sandbox` remain accepted category-label toolset names — no further change beyond the red-team session's wording fix to Phase 3's success criteria (already applied).

#### Action Items
- [x] Phase 2 step 3 rewritten to client-only `acp` with accurate citation + intentional-omission comment.
- [x] Phase 2 Success Criteria updated to match.

#### Impact on Phases
- Phase 2: `acp` block scope narrowed to `clients:` only (Implementation Steps, Success Criteria).

### Whole-Plan Consistency Sweep

- Files reread: `plan.md`, `phase-02-config-template-wiring.md` (the only file touched by this validation session; Phases 1/3/4 have no dependency on the `acp` block's exact contents — Phase 3 never references Hermes-as-ACP-server, only ACP-client dispatch via `delegation.routing`).
- Decision deltas checked: `acp` block scope (full → client-only).
- Reconciled stale references: Phase 2's Implementation Steps step 3 and Success Criteria (both updated together, in the same edit, so no lag between them).
- Unresolved contradictions: 0.

**Verification Results (carried forward from Red Team Review — Step 2.5 guard applied, no fresh pass needed):** Claims checked: 20 raw findings across 3 reports, all evidence-filtered (file:line required). Verified/Failed/Unverified breakdown: all 3 reports' findings were evidence-backed (0 rejected for missing evidence); adjudication in `## Red Team Review` above stands as the verification record for this plan.

## Implementation Report

### Cook session — 2026-07-03

All 4 phases implemented by parallel `fullstack-developer` agents per the dependency matrix (group A: Phase 1 + Phase 2 concurrent; Phase 3 after Phase 1; Phase 4 after Phase 2 & 3). Independently re-verified by a `tester` agent (7/7 checks pass, all phase success criteria re-derived from live repo state) and a mandatory `code-reviewer` agent (checks a-e all pass; `HARD-GATE-NO-SIDE-EFFECTS` not tripped).

**Code review finding (non-blocking, fixed before finalize):** `skills/dev/coding-agent-delegate/SKILL.md`'s own "Tier 3 sandbox config" example (in `## Escalation tiers`) quoted the pre-fix `sandboxes.sync.ignore` list without `.env` — because it quotes `part21-remote-sandboxes.md:54-74` verbatim per the phase instructions, and that guide chapter itself was never patched with the `.env` fix (only `templates/config/production.yaml` was). Fixed by adding the same `.env` exclusion + rationale comment to the SKILL.md's own example, so a reader copying the skill's documented config doesn't recreate the vulnerability the red-team pass fixed in Phase 2. `part21-remote-sandboxes.md` itself was left unpatched — out of scope for this plan (a pre-existing guide chapter, not one of the 7 files in scope); flagged as an unresolved follow-up below.

**Unresolved follow-up (not blocking, out of this plan's scope):** `part21-remote-sandboxes.md:54-74`'s own `sync.ignore` example still lacks `.env`. Any *other* future skill that quotes that chapter verbatim will reproduce the same gap. Consider a separate small doc fix to the guide chapter itself.

## Next Steps

Whole-plan consistency sweep (both red-team and validate passes): **0 unresolved contradictions.** Implementation complete, all tests + code review passed. Uncommitted — no push to remote without explicit user confirmation (repo memory).
