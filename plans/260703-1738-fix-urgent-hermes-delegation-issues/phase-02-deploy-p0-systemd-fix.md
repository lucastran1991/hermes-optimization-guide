---
phase: 2
title: "Deploy P0 Systemd Fix"
status: completed
effort: "25m"
---

# Phase 2: Deploy P0 Systemd Fix

**Priority:** P1 (production-down) · **Status:** pending · **Effort:** ~25m · **Blocked by:** none (parallel group A) · **Ownership:** host-only, no repo writes · **Run ASAP.**

## Context Links

- Root-cause report: `plans/reports/ck-debug-260703-1725-hermes-seccomp-claude-sigsys-stale-unit-report.md` (the exact deploy command + post-deploy checklist).
- Host verification: `research/live-host-verification-findings.md` §1 (drift), §2 (sudo scope).
- Deploys as-is: `templates/systemd/hermes.service` (line 82 = the `sched_setscheduler` re-allow; line 45 = `ReadWritePaths` incl. `/home/hermes/.ccs`).

## Overview

The actual production fix. Deploy the repo's `templates/systemd/hermes.service` to `/etc/systemd/system/`, `daemon-reload`, and `restart`. This clears the SIGSYS kill on every delegated `claude`/`opencode` call. **Downtime is NOT a guaranteed "~5s": best observed case is ~2-5s (one restart today went ~2s because it caught the process idle), but there is no `TimeoutStopSec=` override in the unit, so systemd's default `TimeoutStopSec=90s` applies — a restart that lands mid-tool-call can take up to 90s before SIGKILL. Announce before running, and check for in-flight activity first (step below).** The same deploy also lands `ReadWritePaths+=/home/hermes/.ccs` (commit `72cc2fd`), satisfying a Phase 5 prerequisite for free.

## Key Insights

- Live unit predates `c9631fc` (seccomp re-allow) and `72cc2fd` (`.ccs` RW path); the template carries both, neither is deployed (findings §1; debug report Evidence §2).
- The debug report's bidirectional `strace` gap analysis found **zero other blocked syscalls** under the template filter (Evidence §3) — no second SIGSYS lurking; this is a complete fix for the crash layer.
- `install` to `/etc` is password-gated → `[HUMAN]`. **Only `systemctl {start,stop,restart,status} hermes*`, `daemon-reload`, and `journalctl -u hermes*` are NOPASSWD (verified `sudo -n -l`).** `systemctl show` and `journalctl -k` are NOT covered — they need a password (so any check using them is `[HUMAN]`, not `[AGENT]`). Also `systemctl reset-failed` is NOT covered (relevant to Rollback). Do not overclaim "all NOPASSWD".
- The installed unit is world-readable (`0644`), so its on-disk contents can be read with `systemctl cat hermes.service` / `cat /etc/systemd/system/hermes.service` — **no sudo** — which is how the `[AGENT]` file-content checks below avoid the password-gated `systemctl show`.
- Independent of Phase 1 by design: uses the raw command (not Phase 1's script) and an absolute workspace-clone source path, so it can run in the parallel group without waiting on Phase 1 or the `/opt` reconcile. Once both land, future deploys use the script from the canonical `/opt` clone.

## Requirements

Deploy the template unchanged; post-deploy the running unit's `SystemCallFilter` includes `sched_setscheduler`, `ReadWritePaths` includes `/home/hermes/.ccs`, the service is active, and no new `type=1326` SIGSYS audit lines appear for `claude`/`opencode`.

## Architecture

Repo template → `install` copies to `/etc/systemd/system/hermes.service` → `daemon-reload` reparses → `restart` respawns `hermes gateway run` under the corrected filter → verify via `systemctl cat | grep` (world-readable file, `[AGENT]`) + `systemctl status` + `journalctl -u hermes` (`[AGENT]`), with an optional `[HUMAN]` `journalctl -k` kernel-audit deep check.

## Related Code Files

None modified in the repo. Reads `templates/systemd/hermes.service`. All effects are host-side (`/etc`, systemd state).

## Implementation Steps

1. `[AGENT]` Pre-flight: (a) confirm the sudo grant is present — `sudo -n -l` should show `(root) NOPASSWD: … restart hermes*`, `daemon-reload`, `journalctl -u hermes*`; if it doesn't, stop and treat this as `[HUMAN]`. (b) **In-flight check before restart:** `journalctl -u hermes -n 5 --since "-30s"` to eyeball recent `tool_executor` activity — a restart landing mid-tool-call can block up to the 90s default `TimeoutStopSec`, so prefer a quiet moment. Announce the downtime window.
2. `[AGENT]` Confirm the deploy command. Absolute-path form (CWD-independent):
   ```bash
   sudo install -m 0644 -o root -g root \
     /home/ubuntu/workspace/hermes-optimization-guide/templates/systemd/hermes.service \
     /etc/systemd/system/hermes.service \
     && sudo systemctl daemon-reload && sudo systemctl restart hermes.service
   ```
3. `[HUMAN]` Run it (root password required — outside the agent's NOPASSWD scope, findings §2). **Recommended first**, for a one-command rollback target: `sudo cp /etc/systemd/system/hermes.service{,.bak}` — captures the exact currently-running unit before overwriting.
4. Verify (tags are accurate — NOT "all NOPASSWD"):
   - `[AGENT]` `systemctl cat hermes.service | grep sched_setscheduler` → present (reads the world-readable installed file; no sudo — `systemctl show` would need a password).
   - `[AGENT]` `systemctl cat hermes.service | grep -A1 ReadWritePaths` → contains `/home/hermes/.ccs`.
   - `[AGENT]` `sudo systemctl status hermes.service` → `active (running)` (NOPASSWD).
   - `[AGENT]` `journalctl -u hermes -n 50` → clean startup, no new errors, and specifically **no** `Bad system call`/`core dumped` for `claude`/`opencode` (this is the agent-executable proof the running process no longer SIGSYS-crashes).
   - `[AGENT]` Note the restart timestamp; run `sudo -u hermes bash -c 'export PATH="$HOME/.local/bin:$PATH"; claude --version'` and `… opencode --version` (expect success, no core dump — the **wrapped** form is required: a bare `sudo -u hermes claude --version` fails with `command not found` because sudo's `secure_path` excludes `~/.local/bin`).
   - `[HUMAN]` (optional deeper kernel-audit check, needs a password): `sudo journalctl -k --since "<restart ts>"` shows **no** new `type=1326 … sig=31 … comm="claude"`/`"opencode"` lines. Not `[AGENT]` — `journalctl -k` is outside the NOPASSWD grant; the `journalctl -u hermes` check above is the agent-executable substitute.

## Todo List

- [x] In-flight activity checked; downtime window announced (pre-flight: 0 activity in prior 60s).
- [x] Live unit backed up (`.bak`) — deployed by user (`[HUMAN]`, root password).
- [x] Template deployed + `daemon-reload` + `restart` — restarted 2026-07-03 19:59:20 UTC.
- [x] `systemctl cat … | grep sched_setscheduler` present (installed file). Verified.
- [x] `ReadWritePaths` includes `/home/hermes/.ccs` (via `systemctl cat`). Verified.
- [x] Service active, clean logs (no `Bad system call` in `journalctl -u hermes` since the 19:59:20 restart — the one SIGSYS line found is from 12:21:14, 7+ hours BEFORE the fix, historical evidence not a regression).
- [x] `claude`/`opencode --version` succeed via the **PATH-wrapped** `sudo -u hermes bash -c` form; no new SIGSYS after restart. `claude --version` → `2.1.199`, exit 0. `opencode --version` → `1.17.13`, exit 0.

## Success Criteria

All verification checks pass; delegated `claude`/`opencode` no longer die with SIGSYS.

## Risk Assessment

| Risk | L×I | Mitigation |
|------|-----|------------|
| Service fails to come up after restart | L×H | `systemctl status` + `journalctl -u hermes -n 50` to diagnose; rollback via the `.bak` (see below). |
| **Crash loop trips `StartLimitBurst=5` (`hermes.service:21-22`), stranding the rollback** | L×H | `sudo systemctl reset-failed hermes.service` is the FIRST rollback command (idempotent/harmless if the limit wasn't hit) — without it the rollback's own `restart` is refused with "start request repeated too quickly". `reset-failed` is NOT in the NOPASSWD grant → human-only. |
| Restart lands mid-tool-call → up to 90s stop (not ~5s) | M×M | No `TimeoutStopSec=` override → systemd default 90s; in-flight check (step 1b) before restarting; announce the real window; run off-peak. |
| Undetected template regression | very-L×H | Debug report's zero-blocked-syscalls gap analysis gives high confidence; `.bak` covers the residual. |
| Human runs from wrong CWD | L×M | Command uses the absolute source path. |

## Security Considerations

The unit only *tightens* posture (re-allows exactly one syscall; `CapabilityBoundingSet=` is empty, so real-time priority still fails with EPERM — see `hermes.service:79-81`). No secrets. The single privileged action (root write to `/etc`) is human-gated. The `.ccs` `ReadWritePaths` widening is a pre-accepted risk from plan `260703-1041` (shared hook/plugin write) — unchanged here, only now deployed.

## Rollback

Primary: **`sudo systemctl reset-failed hermes.service`** (FIRST — clears any `StartLimitBurst=5` start-limit-hit so the following `restart` isn't refused; harmless if the limit wasn't tripped), then `sudo cp /etc/systemd/system/hermes.service.bak /etc/systemd/system/hermes.service && sudo systemctl daemon-reload && sudo systemctl restart hermes.service` (restores the last unit the service actually ran under — a unit that at least starts). Secondary: re-deploy the fixed template from git, `git show c9631fc:templates/systemd/hermes.service`. **Do NOT roll back to `c9631fc~1`** — that is the *pre-fix* version and would re-introduce the SIGSYS crash. Verify `active` after any rollback. (`reset-failed` needs a root password — not in the NOPASSWD grant — so rollback is a `[HUMAN]` operation.)

## Next Steps

Unblocks Phase 6's end-to-end test. Also lands the `.ccs` RW path Phase 5 relies on. Once Phase 1's script exists, it supersedes this manual command for future deploys.
