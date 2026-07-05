# ck-debug: hermes agent cannot access CCS auth profiles — root cause report

Date: 2026-07-04. Host: lucas-oracle-instance (OCI). Method: 3 parallel read-only investigation agents.

## Root cause (two independent, stacked issues)

### 1. PRODUCTION BUG — `hermes.service` cannot even invoke `ccs` (primary cause)

`hermes.service`'s systemd sandbox uses the **default systemd PATH**:
```
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
```
`/home/hermes/.local/bin` (where `ccs`, `claude`, `opencode`, `ck` are installed) is **not** in it. No `Environment=PATH=` override in the unit, `.env`/`EnvironmentFile` sets no PATH either.

Live evidence — `journalctl -u hermes`, 2026-07-03 12:22:28:
```
/usr/bin/bash: line 3: ccs: command not found   (exit 127)
```
Reproduced directly: `sudo -u hermes env -i HOME=/home/hermes PATH=<systemd-default> /home/hermes/.local/bin/ccs api list` → works (exit 0). Same env with bare `ccs` → `command not found`. Confirms pure PATH resolution failure, not a permission/sandbox block.

**Why earlier interactive testing missed this:** `sudo -u hermes -i` / `bash -lc` sources `.bashrc`, which prepends `~/.local/bin` — masks the bug. Same failure class as the earlier `sched_setscheduler` seccomp incident (interactive shell ≠ systemd sandbox).

**`ProtectHome=read-only` / `ReadWritePaths=` are NOT the problem** — live unit already grants `ReadWritePaths=/home/hermes/.hermes /home/hermes/.ccs /tmp`, byte-identical to `templates/systemd/hermes.service` (no drift), and filesystem perms on `/home/hermes/.ccs` are correct (`hermes:hermes`, `600` on `config.yaml`).

**Fix (not applied):** add to `hermes.service` (both live unit and `templates/systemd/hermes.service`):
```
Environment=PATH=/home/hermes/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
```
then `daemon-reload` + restart (root-file-write + passwordless restart, same discipline as the seccomp fix). Open item: other CLIs (`claude`/`opencode`/`codex`/`gemini`) invoked by bare name from within hermes.service likely hit the same gap — only `claude` was seen invoked via absolute path in logs.

### 2. No CCS API profile ever configured (secondary — would still block after fix #1)

`ccs api list` (as hermes) → `[!] No API profiles configured`, exit 0. `~/.ccs/profiles.json` doesn't exist for hermes **or for ubuntu** — this is the default unconfigured state host-wide, not hermes-specific. `~/.ccs/config.yaml` structurally identical between hermes/ubuntu (`profiles: {}`). `~/.hermes/config.yaml` and `.env` have no `delegation:` block or CCS reference at all.

**Fix (not applied):** `sudo -u hermes -i bash -c 'export PATH="$HOME/.local/bin:$PATH"; ccs api create <name> --preset <provider>'` (interactive wizard, needs a hermes-dedicated provider credential — per prior plan decision, never reuse ubuntu's own CCS identity), then add the `delegation:` block to `~/.hermes/config.yaml`.

**Unresolved question:** should check `ccs auth list` / `ccs cliproxy status` — "API profiles" (`ccs api`) may not be the only/right mechanism; not verified whether the delegation flow needs `ccs api` specifically vs. some other `ccs auth` subsystem.

### 3. Separately confirmed: `coding-agent-delegate` skill not wired in

`/home/hermes/.hermes/skills/coding-agent-delegate` does not exist (unlike 13 other ops/dev/security skills already symlinked from `/opt/hermes-optimization-guide/skills/...`). Source exists at `/opt/hermes-optimization-guide/skills/dev/coding-agent-delegate`. Even with fixes #1 and #2, the running agent has no way to reach this skill yet.

---

## Hermes agent structure on this host

```
/home/hermes/                          (hermes:hermes, 750)
├── .hermes/                           (700 — live bot state, root of trust)
│   ├── config.yaml (600, 3.8K) + 2 .bak
│   ├── .env (600) — ANTHROPIC_API_KEY, GOOGLE_API_KEY, TELEGRAM_*, PATH
│   ├── auth.json (600, 9.2K) — OAuth/session tokens
│   ├── skills/ (700)
│   │   ├── full copies: apple, autonomous-ai-agents, creative, data-science,
│   │   │   dogfood, email, github, media, mlops, note-taking, productivity,
│   │   │   research, smart-home, social-media, software-development, yuanbao
│   │   ├── symlinks → /opt/hermes-optimization-guide/skills/...: audit-approval-bypass,
│   │   │   audit-mcp, cost-report, daily-inbox-triage, hermes-weekly, meeting-prep,
│   │   │   nightly-backup, pr-review, release-notes, rotate-secrets, spam-trap,
│   │   │   telegram-triage, weekly-dep-audit
│   │   └── coding-agent-delegate — MISSING (not symlinked, see #3 above)
│   ├── logs/, sessions/, memories/, cache/, cron/, pairing/, hooks/,
│   │   audio_cache/, image_cache/, xdg_state/, state/, sandboxes/, platforms/,
│   │   hermes-agent/ (36 entries, likely vendored copy — not reconciled vs /opt),
│   │   bin/ (tirith, uv, uvx), kanban/ + kanban.db*
│   └── locks/state: auth.lock, gateway.lock/.pid, state.db* (sqlite WAL)
├── .claude/ (770) — agents/ (14 .md), skills/ (96), commands/, plugins/, sessions/, settings.json
├── .ccs/ (755)
│   ├── config.yaml (600, 11.9K), profiles.json — MISSING (never configured, see #2)
│   ├── instances/{lucas,ken}/ (700), .locks/, logs/ (current.jsonl + archive/)
│   ├── cache/update-check.json, completions/{bash,zsh,ps1,fish}
│   └── shared/ — 777 symlinks: skills, commands, settings.json, plugins, agents
│       (world-writable symlink perms — flagged, not verified as intentional)
├── .local/
│   ├── bin/: claude (ELF, 247MB), opencode (ELF, 167MB), codex/gemini/hermes
│   │   (bash wrappers), ccs/ck (symlinks → node_modules), ccs-codex/ccsd/ccs-droid/ccsx/ccsxp
│   └── lib/: node_modules/, google-gemini-cli-pkg/, openai-codex-pkg/
├── .config/ — opencode/ only
└── .claude.json (600), .claudekit/ (install-info + locks)

/opt/hermes-optimization-guide          — deployed source, HEAD 5b60fd4, clean, 1 commit
                                           behind this repo's HEAD (0cf76e7)

systemd: hermes.service (active), hermes-dashboard.service (active) — only 2 hermes* units
```

## Unresolved questions
- `ccs auth list` / `ccs cliproxy status` not checked — may be the actual mechanism the delegation flow needs instead of `ccs api`.
- Which provider/preset hermes's profile should use — business decision, not determined here.
- Whether `claude`/`opencode`/`codex`/`gemini` (not just `ccs`) also get invoked bare-name from inside hermes.service and hit the same PATH gap — only `claude` confirmed via absolute path in logs so far.
- `.ccs/shared/*` symlinks at `777` — intentional or a perms smell, not verified.
- `hermes-agent/` (36 entries under `.hermes/`) — unclear if vendored/duplicate source tree needing reconciliation with `/opt`.
