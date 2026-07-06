# Red-Team Fact-Check: Migrate Hermes Agent to Ubuntu User

Role: Security Adversary / Fact Checker. All findings below verified against live host
(`lucas-oracle-instance`) via read-only commands. Secrets redacted in output.

## Finding 1: New systemd units never grant write access to the workspace dir the whole migration is meant to unblock
- **Severity:** Critical
- **Location:** Phase 6, "Stage B — Cutover", step 4 (new unit `ReadWritePaths=`); cross-referenced with Phase 5 Success Criteria and Phase 7 Success Criteria ("original goal of this whole migration")
- **Flaw:** Phase 6's edited unit sets `ReadWritePaths=/home/ubuntu/.hermes /home/ubuntu/.ccs /tmp` — same pattern as today's unit, just s/hermes/ubuntu/, and still omits the workspace directory. `ProtectSystem=strict` makes the entire filesystem read-only except paths explicitly listed in `ReadWritePaths=`, and this restriction is a mount-namespace property inherited by every child process (including delegated coding-agent subprocesses), not just the top-level `hermes gateway run` process.
- **Failure scenario:** Post-cutover, any Hermes-delegated task that tries to write inside `/home/ubuntu/workspace/kitchen` or `/home/ubuntu/workspace/nfi` (edit a file, `git commit`, LFS checkout) fails with `Read-only file system`, identical to the failure already happening today. Phase 5's own stated goal ("Hermes-delegated actions in kitchen/nfi succeed without sudo or permission errors") and Phase 7's success criterion ("confirms the original goal of this whole migration was actually achieved") will both silently fail during Phase 7 verification, or worse, only surface later during a real delegated task after the 48h rollback window has already elapsed and Phase 8 destroyed the rollback path.
- **Evidence:**
  - Current unit file (`/etc/systemd/system/hermes.service`): `ReadWritePaths=/home/hermes/.hermes /home/hermes/.ccs /tmp` — no workspace path.
  - Live `journalctl -u hermes.service` (today, pre-migration):
    ```
    Jul 05 11:16:33 ... hermes[3591449]: WARNING agent.tool_executor: Tool terminal returned error ...
    "Error cleaning Git LFS object: open /home/hermes/workspace/nfi/.git/lfs/tmp/2381534180: read-only file system"
    Jul 05 21:59:48 ... hermes[3704959]: WARNING agent.tool_executor: Tool write_file returned error ...
    "Failed to write file: /usr/bin/bash: line 3: /home/hermes/workspace/nfi/plans/.hermes-tmp.3810427: Read-only file system"
    ```
    (Both are inside hermes's own home, owned by hermes, yet blocked — confirms the block is `ReadWritePaths`, not Unix perms.)
  - Phase 6's planned unit content (verbatim from phase-06 step 4): `ReadWritePaths=/home/ubuntu/.hermes /home/ubuntu/.ccs /tmp` — workspace absent.
  - Phase 5's verification step 4 only checks Unix ownership (`ls -la ... should show ubuntu:ubuntu ownership, already true — no chown needed`), never checks the systemd sandbox layer that is the actual blocker.
- **Suggested fix:** Add `/home/ubuntu/workspace` to `ReadWritePaths=` in the Phase 6 unit edit (both files if the dashboard ever shells out), and change Phase 5's verification step from an `ls -la` ownership check to an actual write test executed through the same systemd-sandboxed path (e.g. `sudo -u ubuntu systemd-run --uid=ubuntu -p ProtectSystem=strict -p ReadWritePaths=... touch /home/ubuntu/workspace/kitchen/.migration-write-test`, or simpler: trigger a real delegated write in Stage A before cutover).

## Finding 2: Phase 3's state-restore list omits several live files, including an uncatalogued credential file
- **Severity:** High
- **Location:** Phase 3, "Key Insights" table and step 3 (copy list)
- **Flaw:** The table claims to enumerate everything under `~/.hermes/` and copy it or explicitly document why not. The live directory has more entries than the table accounts for: `shared/nous_auth.json`, `state/rich_sent_index.json`, `cron/` (ticker heartbeat/last-success + job `output/`), `sandboxes/singularity/`, `.skills_prompt_snapshot.json`, `platforms/pairing/`. None of these appear in the "copy" column or the "not copied (runtime-only, regenerate on start)" column.
- **Failure scenario:** `shared/nous_auth.json` (2237 bytes, last modified today `Jul 6 02:00`, filename strongly implies a NousResearch platform auth/session credential given the installer domain `hermes-agent.nousresearch.com`) is not copied by Phase 3 and is also **absent from Phase 1's manual secrets-export list** (which only names `.env`, `.claude/.credentials.json`, `.ccs/.../.credentials.json`). If this file backs a live auth session (e.g., telemetry, update-check, or platform registration), the ubuntu-hosted instance boots without it post-cutover — either silently degrading a feature or requiring an undocumented re-auth during the live cutover window. `state/rich_sent_index.json` (29KB, modified `Jul 5 22:00`) looks like a sent-message dedup index; losing it risks duplicate message delivery to real Telegram users right after cutover.
- **Evidence:**
  ```
  -rw------- 1 hermes hermes  2237 Jul  6 02:00 shared/nous_auth.json   (recon: `ls -la ~/.hermes/shared/`)
  -rw-r--r-- 1 hermes hermes 29589 Jul  5 22:00 state/rich_sent_index.json (recon: `ls -la ~/.hermes/state/`)
  ```
  Phase 3 "Related Code Files" copy-into list: `{SOUL.md,memories,skills,kanban.db,kanban,channel_directory.json,gateway_state.json,pairing,state.db,sessions,auth.json}` — `shared/`, `state/` (the directory), `cron/`, `sandboxes/` not present.
- **Suggested fix:** Add a step 0 to Phase 3: `sudo -u hermes bash -c 'ls -la ~/.hermes/'` diffed explicitly against the copy list, so every top-level entry is accounted for (copy / regenerate / deliberately-skip-with-reason) instead of relying on a hand-curated table written during planning that has since drifted from the live host.

## Finding 3: Backup tarball and manual-secrets step create a window where live secrets are world-readable
- **Severity:** Medium
- **Location:** Phase 1, step 2 ("Full tarball backup") and "Security Considerations" (chmod 600)
- **Flaw:** `hermes`'s umask is `0002`, so `tar -czf /tmp/hermes-full-backup-260706.tar.gz ...` creates the file at mode `664` (world-readable) inside `/tmp`, which is `drwxrwxrwt` (world read+list, sticky only blocks deletion by others). The file sits there, containing `.env`, `.claude/.credentials.json`, and `.ccs/instances/ccs-hermes/.credentials.json` in plaintext inside the tar, until the subsequent `sudo mv` + `chown`. The `chmod 600` that finally locks it down is written only in the prose "Security Considerations" section at the bottom of the phase file, **not as a numbered Implementation Step** — an operator following the numbered steps literally (1→5) never runs it.
- **Failure scenario:** Any other local account with a usable shell that runs during that window could `cat /tmp/hermes-full-backup-260706.tar.gz` before the `mv`. On this host that risk is currently low (the only other uid-1000 account, `opc`, has shell `/usr/sbin/nologin` and has never logged in — verified via `getent passwd opc` and `lastlog -u opc`), but the plan should not rely on "no other interactive users exist today" as its security boundary, and the chmod 600 step being outside the numbered list means it's likely to be skipped even by the intended operator.
- **Evidence:**
  ```
  $ sudo -u hermes bash -c 'umask'
  0002
  $ ls -ld /tmp
  drwxrwxrwt 65 root root 36864 Jul  6 03:54 /tmp
  $ getent passwd opc
  opc:x:1000:1000::/home/opc:/usr/sbin/nologin
  ```
  Phase 1 file: chmod 600 command appears only under `## Security Considerations`, after `## Risk Assessment`, not under `## Implementation Steps` (steps 1-5).
- **Suggested fix:** Move the `chmod 600` into step 2 itself, immediately after the `mv`, and consider `umask 077` before the `tar` invocation so the file is never world-readable even momentarily in `/tmp`.

## Finding 4: Phase 4's "single ccs-hermes entry" success criterion doesn't account for the dead `accounts.ccs-hermes` entry left in hermes's own config
- **Severity:** Medium
- **Location:** Phase 4, step 6 and Success Criteria bullet 2
- **Flaw:** Step 6 explicitly leaves `hermes`'s `~/.ccs/config.yaml` `accounts.ccs-hermes` entry in place ("dead config ... optional... not worth a risky edit"), but Success Criteria bullet 2 claims "`/home/ubuntu/.ccs/config.yaml` has exactly one `ccs-hermes` entry ... no leftover placeholder" — true only for the ubuntu-side file, while a second, now-orphaned `accounts.ccs-hermes` block (referencing a directory that Phase 4 step 6 deletes: `/home/hermes/.ccs/instances/ccs-hermes`) persists on the hermes side for the entire 48h+ coexistence window. If anything on the hermes side (e.g. the still-running `260703-1738`/`260704-2106` parallel plans explicitly called out in the plan's Overview as "continuing in parallel") invokes `ccs ccs-hermes` against the hermes-side config during that window, it now points at a deleted instance dir instead of a stale-but-harmless placeholder, changing a previously inert reference into an active error path.
- **Evidence:** Phase 4 step 6: `sudo rm -rf /home/hermes/.ccs/instances/ccs-hermes` executes right after the smoke test, while hermes's `~/.ccs/config.yaml` accounts.ccs-hermes entry is explicitly left untouched (plan text: "Leave hermes's `~/.ccs/config.yaml` `accounts.ccs-hermes` entry as dead config"). Plan's own Overview states the two other in-progress plans "continue in parallel" against the hermes-user setup.
- **Suggested fix:** Either flag this explicitly as a known coordination risk with the parallel plans (the plan's Overview already has a "coordinate timing" caution for config reads — extend it to cover this write), or defer `rm -rf` of the hermes-side instance dir to Phase 8 (destructive cleanup phase) instead of Phase 4, since Phase 4 has no reason to delete hermes's copy immediately — the whole point of "copy not move" elsewhere in this plan is to keep a fallback until the 48h window closes.

## Finding 5: Phase 8's `userdel -r hermes` blast-radius claim is accurate but the plan never re-verifies it right before running
- **Severity:** Medium
- **Location:** Phase 8, "Key Insights" and step 3
- **Flaw:** The "zero files owned by hermes outside `/home/hermes`" claim is stated as a fact from planning-time research and is not re-run as a check immediately before `userdel -r hermes` in step 3's implementation steps — step 1's confirmation gate only checks the backup tarball, not blast radius. Given Phase 8 runs 48+ hours after Phase 4-7 (during which the two parallel in-progress plans, per the Overview, may still be actively touching `/home/hermes` or creating new files as hermes), the "confirmed clean" finding could be stale by the time `userdel -r hermes` actually executes.
- **Evidence:** Re-ran the check live during this review: `sudo find /tmp /var/tmp /var/log /opt /srv -user hermes` returned nothing, and `sudo -u hermes crontab -l` / `/etc/cron.d` grep also empty — so the claim holds **right now**, but Phase 8 step 1's gate doesn't re-run this specific check, only the tarball-integrity check.
- **Suggested fix:** Add `sudo find / -xdev -user hermes -not -path "/home/hermes/*" 2>/dev/null` as an explicit re-check inside Phase 8 step 1's confirmation gate, not just inside "Key Insights" prose describing planning-time research.

## Finding 6: `sudo -n -l` live output confirms Phase 8's sudoers claims are accurate, but ubuntu's pre-existing `(ALL:ALL) ALL` / docker+lxd group membership means the "isolation" this migration removes was already moot for privilege purposes
- **Severity:** Medium (informational risk — scopes expectations, not a plan bug per se)
- **Location:** Phase 8 Overview / Security framing across the whole plan
- **Flaw:** The plan frames this migration as retiring the `hermes` isolation boundary in favor of merging into `ubuntu`, but live `sudo -n -l` shows `ubuntu` already has `(ALL : ALL) ALL` and `(ALL) ALL` (full interactive root) plus `docker`/`lxd` group membership (both root-equivalent via container escape) — i.e., `ubuntu` was never a meaningfully lower-privilege account than root to begin with. The plan doesn't state this explicitly anywhere, which matters for the risk narrative: this migration is not "isolated bot account -> semi-privileged account," it's "isolated bot account -> account that already has unrestricted root." Worth having this stated plainly in the plan's security considerations rather than implied.
- **Evidence:**
  ```
  User ubuntu may run the following commands on lucas-oracle-instance:
      (ALL : ALL) ALL
      (ALL) ALL
      (hermes) NOPASSWD: ALL
      (root) NOPASSWD: /bin/systemctl start hermes*, ...
  $ groups ubuntu
  ubuntu adm cdrom sudo dip lxd ollama docker
  ```
- **Suggested fix:** Add one line to the plan's Overview or Phase 6 Security Considerations explicitly acknowledging that post-migration, a compromised Hermes process (e.g. via a malicious delegated task or a Telegram-borne prompt injection) runs as an account that is a `sudo`/`docker` group member away from full root, and that the `NoNewPrivileges=true` + capability-bounding-set systemd hardening is therefore the *only* remaining containment layer (no OS-user boundary backstops it anymore, unlike the current hermes-isolated setup).

## Unresolved Questions
- What does `~/.hermes/shared/nous_auth.json` actually authenticate (NousResearch platform account, update-check token, telemetry)? Could not determine from filename/size alone without reading its content (declined, contains a live credential). Planner should confirm with hermes-agent docs/source before deciding whether Phase 3 needs to copy it.
- Does `state/rich_sent_index.json` gate outbound message dedup, or is it purely inbound-processing state? Determines whether Finding 2's duplicate-message risk is real or cosmetic.
