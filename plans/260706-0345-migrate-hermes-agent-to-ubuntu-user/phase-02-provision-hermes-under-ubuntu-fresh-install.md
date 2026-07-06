---
phase: 2
title: "Provision Hermes Under Ubuntu (Fresh Install)"
status: complete
priority: P1
effort: "30m"
dependencies: [1]
---

# Phase 2: Provision Hermes Under Ubuntu (Fresh Install)

## Overview

Install a fresh Hermes Agent under `ubuntu` via the same official installer command already
proven to work on this host (found in `ubuntu`'s own `bash_history`, run once on 2026-06-28
before the isolation pivot — it got as far as dropping the `/home/ubuntu/.local/bin/hermes`
launcher stub). Do **not** copy hermes's built `venv`/`node_modules` over — Python venvs embed
absolute shebang paths rooted at the old home and will not run from a new path. Do not start
any services yet; this phase only produces an inert, fully-installed-but-unconfigured
`/home/ubuntu/.hermes/`.

## Key Insights

- `/home/ubuntu/.local/bin/hermes` already exists and already points at
  `/home/ubuntu/.hermes/hermes-agent/venv/bin/hermes` — the installer just needs to populate
  that target path; the stub itself needs no changes.
- No `apt-get install` step is needed: `hermes-agent` has no playwright/puppeteer/chromium
  dependency, and the browser shared libs the dashboard's bundled UI assets might reference
  (`libnss3`, `libatk-bridge2.0-0t64`, `libgbm1`, `libxss1`) are already installed system-wide.
- `hermes-agent`'s runtime is a Python venv invoked via `hermes_cli.main` — the `node_modules`
  (1.1G) under `hermes-agent/` are frontend/dashboard build tooling, already pre-built; the
  installer handles this the same way it did for the `hermes` user.

## Related Code Files

- Create (host): `/home/ubuntu/.hermes/` (full installer output)
- No changes to files in this repo.

## Implementation Steps

1. **[AGENT]** Confirm the target is still clean (don't overwrite anything unexpectedly):
   ```bash
   test -d /home/ubuntu/.hermes && echo "ALREADY EXISTS - STOP, do not proceed" || echo "clean, safe to install"
   ```

2. **[AGENT]** Run the installer with `--skip-setup` — **critical, do not omit** (red-team
   finding: the plain `curl | bash` form runs `run_setup_wizard()` by default via `/dev/tty`,
   and if a messaging token is present it can trigger `maybe_start_gateway()`, which would start
   a SECOND live gateway polling the same Telegram bot token as the still-running `hermes`-user
   service — a `409 Conflict` incident during planning/provisioning, weeks before the intended
   cutover window):
   ```bash
   curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup
   ```
   Run this as `ubuntu` directly (you're already that user) — no `sudo -u` needed here, unlike
   the hermes-side steps. Do **not** run `hermes setup` or any onboarding wizard afterward;
   Phase 3 restores the real config over the installer's defaults.

3. **[AGENT]** Verify the install matches the hermes-user version (so restored config/state is compatible):
   ```bash
   /home/ubuntu/.local/bin/hermes --version
   sudo -u hermes bash -c 'hermes --version'
   ```
   These should match. If they don't, note the version delta — Phase 3's config diff step must
   account for any new/removed config keys introduced by a version difference.

4. **[AGENT]** Confirm the installer did not auto-start anything:
   ```bash
   systemctl list-units --all | grep -i hermes   # should still show ONLY the hermes-user units
   ps aux | grep '[h]ermes.*ubuntu'               # should be empty
   ```

## Success Criteria

- [x] `/home/ubuntu/.hermes/` exists with the same directory skeleton as `/home/hermes/.hermes/` (config.yaml, hermes-agent/, bin/, etc. — all installer defaults, not yet the real config). 72 bundled skills synced (will be overwritten by Phase 3's real skill copy).
- [x] `/home/ubuntu/.local/bin/hermes --version` runs successfully — v0.18.0 matches on both sides. Git commit delta investigated: hermes-side reported "+1 local carried commit" (88d1d620, a streaming empty/None-choices fix) due to its shallow clone diffing against no parent; verified via real diff (fetched true parent 76be770 from origin) it's only a 2-file/69-line change, attempted cherry-pick onto ubuntu's clone was empty (already equivalent), confirmed by direct code read at `agent/chat_completion_helpers.py:2043-2062` — same guard logic already present (landed upstream via a different commit, likely squashed into perf commit #59332). No action needed.
- [x] No new systemd units or running processes were created by this step — installation only, no activation. Only the pre-existing hermes-user units are active.

## Risk Assessment

- **Low risk with `--skip-setup`** — this creates new files under `/home/ubuntu` only; nothing existing is touched, and nothing is started. Fully reversible by `rm -rf /home/ubuntu/.hermes` if something goes wrong.
- **Without `--skip-setup`, this step is high-risk** (red-team finding, see step 2) — it can start
  a second live gateway against the production Telegram token before the planned cutover. If
  the flag is somehow unavailable in a future installer version, abort with Ctrl-C rather than
  filling in real credentials at any interactive prompt — Phase 3 handles all real secrets via
  restore, not fresh entry.

## Next Steps

Phase 3 restores real config/state on top of this fresh install and rewrites the paths that
still point at `/home/hermes/...`.
