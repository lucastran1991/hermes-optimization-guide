# Debug Report: claude/opencode SIGSYS under hermes.service — stale deployed unit

Date: 2026-07-03 17:25 UTC · Host: lucas-oracle-instance (OCI aarch64) · Trigger: Hermes bot Telegram report ("claude --version core dumped, Bad system call")

## Executive Summary

Bot's symptom diagnosis correct (seccomp SIGSYS kill), its remediation proposals wrong. Root cause: **fix already exists in repo** (`c9631fc`, `templates/systemd/hermes.service:82` re-allows `sched_setscheduler`) **but was never deployed** to `/etc/systemd/system/hermes.service`. Installed unit mtime `2026-07-02 08:26` predates the fix commit (`2026-07-03 17:19`). Deploy + daemon-reload + restart = complete fix. No Claude-Code-team action, no seccomp disable, no extra capabilities needed.

## Evidence

1. **Kernel audit (definitive):** repeated `type=1326 ... sig=31 (SIGSYS) arch=c00000b7 (aarch64) syscall=119 exe=/home/hermes/.local/bin/claude` (also `opencode`). `/usr/include/asm-generic/unistd.h`: `__NR_sched_setscheduler 119`. Latest kill 17:22:53 — **after** fix commit 17:19:58 → running unit lacks fix.
2. **Config drift:** `diff <(systemctl cat hermes.service) templates/systemd/hermes.service` → exactly 2 hunks missing live: `SystemCallFilter=sched_setscheduler` re-allow (c9631fc) and `ReadWritePaths+=/home/hermes/.ccs` (72cc2fd). `hermes-dashboard.service` in sync.
3. **Gap analysis (no next hidden syscall):** `strace -f -c` of all 4 CLIs as hermes, compared against recursively-expanded effective allow set (`@system-service` − denied groups + re-allow), script `syscall_gap_analysis.py` (session scratchpad). With template filter: **0 blocked syscalls** for `claude --version`, `opencode --version`, `codex --version`, `gemini --version`, `claude auth status`. Negative control (re-allow removed): flags exactly `sched_setscheduler` for exactly the 3 invocations that die in audit log — method validated both directions.
4. **Layer-4 probe (ProtectHome/ReadWritePaths):** `HOME=<mode-555 dir> claude --version` → rc=0; `claude auth status --text` → rc=0 ("Not logged in"). `--version` performs zero write-mode opens under `/home/hermes` outside allowed paths. Read-only HOME does not break the two commands the bot ran (EACCES≈EROFS approximation).

## Bot Report Assessment

| Bot claim | Verdict |
|---|---|
| Seccomp blocks syscalls, binary dies SIGSYS even on `--version`, 100% reproducible | Correct (syscall identified: `sched_setscheduler`, Bun runtime startup) |
| `Seccomp: 2`, 21 filters, `CapEff: 0`, `NoNewPrivs: 1` are problems to fix | Wrong — intentional hardening; keep all |
| Fix: Claude Code team ships OCI seccomp profile / disable seccomp / `--cap-add SYS_PTRACE` | Rejected — local unit drift; template fix is minimal + already reviewed (EPERM-safe with empty CapabilityBoundingSet) |

## Fix (pending — needs root, outside session sudo scope)

Session sudo: NOPASSWD only for `(hermes) ALL` + `systemctl start/stop/restart/status hermes*`, `daemon-reload`, `journalctl -u hermes*`. Unit file write requires password → user runs:

```bash
sudo install -m 0644 -o root -g root \
  /home/ubuntu/workspace/hermes-optimization-guide/templates/systemd/hermes.service \
  /etc/systemd/system/hermes.service \
  && sudo systemctl daemon-reload && sudo systemctl restart hermes.service
```

(~5s bot downtime on restart.)

## Post-deploy verification checklist

1. `systemctl show hermes.service -p SystemCallFilter` contains `sched_setscheduler` (positive entry).
2. `sudo systemctl status hermes.service` active; `journalctl -u hermes` clean start.
3. Bot re-runs `claude --version` → expect `2.1.199 (Claude Code)`, no new `type=1326 ... comm="claude"` audit lines.

## Next failure layers (known, out of scope here)

- **Auth (layer 2, still broken):** `claude` not logged in for hermes user (`claude auth status` → "Not logged in"). Interactive `claude auth login` as hermes, or set real `ANTHROPIC_API_KEY` in `/home/hermes/.hermes/.env`. codex/opencode/gemini auth untested.
- **Real delegation writes (layer 4b, untested):** `claude -p` session state writes (`~/.claude`, `~/.claude.json`) under `ProtectHome=read-only` unverified — auth blocks earlier today. If it breaks post-auth, prefer `CLAUDE_CONFIG_DIR` under `.hermes/` over widening `ReadWritePaths`.

## Unresolved questions

- Who/what deployed the Jul-2 08:26 unit (manual `cp` vs bootstrap re-run)? No repo-side deploy automation exists — consider a `make deploy-units` or bootstrap note to prevent repeat drift.
- `gemini --version` EACCES when cwd under `/home/ubuntu` — known test-method artifact (memory), not service-relevant; unverified whether real service invocation is clean end-to-end.
