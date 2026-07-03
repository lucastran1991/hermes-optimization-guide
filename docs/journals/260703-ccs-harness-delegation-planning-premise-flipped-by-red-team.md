# CCS Harness Delegation Planning — Red-Team Flipped the Premise

**Date**: 2026-07-03 10:41-11:53 UTC
**Severity**: High (design flaw caught pre-implementation)
**Component**: Coding-Agent-Delegate Skill / CCS routing / Hermes service user harness provisioning
**Status**: Planned and validated; no code written yet; 4 open questions require live deployment verification

## What Happened

Ran `/ck:plan --tdd --red-team --validate --auto --parallel` to translate a prior brainstorm report (`plans/reports/brainstorm-260703-1034-ccs-full-harness-delegation-skill-report.md`) into an executable implementation plan. Created `plans/260703-1041-ccs-full-harness-coding-agent-delegation/` containing plan.md + 4 phase files:

1. **Phase 1**: Bootstrap CCS prerequisites on Hermes (fnm, Node, ClaudeKit CLI set, `.claude/` harness baseline)
2. **Phase 2**: Config template wiring (update `hermes.service` EnvironmentFiles for CCS API credentials, profile selection logic)
3. **Phase 3**: Coding-Agent-Delegate skill CCS routing (update SKILL.md conditional logic to route large delegations through CCS harness instead of bare `claude`)
4. **Phase 4**: Docs and catalog sync (update codebase-summary, SKILL registry, deployment guide)

Goal: Enable Hermes' `coding-agent-delegate` skill to opt-in to routing Tier-1 (large, long-lived) Claude Code delegations through a scoped CCS identity — a per-deployment identity-isolation and quota-scoping feature.

Then dispatched 3 parallel adversarial code-reviewer agents (Security Adversary, Failure Mode Analyst, Assumption Destroyer; Standard verification tier) with live CLI test authority.

## The Brutal Truth

The planner's original premise — **"Routing delegations through CCS will grant the hermes service user access to the full ClaudeKit harness"** — was **partially wrong**. Two of the three reviewers ran LIVE tests against actual `ccs` and `claude` CLIs on the real host, not just static analysis. The findings shattered the foundational assumption:

1. **Harness access is orthogonal to CCS routing.** Whether a user routes through CCS or bare `claude`, harness loading depends solely on: (a) does `~/.claude/` exist on the host? and (b) is `--bare` passed to suppress harness? CCS routing changes *identity* and *quota scoping* only — it never grants or denies harness visibility. Our bootstrap plan provisions `~/.claude/` during Phase 1, but only if manually approved per-deployment. On an unmodified Hermes instance with zero bootstrapping, CCS-routing changes quota/identity only; the skill would still have no harness.

2. **Hard failure on missing CCS profile.** Original plan defaulted to `harness: ccs` with fallback logic. Live test: `ccs nonexistent-profile -p ...` exits 1, prints "Profile not found", **no automatic fallback.** Any deployment without a manually-provisioned CCS profile would hard-fail the skill at runtime. This is a production footgun.

3. **CCS API profile instance directory fallback is unresolved.** A live-created CCS profile (via API, no prior manual setup) on a headless host with zero account profiles showed confusing behavior: the profile's runtime instance directory fell back to the default account profile's directory, not getting its own isolated directory. Behavior is unverified in production context.

This cascades to a brutal realization: **the original plan had the right components (API provisioning, ClaudeKit harness setup, fallback logic) but wrong assumptions about what each solves.** The plan doesn't fail — but what it *claims* to deliver (opt-in harness for Hermes service user) is only half true. What it actually delivers is opt-in quota/identity scoping, with harness being a separate, explicit prerequisite.

## Technical Details

**Red-team findings summary (21 raw → 15 accepted + 1 rejected):**

### Accepted findings (15):

1. **Harness is orthogonal to CCS routing** (Security Adversary + Failure Mode Analyst, live-verified via `claude --bare`, CCS env isolation tests)
2. **Default `harness: ccs` is a hard failure** without provisioned CCS profile (Failure Mode Analyst, live `ccs` CLI test, exit 1 on nonexistent-profile)
3. **Phase 1 `~/.claude/` provisioning scope ambiguous** (Assumption Destroyer: manual or auto-triggered by Phase 2? By whom?)
4. **ReadWritePaths in EnvironmentFiles risk** (Security Adversary: CCS API credentials in plaintext env; rotation exposure; audit trail)
5. **CCS profile instantiation unresolved on headless host** (Failure Mode Analyst, live test against CCS API)
6. **Phase 1 fnm installation assumes ubuntu shell profile** — invalid for hermes systemd service (Failure Mode Analyst; verified in prior 260703-hermes-coding-agent-cli-path-fix session)
7. **Phase 2 EnvironmentFiles ordering** — if `.env` loads before bootstrap, CCS variables undefined (Assumption Destroyer)
8. **Phase 3 fallback logic unclear** — what does "fallback to bare" mean if harness doesn't exist? (Failure Mode Analyst)
9. **No smoke-test gate between Phases 1 and 2** — if bootstrap fails silently, Phase 2 proceeds with incomplete setup (Security Adversary)
10. **Phase 4 docs don't clarify mandatory vs. optional** provisioning steps (Assumption Destroyer)
11. **SKILL.md routing condition brittle** — assumes `$CCS_PROFILE_NAME` is always set; no validation (Security Adversary)
12. **Quota isolation claim unverified** — plan promises quota per CCS profile, but no test of concurrent delegation cap (Failure Mode Analyst)
13. **No rollback procedure** if CCS API becomes unavailable (Security Adversary)
14. **Hermes service restart required** after Phase 2 config to reload `.env` — plan doesn't explicitly state this (Assumption Destroyer)
15. **ClaudeKit CLI versions in bootstrap** — plan doesn't pin versions; future CLI updates may break routing (Failure Mode Analyst)

### Rejected findings (1):

- **"Phase 1 should include .gitignore update for .env"** — Superseded by Phase 2 explicit instruction to update `/home/hermes/.hermes/.env` (grep verified in bootstrap plan; .gitignore is orthogonal to systemd ENV loading).

## What We Tried

1. **Self-research against guide docs** (planner): Drafted 4 phases based on codebase-summary (ClaudeKit skill patterns, systemd best practices, prior hermes-coding-agent-cli-path-fix session). All citations resolved; high confidence in component sequencing.

2. **Red-team adversarial review** (3 parallel code-reviewer agents):
   - **Security Adversary**: Focus on secret management, quota isolation, API credential handling. Ran live tests on CCS CLI env isolation and profile creation.
   - **Failure Mode Analyst**: Focus on runtime assumptions, missing prerequisites, fallback logic. Ran live `ccs` CLI tests, examined EnvironmentFiles loading order.
   - **Assumption Destroyer**: Focus on scope ambiguity, implicit dependencies, unvalidated claims. Static analysis + live fnm/hermes context from prior session.

3. **Adjudication on conflicting findings**: Each finding traced to source (live CLI test, file verification, grep on guide docs, or live environment confirmation). Contradictions resolved via re-test or direct read.

4. **Validation pass** (`--validate`): Asked 4 scope/risk-acceptance questions:
   - Q1: Should Phase 1 provisioning be manual or auto-triggered?
   - Q2: Accept ReadWritePaths (CCS credentials in plaintext EnvironmentFiles) risk for MVP?
   - Q3: Accept CCS profile instance-directory fallback as-is pending live deployment verification?
   - Q4: Implement manual smoke-test gate or auto-fallback-to-bare on Phase 2 failure?
   
   No user response within 120s wait; `--auto` flag caused auto-selection of recommended (conservative) option for all 4. Documented in plan's Validation Log with rationale.

## Root Cause Analysis

**Assumption bundling**: The planner's task was "enable opt-in harness for Hermes service user via CCS routing." This is actually *three* orthogonal things:

1. **Harness provisioning** (`~/.claude/` exists, harness loading works)
2. **Identity scoping** (credentials for a CCS profile, not personal account)
3. **CCS routing logic** (skill conditional: use CCS harness if explicitly requested, else bare)

The original plan conflated (1) and (3): "CCS routing grants harness" is wrong. CCS routing grants *identity scoping only*. If you route through CCS without provisioning harness, you get a scoped identity running the bare `claude` CLI (same capability, different account/quota). If you provision harness without using CCS, you get full harness running a personal identity. The orthogonality was invisible because the planner bundled all three into a single 4-phase narrative.

Second layer: **No live testing on the assumption**. The planner's research was rigorous (citations in guide docs all checked out), but it was synchronous — never actually invoked a CCS profile or tested harness loading against a deployed service. The red-team filled this gap by running live CLI tests, which immediately surfaced the contradiction.

## Lessons Learned

1. **Validate orthogonal assumptions with live tests, not docs.** When a plan claims "feature X gives you property Y," verify the causal claim experimentally, especially if Y is a security/capability property. Docs consistency is necessary but not sufficient.

2. **Scope hard failures explicitly.** The original plan had a fallback from CCS to bare, but didn't state what "fallback" means if the harness doesn't exist. On a fresh Hermes with zero provisioning, falling back to bare without harness is still a hard failure (no delegation at all). This needed explicit scope: "Phase 1 is prerequisite; if skipped, Phase 3 fails."

3. **Separate concern: implicit vs. explicit prerequisites.** Phase 1 provisioning should have a clear explicit gate: manual checkbox ("Run Phase 1 bootstrap"), not an implicit assumption ("bootstrap has already happened"). Multi-phase plans hide implicit dependencies; make them explicit or fail loudly.

4. **Validation questions are not optional.** The planner raised 4 genuinely open questions (manual vs. auto provisioning, secret plaintext risk, profile directory fallback behavior, manual vs. auto fallback logic). Skipping these to move faster doesn't save time — it guarantees rework during implementation or post-deploy troubleshooting.

## Next Steps

**Completed:**
- All 15 accepted red-team findings applied to plan.
- 4 validation questions auto-answered (conservatively: manual provisioning, accept plaintext-env risk for MVP, accept instance-directory fallback pending live verification, manual smoke-test gate).
- Plan is structurally sound, sequencing correct, no contradictions remain.

**Blocked on live deployment verification (4 genuinely open questions, documented in plan's Validation Log):**
1. Does Phase 1 bootstrap succeed when run as systemd PreStart hook vs. manual off-box run?
2. Does CCS API profile load its own instance directory on a hermes-like headless host with zero account profiles, or fall back to account profile's?
3. Does manual smoke-test gate (test CCS profile, if fails → hard-error before Phase 2) catch real-world setup issues?
4. If a deployment skips Phase 1 bootstrap, does Phase 3 routing fail gracefully (clear error) or silently route to bare-without-harness?

**Not yet implemented:**
- Zero code written. This is a plan-only session.
- Plan is ready for cook phase as soon as a test Hermes deployment is available for live verification of the 4 open questions.

**For future planning sessions involving harness/identity/quota features:**
- Separate the three concerns upfront: (a) harness loading (prerequisite, phase-gated), (b) identity provisioning (feature itself), (c) routing logic (implementation surface).
- Run live CLI tests on the main claim (e.g., "does CCS routing really change identity without changing harness?") during planning red-team, not after implementation starts.
- Explicit gate each phase prerequisite: "This phase requires Phase N to have succeeded. If Phase N was skipped, this phase fails loudly."

## Unresolved Questions (For Live Deployment)

1. **Phase 1 bootstrap execution context**: Should bootstrap run as systemd `PreStart` hook (auto-triggered on service start) or manual off-box procedure? Original plan assumed manual; Validation Log recommends manual (conservative). Must verify this choice on real Hermes before cook.

2. **CCS API profile instance directory behavior on headless host**: Live test showed profile fell back to account profile's directory when host had zero account profiles. Is this expected? Will it break quota isolation if hermes and a future logged-in admin use the same account profile directory? Pending live deployment verification.

3. **Fallback-to-bare safety**: If a deployment skips Phase 1 bootstrap, Phase 3 routing logic will attempt to invoke CCS (missing), then fallback to bare `claude` (no harness). Is this acceptable, or should it fail hard with an error message? Plan documents as manual smoke-test gate (must pass before proceeding); must validate on real Hermes.

4. **Graceful degradation of SKILL.md routing when CCS becomes unavailable**: Plan assumes CCS profile will be available at runtime. What if CCS API is temporarily down? Should SKILL.md retry, timeout, or fallback immediately? Plan does not specify; must be decided during implementation based on user's tolerance for service degradation.

