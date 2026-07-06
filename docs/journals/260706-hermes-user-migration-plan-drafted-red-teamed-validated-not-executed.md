# Hermes Agent User Migration Plan Drafted, Red-Teamed, Validated (Not Yet Executed)

**Date**: 2026-07-06 04:22  
**Severity**: High  
**Component**: Hermes Agent systemd service (hermes→ubuntu user), CCS credential consolidation, workspace sharing  
**Status**: Plan complete (pending execution), fully validated, 0 unresolved contradictions

## What Happened

Session: user invoked `/ck:plan --tdd --validate --red-team --auto --parallel` to scope a migration moving the live Hermes Agent Telegram bot from the isolated `hermes` system user (uid 1002) back to shared `ubuntu` user, eliminating cross-user filesystem friction and retiring a concerning credential-duplication anti-pattern.

**Phase 1: Live-Host Research & Assumption Verification**  
A draft plan was supplied as the starting point. Two parallel researcher subagents executed live-host recon (CCS instance bridge mechanics; systemd/workspace/security blast radius) and **invalidated four key assumptions**:
- Draft assumed `~/.hermes/profiles/<name>/SOUL.md` directory structure; reality is flat (`~/.hermes/SOUL.md`, `~/.hermes/memories/`, no profiles subdir)
- Draft listed Chromium/Playwright apt dependencies; hermes-agent has zero such dependency
- Draft assumed fresh `hermes setup` on blank ubuntu; `/home/ubuntu/.local/bin/hermes` launcher already exists (from a 2026-06-28 install before the isolation pivot)
- Draft assumed copying hermes's venv+node_modules to save rebuild time; Python venvs embed absolute shebang paths (`/home/hermes/.hermes/...`) that break on relocation — must re-install, copy only state

Additionally, live audit found: ubuntu already has 3 CCS profiles (ken/luan/lucas) plus a **stale placeholder** `ccs-hermes` entry, while the **real working** `ccs-hermes` credential sits in `/home/hermes/.ccs/instances/ccs-hermes/` (verified via smoke test — real OAuth, active). Even more concerning: hermes's `~/.ccs/instances/` contained file-copied duplicates of ubuntu's ken/luan/lucas OAuth credentials. This migration retires that pattern rather than perpetuates it.

**Phase 2: Plan Scaffolding & Red-Team Review**  
Plan scaffolded into 8 sequential phases (backup/baseline, fresh install, restore state, CCS consolidation, workspace reconciliation, blue/green cutover, post-cutover validation + 48h rollback window, cleanup + user removal). Each phase tagged `[AGENT]` (non-interactive) or `[HUMAN]` (root password / judgment calls).

Four independent reviewers (Security Adversary, Failure Mode Analyst, Assumption Destroyer, Scope & Complexity Critic — Full verification tier) produced **21 raw findings**, deduplicated to **15 accepted** (6 Critical, 5 High, 4 Medium). Single most-corroborated critical finding: `ReadWritePaths=` in the systemd units never included `/home/ubuntu/workspace` — this **reproduces a live, already-documented EROFS bug** from a prior plan (260705-1752). All three failure-mode reviewers independently caught this. Other critical findings: missing `--skip-setup` installer flag (Telegram 409 conflict risk before cutover starts), no re-copy step for WAL-mode `state.db`/`kanban.db` between snapshot and actual cutover (data loss), this repo's own `templates/systemd/hermes.service` never being updated (future routine redeploy would silently revert the whole migration), and a rollback-safety claim that was false (Phase 4's draft deleted credentials before the 48-hour window closed).

**Phase 3: Validation Interview & Decision Resolution**  
Per the validation workflow's Step 2.5 guard, the 4 reviewers each carried a verification role (Fact Checker, Flow Tracer, Scope Auditor, Contract Verifier) backed by live-host command output, so the verification pass itself was skipped. Interview went straight to 4 remaining judgment-call decisions:

1. **Default delegation identity**: use ubuntu's own `~/.claude/` (chosen) vs. create dedicated bot credential vs. check if moot. Decision: ubuntu's own, simplest path.
2. **Cutover-ordering residual risk**: accept relying on Stage A's strengthened `systemd-run` validation (chosen) vs. add canary step. Decision: accept; canary adds complexity for marginal coverage.
3. **7 hardcoded `/home/hermes` scripts**: add loud `id hermes` guards (chosen) vs. full rewrite vs. footnote only. Decision: guards (cheap, prevents silent failure).
4. **Downtime target**: <5min was unrealistic once the WAL-copy re-sync step was added. Decision: relax explicitly to <15min.

All 15 red-team findings **accepted and applied**. Whole-plan consistency sweep (all 8 phase files re-read post-fixes): **0 unresolved contradictions**.

## The Brutal Truth

The most uncomfortable finding: hermes's `~/.ccs/instances/` contained actual file-copied duplicates of the human users' real OAuth credential files (`ken`, `luan`, `lucas` — not references, not symlinks, **actual copied tokens**). This isolation architecture that was supposed to sandbox Hermes actually created a secondary credential storage anti-pattern. The migration retires this, which is the right call, but it's a stark reminder that the original "isolate hermes to a separate user" decision came with hidden downsides that only became visible months later.

The red-team's independent triple-catch of the `ReadWritePaths` bug (already documented in a previous plan's journal) is maddening: **the exact same failure mode that broke CCS delegation in Phase 3 of 260705-1752 was about to be shipped again** because it lives in a shared-unit definition that wasn't part of the review scope until red-team explicitly checked it. Future developers: grep for `ReadWritePaths` in `templates/systemd/*.service` as a standing checklist item for any plan involving workspace access.

The <5min downtime estimate not holding once WAL-mode database re-copy was added (another red-team catch) is typical: the plan's original author didn't account for the actual data-consistency cost. This is reasonable — red-team's job is exactly to catch this — but it suggests the validation interview should have included a "estimate re-check post-red-team-fixes" step, not just final-decision-only questions.

## Technical Details

**Plan location:** `plans/260706-0345-migrate-hermes-agent-to-ubuntu-user/plan.md` + 8 phase files (phase-01 through phase-08).

**Red-Team Findings Applied:**  
- Finding #1 (Critical): `ReadWritePaths=/home/ubuntu/workspace` added to Phases 5, 6, 7 (was omitted; would reproduce 260705 EROFS).
- Finding #2 (Critical): Phase 2 installer now includes `--skip-setup` flag (prevents Telegram 409 conflict).
- Finding #3 (Critical): Phase 6 new step 5a: explicit re-copy of WAL-mode `state.db` and `kanban.db` between initial snapshot and cutover moment.
- Finding #4 (Critical): Phase 6 now includes step to update `templates/systemd/hermes.service` in this repo (prevents silent revert on future redeploy).
- Finding #5 (Critical): Phase 4's credential deletion moved to Phase 8 post-rollback-window (Phase 1–6 now genuinely non-destructive).
- Finding #6 (Critical): Phase 1 now produces separate `.bak` unit files for rollback source (git-template fallback removed).
- Finding #7 (High): Phase 3 restore list completed (added `nous_auth.json`, dedup index, cron/sandboxes/snapshot/pairing dirs).
- Finding #8 (High): Phase 3 step 8 reconciles bare-harness `~/.claude/.credentials.json` identity (use ubuntu's, no new credential).
- Finding #9 (High): Phase 8 step 9 adds loud `id hermes` guards to 7 scripts (prevents silent misbehavior on re-run).
- Finding #10 (High): Phase 6 Stage A rewritten to use `systemd-run` instead of plain exec (exercises real sandboxing, not bypassed).
- Finding #11 (High): Phase 3 step 2 retagged `[HUMAN]` (config merge requires judgment).
- Finding #12 (Medium): Phase 1 backup tarball now explicitly chmod 600, and "full backup" list expanded (added `.claude.json`, `.claudekit`, `.config`, `.local`).
- Finding #13 (Medium): Symlink-retarget timing mitigated via Stage A strengthening, not new canary-unit (per validation decision).
- Finding #14 (Medium): Phase 8 destructive gate (step 1) hardened to re-verify blast radius.
- Finding #15 (Medium): Phase 4 YAML edit validation added structure check (not just syntax).

**Validation Interview Outcomes:**
- Default delegation identity: ubuntu's own `~/.claude/` (no dedicated bot credential for bare-harness delegation).
- Cutover risk residual: accepted; no canary step.
- Stale-script guards: all 7 scripts get loud `id hermes` checks in Phase 8 (full rewrite deferred).
- Downtime target: <5min → <15min (applies to plan.md Overview, Phase 6 effort estimate, Success Criteria).

**Consistency Sweep Results:**  
- Files verified: plan.md + all 8 phase files (full re-read post-fixes).
- Stale references checked: `grep -rn "5 min\|5min\|<5"` across all files — only corrected `<15min` figures remain; history notes documenting the change are intentional.
- Unresolved contradictions: **0**.

## Root Cause Analysis

The original decision to isolate Hermes to a separate user (uid 1002) was made to sandbox the bot's process. In practice, it created **distributed credential storage** (OAuth duplicates in hermes's `~/.ccs`), **split filesystem state** (two workspace clones), and **repeated provisioning work** (Hermes's own ClaudeKit, own venv, own CCS profiles). The "isolation benefit" proved negative. This migration's root cause is that assumption: isolation created more friction than benefit.

The multiple independent red-team catches of the same bugs (especially `ReadWritePaths`/workspace omission) point to a **systematic review gap**: shared unit templates (`templates/systemd/*.service`) that are copied to `/opt` and hand-edited per-plan don't get swept for consistency. Future plans touching systemd will re-discover the same omissions unless the template itself is fixed once.

The <5min downtime estimate was optimistic because it didn't account for **WAL-mode database synchronization cost** — that cost only became visible once the red-team asked "how do you prevent data loss between snapshot and cutover?" The original plan author reasonably didn't surface this risk (blue/green migrations in the literature often elide DB sync), but red-team's Failure Mode Analyst perspective caught it.

## Lessons Learned

1. **Shared unit templates are a blind spot**: If a single `templates/systemd/hermes.service` file is the source-of-truth but gets edited per-plan, those edits must propagate back to the template or they'll regress on next redeploy. This plan now includes that step explicitly (Finding #4).

2. **WAL-mode databases introduce hidden cutover costs**: Simply snapshotting state before cutover and assuming it's consistent at restart-time is not safe for WAL-mode databases (SQLite, in this case). Red-team's Failure Mode Analyst independently surfaced the re-copy requirement.

3. **`ReadWritePaths` omissions are a chronic issue in this codebase**: Same failure mode appeared in 260705-1752, now about to appear again in this plan until red-team caught it. Suggests a standing pre-flight checklist: verify `ReadWritePaths` includes all directories the unit actually needs to write to.

4. **Credential duplication is a sign of architectural friction**: The fact that hermes ended up with file-copied OAuth duplicates instead of references or shared access suggests the original isolation decision should have been revisited earlier. Future "sandbox as separate user" proposals should be evaluated on whether they introduce this pattern.

5. **Validation interviews should include estimate re-check**: After red-team applies critical findings, especially ones that change execution flow or add steps, the original effort/downtime estimates should be re-validated. This plan's <5min → <15min change happened post-red-team; catching it in the original validation pass would have prevented the gap.

## Next Steps

- Plan is complete and ready for execution. User chose to defer `/ck:cook` (implementation) to a later session to review manually first.
- Before cook: ensure live host has current `/opt/hermes-optimization-guide` clone (already synced during IMDS fix in 260704).
- After cook: run `/ck:security-scan` to verify no new findings from the provisioning changes.
- 48-hour rollback window post-Phase 6 cutover must be respected (Phase 1–6 non-destructive, Phase 8 cleanup deferred).
- This plan supersedes the isolation architecture but **coexists with** two in-progress sibling plans (`260703-1738` Phase 3/5 in progress, `260704-2106` in progress) — coordinate timing to avoid mid-edit config snapshots.

## Unresolved Questions

None. All red-team findings accepted and applied; all validation decisions recorded; plan swept for consistency (0 contradictions).
