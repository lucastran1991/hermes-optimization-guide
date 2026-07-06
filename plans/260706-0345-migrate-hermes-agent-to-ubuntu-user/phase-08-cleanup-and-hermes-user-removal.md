---
phase: 8
title: "Cleanup and Hermes User Removal"
status: pending
priority: P2
effort: "30m + explicit confirmation gate"
dependencies: [7]
---

# Phase 8: Cleanup and Hermes User Removal

## Overview

Destructive phase — only proceed after Phase 7's 48h+ rollback window has passed without
incident. Removes `/home/hermes` entirely (including the credential-duplication artifacts
identified in research), deletes the `hermes` OS user, and tidies the now-dead sudoers grant.

## Key Insights (blast radius, confirmed via research — this phase is safer than the original draft assumed)

- `sudo find / -user hermes -not -path "/home/hermes/*"` returned **nothing** — no files owned
  by `hermes` exist outside its home directory. `userdel -r hermes` cleanly removes everything.
- No cron entries reference `hermes` (`/etc/cron.d/` clean, hermes's own crontab is empty).
- The `(root) NOPASSWD: systemctl {start,stop,restart,status} hermes*` sudoers grant matches
  unit **names** (`hermes*`), not the OS user — it remains valid and useful after cutover
  (the units now run `User=ubuntu` but are still named `hermes.service`/`hermes-dashboard.service`).
  **Do not remove this grant.**
- The only sudoers line that becomes genuinely dead is `(hermes) NOPASSWD: ALL` — harmless to
  leave (references a user that will no longer exist) but worth removing for hygiene.

## Implementation Steps

1. **[HUMAN]** Final explicit confirmation gate — do not automate past this point. Confirm:
   - 48+ hours have passed since Phase 7's successful cutover.
   - No incidents observed in that window.
   - The Phase 1 backup tarball (`/home/ubuntu/hermes-full-backup-260706.tar.gz`) still exists, is archive-readable, AND its SQLite files aren't torn (red-team finding — `tar -tzf` alone only proves the archive is readable, not that a mid-write DB snapshot inside it is usable; this tarball is the last-resort rollback source, worth the extra check now).
   - The blast-radius claim from planning is re-verified live, not trusted from a 2+ day old snapshot (red-team finding — parallel plans `260703-1738`/`260704-2106` may have changed things under `/home/hermes` in the interim):
   ```bash
   ls -lh /home/ubuntu/hermes-full-backup-260706.tar.gz
   tar -tzf /home/ubuntu/hermes-full-backup-260706.tar.gz > /dev/null && echo "tarball readable"
   mkdir -p /tmp/hermes-backup-integrity-check && tar -xzf /home/ubuntu/hermes-full-backup-260706.tar.gz -C /tmp/hermes-backup-integrity-check .hermes/state.db .hermes/kanban.db
   sqlite3 /tmp/hermes-backup-integrity-check/.hermes/state.db "PRAGMA integrity_check;"
   sqlite3 /tmp/hermes-backup-integrity-check/.hermes/kanban.db "PRAGMA integrity_check;"
   rm -rf /tmp/hermes-backup-integrity-check   # both must print "ok"
   sudo find / -xdev -user hermes -not -path "/home/hermes/*" 2>/dev/null   # must be empty, same as at planning time
   ```

2. **[HUMAN]** Now do the deletion that Phase 4 deferred here specifically for rollback safety
   (red-team correction — see Phase 4 step 6): remove hermes's copy of the `ccs-hermes` CCS
   instance and its dangling config entry, since ubuntu's copy (consolidated in Phase 4) has
   been live and verified working for 48+ hours:
   ```bash
   sudo rm -rf /home/hermes/.ccs/instances/ccs-hermes
   ```
   Cleaning up the now-orphaned `accounts.ccs-hermes` entry in hermes's own `~/.ccs/config.yaml`
   is optional — that file is about to be destroyed wholesale by step 4's `userdel -r hermes`
   anyway, so a separate edit here has no functional benefit.

3. **[HUMAN]** Remove the old systemd unit backup file (superseded — the real backups are the tarball plus the two separate `.bak` unit files from Phase 1):
   ```bash
   sudo rm -f /etc/systemd/system/hermes.service.bak
   ```

4. **[HUMAN]** Delete the `hermes` user and its home directory (this also destroys the redundant `ken`/`luan`/`lucas` credential copies and the stale `nfi` clone identified in research — intentional, not a side effect to be surprised by):
   ```bash
   sudo pkill -u hermes 2>/dev/null   # ensure no lingering processes (services already stopped in Phase 6/7)
   sudo userdel -r hermes
   ```

5. **[HUMAN]** Clean up the now-dead sudoers line (use `visudo` or `visudo -f` on the specific sudoers.d file — never hand-edit `/etc/sudoers` directly):
   ```bash
   sudo visudo   # or: sudo visudo -f /etc/sudoers.d/<the-file-containing-this-grant>
   ```
   Remove only the `(hermes) NOPASSWD: ALL` line. **Leave** the
   `(root) NOPASSWD: /bin/systemctl {start,stop,restart,status} hermes*, ...` grant — it's still
   in active use for managing the (now ubuntu-run) `hermes*` units.

6. **[AGENT]** Verify the sudoers edit didn't break anything (a syntax error in sudoers can lock out `sudo` entirely — `visudo` should have caught this, but confirm):
   ```bash
   sudo -n -l
   ```

7. **[HUMAN, optional]** Clean up temporary migration artifacts once fully confident nothing further is needed:
   ```bash
   rm /tmp/hermes-live-config.yaml /tmp/hermes-ccs-config.yaml /tmp/hermes-config-dryrun.yaml /tmp/hermes-source-mtimes-pre-restore.txt 2>/dev/null
   # Keep /home/ubuntu/hermes-full-backup-260706.tar.gz for at least 30 days
   ```

8. **[HUMAN, optional]** If the `hermes` user had any GitHub/GitLab SSH keys registered under a "hermes" label for git operations, revoke them now (check `sudo find /home/hermes/.ssh` was already captured in the Phase 1 tarball before deletion — if such keys exist and are no longer needed, revoke via the git host's UI).

9. **[AGENT]** Add loud guards to the stale scripts — **decided during validation interview**
   (see plan.md Validation Log): guard-only, not a full rewrite, and not silence either. The
   following scripts hardcode `/home/hermes` and are now dead or host-mismatched post-migration:
   `scripts/provision-hermes-delegation/{0-gh-auth,1-claude-auth,2-ccs-profile,3-ccs-reuse-bridge,4-merge-delegation-config}.sh`,
   `scripts/vps-bootstrap.sh`, `scripts/vps-bootstrap-oci.sh`. They were designed to be
   independently re-runnable later (bot account rotation, fresh-host bootstrap per plan
   `260704-2106`'s own description), so a future re-run needs to fail loudly instead of silently
   targeting a nonexistent user or corrupting state. Add near the top of each script:
   ```bash
   if ! id hermes >/dev/null 2>&1; then
     echo "ERROR: hermes user no longer exists (migrated to ubuntu, see plans/260706-0345-migrate-hermes-agent-to-ubuntu-user/). This script targets the old hermes-user layout and is stale post-migration. Update it before use." >&2
     exit 1
   fi
   ```
   This is a mechanical, low-risk addition to 7 files — commit it as its own change, separate
   from any host-only migration step. The actual rewrite to target ubuntu-based paths is
   explicitly deferred to a future follow-up plan, not this one.

## Success Criteria

- [ ] Step 1's gate passed: tarball archive-readable AND `state.db`/`kanban.db` inside it pass `PRAGMA integrity_check` AND live blast-radius re-check still returns empty.
- [ ] `ccs-hermes` instance dir under `/home/hermes/.ccs/instances/` removed (step 2) only after 48h+ verified-working window, not earlier.
- [ ] `id hermes` returns "no such user" — user and home directory fully removed.
- [ ] `sudo -l` still shows the `(root) NOPASSWD: systemctl hermes*` grant intact; the `(hermes) NOPASSWD: ALL` line is gone.
- [ ] `hermes.service`/`hermes-dashboard.service` still `active (running)` under `User=ubuntu` — deleting the old user did not affect the already-cutover services (they no longer reference `/home/hermes` for anything).
- [ ] Backup tarball from Phase 1 retained for at least 30 days per the draft's original guidance.
- [ ] Loud `id hermes` guard added to all 7 stale scripts (step 9), committed as its own repo change.

## Risk Assessment

- **Destructive, irreversible after this point** — this is why the 48h gate (step 1) and the
  intact-tarball check exist. If step 1's conditions aren't met, do not proceed; extend the
  rollback window instead.
- Low technical risk otherwise: research confirmed a clean blast radius (no orphaned files,
  no cron/sudoers surprises beyond the one expected dead line).

## Next Steps

Step 9 above states the script-staleness fact explicitly rather than leaving it implicit.
Beyond that: optionally revisit `260703-1738-fix-urgent-hermes-delegation-issues` and
`260704-2106-bootstrap-script-delegation-provisioning-scripts` to mark them explicitly
superseded/closed now that the `hermes`-user architecture they were built for no longer exists
(left as a separate decision for the user, not automated by this plan per the "keep both running
in parallel, decide later" choice made during scope challenge).
