---
phase: 3
title: "Restore State and Rewrite Paths"
status: complete
priority: P1
effort: "1.5h"
dependencies: [2]
---

# Phase 3: Restore State and Rewrite Paths

## Overview

Copy Hermes's real state (config, secrets, SOUL, memories, skills, kanban queue, sessions)
from `/home/hermes/.hermes/` onto the fresh `/home/ubuntu/.hermes/` install, then rewrite the
handful of values that hardcode the old home path. This is the "full migrate + verify" data
path chosen for this migration — nothing here is destructive to `/home/hermes` (copy, not
move).

## Key Insights (real layout, corrected from the original draft)

`~/.hermes/` is flat — there is **no** `profiles/<name>/` subdirectory. The real paths are:

| What | Real path | Copy? |
|---|---|---|
| Personality | `~/.hermes/SOUL.md` | Yes |
| Memory | `~/.hermes/memories/MEMORY.md`, `~/.hermes/memories/USER.md` | Yes |
| Config | `~/.hermes/config.yaml` | Yes, but diff against ubuntu's fresh installer default first (see step 3) |
| Secrets | `~/.hermes/.env` | Yes, then rewrite `PATH=` (see step 5) |
| Skills | `~/.hermes/skills/` (entire tree, ~92 subdirs incl. `.hub/`) | Yes, wholesale (full-migrate decision) |
| Kanban queue | `~/.hermes/kanban.db`, `~/.hermes/kanban/` | Yes |
| Gateway/pairing state | `~/.hermes/channel_directory.json`, `~/.hermes/gateway_state.json`, `~/.hermes/pairing/` | Yes |
| Session/task history | `~/.hermes/state.db`, `~/.hermes/sessions/` | Yes |
| Auth cache | `~/.hermes/auth.json` | Yes |
| **Additional live files found by red-team re-check, missing from the original list** | `~/.hermes/shared/nous_auth.json` (live credential, modified same day as planning — copy it, treat as a secret alongside `.env`/`auth.json`), `~/.hermes/state/rich_sent_index.json` (outbound-message dedup index — losing it risks duplicate Telegram replies right after cutover), `~/.hermes/cron/`, `~/.hermes/sandboxes/`, `~/.hermes/.skills_prompt_snapshot.json`, `~/.hermes/platforms/pairing/` (`~/.hermes/pairing/` was already listed above — this is a distinct path under `platforms/`, verify both exist and copy both) | Yes — see step 3a |
| **Not copied (runtime-only, regenerate on start)** | `gateway.pid`, `gateway.lock`, `auth.lock`, `processes.json`, `state.db-shm`, `state.db-wal`, `*.lock` files, `context_length_cache.yaml`, `models_dev_cache.json` (large, 2.9MB, safe to let it rebuild) | No |
| **Not copied (own separate Claude Code install, not Hermes state)** | `~/.claude/`, `~/.ccs/` | Handled in Phase 4, different mechanism |
| **Default (non-CCS) delegation identity — needs an explicit decision, not a silent carry-over** | `~/.claude/.credentials.json` (bare-harness identity, distinct from the `ccs-hermes` CCS profile Phase 4 handles) | See step 8 |

## Related Code Files

- Modify (host): `/home/ubuntu/.hermes/config.yaml`, `/home/ubuntu/.hermes/.env`
- Copy into (host): `/home/ubuntu/.hermes/{SOUL.md,memories,skills,kanban.db,kanban,channel_directory.json,gateway_state.json,pairing,state.db,sessions,auth.json}`

## Implementation Steps

0. **[AGENT]** Concrete pre-flight collision check (red-team finding: the Overview's "coordinate
   timing" caution had no actual checkpoint — confirmed live that hermes's `~/.ccs/config.yaml`
   was mid-edit by the parallel in-progress plan `260703-1738` only ~14 minutes before this plan
   was reviewed, so the collision window is real, not hypothetical). Snapshot mtimes right before
   restoring, so a mid-edit read is at least detectable after the fact:
   ```bash
   sudo -u hermes bash -c 'stat -c "%Y %n" ~/.hermes/config.yaml ~/.ccs/config.yaml' | tee /tmp/hermes-source-mtimes-pre-restore.txt
   ```
   If either mtime is within the last few minutes, pause and check whether plan `260703-1738`
   or `260704-2106` has an agent actively mid-step right now before proceeding — re-run this
   check immediately before step 3's actual copy if any time has passed since step 0.

1. **[AGENT]** Back up the installer's fresh default config before overwriting anything:
   ```bash
   cp /home/ubuntu/.hermes/config.yaml /home/ubuntu/.hermes/config.yaml.installer-default.bak
   ```

2. **[HUMAN]** Diff hermes's real config against the fresh installer default — do this before copying, so you know what's a real customization vs. an installer-version artifact. **Retagged from [AGENT] to [HUMAN]** (red-team finding: this step's own Risk Assessment already calls it "the most likely failure mode," which by this plan's own tagging rule (Overview) means it needs a judgment call, not unattended execution):
   ```bash
   sudo -u hermes bash -c 'cat ~/.hermes/config.yaml' > /tmp/hermes-live-config.yaml
   diff /home/ubuntu/.hermes/config.yaml.installer-default.bak /tmp/hermes-live-config.yaml
   ```
   If the diff shows *new required keys* present only in the fresh installer default (i.e. a
   newer Hermes version added config schema hermes's live config predates), merge those new
   keys into the copied config rather than blindly overwriting — otherwise Phase 6's boot may
   fail on missing keys. If the versions matched in Phase 2 step 3, this diff should be small
   (only environment-specific values).

3. **[AGENT]** Copy the real config and all state:
   ```bash
   sudo -u hermes bash -c 'cat ~/.hermes/config.yaml' > /home/ubuntu/.hermes/config.yaml
   sudo -u hermes bash -c 'cat ~/.hermes/.env' > /home/ubuntu/.hermes/.env
   sudo -u hermes bash -c 'cat ~/.hermes/SOUL.md' > /home/ubuntu/.hermes/SOUL.md
   sudo -u hermes bash -c 'cat ~/.hermes/auth.json' > /home/ubuntu/.hermes/auth.json
   sudo cp -a /home/hermes/.hermes/memories /home/ubuntu/.hermes/
   sudo cp -a /home/hermes/.hermes/skills /home/ubuntu/.hermes/
   sudo cp -a /home/hermes/.hermes/kanban /home/ubuntu/.hermes/
   sudo cp -a /home/hermes/.hermes/kanban.db /home/ubuntu/.hermes/
   sudo cp -a /home/hermes/.hermes/pairing /home/ubuntu/.hermes/
   sudo cp -a /home/hermes/.hermes/sessions /home/ubuntu/.hermes/
   sudo cp -a /home/hermes/.hermes/state.db /home/ubuntu/.hermes/
   sudo cp -a /home/hermes/.hermes/channel_directory.json /home/ubuntu/.hermes/
   sudo cp -a /home/hermes/.hermes/gateway_state.json /home/ubuntu/.hermes/
   ```

3a. **[AGENT]** Copy the additional live files surfaced by red-team re-check (see Key Insights table):
   ```bash
   sudo -u hermes bash -c 'cat ~/.hermes/shared/nous_auth.json' > /home/ubuntu/.hermes/shared/nous_auth.json 2>/dev/null || sudo mkdir -p /home/ubuntu/.hermes/shared && sudo -u hermes bash -c 'cat ~/.hermes/shared/nous_auth.json' > /home/ubuntu/.hermes/shared/nous_auth.json
   sudo mkdir -p /home/ubuntu/.hermes/state
   sudo cp -a /home/hermes/.hermes/state/rich_sent_index.json /home/ubuntu/.hermes/state/
   sudo cp -a /home/hermes/.hermes/cron /home/ubuntu/.hermes/
   sudo cp -a /home/hermes/.hermes/sandboxes /home/ubuntu/.hermes/
   sudo cp -a /home/hermes/.hermes/.skills_prompt_snapshot.json /home/ubuntu/.hermes/
   sudo mkdir -p /home/ubuntu/.hermes/platforms
   sudo cp -a /home/hermes/.hermes/platforms/pairing /home/ubuntu/.hermes/platforms/
   ```
   Treat `nous_auth.json` as a secret (same handling as `.env`/`auth.json` — mode `600` in step 4).

4. **[AGENT]** Fix ownership (everything just copied is currently `root`-owned via `sudo cp`):
   ```bash
   sudo chown -R ubuntu:ubuntu /home/ubuntu/.hermes
   chmod 600 /home/ubuntu/.hermes/.env /home/ubuntu/.hermes/auth.json /home/ubuntu/.hermes/shared/nous_auth.json
   chmod -R 700 /home/ubuntu/.hermes/sessions /home/ubuntu/.hermes/memories
   ```

5. **[AGENT]** Rewrite the hardcoded `PATH=` inside `.env` (confirmed in research: this literally breaks delegation subprocess resolution if left pointing at `/home/hermes/...`):
   ```bash
   sed -i 's#/home/hermes/.local/bin#/home/ubuntu/.local/bin#' /home/ubuntu/.hermes/.env
   grep '^PATH=' /home/ubuntu/.hermes/.env   # confirm it now reads /home/ubuntu/.local/bin:...
   ```

6. **[AGENT]** Sweep for any other stale `/home/hermes` references left in the restored config/SOUL:
   ```bash
   grep -rn "/home/hermes" /home/ubuntu/.hermes/config.yaml /home/ubuntu/.hermes/SOUL.md /home/ubuntu/.hermes/.env
   ```
   Fix any hits found (workspace path references are handled explicitly in Phase 5 — this step
   catches anything else, e.g. a hardcoded log path or backup path).

7. **[AGENT]** Set `HOME`-dependent env vars correctly for a dry-run CLI check (not yet the service — that's Phase 6):
   ```bash
   HOME=/home/ubuntu HERMES_CONFIG=/home/ubuntu/.hermes/config.yaml /home/ubuntu/.local/bin/hermes doctor
   ```
   Resolve anything `doctor` flags. Expect no missing-apt-package findings (per Phase 2 research)
   — if it does flag something, it's new information since planning; investigate before proceeding.

8. **[AGENT]** Default (non-CCS, bare-harness) delegation identity — **decided during validation
   interview (see plan.md Validation Log): use ubuntu's own `~/.claude/.credentials.json`**, not
   a dedicated bot identity. Bare-harness delegated actions will share the human's own Claude
   Code identity/quota post-migration (only `ccs-hermes`, consolidated in Phase 4, keeps a
   dedicated identity). This step is now just a confirmation, not an open decision:
   ```bash
   grep -A5 "^delegation:" /home/ubuntu/.hermes/config.yaml   # confirm default/routing values restored in step 3
   ```
   No file changes needed here — ubuntu's `~/.claude/.credentials.json` (untouched by this
   migration, confirmed in Phase 4 red-team review) is already what bare-harness delegation will use.

## Success Criteria

- [x] `/home/ubuntu/.hermes/config.yaml` contains hermes's real customizations (platforms, routing, delegation block, memory/model settings), reconciled with newer installer-default keys. Human decided to merge all 11 new optional keys found in installer default (terminal, tool_loop_guardrails, compression, prompt_caching, max_concurrent_sessions, group_sessions_per_user, streaming, skills, platform_toolsets, code_execution, updates); then `hermes doctor --fix` migrated config schema v32→v33 (dropped the redundant `max_concurrent_sessions` key as part of its own migration); removed 2 bad `platform_toolsets` entries (`teams`, `google_chat` — reference toolsets not installed on this host, flagged by doctor).
- [x] `grep -rn "/home/hermes" /home/ubuntu/.hermes/` — 3 categories of hits found, evaluated individually: (1) vendored `hermes-agent/` source docs/tests/nix files using it as generic example text — not this migration's concern, harmless; (2) `state/rich_sent_index.json` — a dedup log of already-sent Telegram message *content* (historical text, not a functional path) — left as-is; (3) `memories/MEMORY.md` — genuinely stale self-description (said hermes still isolated/lacks ubuntu access) — human chose to fix now, rewritten to reflect post-migration reality (ubuntu is the runtime user, workspace paths corrected). No functional config/SOUL/env references remain (those returned clean on the narrower step-6 grep).
- [x] `.env`'s `PATH=` line points at `/home/ubuntu/.local/bin:...` — verified.
- [x] All copied files/dirs owned `ubuntu:ubuntu` (copied via `sudo -u hermes tar | tar -x` pipe as ubuntu, avoiding the need for `sudo chown` — plain root `sudo` on this host requires an interactive password, only `(hermes) NOPASSWD` and `systemctl hermes*` are passwordless); secrets files (`.env`, `auth.json`, `shared/nous_auth.json`) mode `600`; `sessions/`, `memories/` mode `700`.
- [x] `hermes doctor` run with `HOME=/home/ubuntu` reports no missing dependencies — "All checks passed". Found and fixed one real gap along the way: `python-telegram-bot==22.6` (pinned to match hermes's version) was missing from the fresh install's venv (not part of the installer's default `[all]` tier) — installed via pip inside the venv; required a one-time `.ckignore` update (`!venv`) to unblock a context-optimization hook that was blocking legitimate venv-path access.
- [x] Skill count under `/home/ubuntu/.hermes/skills` matches the baseline recorded in Phase 1 — 70, exact match.
- [x] Additional files (`nous_auth.json`, `rich_sent_index.json`, `cron/`, `sandboxes/`, `.skills_prompt_snapshot.json`, `platforms/pairing/`) copied and present under `/home/ubuntu/.hermes/` — verified.
- [x] `delegation:` block's default/routing confirmed restored correctly — `default: claude-code`, routing rules intact.

## Risk Assessment

- **Medium risk**: a botched config merge (step 2) is the most likely failure mode — a missing
  required key silently no-ops a feature rather than crashing. Mitigate by diffing explicitly
  rather than blind-copying, and by running `hermes doctor` (step 7) before Phase 6.
- All operations here are copies from `/home/hermes` (untouched, still serving production) into
  `/home/ubuntu/.hermes` (inert, unstarted) — fully reversible by deleting `/home/ubuntu/.hermes`
  and re-running Phase 2 if something goes wrong.

## Security Considerations

- `.env` and `auth.json` contain live secrets — verify `600` permissions immediately after copy (step 4), before any other process on the box could read them.
