---
phase: 1
title: "Pre-Migration Backup and Baseline"
status: complete
priority: P1
effort: "1h"
dependencies: []
---

# Phase 1: Pre-Migration Backup and Baseline

## Overview

Back up the entire `/home/hermes` state before touching anything, and capture a "known-good"
baseline (bot responds, memory recall works, queue is idle) so Phase 7's verification has
something concrete to diff against. Nothing in this phase is destructive or user-visible.

## Requirements

- Full tarball backup of `.hermes`, `.claude`, `.ccs`, `.gitconfig`, `.codex`, `.gemini`, `workspace`.
- Secrets extracted separately (defense in depth — don't rely solely on the tarball).
- Current systemd unit content, sudoers grant, and crontab snapshotted to plain files.
- A written baseline of bot behavior to compare against post-cutover.

## Related Code Files

- Create: `/home/ubuntu/hermes-full-backup-260706.tar.gz` (host artifact, not in this repo)
- Create: `/home/ubuntu/hermes-old-hermes.service-260706.bak`, `/home/ubuntu/hermes-old-hermes-dashboard.service-260706.bak`, `/home/ubuntu/hermes-old-sudoers-snapshot-260706.txt` (host artifacts)

## Implementation Steps

1. **[AGENT]** Confirm current state one more time immediately before backing up (things may have changed since planning):
   ```bash
   systemctl is-active hermes.service hermes-dashboard.service
   sudo -u hermes bash -c 'cat ~/.hermes/kanban/.dispatcher.lock; ls ~/.hermes/kanban.db.*.lock 2>/dev/null'
   ```
   Confirm both services are `active` and the kanban dispatcher lock is empty (idle queue) before backing up — a backup taken mid-task-execution is still fine (state is file-based), but note actual status here.

2. **[AGENT]** Full tarball backup, readable by ubuntu only (red-team finding: the original
   list omitted `.claude.json`, `.claudekit/`, `.config/`, `.local/` which all exist under
   `/home/hermes` and are needed for a genuinely full rollback copy; `.npm`/`.cache` are
   disposable caches, deliberately excluded). Also fixed: the previous version left a window
   where the tarball sat world-readable (mode 664, hermes's `umask 0002`) in the world-listable
   `/tmp` before being chmod'd — `umask 077` closes that at creation time instead of after:
   ```bash
   sudo -u hermes bash -c '(umask 077 && tar -czf /tmp/hermes-full-backup-260706.tar.gz -C /home/hermes .hermes .claude .claude.json .claudekit .config .local .ccs .gitconfig .codex .gemini workspace 2>/dev/null)'
   sudo mv /tmp/hermes-full-backup-260706.tar.gz /home/ubuntu/
   sudo chown ubuntu:ubuntu /home/ubuntu/hermes-full-backup-260706.tar.gz
   chmod 600 /home/ubuntu/hermes-full-backup-260706.tar.gz
   ls -lh /home/ubuntu/hermes-full-backup-260706.tar.gz   # expect ~2.9G+ uncompressed, less after gzip
   ```

3. **[HUMAN]** Export secrets to a password manager separately (do not just trust the tarball):
   ```bash
   sudo -u hermes bash -c 'cat ~/.hermes/.env'
   sudo -u hermes bash -c 'cat ~/.claude/.credentials.json'
   sudo -u hermes bash -c 'cat ~/.ccs/instances/ccs-hermes/.credentials.json'
   ```
   Copy `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ADMIN_BOT_TOKEN`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, and both OAuth credential blobs into your password manager now.

4. **[AGENT]** Snapshot systemd units as two SEPARATE, directly-installable files — not one
   concatenated `.txt` (red-team finding: a concatenated file can't be `install`ed directly
   during a Phase 7 rollback under time pressure; the rollback step must not require a manual
   split-or-choose-template decision mid-incident). Also snapshot sudoers-visible grants
   (sudoers.d itself is root-only-readable, so snapshot what `sudo -l` shows instead):
   ```bash
   cat /etc/systemd/system/hermes.service > /home/ubuntu/hermes-old-hermes.service-260706.bak
   cat /etc/systemd/system/hermes-dashboard.service > /home/ubuntu/hermes-old-hermes-dashboard.service-260706.bak
   sudo -n -l > /home/ubuntu/hermes-old-sudoers-snapshot-260706.txt 2>&1
   sudo -u hermes crontab -l > /home/ubuntu/hermes-old-crontab-260706.txt 2>&1  # expect empty/no crontab for hermes
   ```
   These two `.bak` files are the ones Phase 7's rollback procedure installs directly — do not
   rely on `git log templates/systemd/` as a rollback source; red-team confirmed the repo's
   template already diverges from the live production unit (extra `Environment=PATH=...` block,
   different `ReadWritePaths`), so it is not a safe rollback substitute.

5. **[HUMAN]** Record a baseline functional check (write results into this phase file's Success Criteria checklist below, don't just check the box blind):
   - Send a real message to the Hermes Telegram bot, confirm it responds normally.
   - Ask it something that requires recalling `~/.hermes/memories/MEMORY.md` content, confirm it recalls correctly.
   - Note current skill count: `sudo -u hermes bash -c 'find ~/.hermes/skills -mindepth 2 -maxdepth 2 -type d | wc -l'`.

## Success Criteria

- [x] Tarball backup exists at `/home/ubuntu/hermes-full-backup-260706.tar.gz`, mode `600` (verified: `-rw------- ubuntu ubuntu 1316627921 bytes`), includes `.claude.json`/`.claudekit`/`.config`/`.local` in addition to the originally-listed dirs. Note: `tar` exited 1 (non-fatal — expected, live SQLite files changed during read, per Risk Assessment below). Note: step 2's `sudo mv`/`sudo chown` required an interactive root password — ubuntu's sudoers only has `NOPASSWD` for `(hermes) ALL` and `systemctl hermes*`, not blanket root; done manually by human.
- [x] Secrets (`.env` values, both `.credentials.json` files) copied into password manager. — confirmed by human.
- [x] Both systemd units backed up as separate, directly-installable files (`hermes-old-hermes.service-260706.bak` 1343 bytes, `hermes-old-hermes-dashboard.service-260706.bak` 1343 bytes) — not a concatenated `.txt`. Read directly (world-readable, no sudo needed).
- [x] `sudo -n -l` output (549 bytes) and crontab (`no crontab for hermes`) snapshotted to `/home/ubuntu/hermes-old-*-260706.txt`.
- [x] Baseline functional check done: bot responded normally and correctly recalled prior session's technical detail (coding-agent-delegate background-mode test history) — stronger evidence than a simple MEMORY.md fact-recall. Skill count: 70.

## Risk Assessment

- **Low risk overall** — read-only except for writing new files under `/home/ubuntu` and `/tmp`; nothing under `/home/hermes` is modified.
- Tarball read of live SQLite files (`kanban.db`, `state.db`) while the service is running could capture a mid-write snapshot — acceptable here since Phase 3 restores actual state from a live re-copy at cutover time, not from this tarball (this tarball is the *rollback* copy, not the migration source).

## Security Considerations

- The tarball contains real secrets (API keys, OAuth tokens, Telegram bot token). Step 2 now
  creates it with `umask 077` and chmods it `600` immediately after `mv` — closing the
  red-team-flagged window where it briefly sat world-readable in `/tmp`.
- Do not commit this tarball or any of the snapshot `.bak`/`.txt` files to git.
