---
title: "CCS Full-Harness Delegation for Coding-Agent Skill"
description: "Add an opt-in ccs-routed identity for coding-agent-delegate's Tier-1 claude-code branch (default stays bare claude); CCS-routing alone does not grant ClaudeKit harness — that needs a separately-provisioned ~/.claude/ on the host, which this plan documents as an explicit, out-of-scope prerequisite rather than assuming."
status: completed
priority: P2
effort: "5h"
branch: "main"
tags: [skill, delegation, ccs, infra, tdd]
blockedBy: []
blocks: []
created: "2026-07-03T10:44:51.651Z"
createdBy: "ck:plan"
source: skill
---

# CCS Full-Harness Delegation for Coding-Agent Skill

## Overview

`skills/dev/coding-agent-delegate/SKILL.md` Tier 1 currently shells out to bare
`claude -p "..."`. The original ask (see brainstorm report) was to route this
through CCS so delegated sessions inherit "the full ClaudeKit harness" a human dev
gets via `ccs <profile>` — this plan's own research (below, then deepened by a
red-team pass — see `## Red Team Review`) found that premise is **only partly
true**, and revised scope accordingly: enhance in place (approach A from the
brainstorm), add CCS-routing as an **opt-in identity/quota mechanism**, and be
explicit that harness itself has a separate, unmet prerequisite.

**Corrections from this plan's own research (supersede the brainstorm's
assumptions; further corrected by the red-team pass below — see each phase's Key
Insights for citations):**
- ~~Full harness loads for any `ccs <profile> -p` call by default~~ — **superseded**:
  it loads only if `~/.claude/` (ClaudeKit's `CLAUDE.md`/`rules/*`/skills/hooks)
  already exists on the invoking host, gated by `claude`'s own `--bare` flag
  (neither bare nor `ccs`-routed calls pass it). **Nothing in this repo's bootstrap
  scripts provisions `~/.claude/` for the `hermes` service user** (verified: zero
  grep hits across `scripts/vps-bootstrap*.sh` + the systemd template). So on an
  unmodified deployment, CCS-routing changes identity/quota only — it does not, by
  itself, deliver the harness the original ask wanted. Getting ClaudeKit onto the
  `hermes` box is a real, separate prerequisite this guide does not own or automate
  (out of scope — flagged in Unresolved Questions).
- Recommend a CCS **API profile** (`ccs api create --preset anthropic --api-key ...
  --target claude --yes`), not an **account profile** (`ccs auth create hermes`).
  Account profiles need an interactive OAuth browser login at creation time (`ccs
  auth create <name>` = "Create new profile and **login**") — a real blocker for a
  headless service. API profiles use `ANTHROPIC_API_KEY`-style auth and still
  target the `claude` binary (`--target claude`), avoiding that interactive step.
  **Caveat added by red-team:** live-testing this session found a real API
  profile's runtime state/memory-path fell back to the machine's *default account
  profile*, not a dedicated instance dir — behavior on a headless box with zero
  account profiles is unverified (see Phase 3 Key Insights, Unresolved Questions).
- Print mode (`-p`) is already structurally non-interactive (part18: "no PTY, no
  approval prompts to manage") — there is no separate "make Claude Code
  non-interactive" flag to add. The one real `--auto`-shaped lever already exists:
  `templates/config/production.yaml`'s `delegation.approval.require_approval`
  already gates `{ tool: delegate_task, actions: [dispatch] }` — this applies
  identically whether Tier 1 invokes bare `claude` or `ccs <profile>`. No new
  config field needed for that half of the brainstorm's assumption 3.
- **Default flipped to `harness: bare` (red-team reversal, not in the original
  draft):** live-testing found `ccs <profile> -p` hard-fails with no fallback when
  the profile doesn't exist yet — making `ccs` the default would break every
  Tier-1 `claude-code` delegation on a deployment that hasn't completed the manual
  profile-provisioning step. `ccs` is now an explicit opt-in, gated behind Phase 1's
  smoke-test.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Bootstrap CCS Prerequisites](./phase-01-bootstrap-ccs-prerequisites.md) | Completed |
| 2 | [Config Template Wiring](./phase-02-config-template-wiring.md) | Completed |
| 3 | [Coding-Agent-Delegate Skill CCS Routing](./phase-03-coding-agent-delegate-skill-ccs-routing.md) | Completed |
| 4 | [Docs and Catalog Sync](./phase-04-docs-and-catalog-sync.md) | Completed |

## Parallel Execution (`--parallel` plan mode)

| Phase | blockedBy | Parallel group | File ownership (no overlap) |
|-------|-----------|-----------------|------------------------------|
| 1 | — | A (start now) | `scripts/vps-bootstrap.sh`, `scripts/vps-bootstrap-oci.sh`, `templates/systemd/hermes.service` |
| 2 | — | A (start now) | `templates/config/production.yaml` |
| 3 | [1, 2] | B (after A) | `skills/dev/coding-agent-delegate/SKILL.md` |
| 4 | [1, 2, 3] | C (after B) | `part18-coding-agents.md`, `skills/README.md`, `CHANGELOG.md` |

Phase 3 needs Phase 1's confirmed CLI-name/install-step (for its Prerequisites
section) and Phase 2's confirmed config key name (`delegation.ccs_profile`) before
its own content is accurate — it is not blocked by any *file* overlap (no shared
files with 1 or 2), only by needing their finalized naming. Phase 4 documents all
three prior phases, so it runs last.

## Dependencies

**No blocking cross-plan dependency.** `plans/260703-1017-fix-remaining-security-scan-issues`
(status: pending) also touches `scripts/vps-bootstrap.sh` and
`scripts/vps-bootstrap-oci.sh` (its Phase 2, NodeSource install hardening, near the
top of each script) but in a disjoint region from this plan's Phase 1 (the `6b.
Coding-agent CLIs` block, further down). Same disjoint-region pattern the sibling
`260703-0347-hermes-coding-agent-delegation-skill` plan already used for shared
`production.yaml` edits — flagged here for parallel-session awareness, not wired as
`blockedBy`/`blocks`.

## Red Team Review

### Session — 2026-07-03

Three hostile `code-reviewer` agents reviewed `plan.md` + all 4 phase files with
grep/live-CLI-verified evidence (Standard tier: Fact Checker + Contract Verifier
methods applied by all three, per 4-phase plan size): Security Adversary, Failure
Mode Analyst, Assumption Destroyer. Reports:
`reports/from-code-reviewer-to-planner-red-team-security-adversary-plan-review-report.md`,
`reports/from-code-reviewer-to-planner-red-team-failure-mode-analyst-plan-review-report.md`,
`reports/from-code-reviewer-to-planner-red-team-assumption-destroyer-plan-review-report.md`.

**Findings:** 21 raw findings across 3 reports, deduplicated to 15 unique clusters
(all evidence-backed — file:line citations or, notably, two reviewers ran LIVE
tests against the real `ccs`/`claude` CLIs in this session rather than relying on
static analysis).
**Severity breakdown (post-dedup):** 4 Critical, 5 High, 6 Medium.
**Disposition:** 15 accepted, 1 rejected (superseded by an accepted finding covering
the same root cause).

| # | Finding | Severity | Disposition | Applied To |
|---|---------|----------|-------------|------------|
| 1 | `~/.claude` (ClaudeKit harness) is never provisioned for the `hermes` user — CCS-routing alone does not grant harness | Critical | Accept | plan.md Overview, Phase 1, Phase 3 |
| 2 | `harness: ccs` as default has no rollout safety net — live-tested hard-fail (`Profile not found`, exit 1) with no fallback | Critical | Accept | Phase 3 (default flipped to `bare`) |
| 3 | API-profile state-directory/memory-path behavior empirically differs from assumed (live-tested: falls back to default account profile, not a dedicated instance dir) | Critical | Accept (flagged unresolved, needs live verification on real target) | Phase 1, Phase 3, Unresolved Questions |
| 4 | `ReadWritePaths=/home/hermes/.ccs` grants write to shared, auto-executed hook/plugin code, not just per-profile state | Critical | Accept (documented as accepted risk, not eliminated — CCS doesn't publish a narrower stable subpath) | Phase 1 |
| 5 | Security Adversary's "default-harness broadens injection blast radius" — premise superseded by Finding 1 (CCS-routing doesn't change harness loading at all; the real gate is `~/.claude` presence, orthogonal to ccs-vs-bare) | Critical (as originally framed) | **Reject** (superseded — root cause captured correctly by Finding 1 instead) | — |
| 6 | `--parallel=N` / `${delegation.ccs_profile}` fabricated syntax — no frontmatter entry, no precedent, `validate_skills.py` doesn't constrain `parameters` shape so CI green proves nothing | High | Accept | Phase 3 (added `parallel` frontmatter param, reworded interpolation as illustrative) |
| 7 | Supply-chain risk: `@kaitranntt/ccs` unpinned, single-maintainer personal npm scope, now trusted with widened `ReadWritePaths` | High | Accept | Phase 1 (pinned `@8.7.0`) |
| 8 | `ccs api create --api-key <key>` leaks the real key via `ps`/shell history/`/proc/<pid>/cmdline` | High | Accept | Phase 2 (wizard recommended over CLI-arg form) |
| 9 | Same-repo parallel fan-out needs git worktrees, not just branch naming — concurrent processes sharing one working tree race on writes | High | Accept | Phase 3 (worktree-per-subtask requirement added) |
| 10 | "Unlimited concurrency" claim unverified, contradicted by `proper-lockfile` in `@kaitranntt/ccs`'s own dependency tree | High | Accept | Phase 3 (softened to "verify on your deployment") |
| 11 | Approval-gate parity claim ignores `production.yaml`'s own documented `denylist` gap (doesn't see structured `delegate_task`/`kanban`/`sandbox` calls) | Medium | Accept | Phase 1 Security Considerations (clarified gate covers dispatch, not reach) |
| 12 | `--bare` flag position/order in the constructed command unverified against real CLI parsing | Medium | Accept | Phase 3 (kept as documented pattern, flagged for operator verification) |
| 13 | Vietnamese doc mirror (`vi-docs/part18-coding-agents.md`) silently drifts stale with no sync rule | Medium | Accept | Phase 4 (declared explicitly out of scope, not silently skipped) |
| 14 | `part18-coding-agents.md`'s top-level Prerequisites block not updated — contradicts new CCS subsection deeper in the doc | Medium | Accept | Phase 4 (added `ccs` line to top-level Prerequisites too) |
| 15 | `delegation.ccs_profile`/`harness` have zero consumers in this repo — CI green only proves well-formed YAML/frontmatter, not runtime behavior | Medium | Accept | Phase 2, Phase 3 (explicit caveat added: consumed by the operator's external Hermes gateway, not this repo) |
| 16 | Brainstorm assumptions (multi-instance `--parallel`, `--auto` approval-skip) silently reversed/replaced without an explicit "unconfirmed" callout | Medium | Accept | plan.md Overview (strengthened framing), Unresolved Questions |

**Adjudication note on rejected Finding 5:** Security Adversary's framing ("making
`ccs` the default broadens blast radius vs. today's bare invocation") assumed
CCS-routing changes whether harness loads. Assumption Destroyer's Finding 1/2
(accepted as this table's Finding 1) established that's false — bare and
`ccs`-routed calls load identical harness on a given host, gated only by whether
`~/.claude/` exists there. The real, larger risk isn't "this plan's default
change increases exposure" — it's "harness exposure already exists today,
identically, on any host where `~/.claude/` happens to be present, regardless of
this plan." Captured correctly under Finding 1/4 instead of as a standalone item.

### Whole-Plan Consistency Sweep

- **Files reread:** `plan.md`, `phase-01-bootstrap-ccs-prerequisites.md`,
  `phase-02-config-template-wiring.md`,
  `phase-03-coding-agent-delegate-skill-ccs-routing.md`,
  `phase-04-docs-and-catalog-sync.md`.
- **Decision deltas checked:** `harness` default (`ccs` → `bare`); `ccs_profile`
  provisioning command (non-interactive `--api-key` → wizard-preferred, with
  exposure caveat kept for the CLI-arg form); `ReadWritePaths` framing (confident
  "necessary and complete" → accepted-but-unresolved risk, scope of what it
  protects corrected from "per-profile state" to "per-profile state + shared
  auto-executed code"); npm install pin (`@latest` implicit → `@8.7.0` explicit);
  `--parallel=N` flag syntax → `parallel=N` key=value + new `parallel` frontmatter
  parameter; branch-only isolation → git-worktree-per-subtask requirement;
  "unlimited concurrency" → "unverified, test on your deployment"; part18
  Prerequisites block (untouched → gains a `ccs` line); vi-docs (silent gap →
  explicit out-of-scope statement); effort estimates bumped (Phase 3 `2h`→`2.5h`,
  plan total `4.5h`→`5h`) to reflect the added worktree/smoke-test/wizard content.
- **Reconciled stale references:** plan.md Overview (struck through and replaced
  the superseded "full harness loads for any ccs call" claim; added the
  API-profile-fallback caveat and the default-flip note); Phase 1 (Key Insights,
  Implementation Steps 3 and new step 10, Risk Assessment rows, Security
  Considerations — five sections touched by the ReadWritePaths/supply-chain/
  smoke-test findings); Phase 2 (Key Insights, the provisioning-comment code
  block, Risk Assessment, Security Considerations — four sections touched by the
  API-key-exposure and zero-consumers findings); Phase 3 (Overview, Key Insights,
  Requirements, Architecture, all 4 numbered Implementation Steps sub-items,
  Success Criteria, Risk Assessment, Security Considerations, and the Context
  Links "always loads" claim — nine sections touched by the default-flip,
  worktree, and concurrency findings, the most extensively revised phase); Phase 4
  (Key Insights, Implementation Steps 2/2b/3, the embedded CHANGELOG.md draft,
  Success Criteria — five sections touched by the Prerequisites-block and
  vi-docs findings).
- **Unresolved contradictions:** 0. (Three items remain genuinely open questions
  rather than contradictions — listed below, not silently resolved.)

## Unresolved Questions

1. **[Critical, needs live verification]** CCS API-profile state-directory/
   memory-path fallback behavior on a headless deployment target with **zero**
   pre-existing account profiles is untested (this dev session always had `lucas`/
   `ken`/`luan` account profiles present, so the live test's fallback path may not
   generalize). Before enabling `harness: ccs` in production, run the same test
   (`ccs api create ...` then `ccs <profile> -p "echo ok" --output-format json`)
   on the actual target host and confirm where state/memory actually lands and
   whether it stays within the granted `ReadWritePaths`.
2. **[Critical, out of this guide's scope]** Provisioning ClaudeKit (`~/.claude/`
   — `CLAUDE.md`, `rules/*`, skills catalog, hooks) onto the `hermes` service user
   is a real, separate prerequisite for `harness: ccs` to deliver any harness
   benefit at all, and this guide repo does not document or automate a ClaudeKit
   install process. Is that acceptable to ship as a documented external
   dependency, or should this plan be re-scoped to not claim "harness" as a
   benefit until that gap has an owner?
3. **[Medium]** Real concurrent-invocation throughput ceiling for one CCS API
   profile is unverified (auth failed before reaching load in this session's test;
   `proper-lockfile` in the dependency tree suggests possible serialization) —
   needs a real test with a valid key before the `parallel` example's claims can
   be fully trusted.
4. **[Medium]** `ReadWritePaths=/home/hermes/.ccs` is accepted as a known,
   documented risk (shared hook/plugin write access) rather than solved — revisit
   if/when CCS publishes a stable, narrower per-profile-only subpath.

## Validation Log

### Session 1 — 2026-07-03

**Trigger:** Post-red-team `/ck:plan validate` pass (`--parallel --auto` mode).
`## Red Team Review` above already contains evidence-based verification (live
CLI tests + grep citations), so per the validate workflow's Step 2.5 guard, a
fresh verification pass was skipped — no `[UNVERIFIED]` tags existed to resolve.
**Questions asked:** 4 (all genuine scope/risk-acceptance decisions the red-team
pass surfaced but could not resolve by grep alone).

#### Questions & Answers

1. **[Scope]** Red-team found CCS-routing doesn't grant harness by itself —
   ClaudeKit provisioning on the `hermes` host is a separate, unmet prerequisite
   outside this guide's ownership. Ship with that limitation documented, or expand
   scope with a new phase to solve ClaudeKit provisioning?
   - Options: Ship with clear caveat (Recommended) | Add Phase 5 for ClaudeKit provisioning
   - **Answer:** No response within the wait window; proceeded with the
     recommended option per this session's `--auto` directive.
   - **Rationale:** ClaudeKit's own install/distribution mechanism is not owned by
     this repo (a Hermes guide) — a new phase here could not actually solve
     provisioning without documenting a process this repo has no authority over.
     Documenting the gap honestly is more useful than a phase that can't
     guarantee its own success criteria.
2. **[Risk]** `ReadWritePaths=/home/hermes/.ccs` grants write access to shared
   auto-executed hook/plugin code, not just per-profile state. Accept and
   document, or block Phase 1 until a narrower path is found?
   - Options: Accept risk, document clearly (Recommended) | Block until narrower path found
   - **Answer:** No response within the wait window; proceeded with the
     recommended option per this session's `--auto` directive.
   - **Rationale:** CCS does not publish a stable per-profile-only subpath from
     outside its source — blocking indefinitely on an external dependency this
     repo doesn't control would stall the whole plan for an unbounded amount of
     time. Documented as an explicit, revisitable risk instead (Phase 1 Security
     Considerations, Unresolved Question 4).
3. **[Risk]** API-profile state-directory fallback behavior is untested on a
   headless host with zero pre-existing account profiles (this dev session always
   had `lucas`/`ken`/`luan` present). Ship with a caveat for the operator to verify
   at rollout, or block this plan until a zero-account-profile environment is
   available to test against?
   - Options: Ship with caveat, operator verifies at rollout (Recommended) | Block until verified
   - **Answer:** No response within the wait window; proceeded with the
     recommended option per this session's `--auto` directive.
   - **Rationale:** No zero-account-profile test environment is available in this
     session or repo — blocking would stall indefinitely on an environment this
     plan cannot provision for itself. Documented as Unresolved Question 1 with an
     explicit verification step for the operator's real deployment.
4. **[Architecture]** Phase 3 flips the `harness` default to `bare` for safety.
   Is a manual smoke-test gate (Phase 1 step 10) sufficient, or should the skill
   also document an auto-fallback procedure (retry as `bare` if `ccs` errors with
   "profile not found")?
   - Options: Manual smoke-test only (Recommended) | Add auto-fallback guidance in SKILL.md
   - **Answer:** No response within the wait window; proceeded with the
     recommended option per this session's `--auto` directive.
   - **Rationale:** `SKILL.md` is a natural-language procedure for Hermes's agent
     to follow, not executable code with a real try/catch — a documented
     go/no-go gate before enabling `harness: ccs` is proportionate; an
     auto-fallback procedure would add process complexity to a docs file for a
     failure mode the safe default (Finding 2, `bare`) already avoids by not
     defaulting to the failure-prone path in the first place.

#### Confirmed Decisions
- Ship with the ClaudeKit-provisioning gap documented as an explicit,
  out-of-scope prerequisite — no new phase added.
- `ReadWritePaths=/home/hermes/.ccs` ships as-is with the risk documented — no
  narrower scoping attempted (would require CCS internals this repo doesn't own).
- API-profile fallback behavior ships with an explicit unresolved-verification
  caveat — operator verifies on their real target before enabling `harness: ccs`.
- No auto-fallback procedure added to `SKILL.md` — manual smoke-test gate
  (Phase 1 step 10) stands as the sole go/no-go check.

#### Action Items
- [x] All four decisions above already match the plan's current state (red-team
      pass already applied the recommended framing to every phase file) — no
      further edits required by this validation session.

#### Impact on Phases
- None — this session's answers confirm the red-team-revised plan as-is; no
  phase file required further changes.

### Whole-Plan Consistency Sweep

- **Files reread:** `plan.md`, all 4 `phase-*.md` files (same set as the
  red-team sweep above).
- **Decision deltas checked:** 4 (all four validate answers matched the
  already-applied red-team revisions — no new deltas to propagate).
- **Reconciled stale references:** 0 (nothing changed as a result of this
  session; the red-team sweep already reconciled every affected section).
- **Unresolved contradictions:** 0.

**Verification Results (carried forward from Red Team Review — Step 2.5 guard
applied, no fresh pass needed):** Claims checked: 21 raw findings across 3
reports, all evidence-filtered (file:line citation or live-CLI-test required).
Verified/Failed/Unverified breakdown: all 3 reports' findings were evidence-backed
(0 rejected for missing evidence); adjudication in `## Red Team Review` above
stands as the verification record for this plan. 4 items remain genuinely
open/unresolved (not contradictions) — see Unresolved Questions above.
