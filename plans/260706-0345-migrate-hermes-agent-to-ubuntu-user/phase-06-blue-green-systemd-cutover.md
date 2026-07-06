---
phase: 6
title: "Blue/Green Systemd Cutover"
status: complete
priority: P1
effort: "2h (includes validation time; actual bot downtime target <15min, relaxed from an initial <5min estimate per validation interview once the state.db/kanban.db re-copy step was added)"
dependencies: [3, 4, 5]
---

# Phase 6: Blue/Green Systemd Cutover

## Overview

Bring up the ubuntu-hosted Hermes instance ("green") and validate everything **except** the
live Telegram connection, then do a short stop-old/start-new cutover to switch the real bot
traffic over. This phase implements the "blue/green cutover" decision with one necessary
adjustment surfaced by research: Telegram bots are very likely single-poller (Bot API
`getUpdates` returns `409 Conflict` to a second concurrent poller for the same token), so
literal simultaneous dual-live serving isn't safe for this specific integration. Everything
that *can* be validated concurrently is validated concurrently; only the Telegram-facing
piece is a genuine stop/start swap, kept as short as possible.

## Key Insights

- `ExecStart=/usr/local/bin/hermes gateway run` (main) and
  `ExecStart=/usr/local/bin/hermes dashboard --host 127.0.0.1 --port 8765 --no-open --skip-build` (dashboard).
- `/usr/local/bin/hermes` is a symlink to `/home/hermes/.hermes/hermes-agent/venv/bin/hermes` —
  this symlink is shared systemwide (root-owned path), so it can only point at one user's venv
  at a time. This is the actual reason true dual-live isn't just a Telegram-polling problem —
  the *binary path itself* is a single shared resource today.
- The `(root) NOPASSWD: systemctl {start,stop,restart,status} hermes*` sudoers grant matches
  unit **names**, not the `User=` directive inside them — it keeps working unchanged after the
  units are edited to run as `ubuntu`. No sudoers change needed for this grant.
- `ReadWritePaths=/home/hermes/.hermes /home/hermes/.ccs /tmp` (systemd sandboxing directive) —
  must be updated to the ubuntu paths **and must add `/home/ubuntu/workspace`** (red-team
  finding, corroborated independently by 3 of 4 reviewers): the current unit never granted
  write access to the workspace dir at all — `ProtectHome`-style sandboxing makes the rest of
  `/home` read-only regardless of Unix file ownership. This is a live, already-reproduced bug
  (`plans/260705-1752-ccs-delegation-timeout-progress-tracking-fix/phase-03-live-host-verification.md:544`,
  `Read-only file system` on writes into `/home/hermes/workspace/nfi`). A straight path-swap
  without adding workspace would reproduce the identical bug under `/home/ubuntu/workspace`,
  defeating this migration's own stated goal (see Phase 5's Key Insights for detail).
- This repo's own canonical unit templates (`templates/systemd/hermes.service`,
  `templates/systemd/hermes-dashboard.service`, plus their clone at
  `/opt/hermes-optimization-guide/templates/systemd/`) still hardcode `User=hermes`,
  `WorkingDirectory=/home/hermes`, `ReadWritePaths=/home/hermes/...` (red-team finding). A
  precedented redeploy script, `scripts/deploy-systemd-units.sh`, exists specifically to sync
  these templates onto `/etc/systemd/system/` — it was used for exactly this purpose 3 days ago
  in plan `260703-1738` Phase 2. Left unfixed, any future run of that script silently reverts
  this entire migration back to `User=hermes`, which will then fail outright once Phase 8
  deletes that user. This phase updates the templates in the same pass as the live units.

## Related Code Files

- Modify (host, root-owned): `/etc/systemd/system/hermes.service`, `/etc/systemd/system/hermes-dashboard.service`
- Modify (host, root-owned): `/usr/local/bin/hermes` (symlink retarget)
- Modify (repo): `templates/systemd/hermes.service`, `templates/systemd/hermes-dashboard.service`
- Modify (host): `/opt/hermes-optimization-guide/templates/systemd/{hermes.service,hermes-dashboard.service}` (canonical clone, kept in sync per this repo's own convention)

## Implementation Steps

### Stage A — Validate the green instance without touching the live bot

1. **[AGENT]** Dry-run the gateway as ubuntu, with the Telegram platform temporarily disabled in
   a scratch copy of config (do not edit the real restored config for this — copy it). **Run it
   under `systemd-run` with the exact `ReadWritePaths=`/`ProtectHome=` the real unit will use,
   not a bare foreground process** (red-team finding: a bare process bypasses sandboxing
   entirely and cannot catch the exact class of bug in the Key Insights above — Stage A must
   validate the sandbox, not just the application code):
   ```bash
   cp /home/ubuntu/.hermes/config.yaml /tmp/hermes-config-dryrun.yaml
   python3 -c "
   import yaml
   c = yaml.safe_load(open('/tmp/hermes-config-dryrun.yaml'))
   c['platforms']['telegram']['enabled'] = False
   yaml.safe_dump(c, open('/tmp/hermes-config-dryrun.yaml', 'w'))
   "
   sudo systemd-run --uid=ubuntu --gid=ubuntu \
     -p ProtectHome=read-only \
     -p ReadWritePaths="/home/ubuntu/.hermes /home/ubuntu/.ccs /home/ubuntu/workspace /tmp" \
     -p Environment="HOME=/home/ubuntu" \
     -p Environment="HERMES_CONFIG=/tmp/hermes-config-dryrun.yaml" \
     --unit=hermes-dryrun-test --pipe \
     timeout 20 /home/ubuntu/.local/bin/hermes gateway run
   ```
   Confirm it boots cleanly (no crash/traceback, no `Read-only file system` errors) with
   Telegram disabled. Also run the real write test from Phase 5 step 4 here if not already done
   — Stage A is the right place to catch a `ReadWritePaths` gap, before any live downtime starts:
   ```bash
   sudo systemd-run --uid=ubuntu --gid=ubuntu -p ProtectHome=read-only \
     -p ReadWritePaths="/home/ubuntu/.hermes /home/ubuntu/.ccs /home/ubuntu/workspace /tmp" \
     --pipe --wait bash -c 'touch /home/ubuntu/workspace/nfi/.hermes-migration-write-test && rm /home/ubuntu/workspace/nfi/.hermes-migration-write-test && echo WRITE_OK'
   ```
   Must print `WRITE_OK`. Do not rely on `hermes doctor` for this check — it does not exercise
   systemd sandboxing and will pass even when this class of bug is present (red-team finding).

2. **[AGENT]** Validate CCS delegation and skill loading work from the ubuntu-hosted install (already smoke-tested in Phase 4, re-confirm in this exact context):
   ```bash
   HOME=/home/ubuntu ccs ccs-hermes -p "echo ok" --output-format json
   ```

3. **[AGENT]** Validate memory recall against the restored state (compare to Phase 1's baseline):
   ```bash
   cat /home/ubuntu/.hermes/memories/MEMORY.md   # spot-check content matches what was recalled in Phase 1's baseline check
   ```

If any of Stage A's checks fail, stop here — do not proceed to Stage B. Fix the issue (likely
back in Phase 3's config/state restore) and re-run Stage A before touching the live services.

### Stage B — Cutover (this is the actual downtime window)

4. **[HUMAN]** Prepare the new unit file content (based on the existing units, `User=`/`Group=`/`WorkingDirectory=`/`Environment=`/`ReadWritePaths=` updated to ubuntu). **`ReadWritePaths=` now includes `/home/ubuntu/workspace`** — the single most-corroborated red-team finding on this plan (independently flagged by 3 of 4 reviewers as a live, already-reproduced bug):
   ```ini
   # /etc/systemd/system/hermes.service (relevant lines to change)
   User=ubuntu
   Group=ubuntu
   WorkingDirectory=/home/ubuntu
   EnvironmentFile=-/home/ubuntu/.hermes/.env
   Environment=HOME=/home/ubuntu
   Environment=HERMES_CONFIG=/home/ubuntu/.hermes/config.yaml
   Environment=XDG_STATE_HOME=/home/ubuntu/.hermes/xdg_state
   ReadWritePaths=/home/ubuntu/.hermes /home/ubuntu/.ccs /home/ubuntu/workspace /tmp
   ```
   Apply the equivalent change to `hermes-dashboard.service`
   (`ReadWritePaths=/home/ubuntu/.hermes /home/ubuntu/workspace /tmp`).
   Everything else in both unit files (`Description=`, `After=`, `Restart=`, `RestartSec=`, `WantedBy=`) stays as-is.
   Save both edited files locally before installing (referenced by step 7).

   **[AGENT]** Also update this repo's canonical templates in the same pass, so a future
   `scripts/deploy-systemd-units.sh` run doesn't silently revert this migration (red-team
   finding — see Key Insights): apply the identical `User=`/`Group=`/`WorkingDirectory=`/
   `Environment=`/`ReadWritePaths=` changes to `templates/systemd/hermes.service` and
   `templates/systemd/hermes-dashboard.service` in this repo, and to their clone at
   `/opt/hermes-optimization-guide/templates/systemd/` (confirm that clone's remote/branch
   first — `cd /opt/hermes-optimization-guide && git status` — and pull or hand-apply
   consistently with whatever that clone's own update convention is; do not let the two
   diverge). Commit the repo-side template change separately from any host-only step.

5. **[HUMAN]** Announce/accept the downtime window is starting now (Telegram bot will be briefly unresponsive). Stop the old services:
   ```bash
   sudo systemctl stop hermes.service hermes-dashboard.service
   ```

5a. **[AGENT]** Re-copy the live, still-changing state files that Phase 3 only captured once,
   hours earlier (red-team finding: `state.db`/`kanban.db` are SQLite **WAL-mode**, confirmed
   live via `PRAGMA journal_mode`, and stayed open for writes by the still-running `hermes`
   service through Phases 4-6 Stage A — anything written in that gap is lost if not re-copied
   now, right after the old service has actually stopped and can no longer write):
   ```bash
   sudo cp -f /home/hermes/.hermes/state.db /home/ubuntu/.hermes/state.db
   sudo cp -f /home/hermes/.hermes/kanban.db /home/ubuntu/.hermes/kanban.db
   sudo cp -a /home/hermes/.hermes/kanban/. /home/ubuntu/.hermes/kanban/
   sudo cp -a /home/hermes/.hermes/sessions/. /home/ubuntu/.hermes/sessions/
   sudo cp -f /home/hermes/.hermes/channel_directory.json /home/ubuntu/.hermes/channel_directory.json
   sudo cp -f /home/hermes/.hermes/gateway_state.json /home/ubuntu/.hermes/gateway_state.json
   sudo cp -f /home/hermes/.hermes/state/rich_sent_index.json /home/ubuntu/.hermes/state/rich_sent_index.json
   sudo chown -R ubuntu:ubuntu /home/ubuntu/.hermes/state.db /home/ubuntu/.hermes/kanban.db /home/ubuntu/.hermes/kanban /home/ubuntu/.hermes/sessions /home/ubuntu/.hermes/channel_directory.json /home/ubuntu/.hermes/gateway_state.json /home/ubuntu/.hermes/state
   ```
   This step must run **after** step 5 (old service stopped, so the source files are quiescent)
   and **before** step 8 (new service starts reading them) — it is the reason step 5 and step 8
   cannot be collapsed into one immediate action.

6. **[HUMAN]** Retarget the shared binary symlink:
   ```bash
   sudo ln -sfn /home/ubuntu/.hermes/hermes-agent/venv/bin/hermes /usr/local/bin/hermes
   ```

7. **[HUMAN]** Install the edited unit files (the ones saved locally in step 4, with the corrected `ReadWritePaths=`) and reload:
   ```bash
   sudo install -m 0644 /path/to/edited/hermes.service /etc/systemd/system/hermes.service
   sudo install -m 0644 /path/to/edited/hermes-dashboard.service /etc/systemd/system/hermes-dashboard.service
   sudo systemctl daemon-reload
   ```

8. **[HUMAN]** Start the new (ubuntu-based) services:
   ```bash
   sudo systemctl start hermes.service
   sudo systemctl start hermes-dashboard.service
   sudo systemctl status hermes.service hermes-dashboard.service --no-pager
   ```

9. **[AGENT]** Immediately tail logs to catch startup errors fast:
   ```bash
   sudo journalctl -u hermes.service -n 50 --no-pager
   ```

## Success Criteria

- [x] Stage A DONE (with one substitution, documented): the literal `hermes gateway run` dry-run (step 1's first command) could not execute — hermes-agent's own "already running" guard reads the (correctly, per-plan) copied `gateway_state.json`, which still records hermes's real live PID as `gateway_state:"running"`; that PID is genuinely still alive (old service not stopped yet, by design — Stage A must not touch it), so the guard correctly refuses a second instance. This is a foreseeable, harmless side effect of Phase 3's full-state copy, not a bug — it self-resolves at Stage B step 5 (old service stops, PID exits) before step 5a re-copies fresh state. Substituted `hermes doctor` under the identical `systemd-run` sandbox (`ProtectHome=read-only`, same `ReadWritePaths=`) as the closest available "config loads + sandbox works" check — "All checks passed". The sandboxed `WRITE_OK` write test passed against `/home/ubuntu/workspace/nfi` (the actual most-corroborated red-team finding). CCS delegation smoke test passed (`is_error:false`, real response). Memory content spot-checked, matches Phase 3's corrections. The real full-gateway-boot validation now happens for real at Stage B step 8, where it must work anyway.
- [x] Stage B: `systemctl status hermes.service hermes-dashboard.service` both show `active (running)` under the new unit files, with `ReadWritePaths=` including `/home/ubuntu/workspace`.
- [x] Step 5a's state re-copy ran after old service stop and before new service start — `state.db`/`kanban.db` reflect the moment of cutover, not Phase 3's earlier snapshot.
- [x] `templates/systemd/hermes.service`/`hermes-dashboard.service` in this repo updated to match the deployed unit (uncommitted, ready for a git-manager commit); `/opt` clone hand-applied by human (root-owned, needed interactive sudo).
- [x] `/usr/local/bin/hermes` resolves to the ubuntu venv path.
- [x] `journalctl -u hermes.service` shows a clean startup on the final unit files (no tracebacks, no missing-config errors, no `Read-only file system`) — confirmed after the `SystemCallErrorNumber=EPERM` fix and dashboard `web_dist` build.
- [ ] **Missed — 55min actual, not <15min.** Two unplanned incidents extended the window: a `User=ubuntu`-only SIGSYS crash (fixed via `SystemCallErrorNumber=EPERM`) and a missing dashboard `web_dist` build artifact (fixed via `npm run build -w web`). Both documented in Phase 7. Root cause of the SIGSYS syscall itself was not pinned to an exact name (no `coredumpctl`/`dmesg`/`strace` access on this host during the incident) — see Phase 7's incident log.

## Risk Assessment

- **High risk, tightly time-boxed**: this is the phase with real user-facing downtime and the
  only phase editing root-owned files live. Mitigations already built in: Stage A now performs
  every check under the real sandboxing properties (not a bare process, per red-team finding),
  so Stage B is a short, mechanical stop/copy/edit/start sequence rather than a debugging
  session performed while the bot is down.
- **Symlink-retarget ordering (red-team finding):** steps 5-8 still commit the shared
  `/usr/local/bin/hermes` symlink and overwrite the live unit files before the new service is
  confirmed running — a partial failure at step 8 leaves neither flavor cleanly working until
  Phase 7's rollback is run. This plan does not add a full canary/throwaway-unit step for this
  (would be real added complexity per Scope Critic's own review — the mitigation already in
  place is that Stage A now validates the exact sandboxing properties the real unit will use,
  which removes most of the realistic causes of a step-8 failure). What remains genuinely
  time-boxed is the mechanical stop/copy/edit/start sequence itself, not the underlying
  application/config correctness — accept this residual risk rather than adding a second
  validation layer for it.
- If Stage B step 8 fails to start cleanly, the fastest safe recovery is the Phase 7 rollback
  procedure (re-point the symlink back, reinstall the original unit files from Phase 1's
  separate `.bak` files, restart as hermes) rather than debugging live — debug against the
  backed-up old units afterward, at leisure, using the still-intact `/home/hermes` state.

## Security Considerations

- Steps 4-8 require root. Use `visudo`-equivalent care with unit file edits — a malformed
  systemd unit can fail silently or, worse, start successfully with wrong `ReadWritePaths`
  (e.g., accidentally leaving `/home/hermes/.hermes` writable) which would reopen exactly the
  cross-user surface this migration is meant to close. Diff the new unit file against the old
  one before installing (`diff /home/ubuntu/hermes-old-hermes.service-260706.bak /path/to/edited/hermes.service`).
- **Containment note (red-team finding):** unlike `hermes`, `ubuntu` already holds unrestricted
  `sudo` (`(ALL:ALL) ALL`) plus `docker`/`lxd` group membership — both effectively root-equivalent.
  Post-migration, a compromised Hermes process runs as an account one step from full root, with
  **systemd sandboxing as the only containment layer** (no OS-user boundary anymore). This is an
  accepted trade-off of the "merge users to eliminate friction" goal, not an oversight — state it
  here so it's a conscious decision, not a silent regression discovered later.
