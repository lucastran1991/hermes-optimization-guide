---
title: "Fix Remaining Security-Scan Findings"
description: "Close the 5 remaining actionable findings from the 2026-07-03 full-repo security scan (schema drift, curl|bash, false rate-limit claim, unpinned CI action, cron drift)."
status: completed
priority: P2
effort: "5.5h"
branch: "main"
tags: [security, docs, infra, config]
blockedBy: []
blocks: []
created: "2026-07-03T10:26:34.730Z"
createdBy: "ck:plan"
source: skill
---

# Fix Remaining Security-Scan Findings

## Overview

Closes the 5 remaining actionable findings from the 2026-07-03 full-repo security scan (`plans/reports/security-scan-260703-1005-full-repo-secrets-code-config-audit-report.md`). Of the original 7 findings: 1 HIGH (secret-leak via Modal/Daytona sync) was already fixed in commit `e3c50b4`, and 1 LOW (hermes-agent installer curl|bash as unprivileged user) needs no action per the scan. This plan addresses the rest. All fixes are docs/template/config accuracy fixes on a guide repo — no application code. Ground truth for the schema rewrite is the verified research report (`research/researcher-real-hermes-schema-and-fix-verification-report.md`), checked against the live `NousResearch/hermes-agent` source.

## Phases

| Phase | Name | Finding | Sev | Status |
|-------|------|---------|-----|--------|
| 1 | [Real Security Schema Rewrite](./phase-01-real-security-schema-rewrite.md) | #1 | HIGH | Done |
| 2 | [NodeSource Install Hardening](./phase-02-nodesource-install-hardening.md) | #3 | MEDIUM | Done |
| 3 | [Caddyfile Rate-Limit Claim Fix](./phase-03-caddyfile-rate-limit-claim-fix.md) | #4 | MEDIUM | Done |
| 4 | [CI Action SHA Pin](./phase-04-ci-action-sha-pin.md) | #6 | LOW | Done |
| 5 | [Cron Drift Reconciliation](./phase-05-cron-drift-reconciliation.md) | #7 | LOW | Done |

## File-Ownership Matrix

Each phase owns a disjoint file/region set. The ONLY shared file is `templates/config/production.yaml`, split into non-overlapping regions between Phase 1 and Phase 5.

| Phase | Files owned | Region(s) |
|-------|-------------|-----------|
| 1 | `templates/config/production.yaml` | `mcp_servers.*.{trust,tools_allowlist,allow_sampling}` ~139-167 + `platforms.*.trust_label` ~68-116 + `security:` block ~237-275 (NOT the cron block — Phase 5) |
| 1 | `templates/config/security-hardened.yaml` | `profile:`/`profiles:` scaffold disclosure ~17-31 (incl. nested `profiles.quarantine.security.*` ~24-29) + top-level `security:` ~60-95 |
| 1 | `templates/config/telegram-bot.yaml` | `security:` block ~45-69 (confirmed present, 78 lines total — do not assume otherwise without re-grepping) + `platforms.telegram.trust_label` ~33 |
| 2 | `scripts/vps-bootstrap.sh` | NodeSource line ~55 only (NOT the Caddy gpg lines ~64-70) |
| 2 | `scripts/vps-bootstrap-oci.sh` | NodeSource line ~68 only |
| 3 | `templates/caddy/Caddyfile` | comment line ~59 only |
| 4 | `.github/workflows/ci.yml` | action `uses:` line ~16 only |
| 5 | `templates/cron/production-crons.yaml` | whole file |
| 5 | `templates/config/production.yaml` | `cron:` block ~289-302 ONLY (NOT `security:`/`mcp_servers`) |

Line numbers are current-as-of-plan and will shift after edits — relocate by anchor (`grep '^security:'`, `grep '^cron:'`, `grep 'setup_20.x'`, etc.), never by hard line number.

## Execution Strategy — `--parallel`

Phases 2, 3, and 4 have **no dependencies** on anything and can run fully concurrently. Phase 1 and Phase 5 both touch `templates/config/production.yaml` and require ordering — see below (red-team correction, 2026-07-03: the original version of this section said "no logical dependencies... all can run concurrently" in one line and then required Phase 1-before-Phase-5 ordering two lines later, an internal contradiction; that ordering is now a hard requirement, not optional prose).

- **Phases 2, 3, 4** touch entirely distinct files (`scripts/*.sh`, `Caddyfile`, `ci.yml`) — zero coupling, freely parallel.
- **Phase 1 → Phase 5 is a REQUIRED sequential dependency on `templates/config/production.yaml`, not a suggestion.** Both edit that file in non-adjacent regions (Phase 1: `mcp_servers`/`platforms:` trust fields + `security:` block, all before line 276; Phase 5: `cron:` block at 289-302, with `telemetry:` at 277-287 sitting between them). Conflict-prevention rule: **each phase applies a scoped `Edit` touching only its own region — never a full-file `Write`/rewrite.** **Do not dispatch Phase 1 and Phase 5 as concurrent subagents/processes.** Either route both `production.yaml` edits through a single subagent/turn (Phase 1's edit, then Phase 5's edit, same turn), or explicitly block Phase 5 on Phase 1 completing first in whatever task tracker is used. Prose alone does not survive a scheduler that only reads structured fields — if your orchestration tool supports phase dependencies, encode Phase 5 as blocked-by Phase 1.

Suggested parallel grouping: {Phase 2}, {Phase 3}, {Phase 4}, {Phase 1 then Phase 5 — same owner, sequential}. Phase 5's `production-crons.yaml` edit (the whole-file part) is independent and can start immediately; only its `production.yaml` cron-block edit waits on Phase 1.

## TDD Approach — `--tdd`

Repo has no unit-test framework; "tests" = real repo tooling already wired into CI:
- `yamllint -c .github/yamllint.yml <file>` — syntax gate for `templates/**/*.yaml` (config + cron). Already run by `.github/workflows/ci.yml:32` over `templates/`.
- `bash -n <script>` — syntax-only check for shell (no shellcheck installed).
- `grep -c` assertions — prove a stale key was removed (== 0) or a real key added (>= 1). yamllint checks syntax, NOT schema, so grep assertions are the real schema-correctness gate.
- `git ls-remote` — one-time SHA authenticity check for the CI pin (Phase 4).

Each phase file carries: **Tests Before** (baseline command + current output) → **Refactor** (the change) → **Tests After** (verification command + expected passing output) → **Regression Gate** (exact command(s) that must pass before the phase is done).

## Dependencies

Phase 5 depends on Phase 1 completing first (shared file `templates/config/production.yaml`, see Execution Strategy — this is a real, enforced ordering requirement, not a suggestion). Phases 2, 3, 4 have no dependencies. External ground truth: research report + live hermes-agent source (already verified, do not re-derive) + 3 red-team review reports (see `## Red Team Review` below).

## Unresolved Questions

Surface these at `/ck:plan validate` (interview the user) — **not resolved here**. Expanded from 3 to 4 items by red-team review 2026-07-03 (see `## Red Team Review`):

1. Phase 1 capability loss (no per-tool approval granularity, no custom denylist, no per-server `tools_allowlist`, no per-platform `trust_label`) — confirm user accepts the accuracy-over-aspiration tradeoff.
2. Phase 1 — should `security-hardened.yaml`'s whole `profiles:`/`profile:` scaffold fix (not just its nested `security:` key — confirmed fully fictional by red-team review) block this plan's Phase 1 sign-off, or ship as a documented known-gap alongside the other capability losses?
3. Phase 3 — now that hermes-agent itself rate-limits webhooks post-proxy (30/min default, confirmed by red-team review), is Caddy-layer rate limiting (`xcaddy` + `caddy-ratelimit`) still wanted as pre-auth defense-in-depth, or does the corrected comment (no plugin) fully close this finding?
4. Phase 5 — one-time sync vs. structural dedup to prevent re-drift, AND how to handle the 2 same-time cron collisions the sync itself introduces (stagger vs accept-as-is, confirmed by red-team review).

## Red Team Review

### Session — 2026-07-03

3 reviewers (Security Adversary/Fact Checker, Failure Mode Analyst/Flow Tracer, Assumption Destroyer/Scope Auditor — Full tier, 5 phases) against ground truth `/home/ubuntu/workspace/hermes-agent` (`b699d27a`) + live GitHub API/NodeSource wiki checks. Reports: `reports/from-code-reviewer-to-planner-red-team-security-adversary-plan-review-report.md`, `reports/from-code-reviewer-to-planner-red-team-assumption-destroyer-plan-review-report.md`, `reports/from-code-reviewer-to-planner-red-team-failure-mode-analyst-plan-review-report.md`.

**Findings:** 13 raised (before dedup of convergent findings across reviewers), 12 accepted, 1 rejected.
**Severity breakdown (accepted):** 4 Critical, 3 High, 5 Medium.

| # | Finding | Severity | Disposition | Applied To |
|---|---------|----------|-------------|------------|
| 1 | Phase 4 SHA (`499c1e7f...`) is the annotated-tag OBJECT sha, not the commit sha (`5c5dfc0a...`) — confirmed via GitHub API (`/git/commits/499c1e7f...` → 404) | Critical | Accept | Phase 4, research report |
| 2 | `security-hardened.yaml`'s entire `profile:`/`profiles:` scaffold (not just its nested `security:` key) has zero backing in DEFAULT_CONFIG — bigger gap than originally scoped | Critical | Accept | Phase 1, research report |
| 3 | Phase 1's Regression Gate false-passes if a target file is left untouched — reproduced live (deleted telegram-bot.yaml's `security:` block, gate still printed PASS) | Critical | Accept | Phase 1 |
| 4 | Phase 5's Regression Gate never checks schedule/rename realignment — reproduced live (left all 3 overlapping-job schedules unaligned, gate still printed PASS) | Critical | Accept | Phase 5 |
| 5 | "No rate limit is enforced" / "body cap is Caddy-side" claims are false — hermes-agent's own webhook adapter enforces `rate_limit` (30/min) and `max_body_bytes` (1MB) via `platforms.webhook.extra.*`, independent of Caddy | High | Accept | Phase 1, Phase 3, research report |
| 6 | Adjacent fictional keys (`trust_label` 8x, `tools_allowlist`, `allow_sampling`) left untouched with reasoning "not flagged by research" — confirmed equally fictional (or, for `allow_sampling`, real-but-differently-shaped) by direct grep | High | Accept | Phase 1, research report |
| 7 | Phase 2's Regression Gate never verifies `vps-bootstrap-oci.sh` actually installs Node — reproduced live (no-op'd the OCI script's Node install, gate still printed PASS) | High | Accept | Phase 2 |
| 8 | "Apply Phase 1 before Phase 5" was unenforced prose contradicting the plan's own "no dependencies" declaration one paragraph earlier | High | Accept | plan.md |
| 9 | 4 byte-identical `trust: trusted` lines make a single unique-match scoped `Edit` ambiguous/rejectable | Medium | Accept | Phase 1 |
| 10 | Phase 5's gate/refactor scope mismatch: 1 of 9 `telegram_private` occurrences sits in a commented-out example line, easy to miss under a literal reading of the refactor step | Medium | Accept | Phase 5 |
| 11 | Research report's own line-citation for the real schema (`config.py:2408-2434`) pointed at unrelated code; actual lines are 2348/2372/2412-2438 | Medium | Accept | research report |
| 12 | Phase 5's reconciliation policy itself creates 2 new same-time cron collisions (weekly-dep-audit/weekly-cost-report both 9am; weekly-mcp-audit/weekly-bypass-audit both 10am) | Medium | Accept | Phase 5 |
| 13 | "telegram-bot.yaml has no `security:` block at all, file is 52 lines" | Critical (as claimed) | **Reject** | — verified false by direct `cat -n`/`wc -l`/`git status` re-check: file is 78 lines, `security:` block present at line 45, working tree clean (no uncommitted drift). One reviewer's claim, independently contradicted by the other two reviewers' own citations and by direct re-verification. |

### Whole-Plan Consistency Sweep

- Files reread: `plan.md`, `phase-01-real-security-schema-rewrite.md`, `phase-02-nodesource-install-hardening.md`, `phase-03-caddyfile-rate-limit-claim-fix.md`, `phase-04-ci-action-sha-pin.md`, `phase-05-cron-drift-reconciliation.md`, `research/researcher-real-hermes-schema-and-fix-verification-report.md`.
- Decision deltas checked: 12 (all accepted findings above).
- Reconciled stale references: SHA `499c1e7f...` → `5c5dfc0ac2e225883c0e5f03a85311ec2830d368` in phase-04 (5 occurrences) and research report; unresolved-questions renumbering (3→4 items) propagated to plan.md, phase-01's Risk Assessment, and research report consistently; Phase 3's "unresolved question 2" references renumbered to "question 3" throughout phase-03; Phase 5's "unresolved question 3" references renumbered to "question 4" throughout phase-05 and research report; "3 capability losses" → "5 capability losses" propagated to phase-01's Overview/Requirements/Success Criteria.
- Unresolved contradictions: 0.

**Verdict: plan is internally consistent post-fixes. All 4 unresolved questions require a `/ck:plan validate` interview before implementation — do not recommend `/ck:cook` until that interview completes.**

## Validation Log

### Session — 2026-07-03

Interview attempted via `AskUserQuestion` for all 4 unresolved questions (grouped in one call, within the `questions=3-8` range from Plan Context). **No user response after 60s (twice, including the earlier red-team apply-gate).** Per the user's explicit `--auto` flag on the original request, proceeded with the pre-marked "(Recommended)" option for each — the lowest-scope, most-conservative choice in every case. **These are auto-selected defaults, not confirmed user decisions — revisit before `/ck:cook` if any assumption below is wrong.**

| # | Question | Decision | Applied To |
|---|----------|----------|------------|
| 1 | Capability-loss handling (no per-tool matrix, no denylist, no tools_allowlist, no trust_label) | **Document as accepted gap** — inline comments only, no mitigation-pointer additions | Phase 1 (no change needed — already the plan's default) |
| 2 | `security-hardened.yaml` `profiles:` scaffold — fix now or disclose-only | **Disclose only, defer full rewrite** — Phase 1 adds the disclosure comment; a full scaffold rewrite is a follow-up task, not part of this plan | Phase 1 (no change needed — already the plan's default); noted as a follow-up in Phase 1's Next Steps |
| 3 | Caddy-layer rate limiting as defense-in-depth | **No — reword only** | Phase 3 (no change needed — already the plan's default) |
| 4 | Cron collision handling (sync creates 2 new same-time collisions) | **Sync + accept collisions as-is** — no staggering, no structural dedup in this plan | Phase 5 (no change needed — already the plan's default) |

All 4 defaults matched the plan's existing default policy (each phase file already implements the "(Recommended)" path) — no phase-file edits were required as a result of this validation pass. This is expected: the defaults were chosen during red-team correction specifically because they're the most defensible, lowest-risk option per finding; the interview existed to give the user a chance to override them, not because the default path was left undecided.

### Whole-Plan Consistency Sweep

- Files reread: `plan.md`, all 5 `phase-*.md`, research report.
- Decision deltas checked: 4 (all confirmed the existing default — no propagation needed).
- Reconciled stale references: none required.
- Unresolved contradictions: 0.

**Recommendation: eligible for `/ck:cook --parallel {this plan's absolute path}/plan.md --tdd`. Flag before running: questions 1-4 above were auto-decided under `--auto` with no user confirmation — if the user is available, a quick verbal confirmation of the 4 defaults (all pre-marked "Recommended") is cheap insurance before implementation, since Phase 1's capability-loss framing and Phase 5's cron-collision handling are the two most judgment-call-shaped of the four.**
