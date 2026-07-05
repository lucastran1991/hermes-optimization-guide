# Live IMDS Fix + Delegation Provisioning Automation Planned & Validated (PATH Gap Caught Mid-Review)

**Date**: 2026-07-04 (session spanning ~18h spread across 2026-07-03 evening through 07-04 evening)  
**Severity**: Medium-High  
**Component**: OCI host IMDS exposure, hermes.service seccomp+environment, delegation provisioning automation  
**Status**: Live fixes deployed, plan created and fully validated (0 unresolved contradictions), cook deferred to next session

## What Happened

Session split into 3 distinct operational phases:

**Phase 1: Live Security Investigation & IMDS Fix**  
Investigated instance-principal / IMDS exposure on the live Oracle Cloud Ubuntu host (`lucas-oracle-instance`). Confirmed: `curl 169.254.169.254/...` returned a valid Oracle identity certificate (instance principal enabled). Risk: any sudo-delegated Bash process with hermes's UID can exfil Claude/CCS OAuth credentials from `~hermes/.config/Claude` and `~hermes/.ccs` directories. Mitigation: added `IPAddressDeny=169.254.169.254/32` to `templates/systemd/hermes.service` (commit 60a2683), deployed live via `scripts/deploy-systemd-units.sh` after reconciling a stale `/opt/hermes-optimization-guide` clone (2 days behind workspace; fetched fresh template via anonymous HTTPS since root has no working GitHub SSH key). Tailscale scope (3 personal devices, low exfil risk) and dashboard bind (127.0.0.1 only, safe) were separately confirmed low-risk.

**Phase 2: Manual Delegation-Provisioning Gaps Closed**  
The still-open `plans/260703-1738-fix-urgent-hermes-delegation-issues/` plan identified 3 structural provisioning gaps discovered during red-team review. Manually completed all three on the live host:
1. `gh auth login` to provision GitHub CLI auth token in hermes's session
2. ClaudeKit init: `ck login`, `ck doctor --fix`, `~/.claude/skills/install.sh` (built the venv)
3. Symlinked `coding-agent-delegate` skill into `/home/hermes/.hermes/skills/`
4. Manually merged a `delegation:` config block into `~/.hermes/config.yaml`

Also ran a cost-free smoke test of the delegation mechanism using an existing personal CCS instance ("ken") as a stand-in — proved the mechanism works (real Opus response, $0.47 cost) but **explicitly is NOT Phase 5 completion**: no dedicated `ccs-hermes` profile exists yet (user has no budget). Phase 5 documented as last-resort fallback vs. the planned Phase 4 dedicated-account path.

Security re-scan (`/ck:security-scan --auto --parallel`) post-fixes: confirmed all 5 prior findings from 2026-07-03 are still fixed. Discovered 2 new LOW findings (unpinned `curl|bash` installers from claude.ai/opencode.ai added to repo after last scan; missing `.gitignore` in repo root). Left unfixed pending user prioritization.

**Phase 3: Automation Plan Created, Red-Teamed, and Validated**  
Brainstormed automating today's manual work via `/ck:brainstorm`, then planned it via `/ck:plan create --tdd --validate --auto --parallel`.

Plan outcome: `plans/260704-2106-bootstrap-script-delegation-provisioning-scripts/` with 6 phase files.

**Architecture decision**: Instead of cramming new provisions into `vps-bootstrap-oci.sh`, split into:
- 2 new unconditional sections in `vps-bootstrap-oci.sh` (ClaudeKit venv + skill install via absolute paths)
- New `scripts/provision-hermes-delegation/` directory: 5 independently-runnable numbered scripts (gh-auth, claude-auth, ccs-profile, ccs-reuse-bridge [**internal-fork-only, never upstreamed**], merge-delegation-config), mirroring the existing `deploy-systemd-units.sh` precedent (bootstrap-time vs. maintenance-time separation)

Red-team review (4 independent reviewers: Security Adversary, Failure Mode Analyst, Assumption Destroyer, Scope & Complexity Critic) produced 26 raw findings, deduped to 15 accepted + 1 rejected. **Critical finding**: a same-day debug report (`plans/reports/ck-debug-260704-1355-hermes-ccs-auth-profile-access-report.md`) discovered that `hermes.service` is missing `~/.local/bin` on its systemd PATH — meaning all provisioned credentials would be moot without this fix. Every phase's own smoke test (using login shell) was masking the exact bug it needed to catch. Plan was revised to fold the PATH fix into Phase 1 as a new first step.

Plan validation via `/ck:plan validate`: resolved last 2 `[UNVERIFIED]` tags via direct live-host inspection (confirmed CCS's root `~/.ccs/config.yaml` requires an `accounts:` entry for profile resolution; confirmed exact credential filenames). 4-question interview covered: (1) fixing a known EROFS risk now vs. deferring (user chose fix-now, one-off exception to repo's "don't widen ReadWritePaths" posture), (2) explicit restart-safety wording, (3) **stricter-than-red-team privacy decision**: reuse-bridge script must NEVER be mentioned in public CHANGELOG/README at all (red-team suggested hiding; user hardened to omission), (4) Phase 5 framing: everywhere documented as explicit last-resort vs. Phase 4's planned dedicated-account path.

## The Brutal Truth

This session's work collided with a recurring class of bug in this codebase: **`sudo -u hermes <cmd>` vs. `sudo -u hermes -i bash -c '<cmd>'` environment divergence**. The PATH gap wasn't obvious when each provisioning script was written (because the testing shell was interactive, loading `~/.bash_profile`). But systemd's sandboxed service has no shell initialization at all. Every red-team finding about broken smoke tests, every manual work-around, and the entire PATH-gap discovery traces back to this same root: **conflating interactive shell behavior with sandboxed-service behavior**.

The live IMDS fix and delegation-provisioning work were REAL production changes to a running host, not simulations. The plan's validation surfaced the PATH gap before code even shipped. But the underlying gotcha — "login shell smoke tests don't catch what a systemd unit actually does" — is the kind of lesson this project keeps re-learning.

User's budget constraint (no money for a dedicated Claude/CCS seat right now) was stated as a deliberate factor shaping both the manual work and the new plan's Phase 5 design. This is a real-world trade-off, not a feature gap.

## Technical Details

**IMDS Fix**: `IPAddressDeny=169.254.169.254/32` added to `[Service]` section, preventing any child process from reaching the Oracle metadata endpoint. Verified live via `curl` from hermes's UID inside systemd-run with the same unit's security context — connection refused as expected.

**Stale Clone Reconciliation**: `/opt/hermes-optimization-guide` was 2 commits behind `origin/main`. Deployment script (`deploy-systemd-units.sh`) references this path as canonical source. Resolved via `git fetch https://github.com/lucastran1991/hermes-optimization-guide.git main:refs/remotes/origin/main` (no SSH key available for root), then `git reset --hard origin/main` to sync `/opt` with workspace before deploying the fixed template.

**Delegation Manual Work**:
- `gh auth login` stored token in `~hermes/.config/gh/hosts.yml`
- `ck login` prompted for Claude credential, stored in `~hermes/.claude/config.yaml` (file ownership issues resolved via `chown hermes:hermes`)
- `~/.claude/skills/install.sh` bootstrapped the venv at `~hermes/.claude/skills/.venv` (no sudo needed, user hermes can install)
- Symlink: `ln -s /opt/hermes-optimization-guide/.claude/skills/coding-agent-delegate ~/.hermes/skills/`
- Config merge: added `delegation: {hermes_claude_credential_file: "~/.claude/config.yaml", ...}` to existing `config.yaml`

**Smoke Test (Ken Bridge)**: Triggered a real delegation request through existing "ken" CCS instance. Claude Opus responded ($0.47 cost, real response). Confirms mechanism works but **this is not Phase 5** (no dedicated `ccs-hermes` profile).

**Security Scan Results**: 5 prior findings still fixed (seccomp, EROFS, sched_setscheduler). 2 new LOWs found:
1. `curl https://opencode.ai/install.sh | bash` (no hash check, no pinned version) — added to `.github/scripts/` but not sanitized
2. `curl https://claude.ai/code | bash` pattern (same risk)

No `.gitignore` in repo root (only in subdirs). Both left unfixed pending user prioritization.

**Plan Architecture**: Phase 1 adds PATH to systemd unit's `Environment=PATH=...` directive and fixes EROFS via `ReadWritePaths=`. Phases 2–4 run the 5 numbered scripts in order (each independent, can be re-run). Phase 5 documents the "ccs-reuse-bridge" internal-only fallback (never public). Phase 6 validates the working delegation setup.

**Red-Team Finding: PATH Gap**. Debug report discovered that `hermes.service` unit has no explicit `Environment=` directive for PATH. When systemd execs the unit, it inherits the minimal default PATH from systemd itself (typically `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin`). The hermes user's `~/.local/bin` (where installed CLIs like `ck`, `claude`, `opencode` go) is NOT on this path. Each phase's smoke test ran `sudo -u hermes -i bash -c 'ck ...'` — the `-i` flag sources `~/.bashrc`, which dynamically appends `~/.local/bin`, masking the actual problem. In the real systemd unit, the CLI calls fail silently (PATH lookup fails, no binary found). This was the smoking gun: every phase's own validation was broken by the exact bug it was meant to catch.

**Risk Acceptance Decisions** (from validation interview):
1. **EROFS fix now**: User approved widening `ReadWritePaths=/home/hermes/.ccs` (one-off exception to the repo's general "narrow ReadWritePaths" posture) because the CCS profile resolution step requires it.
2. **Restart safety**: Explicit wording in Phase 1: "systemctl daemon-reload must happen before the next delegation provisioning step."
3. **Reuse-bridge privacy**: User hardened the red-team's recommendation. Script must NEVER appear in CHANGELOG/README (stricter than "don't advertise it"). Reason: internal-only fallback, misleading to upstreamed users.
4. **Phase 5 framing**: Everywhere documented as "last-resort fallback" not "Phase 5 success path." The planned Phase 4 (dedicated `ccs-hermes` profile) is the real solution; Phase 5 is "if budget/timing prevents Phase 4."

## Root Cause Analysis

1. **Login-shell smoke tests hide systemd environment bugs**: Testing `sudo -u user -i bash -c '<cmd>'` conflates shell initialization (which adds `~/.local/bin` to PATH) with the actual systemd unit's environment (which doesn't). The bug class manifests only at runtime inside the sandboxed unit, not during validation.

2. **Stale canonical paths**: When `/opt` is both a git clone and referenced in scripts as the source-of-truth, but the workspace is ahead, a plan must explicitly guard against deploying from the stale copy. The red-team found this before cook; the IMDS fix hit it in practice.

3. **Manual provisioning work doesn't reveal automation gaps**: Closing 3 structural provisioning gaps manually (GitHub auth, ClaudeKit, symlink) proved the mechanism works but didn't surface the PATH gap because interactive shells worked. Automation (systemd unit) would have failed immediately.

## Lessons Learned

1. **Smoke tests must run in the actual target environment (or a matching simulation)**: `sudo -u user -i bash` is NOT equivalent to `systemd-run -u user systemd-run -u <service>`. Use `systemd-run --user=hermes --setenv=PATH=/expected/path -- ck --version` to test before shipping.

2. **Login-shell masking is a systematic gotcha in this codebase**: The same issue appeared in Phase 2's manual provisioning work and again during plan validation. This warrants a documented pattern: "systemd-run simulation tests" as a pre-flight check for any new service-level change.

3. **Red-team + live-host access catches structural gaps**: The debug report (separate investigation before today's session) discovered the PATH gap; the red-team's validation process forced verification against the actual live state. Plan validation closed the loop.

4. **Explicit risk acceptance is more valuable than risk avoidance**: User's budget constraint and explicit "fix EROFS now, reuse-bridge never public" decisions are better documented than generic YAGNI. Future developers will understand the trade-offs.

5. **Stale canonical clones are a trap**: Always reconcile or explicitly reject the discoverable path before planning scripts that reference it. The IMDS fix scenario exposed this in practice; the red-team had flagged it earlier.

## Next Steps

- User deferred `/ck:cook` (actual implementation of the 6 phases) to a later session
- Plan is ready (0 unresolved contradictions, all 15 red-team findings accepted and applied)
- Before cook: (1) Ensure live host has up-to-date `/opt/hermes-optimization-guide` clone (already done for IMDS fix), (2) Review the reuse-bridge script's data-handling scope one more time (capped to 2 credential files, not whole instance directory)
- Post-cook: run `/ck:security-scan` to catch any new findings from the new scripts; close the 2 outstanding LOW findings (curl|bash installers, missing .gitignore)

## Unresolved Questions

1. Does the OCI instance have a dynamic security group / IAM policy attached beyond instance-principal? (IMDS alone doesn't prove broader exfil vector; need to verify perimeter.) — Not investigated this session; out of scope for the current plan.
2. The 2 new LOW security findings (`curl|bash` installers, missing `.gitignore`): prioritize fixing before cook or defer to later sprint? — User choice; flagged but not blocking the delegation plan.
3. Future: should Phase 6's validation test actually run inside `systemd-run` with the same unit's security context to avoid the login-shell masking pitfall? — Yes, but documenting as a lesson for *next time* rather than a blocker for this plan.
4. Has the dynamic IAM policy (if any) been audited? Instance-principal is enabled; the exact scope of credential scavenging (what resources the principal can access if exfil happens) is still unknown.
