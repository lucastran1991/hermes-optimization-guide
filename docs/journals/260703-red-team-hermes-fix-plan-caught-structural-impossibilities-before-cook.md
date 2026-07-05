# Red-Team Review Exposed 3 Unfixable Structural Gaps in Hermes Delegation Plan Before Cook

**Date**: 2026-07-03 17:38–19:10 (approx.)  
**Severity**: Critical  
**Component**: hermes delegation, service deployment, ClaudeKit provisioning  
**Status**: Plan revised, red-team findings accepted (21/23), not yet implemented  

## What Happened

A 6-phase parallel plan to fix the Hermes P0 crash (`sched_setscheduler` Bad system call) and provision CCS/ClaudeKit delegation was created, then independently reviewed by 4 red-team reviewers with live-host read access. During adjudication of their 23 findings, 3 structural impossibilities were uncovered that would have prevented the plan from achieving its stated goal *even with perfect execution*:

1. **Dual Git Clone Gap**: A stale `/opt/hermes-optimization-guide` clone (2 days behind) exists and is referenced in the bootstrap scripts as the canonical source. The planned Phase 1 deploy-drift-prevention tooling, if pointed at this discoverable path, would have redeployed the *pre-fix* systemd template and reintroduced the exact crash being fixed.

2. **Wrong NPM Package**: Phase 4 specified installing `claudekit` (provides `claudekit` binary, not the `ck` CLI). Should be `claudekit-cli` (by mrgoonie). This would have silently left the ck binary missing and made the entire ClaudeKit provisioning a no-op.

3. **Missing Skill Symlink**: The `coding-agent-delegate` skill was never symlinked into the live hermes skill catalog. Phase 6's completion gate ("trigger a real bot task") was impossible regardless of other phase success.

## The Brutal Truth

This is the failure mode of planning-without-live-verification: the original plan looked sound on paper, but would have shipped a "fixed" system that still crashed under load, left the target binary uninstalled, and had no way to actually invoke delegation. A code-only review (without live-host spot-checks) would have missed all three. The review process caught this *before* any mutations, but the original author (planner agent) had no live-host visibility — a hard constraint that cascaded downstream.

## Technical Details

**Dual Clone**: `/opt/hermes-optimization-guide` is referenced in `scripts/vps-bootstrap-oci.sh` as `GUIDE_DIR`. The workspace clone is 2 days ahead. Phase 1's deploy script would have defaulted to the discoverable path without an explicit override.

**Package Name**: Phase 4 sourced `claudekit` from npm (carlrannaberg). Live query: `npm view claudekit` has binary scope `bin: claudekit`, not `bin: ck`. The actual `ck` binary is `npm view claudekit-cli`, maintainer mrgoonie.

**Missing Symlink**: `sudo -u hermes ls ~/.hermes/skills/` (i.e. `/home/hermes/.hermes/skills/`) lists 29 skills; `coding-agent-delegate` is not among them, and a recursive grep for it across that tree returns zero hits. The repo's skill exists but was never deployed to the live skill catalog.

**Live Config Mismatch**: The running hermes service reads `~/.hermes/config.yaml` (has zero `delegation:` block). The repo's `templates/config/production.yaml` is aspirational, not what's actually deployed.

## Root Cause Analysis

Planning without **live-host spot-checks** during design. The planner had access to repo templates and docs but no read-only host verification to catch:
- Stale clones in "official" paths shadowing the actual workspace.
- Package names that differ from what's actually needed.
- Symlinks that were never created despite code existing.
- Divergence between aspirational templates and running configs.

## Lessons Learned

1. **Red-team + live-host access is non-negotiable for deployment plans**: textual review catches style/security, but structural gaps (wrong packages, missing files, shadowing paths) require walking the actual host.

2. **Bootstrap paths matter**: when a script references `/opt/...` as canonical but the workspace is at `~/workspace/...`, the plan must explicitly reconcile both or accept the risk of deploying from the stale copy.

3. **Always verify post-install state, not just install commands**: `npm install claudekit` succeeds; the missing `ck` binary is only caught by `which ck` or `ls ~/.local/bin/ck`.

## Next Steps

1. **Reconcile dual clones**: Phase 1 now sources templates from the canonical `/opt/hermes-optimization-guide` clone (via `GUIDE_DIR`) with a stale-canonical guard that refuses to deploy if `/opt` is behind `origin/main`; a `[HUMAN]` step reconciles `/opt` via `git pull --ff-only`.
2. **Fix package name**: Phase 4 now specifies `claudekit-cli` (mrgoonie) instead of `claudekit`.
3. **Symlink deployment**: Phase 6 (not Phase 5) now includes explicit symlinking of `coding-agent-delegate` into the live skill catalog, sourced from the reconciled `/opt` clone — this is why Phase 6 gained Phase 1 as a new dependency.
4. **Live config sync**: Phase 6 (not Phase 5) now merges the `delegation:` block from the repo template into the running `~/.hermes/config.yaml`, since the live service reads that file, not the repo template.
5. **Revised plan**: `plans/260703-1738-fix-urgent-hermes-delegation-issues/` updated with 21 accepted findings (2 rejected with logged rationale); effort now 4h25m (was 3h25m); user chose to run `/ck:plan validate` next, with 3 default trade-off decisions (documented in the plan) still open for override before cook.

**Plan path**: `/home/ubuntu/workspace/hermes-optimization-guide/plans/260703-1738-fix-urgent-hermes-delegation-issues/`  
**Debug report**: `/home/ubuntu/workspace/hermes-optimization-guide/plans/reports/ck-debug-260703-1725-hermes-seccomp-claude-sigsys-stale-unit-report.md`  
**Red-team findings**: adjudicated within plan document; 4 independent reviewers each backed findings with live-host evidence; the 4 most consequential claims (dual clone, wrong package, missing symlink, missing config block) were independently re-verified live by the main session before acceptance.
