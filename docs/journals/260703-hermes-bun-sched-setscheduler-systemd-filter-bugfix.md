# Claude/Opencode CLI "Bad System Call" Under hermes.service Seccomp Filter

**Date**: 2026-07-03
**Component**: `templates/systemd/hermes.service`, coding-agent-delegate skill (claude, opencode CLIs)
**Status**: Root-caused and fixed in the repo template; not yet deployed to the live host

## What Happened

User reported that the `claude` CLI crashes with "Bad system call" immediately — even on `--version` — in the environment where the `coding-agent-delegate` skill's CLIs run, and that `/proc/cpuinfo` couldn't even be read there. Their own read: a restricted container/security profile, not a missing install.

This session had direct shell access to the actual live host running `hermes.service` (an Oracle Cloud Ubuntu 24.04 aarch64 box, systemd 255) — the same box the guide's bootstrap scripts and this plan's templates target. The live service itself was running fine (no crash in its own journal/dmesg — `journalctl -u hermes` and `dmesg` had zero SIGSYS/seccomp entries at the time of investigation); the failure is specific to invoking the Bun-based coding CLIs *as a child process inheriting the unit's hardening*, not a crash of the bot process itself.

## Diagnosis

1. `sudo -u hermes claude --version` (outside systemd, plain shell) → worked fine, printed the version. `sudo -u hermes cat /proc/cpuinfo` → worked fine too. This isolated the cause to `hermes.service`'s own sandboxing, not the binary or install.
2. `/proc/cpuinfo` unreadable is a *separate*, expected effect of `ProcSubset=pid` in the unit (documented systemd behavior — hides non-PID `/proc` entries like `/proc/cpuinfo`/`/proc/meminfo`). Not the crash cause, just confirms the user was testing inside the hardened context.
3. `file`/`strings` on `~hermes/.local/bin/claude` and `.../opencode` confirmed both are **Bun-compiled** binaries (Bun HMR runtime strings, `oven-sh/bun` references) — not plain Node. `codex`/`gemini` are plain `#!/usr/bin/env bash exec node ...` wrapper scripts — different runtime, so not necessarily affected the same way.
4. First hypothesis: Bun uses io_uring for its Linux I/O event loop; `io_uring_setup`/`enter`/`register` aren't part of any named systemd syscall group (confirmed via `systemd-analyze syscall-filter`, no root needed) so they'd be denied by the unit's default-deny filter. Built a ~30-line C program that self-installs a seccomp-bpf filter via `prctl(PR_SET_SECCOMP)` (no root required — restricting only yourself never needs privilege) blocking just `io_uring_setup`, then execs the target. Result: `claude --version` still worked fine. **Hypothesis ruled out** — good thing it was tested before touching the live unit.
5. Instead, ran `strace -f -c -o /tmp/... claude --version` (unsandboxed) to get the full, real syscall list the binary actually makes. Separately computed the unit's true effective allow-list by recursively expanding `@system-service`'s nested subgroups (`@aio`, `@basic-io`, `@chown`, `@default`, `@file-system`, `@io-event`, `@ipc`, `@keyring`, `@memlock`, `@network-io`, `@process`, `@resources`, `@setuid`, `@signal`, `@sync`, `@timer` — 375 syscalls total) via `systemd-analyze syscall-filter`, then subtracting the unit's own exclusion line (`~@privileged @resources @mount @cpu-emulation @debug @reboot @swap`, 65 syscalls) → 351-syscall effective allow-list.
6. Diffed claude's strace'd syscalls against that 351-syscall list: exactly one mismatch — `sched_setscheduler` (part of `@resources`, explicitly excluded).
7. Confirmed with the same no-root seccomp harness, this time blocking only `sched_setscheduler`: reproduced the exact "Bad system call" (SIGSYS, exit 159) on both `claude` and `opencode`. `node --version` under the identical filter was unaffected (control) — consistent with plain Node not calling this syscall.

## Root Cause

Bun's runtime calls `sched_setscheduler()` during normal process startup (before any user code runs — happens even on `--version`). `hermes.service`'s hardened `SystemCallFilter=@system-service` minus `@resources`/`@privileged`/`@mount`/`@cpu-emulation`/`@debug`/`@reboot`/`@swap` denies that syscall outright, and systemd's default action for a denied syscall is to kill the process with SIGSYS — not return an error the runtime could catch and fall back from.

## Fix

Added one line to `templates/systemd/hermes.service`:

```
SystemCallFilter=sched_setscheduler
```

with a comment explaining why (Bun startup) and why it's safe: `CapabilityBoundingSet=` in the same unit is already empty, so even with the syscall allowed, the kernel still returns `EPERM` for anything requiring `CAP_SYS_NICE` (real-time priority, affecting other processes). Re-allowing this one syscall doesn't reopen what `@resources` exists to block.

## Status

- Fixed in the repo template only (`templates/systemd/hermes.service`), uncommitted.
- **Not deployed to the live host.** This session's sudo access is scoped to the `hermes` user (NOPASSWD, all commands) plus a handful of specific root verbs (`systemctl {start,stop,restart,status,daemon-reload}` and `journalctl -u hermes*`) — no generic root file-write, so the agent could not copy the fixed template into `/etc/systemd/system/hermes.service` itself.
- Handed the user the exact redeploy sequence (same pattern the bootstrap scripts already use):
  ```sh
  sudo install -m 0644 templates/systemd/hermes.service /etc/systemd/system/hermes.service
  sudo systemctl daemon-reload
  sudo systemctl restart hermes
  ```

## Lessons

1. **Test the hypothesis before touching production hardening.** The io_uring theory was plausible (well-known Bun/seccomp incompatibility class) but wrong here. A cheap, no-root, self-imposed seccomp reproduction (`prctl(PR_SET_SECCOMP)` blocking one syscall at a time) settled it in minutes instead of shipping a guess to a live unit.
2. **`systemd-analyze syscall-filter` needs recursive expansion.** `@system-service` is defined as a union of ~16 other named groups, not a flat list — naively grepping the direct output for a syscall name gives false negatives for everything nested one level down.
3. **Least-privilege scoped sudo worked as a real safety rail here**, not just a policy nicety — it physically prevented a same-session live redeploy of an unverified fix to a running Telegram bot, forcing a human-reviewed handoff instead.

## Unresolved Questions

1. Does the same `sched_setscheduler` block affect any other Bun-based tool that might get added to the coding-agent-delegate routing table later? (`codex`/`gemini` are plain Node, unaffected today.)
2. Worth a comment in the unit file (or a bootstrap-script post-install check) that runs `sudo -u hermes claude --version` *inside* a matching systemd-run scope as part of deployment verification, so this class of bug surfaces before going live rather than after?
