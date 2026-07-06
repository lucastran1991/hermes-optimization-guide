---
title: "Migrate Hermes Agent from hermes User to Ubuntu User"
description: "Move the live Hermes Agent Telegram bot from the isolated `hermes` system user back to `ubuntu`, eliminating cross-user permission friction and credential duplication, via a fresh install + state restore + blue/green cutover."
status: pending
priority: P1
effort: "8-12h (mostly [HUMAN] root/interactive steps; wait-time for the 48h rollback window not counted)"
branch: "main"
tags: [infra, hermes, migration, systemd, ccs, security]
blockedBy: []
blocks: []
created: "2026-07-06T03:48:20.514Z"
createdBy: "ck:plan"
source: skill
---

# Migrate Hermes Agent from hermes User to Ubuntu User

## Overview

Hermes Agent (Telegram bot + coding-agent delegation gateway) currently runs as the isolated
Linux user `hermes` (uid 1002), live and in production right now (`hermes.service` +
`hermes-dashboard.service`, both active). The isolation was meant to sandbox the bot, but it
created the opposite of the intended benefit: `hermes` has its own separate Claude Code /
CCS install, its own copy of two workspace repos, and — the most concerning finding — its
own **file-copied duplicates of the human user's `ken`/`luan`/`lucas` CCS credentials**
(real OAuth tokens, not references). This plan merges Hermes into `ubuntu` so it shares one
filesystem, one CCS/Claude install, and one set of workspace clones, and retires the
credential-duplication pattern instead of extending it further.

This plan **supersedes the isolation architecture** but does **not cancel or block** the two
plans still in progress against the `hermes`-user setup: `260703-1738-fix-urgent-hermes-delegation-issues`
(Phase 3/5, claude auth + CCS profile for hermes) and
`260704-2106-bootstrap-script-delegation-provisioning-scripts`. Per explicit user decision,
those continue in parallel — `/home/hermes/...` is left untouched until Phase 8 (48h+ after
cutover), so there is no file-level conflict. **Caution:** if either of those plans is being
actively executed at the same moment as this plan's Phase 1-3 (which read a snapshot of
`/home/hermes/.hermes/config.yaml` and `~/.ccs/`), coordinate timing to avoid restoring a
mid-edit config.

### Key findings from live-host research (this plan's own recon, not the original draft)

The original draft this plan is based on made several assumptions that don't match the real
host and have been corrected here:

| Draft assumed | Reality found | Impact |
|---|---|---|
| `~/.hermes/profiles/<name>/{SOUL,MEMORY,USER}.md` | Flat layout: `~/.hermes/SOUL.md`, `~/.hermes/memories/{MEMORY,USER}.md` — no `profiles/` subdir at all | Phase 3 paths corrected |
| Chromium/Playwright apt deps needed | `hermes-agent` has **no** playwright/puppeteer/chromium dependency; browser libs (`libnss3`, `libatk-bridge2.0-0t64`, `libgbm1`) already installed on the host for other reasons | Dropped from plan — no `apt-get install` step needed |
| Fresh `hermes setup` on a blank ubuntu | `/home/ubuntu/.local/bin/hermes` launcher stub **already exists** (created 2026-06-28, `bash_history` confirms `curl \| bash` install ran once as ubuntu before the isolation pivot) — `/home/ubuntu/.hermes/` itself does not exist | Phase 2 re-runs the same proven installer command; low risk |
| Copy hermes's whole `hermes-agent` dir (venv + node_modules) to save rebuild time | Python venvs embed absolute shebang paths (`/home/hermes/.hermes/hermes-agent/venv/bin/python3`) — copying to a new home breaks them | Phase 2 does a fresh install (installer recreates venv correctly rooted); only **state** (config/skills/memories/kanban) is copied in Phase 3, not the venv/build artifacts |
| "Restore config.yaml + .env as-is" | `.env` hardcodes `PATH=/home/hermes/.local/bin:...` — must be rewritten to `/home/ubuntu/.local/bin:...` or the gateway's shelled-out subprocesses (delegation calls) resolve the wrong binaries | Phase 3 explicit path-rewrite step |
| "ubuntu's CCS/AI stack — do not touch yet" (implied blank slate) | `ubuntu` already has 3 established CCS profiles (`ken`/`luan`/`lucas`) plus a **stale placeholder** `ccs-hermes` entry (`ANTHROPIC_AUTH_TOKEN: "x"`) in its own `config.yaml`. The **real, working** `ccs-hermes` credential lives under `/home/hermes/.ccs/instances/ccs-hermes/` (verified via live smoke test — real OAuth, last used today) | Phase 4 moves the real credential over and removes the stale placeholder, instead of creating anything new |
| "hermes has its own workspace clones, migrate them" | `kitchen` is identical commit both sides; `nfi` — hermes is **behind** ubuntu (`1aa032f6` vs `9201b4a`), but hermes's copy has a **clean working tree** (no uncommitted changes, no stashes) | Phase 5 does not merge anything — ubuntu's copies are simply reused, hermes's stale copies are discarded with the rest of `/home/hermes` at cleanup |
| Simple blue/green (both instances live simultaneously) | Hermes's Telegram integration is very likely single-poller (Bot API `getUpdates` rejects a second concurrent poller with `409 Conflict`); true dual-live risks duplicate/missing replies to real users | Phase 6 brings the ubuntu ("green") instance up with the Telegram platform **disabled** first, validates everything else, then does a short stop-old/start-new cutover — documented as the realistic safe interpretation of "blue/green" for a single-token bot, not literal simultaneous dual-serving |
| `userdel -r hermes` cleanup risk unclear | Confirmed: **zero** files owned by `hermes` outside `/home/hermes` (`find / -user hermes` outside home returns nothing); the `(root) NOPASSWD: systemctl hermes*` sudoers grant matches unit *names*, not the OS user, so it keeps working after the units switch to `User=ubuntu` — no sudoers edit needed for that grant | Phase 8 cleanup scope narrows to: home dir removal + the now-dead `(hermes) NOPASSWD: ALL` sudoers line |
| 15-30 min estimated downtime | ~2.9G of state, live prod bot, credential consolidation, blue/green validation — 15-30 min was unrealistic | Re-estimated at 8-12h total elapsed work (mostly [HUMAN] root steps done interactively); actual bot downtime during cutover itself targeted at under 15 minutes (relaxed from an initial <5min estimate per validation interview, once Phase 6's `state.db`/`kanban.db` re-copy step was added by red-team) |

### [HUMAN] vs [AGENT] tagging

Every implementation step below is tagged:
- **[AGENT]** — safe to run non-interactively as `ubuntu` (covered by the existing `sudo -u hermes NOPASSWD: ALL` or the scoped `systemctl hermes*` grant).
- **[HUMAN]** — needs an interactive terminal (root password for `apt`/`userdel`/new systemd unit files/`visudo`, or a judgment call). `/ck:cook --parallel` must not attempt `[HUMAN]` steps unattended.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Pre-Migration Backup and Baseline](./phase-01-pre-migration-backup-and-baseline.md) | Complete |
| 2 | [Provision Hermes Under Ubuntu (Fresh Install)](./phase-02-provision-hermes-under-ubuntu-fresh-install.md) | Complete |
| 3 | [Restore State and Rewrite Paths](./phase-03-restore-state-and-rewrite-paths.md) | Complete |
| 4 | [Consolidate CCS/Claude Identity](./phase-04-consolidate-ccs-claude-identity.md) | Complete |
| 5 | [Workspace and Project Access Reconciliation](./phase-05-workspace-and-project-access-reconciliation.md) | Complete |
| 6 | [Blue/Green Systemd Cutover](./phase-06-blue-green-systemd-cutover.md) | Complete |
| 7 | [Post-Cutover Verification and Rollback Window](./phase-07-post-cutover-verification-and-rollback-window.md) | Verification complete; 48h hold until 2026-07-08T07:50Z |
| 8 | [Cleanup and Hermes User Removal](./phase-08-cleanup-and-hermes-user-removal.md) | Blocked until hold period ends |

## Dependencies

None blocking. Coexists with `260703-1738-fix-urgent-hermes-delegation-issues` (in-progress) and
`260704-2106-bootstrap-script-delegation-provisioning-scripts` (in-progress) — see coordination
caution in Overview. No shared file paths until Phase 8's `userdel -r hermes`, which those two
plans' remaining work should complete before (or accept as moot after).

## Rollback Window

Phases 1-6 read from `/home/hermes` but do not delete or modify anything under it — **corrected
by red-team review**: an earlier draft of Phase 4 deleted the `ccs-hermes` CCS instance
immediately after moving it, which would have made a mid-window rollback restart `hermes.service`
with a broken CCS identity. That deletion is now deferred to Phase 8, after the rollback window
actually closes, so the "non-destructive through Phase 6" claim holds as currently written.
Phase 7 stops (but does not delete) the old `hermes`-user services and keeps `/home/hermes`
intact for **at least 48 hours** before Phase 8's `userdel -r hermes` runs. Rollback = re-enable
+ start the old `hermes.service`/`hermes-dashboard.service` from Phase 1's separate `.bak` unit
files, stop the new ubuntu ones. See Phase 7 for the exact commands.

## Red Team Review

### Session — 2026-07-06
**Findings:** 21 raw findings from 4 hostile reviewers (Security Adversary, Failure Mode Analyst,
Assumption Destroyer, Scope & Complexity Critic — Full verification tier, 8 phases), deduplicated
to 15 (21 accepted, applied — several raw findings were corroborating duplicates of the same
underlying issue, most notably the `ReadWritePaths`/workspace gap independently found by 3 of 4
reviewers).
**Severity breakdown:** 6 Critical, 5 High, 4 Medium
**Disposition:** All 15 accepted and applied (user selected "apply all accepted findings" — no
finding lacked codebase/live-host evidence, no reviewer disagreement on any finding's merit).

| # | Finding | Severity | Disposition | Applied To |
|---|---------|----------|-------------|------------|
| 1 | `ReadWritePaths=` never included `/home/ubuntu/workspace` — reproduces a live, already-documented `EROFS` bug (found independently by Security Adversary, Failure Mode Analyst, Assumption Destroyer) | Critical | Accept | Phase 5, Phase 6, Phase 7 |
| 2 | Phase 2 installer command missing `--skip-setup` — risks a second live gateway polling the production Telegram token before cutover | Critical | Accept | Phase 2 |
| 3 | `state.db`/`kanban.db` (WAL-mode) never re-copied between Phase 3's snapshot and Phase 6 cutover — data loss | Critical | Accept | Phase 6 (new step 5a) |
| 4 | Repo's canonical `templates/systemd/*.service` (+ `/opt` clone) never updated — a precedented future redeploy would silently revert the migration | Critical | Accept | Phase 6 (Key Insights + new template-update step) |
| 5 | Phase 7's "non-destructive to /home/hermes" claim was false — Phase 4 deleted `ccs-hermes` before the 48h window closed | Critical | Accept | Phase 4 (step 6 rewritten), Phase 8 (deletion moved here), plan.md Rollback Window |
| 6 | Phase 7 rollback referenced a backup artifact Phase 1 never produced; git-template fallback diverges from live production | Critical | Accept | Phase 1 (separate `.bak` files), Phase 7 (rollback procedure) |
| 7 | Phase 3 restore list missing live files incl. a credential (`nous_auth.json`), dedup index, cron/sandboxes/snapshot/pairing dirs | High | Accept | Phase 3 |
| 8 | Default (non-CCS, bare-harness) delegation identity via `~/.claude/.credentials.json` never reconciled | High | Accept | Phase 3 (new step 8) |
| 9 | 7 scripts elsewhere in this repo hardcode `/home/hermes`, silently break post-migration, plan only said "decide later" | High | Accept | Phase 8 (new step 9) |
| 10 | Stage A's dry-run bypassed systemd sandboxing entirely — couldn't catch the `ReadWritePaths` bug class; `hermes doctor` can't either | High | Accept | Phase 6 (Stage A rewritten with `systemd-run`) |
| 11 | Phase 3's config-merge step required judgment but was tagged `[AGENT]`, violating the plan's own tagging rule | High | Accept | Phase 3 (step 2 retagged `[HUMAN]`) |
| 12 | Backup tarball briefly world-readable in `/tmp`; tarball also wasn't fully "full" (missing `.claude.json`/`.claudekit`/`.config`/`.local`) | Medium | Accept | Phase 1 |
| 13 | Symlink retarget commits a shared resource before the new unit is confirmed healthy, widening partial-failure blast radius | Medium | Accept (mitigated via strengthened Stage A rather than a new canary-unit step — see Phase 6 Risk Assessment for rationale) | Phase 6 |
| 14 | Phase 8's destructive gate relied on planning-time blast-radius/tarball claims without a live re-check | Medium | Accept | Phase 8 (step 1 hardened) |
| 15 | Phase 4's YAML edit validated syntax only, not structure — could silently misnest `ccs-hermes` under the wrong parent | Medium | Accept | Phase 4 (step 3) |

Two additional lower-priority observations were folded into the fixes above rather than tracked
as separate findings: an explicit containment note (ubuntu already holds unrestricted
sudo/docker/lxd, unlike hermes — folded into Phase 6 Security Considerations) and a concrete
pre-flight checkpoint for the "coordinate timing with parallel plans" caution (folded into
Phase 3's new step 0).

### Whole-Plan Consistency Sweep
- Files reread: `plan.md`, `phase-01` through `phase-08` (all 8 phase files), in full, after applying all edits above.
- Decision deltas checked: 15 (the accepted findings) plus 2 folded-in observations.
- Reconciled stale references:
  - Phase 4's Success Criteria, Risk Assessment, and Security Considerations all updated to match the deferred-deletion decision (no longer claim `ccs-hermes` is removed from hermes's side during Phase 4).
  - Phase 7's Overview and rollback procedure updated to stop claiming unconditional non-destructiveness and instead point at a live verification command.
  - Phase 8's step numbering re-sequenced end-to-end after inserting the deferred-deletion step and the gate-hardening changes (was a duplicate "step 4" before the fix).
  - Phase 5's success criteria and risk assessment rewritten to stop claiming success from an ownership-only check, now explicitly deferring the real assertion to Phase 6/7's sandboxed write test.
  - Phase 1's Security Considerations updated to stop referencing a now-redundant separate `chmod 600` step (folded into step 2 directly).
  - `plan.md`'s own Rollback Window section updated to match Phase 4/7/8's corrected sequencing.
  - Sweep caught one genuine miss on the first pass: Phase 1's "Related Code Files" section still
    listed the old concatenated `hermes-old-systemd-units-260706.txt` filename after step 4 had
    already been rewritten to produce two separate `.bak` files — fixed to match.
- Verified via `grep -rn "hermes-old-systemd-units-260706"` and `grep -rn "remove hermes's copy to avoid"` across `plan.md` + all `phase-*.md` after fixes: zero hits.
- Unresolved contradictions: **0**.

## Validation Log

### Session 1 — 2026-07-06
**Trigger:** User explicitly requested `--validate` alongside `--red-team` for this plan.
**Questions asked:** 4

Per the validate workflow's Step 2.5 guard, the `## Red Team Review` section above already
contains verification evidence (each of the 4 reviewers carried a persona-specific verification
role — Fact Checker, Flow Tracer, Scope Auditor, Contract Verifier — backed by live-host
command output), so the verification pass was skipped and the interview went straight to
remaining genuine decision points the red-team fixes left as open judgment calls rather than
resolved specifics.

#### Questions & Answers

1. **[Assumptions]** Phase 3 flags that the default (non-CCS, bare-harness) delegation identity
   via `~/.claude/.credentials.json` was never reconciled between hermes and ubuntu — hermes has
   its own distinct bot credential file there. How should this be resolved?
   - Options: Use ubuntu's own `~/.claude/` (Recommended) | Create a dedicated bot identity | Check if it's already moot first
   - **Answer:** Use ubuntu's own `~/.claude/` (Recommended)
   - **Rationale:** Simplest path; only `ccs-hermes` (already consolidated with its own identity in Phase 4) needs a dedicated credential. Avoids extra `CLAUDE_CONFIG_DIR` isolation work for a fallback code path.

2. **[Risk]** Phase 6's cutover still commits the shared `/usr/local/bin/hermes` symlink and
   overwrites live unit files before the new service is confirmed running. Accept relying on
   Stage A's strengthened sandboxed validation instead of adding a canary step?
   - Options: Accept as documented (Recommended) | Add a canary step anyway
   - **Answer:** Accept as documented (Recommended)
   - **Rationale:** Stage A's `systemd-run`-based validation (added by red-team) already exercises the real sandboxing properties that caused the realistic failure modes; a canary/throwaway-unit step would add real complexity for marginal incremental coverage.

3. **[Scope]** Phase 8 states 7 scripts elsewhere in this repo hardcode `/home/hermes` and will
   silently misbehave post-migration. How much should this plan do about it?
   - Options: Add loud guards only (Recommended) | Fully rewrite all 7 scripts now | Documented footnote only, no code change
   - **Answer:** Add loud guards only (Recommended)
   - **Rationale:** Cheap (~7 small mechanical edits), prevents silent failure/corruption on a future re-run, without expanding this plan's scope into rewriting delegation-provisioning scripts that are a different plan's concern (`260704-2106`).

4. **[Risk]** Phase 6's original <5min downtime target didn't account for the newly-added
   `state.db`/`kanban.db` re-copy step (5a). How should the target be handled?
   - Options: Keep <5min as a soft target (Recommended) | Relax the target explicitly | Make <5min a hard gate
   - **Answer:** Relax the target explicitly
   - **Custom input:** none (selected option, not "Other")
   - **Rationale:** User chose not to keep a number that might not hold, and explicitly did not want a hard gate that could pressure skipping or rushing the data-loss-prevention copy step. Target changed to <15min throughout the plan.

#### Confirmed Decisions
- Default delegation identity: ubuntu's own `~/.claude/` — no dedicated bot credential for bare-harness delegation.
- Cutover ordering residual risk: accepted as documented, no canary step added.
- Stale-script handling: loud `id hermes` guards added to all 7 scripts; full rewrite explicitly deferred to a future plan.
- Downtime target: relaxed to <15min (was <5min), applied consistently across `plan.md` and Phase 6.

#### Action Items
- [x] Phase 3 step 8 rewritten from an open 3-option decision to a one-line confirmation matching the chosen identity approach.
- [x] Phase 8 step 9 rewritten from an either/or suggestion to a definitive guard-snippet instruction.
- [x] Phase 6 (frontmatter `effort`, Success Criteria) and `plan.md`'s draft-comparison table downtime figures updated from <5min to <15min.

#### Impact on Phases
- Phase 3: step 8 and its Success Criteria bullet simplified (decision made, not deferred).
- Phase 6: `effort` frontmatter and downtime Success Criteria bullet updated; no other phase content needed changes since the canary-step question was answered "keep as documented."
- Phase 8: step 9 and its Success Criteria bullet firmed up into a concrete, committed action rather than a footnote.

### Whole-Plan Consistency Sweep
- Files reread: `plan.md`, `phase-01` through `phase-08` (all 8 phase files), in full, after applying all 4 validation decisions.
- Decision deltas checked: 4 (the validation answers above).
- Reconciled stale references: verified via `grep -rn "5 min\|5min\|<5" plan.md phase-*.md` — the only remaining hits are the corrected `<15min` figures and the explicit "relaxed from an initial <5min estimate" history notes, which are intentional (documenting the change, not a stale leftover). No other phase references the old `<5min` figure or the old open-ended delegation-identity/script-scope framing.
- Unresolved contradictions: **0**.

**Verification Results:** Skipped per Step 2.5 guard (red-team's embedded verification evidence already covers this plan) — Claims checked: N/A, Verified: N/A, Failed: 0, Tier: N/A (inherited Full-tier evidence from red-team session).

**Recommendation:** Proceed. All red-team findings applied and swept; all validation decisions applied and swept. No unresolved contradictions in either gate.
