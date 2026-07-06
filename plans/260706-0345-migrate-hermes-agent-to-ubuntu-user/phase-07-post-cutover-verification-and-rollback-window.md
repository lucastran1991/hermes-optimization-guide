---
phase: 7
title: "Post-Cutover Verification and Rollback Window"
status: verification-complete (48h hold period active until 2026-07-08T07:50:00Z)
priority: P1
effort: "30m active + 48h passive wait"
dependencies: [6]
---

# Phase 7: Post-Cutover Verification and Rollback Window

## Overview

Confirm the ubuntu-hosted Hermes is fully functional against the Phase 1 baseline, then hold
`/home/hermes` fully intact (services stopped) for at least 48 hours as a rollback safety net
before Phase 8's destructive cleanup.

**Correction (red-team finding):** the claim that `/home/hermes` is "fully untouched" through
Phase 6 is not quite accurate as originally written — Phase 4 was corrected to defer its
`ccs-hermes` instance-dir deletion to Phase 8 specifically so this statement would be true.
As currently written (post red-team fixes), Phases 1-6 only **read** from `/home/hermes`; no
step in Phases 1-6 deletes or modifies anything under it. Verify this hasn't drifted before
relying on it: `sudo find /home/hermes -newer /home/ubuntu/hermes-full-backup-260706.tar.gz -not -path "*/logs/*" -not -name "*.db*"` should show no unexpected changes from this migration's own steps (log/db growth from the service still running through Phase 6 Stage A is expected).

## Implementation Steps

### Functional verification

1. **[HUMAN]** Send a real message to the Hermes Telegram bot, confirm it responds — this is the definitive end-to-end check.
2. **[HUMAN]** Ask it something requiring the memory recall tested in Phase 1's baseline; confirm the answer matches.
3. **[AGENT]** Confirm CCS delegation works live (not just the dry-run smoke test): trigger an actual delegated task through the bot if feasible, or re-run `ccs ccs-hermes -p "echo ok"` as a minimum bar.
4. **[AGENT]** Confirm skill count matches Phase 1's baseline:
   ```bash
   find /home/ubuntu/.hermes/skills -mindepth 2 -maxdepth 2 -type d | wc -l
   ```
5. **[AGENT]** Confirm cross-tool access (the original goal of this whole migration) — including
   the actual sandboxed write test, not just ownership (red-team finding, see Phase 5/6):
   ```bash
   tailscale status
   ccs ken --version 2>&1 | head -3    # confirm human's own profiles still work post Phase 4 edits
   ccs lucas --version 2>&1 | head -3
   ccs luan --version 2>&1 | head -3
   sudo systemd-run --uid=ubuntu --gid=ubuntu -p ProtectHome=read-only \
     -p ReadWritePaths="/home/ubuntu/.hermes /home/ubuntu/.ccs /home/ubuntu/workspace /tmp" \
     --pipe --wait bash -c 'touch /home/ubuntu/workspace/nfi/.hermes-post-cutover-write-test && rm /home/ubuntu/workspace/nfi/.hermes-post-cutover-write-test && echo WRITE_OK'
   ```
   The last command must print `WRITE_OK` — this is the definitive proof the `ReadWritePaths`
   fix from Phase 6 actually took effect in production, not just in Stage A's rehearsal.
6. **[HUMAN, optional]** Reboot survival test — only do this if a maintenance window for a full host reboot is separately acceptable (this affects everything on the box, not just Hermes):
   ```bash
   sudo reboot
   # after reboot:
   systemctl status hermes.service hermes-dashboard.service --no-pager
   ```

### Rollback procedure (use if any check above fails)

**Corrected (red-team finding):** the original version of this procedure referenced a
`-derived-hermes.service` file that Phase 1 never actually produced, and suggested a git-template
fallback that red-team confirmed diverges from the real production unit. Phase 1 now backs up
both units as separate, directly-installable `.bak` files — use those:

```bash
# Stop the new (ubuntu) services
sudo systemctl stop hermes.service hermes-dashboard.service

# Re-point the shared binary symlink back
sudo ln -sfn /home/hermes/.hermes/hermes-agent/venv/bin/hermes /usr/local/bin/hermes

# Restore the original unit files from Phase 1's backup (separate, directly-installable files)
sudo install -m 0644 /home/ubuntu/hermes-old-hermes.service-260706.bak /etc/systemd/system/hermes.service
sudo install -m 0644 /home/ubuntu/hermes-old-hermes-dashboard.service-260706.bak /etc/systemd/system/hermes-dashboard.service
sudo systemctl daemon-reload
sudo systemctl start hermes.service hermes-dashboard.service
```
This is safe at any point in the 48h window because Phases 1-6 (as corrected by red-team,
including deferring Phase 4's `ccs-hermes` deletion to Phase 8) only read from `/home/hermes` —
verify this with the `find -newer` check in the Overview above before relying on it, since it's
now a load-bearing claim for this exact rollback procedure to work.

### Hold period

7. **[HUMAN]** Do not proceed to Phase 8 until at least 48 hours have passed since a successful
   cutover, and the bot has been observed handling real interactions without issues during that
   window (not just the immediate post-cutover check).

## Success Criteria

- [x] Telegram bot responds correctly to a real message — confirmed by human.
- [x] Memory recall matches Phase 1 baseline — confirmed by human.
- [x] CCS delegation confirmed working live — `ccs ccs-hermes -p "echo ok"`, `is_error:false`, `result:"ok"`.
- [x] Skill count matches baseline — 70, exact match.
- [x] `tailscale status` and `ccs {ken,lucas,luan}` all work from the merged ubuntu environment — all returned `2.1.201 (Claude Code)`, tailscale shows 3 devices including this host.
- [x] Sandboxed workspace write test prints `WRITE_OK` in production — confirmed, real `ReadWritePaths` fix verified live (not just Stage A rehearsal).
- [ ] 48+ hours elapsed with no incidents before Phase 8 proceeds — **hold period started 2026-07-06 07:50 UTC (moment both services came up healthy on final unit files), ends 2026-07-08 07:50 UTC.** Do not run Phase 8 before then.

### Incidents during cutover (documented, both resolved before this checklist was completed)
- `hermes.service` crashed with SIGSYS on first start under `User=ubuntu` (never happened under `User=hermes`) — root syscall not pinned exactly (no `coredumpctl`/`dmesg`/`strace` access available), but confirmed via `SystemCallErrorNumber=EPERM` substitution that the app tolerates the denial gracefully. Adopted as the permanent fix (`SystemCallErrorNumber=EPERM` in both units + repo templates), not just a stopgap — doesn't widen `CapabilityBoundingSet=`/`NoNewPrivileges=true`, only changes the failure mode of an already-narrow denied-syscall surface from process-killing to a catchable error.
- `hermes-dashboard.service` failed separately (`--skip-build` with no `web_dist` present) — Phase 2's fresh install never built the web frontend (only hermes-agent's Python/CLI side). Fixed with `npm install --workspace web && npm run build -w web` inside `/home/ubuntu/.hermes/hermes-agent`.
- Actual downtime: 06:55 UTC (old service stop) to 07:50 UTC (new services healthy) = **~55 minutes**, over the <15min target — driven entirely by the two incidents above, not by the planned mechanical steps.

## Risk Assessment

- **Low risk if Phases 1-6 were done correctly** — this phase is verification + a waiting period, not new mutation. The rollback procedure is the safety net for anything Phase 6 missed.
