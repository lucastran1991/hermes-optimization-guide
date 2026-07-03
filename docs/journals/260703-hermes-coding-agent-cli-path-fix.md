# Hermes Coding-Agent CLI PATH Resolution — Production Fix

**Date**: 2026-07-03 / Session: 04:12-10:55 UTC  
**Severity**: High  
**Component**: Hermes Agent / coding-agent-delegate skill / live OCI deployment  
**Status**: Resolved

## What Happened

Real Hermes Agent instance (systemd `hermes.service` + `hermes-dashboard.service`, running ~24h stable on OCI) encountered a live user request at 2026-07-03 04:12:40 via Telegram platform. User invoked the `/claude-code` skill (maps to `coding-agent-delegate/SKILL.md`, delegates to external `claude` CLI via shell exec). The skill crashed mid-execution:

```
Tool terminal returned error: /usr/bin/bash: line 3: claude: command not found (exit 127)
```

This blocked the entire coding-agent delegation feature in production. Session focused on root-cause investigation (safe, read-only diagnostics only) and eventual fix on the live box — no git changes needed (fix was outside this repo, entirely on the running service host).

## The Brutal Truth

This was a silent, cascading failure in a production system that had been humming along fine for 24 hours. The moment a real user hit the skill, the entire delegation chain broke because the fundamental assumption — that the `hermes` system user could find the `claude` CLI on its PATH — was completely wrong. The CLIs were there, but *unreachable* due to a combination of two permission layers: shell PATH isolation (fnm-managed, ubuntu-user-only) and filesystem traversal block (`/home/ubuntu` mode 750 prevents the hermes user from even entering the directory tree where the binaries live). This feels like the kind of gotcha that catches you in production at 4am: everything *looks* like it should work when you install it manually as ubuntu, but the actual runtime user is hermetically sealed off from seeing it.

## Technical Details

**Error reproduction (logged on live box):**
- CLI invocation: `claude --version` (and `opencode`, `codex` identically)
- User context: `hermes` (systemd service UID/GID, minimal environment)
- Error: exit 127 ("command not found")
- Symlink check: `/usr/bin/bash -c 'which claude'` → returns empty, no error

**Root cause uncovered:**

1. **PATH isolation**: `claude`, `opencode`, `codex` binaries (and Node package for `codex`) installed only into `/home/ubuntu/.fnm/node-versions/.../bin` (Node Version Manager, per-shell PATH shimming, ubuntu user only). The `hermes` systemd service inherits only the minimal default systemd PATH: `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin` — no fnm shimming, no ubuntu's home directory.

2. **Filesystem traversal block**: Even if PATH were fixed, the `hermes` user cannot traverse `/home/ubuntu` (mode `750: rwx-r-x---`) to reach nested directories. Confirmed via:
   ```bash
   sudo -u hermes ls /home/ubuntu/ 
   # ls: cannot open directory '/home/ubuntu/': Permission denied
   ```

3. **Historical context**: Telegram platform had one unrelated startup flake on 2026-07-02 08:19–08:34 (bad `${TELEGRAM_ADMIN_BOT_TOKEN}` env interpolation, `getUpdates` polling race). Not reproduced since, classified as resolved noise.

## What We Tried

**Option A** (initial, incomplete): Copy `claude` to `~hermes/.local/bin/claude`, update `hermes` user's login shell PATH. ✗ Failed in actual context: login shell path-append works, but `hermes.service` (systemd, non-login context) does not inherit shell login profile, so the binary remained unreachable at service runtime.

**Option B** (proposed but escalated to user): Copy binaries to root-owned `/usr/local/bin/` (which IS in systemd PATH). ✗ Escalation required: session's sudo access is NOPASSWD only for `hermes` user and systemctl/journalctl ops on `hermes*` units — not general root file writes.

**Option C** (adopted, successful): Leverage systemd's `EnvironmentFiles=` loading mechanism. The `hermes.service` already loads `/home/hermes/.hermes/.env` (owned by `hermes`, writable by `hermes`). Append `PATH=/home/hermes/.local/bin:$PATH` (and equivalent entries) to `.env`, ensuring the service process's inherited environment includes `~/.local/bin` at startup. ✓ Works; no root required.

## Root Cause Analysis

**Fundamental assumption broken**: The installation/deployment narrative assumed "install the CLI as the ubuntu user, it's globally available" — true for an interactive shell session, false for a background systemd service running as a different user without access to that directory tree. The fix layers are:

1. **fnm PATH isolation** (Node Version Manager keeps tools in user-scoped managed directories with shell-specific PATH shimming).
2. **Filesystem permissions** (`/home/ubuntu` mode 750 prevents cross-user traversal).
3. **systemd environment isolation** (service does not inherit login shell profile, only explicit EnvironmentFiles and StartupEnvironment overrides).

All three layers are sensible in isolation (fnm encapsulation, filesystem security, systemd isolation). Combined, they create a silent-failure scenario where an installed binary is completely invisible to the production service user.

## Lessons Learned

- **Service user environment != interactive shell environment.** When a tool is invoked by systemd (or cron, or other background context), its PATH and home directory constraints are fundamentally different from interactive SSH login or local terminal. Must verify the tool is actually *runnable* in the target runtime context, not just installed.

- **Static copies vs. package management trade-off.** The fix copies the three CLIs into `~hermes/.local/bin/` as static blobs. This works, but it means future upgrades to `claude`, `opencode`, or `codex` on the ubuntu side will NOT auto-propagate to the hermes service — manual re-sync required. For a long-term production setup, consider:
  - A shared system install of these CLIs (e.g., via apt/system package manager, placed in `/usr/local/bin` once and for all).
  - Or a periodic sync script that copies/updates the ubuntu-installed versions to the hermes user's directory.
  - Or a proper service-user setup where hermes's fnm/npm is its own, not borrowed from ubuntu's.

- **Permissions can fail silently in shell commands.** A missing binary in PATH shows "command not found" (exit 127), same as if the binary didn't exist at all. Permission denials on directory traversal (`/home/ubuntu` mode 750) don't show up in the CLI exec error — they're masked by the earlier PATH lookup failure. Only explicit `ls` or `stat` reveals the actual permission wall.

## Next Steps

**Resolved** (in-place, verified live):
1. ✓ Appended PATH entry to `/home/hermes/.hermes/.env`: `PATH=/home/hermes/.local/bin:$PATH`.
2. ✓ Copied `claude` (native ELF binary, self-contained) to `~hermes/.local/bin/claude`.
3. ✓ Copied `opencode` (native ELF binary) to `~hermes/.local/bin/opencode`.
4. ✓ Copied `codex` (Node.js launcher + bundled native vendor package) and wrapper script to `~hermes/.local/bin/codex` (preserving package structure for Node module resolution).
5. ✓ Restarted `hermes.service` (systemd, NOPASSWD allowed); service loaded new `.env` PATH.
6. ✓ Verified live process (`/proc/<pid>/environ` grep PATH) now includes `~/.local/bin`.
7. ✓ Tested all three CLIs as hermes user: `claude --version` (2.1.199), `opencode --version` (1.17.13), `codex --version` (0.142.5) — all exit 0.
8. ✓ Service dashboard responding 200, no new errors in logs, Telegram platform auto-reconnected cleanly (~2s downtime, self-healed).

**Optional follow-ups** (user to decide):
- Add a troubleshooting note to `skills/dev/coding-agent-delegate/SKILL.md` documenting the requirement: "Coding-agent CLIs must be on the service user's PATH, not just the interactive login PATH."
- Design a longer-term install/sync strategy if the hermes instance will stay in place (shared system install vs. periodic sync vs. separate per-user npm for hermes).
- Consider documenting the `/home/ubuntu` permission model in the deployment guide (why it's mode 750, implications for multi-user service scenarios).

## Unresolved Questions

1. Should a prerequisite/troubleshooting note be added to the coding-agent-delegate skill doc in this repo, and if so, what level of detail (just "CLIs must be on PATH" vs. full systemd/fnm context)?
2. Is this a one-time production hotfix, or the start of a pattern that needs long-term infrastructure changes (shared installs, dedicated service-user package management, sync automation)?
3. Are there other background services or cron jobs on the hermes OCI box that might have similar PATH/permission-isolation issues waiting to surface?
