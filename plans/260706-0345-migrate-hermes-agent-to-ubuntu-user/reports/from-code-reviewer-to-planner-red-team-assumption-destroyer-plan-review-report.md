# Red Team Review: Assumption Destroyer / Scope Auditor — Migrate Hermes to Ubuntu

Reviewed: plan.md + all 8 phase files. Role: Scope Auditor (state ownership/lifetime boundaries) with assigned probes on Phase 2/3/6 assumptions. All findings below are grep/live-host verified against the actual OCI box, not trusted from plan prose.

## Finding 1: Phase 2 install command is not actually inert — installer can auto-register secrets and start a live conflicting gateway
- **Severity:** Critical
- **Location:** Phase 2, section "Implementation Steps" step 2 (`curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash`)
- **Flaw:** Phase 2's Overview claims this step "only produces an inert, fully-installed-but-unconfigured `/home/ubuntu/.hermes/`" and step 2's own note says "Do not run `hermes setup`... afterward." But the command given does **not** pass `--skip-setup` or `--non-interactive`. I fetched and read the real installer (`/tmp/hermes-install.sh`, 3133 lines) run on this exact host. `run_setup_wizard()` runs by default whenever a tty is reachable (it explicitly opens `/dev/tty` even when piped via `curl | bash`, by design, specifically so `curl | bash` setup prompts work). If it runs and a human enters the real `TELEGRAM_BOT_TOKEN` (an easy mistake mid-migration, since Phase 3 hasn't happened yet so there's no reason to think it's "the same bot"), `maybe_start_gateway()` then detects the token in the just-written `.env`, and — defaulting to "yes" — calls `hermes gateway install` **and** `hermes gateway start`, creating and launching a second live systemd gateway that would poll the same Telegram bot token concurrently with the still-active `hermes`-user service.
- **Failure scenario:** Whoever runs Phase 2 interactively is prompted "Configure API keys and settings?" / "Would you like to install the gateway as a background service?" (default yes on both). If they answer normally (as a first-time install experience implies) instead of recognizing this as a migration step, a second `hermes.service`-equivalent starts polling `getUpdates` for the same bot token the still-running `hermes`-user service is polling → `409 Conflict` storms and possibly duplicate/dropped replies to real users, weeks before Phase 6's planned cutover window.
- **Evidence:**
  ```
  run_setup_wizard() {
    ...
    # Only skip if no terminal is available at all (e.g. Docker build, CI).
    if ! (: </dev/tty) 2>/dev/null; then ...; return 0; fi
    "$INSTALL_DIR/venv/bin/python" -m hermes_cli.main setup < /dev/tty
  }
  maybe_start_gateway() {
    ... for VAR in TELEGRAM_BOT_TOKEN ...; if [ -n "$VAL" ] ...; then HAS_MESSAGING=true
    if prompt_yes_no "Would you like to install the gateway as a background service?" "yes"; then
      $HERMES_CMD gateway install ...; $HERMES_CMD gateway start ...
  ```
  (from `/tmp/hermes-install.sh`, fetched live from `https://hermes-agent.nousresearch.com/install.sh`)
- **Suggested fix:** Change Phase 2 step 2's command to `curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup`, making "inert" a guaranteed property of the command instead of a prose warning that depends on the human noticing and Ctrl-C'ing a prompt in time.

## Finding 2: Phase 6's new ReadWritePaths carries forward a real, currently-occurring production bug — workspace writes will still fail post-cutover
- **Severity:** High
- **Location:** Phase 6, "Key Insights" / Stage B step 4 (unit file `ReadWritePaths=`); cross-referenced with Phase 5 success criteria
- **Flaw:** The plan's new unit file sets `ReadWritePaths=/home/ubuntu/.hermes /home/ubuntu/.ccs /tmp` — a straight `/home/hermes/...` → `/home/ubuntu/...` substitution of the *current* unit's `ReadWritePaths`. Neither the current nor the proposed value includes the workspace directory (`/home/hermes/workspace` today, `/home/ubuntu/workspace` after). I confirmed via `journalctl -u hermes.service` that this is already causing real production failures today, not a theoretical gap.
- **Failure scenario:** Post-cutover, Hermes delegates a coding task that writes into `/home/ubuntu/workspace/nfi` or `kitchen` (exactly the workflow Phase 5 exists to reconcile) → `ProtectSystem=strict` + `ProtectHome=read-only` + the narrow `ReadWritePaths` blocks the write → same class of failure as today, just with `/home/ubuntu` in the path instead of `/home/hermes`. Phase 5's own success criteria ("Hermes-delegated actions in kitchen/nfi succeed without sudo or permission errors, verified in Phase 7") will fail for a reason that has nothing to do with path reconciliation — the sandboxing boundary itself needs to grow, and nothing in Phases 3–6 does that.
- **Evidence:** live `journalctl -u hermes.service --no-pager` output (verified minutes before this report):
  ```
  Jul 05 11:16:33 ... hermes[3591449]: WARNING agent.tool_executor: Tool terminal returned error ...
    "Error cleaning Git LFS object: open /home/hermes/workspace/nfi/.git/lfs/tmp/2381534180: read-only file system"
  Jul 05 21:59:48 ... hermes[3704959]: WARNING agent.tool_executor: Tool write_file returned error ...
    "Failed to write file: ... /home/hermes/workspace/nfi/plans/.hermes-tmp.3810427: Read-only file system"
  Jul 02 08:19:53 ... hermes[3079223]: Gateway started with no connected platforms ... Telegram startup failed:
    [Errno 30] Read-only file system: '/home/hermes/.local/state/hermes'
  ```
  current unit file: `ReadWritePaths=/home/hermes/.hermes /home/hermes/.ccs /tmp` (no workspace, no `.local/state`).
- **Suggested fix:** Add `/home/ubuntu/workspace` (and confirm `.local/state/hermes` is actually redirected via `XDG_STATE_HOME`, since that's what already failed once in production per the Jul 02 log line above) to the new unit's `ReadWritePaths=` in Phase 6 step 4, and add an explicit Phase 7 verification step that performs a real write inside `/home/ubuntu/workspace/{kitchen,nfi}` through the actual systemd-run service (not a bare CLI call) — not just an `ls -la` ownership check as currently written.

## Finding 3: `hermes doctor` (Phase 3 step 7) cannot detect the systemd-sandbox class of failure found in Finding 2
- **Severity:** Medium
- **Location:** Phase 3, step 7 and Success Criteria ("`hermes doctor` run with `HOME=/home/ubuntu` reports no missing dependencies")
- **Flaw:** `doctor.py`'s checks (read from the real source: Python version, provider API keys via `_PROVIDER_ENV_HINTS`, SSL CA bundle, systemd *linger*, MCP stdio command safety, version-file consistency) never execute inside the actual hardened unit (`ProtectSystem=strict`, `ProtectHome=read-only`, `ReadWritePaths=`). It's invoked directly as `HOME=/home/ubuntu HERMES_CONFIG=... hermes doctor` from an unrestricted shell, so it has no way to observe that a real write to `/home/ubuntu/workspace` would be blocked once the process runs under the systemd unit. Phase 3's Success Criteria treats a clean `doctor` run as evidence the restore is sound; Finding 2 shows that class of failure exists in production today specifically because nothing exercises the sandbox boundary before cutover.
- **Failure scenario:** Phase 3 checks pass cleanly (doctor is happy), Phase 6 Stage A's dry-run (`hermes gateway run` invoked directly, also outside systemd) also passes, giving two false-green signals — the actual sandboxed `systemctl start` in Stage B is the first time the real `ReadWritePaths` boundary is exercised, i.e. during the live downtime window itself.
- **Evidence:** `hermes_cli/doctor.py` function list (`_check_version_consistency`, `_check_s6_supervision`, `check_certificates`, `_check_gateway_service_linger`, `managed_scope_check`, `_build_apikey_providers_list`) — no function references `ReadWritePaths`, `ProtectHome`, or performs a write-permission probe against workspace paths.
- **Suggested fix:** Add an explicit Stage A step in Phase 6 that starts the new unit (with Telegram still disabled via the scratch config) through actual `systemctl` against a throwaway unit name, and performs a real write into `/home/ubuntu/workspace/nfi` to prove the sandbox boundary is correct before Stage B's live cutover.

## Finding 4: Phase 1's "Full tarball backup" claim doesn't match what the tar command actually captures
- **Severity:** Medium
- **Location:** Phase 1, "Requirements" ("Full tarball backup of `.hermes`, `.claude`, `.ccs`, `.gitconfig`, `.codex`, `.gemini`, `workspace`.") and step 2's `tar` command
- **Flaw:** `/home/hermes`'s real top-level contents (verified via `ls -la`) also include `.claude.json` (31KB, Claude Code's own project/trust/session state file, separate from the `.claude/` directory), `.claudekit/`, `.config/`, `.npm/`, `.cache/`, `.local/`, `.bash_history`, `.bashrc`, `.profile` — none of which are in the `tar -C /home/hermes .hermes .claude .ccs .gitconfig .codex .gemini workspace` argument list. The phase calls this a "Full tarball backup" but it's actually a curated 7-item backup.
- **Failure scenario:** If Phase 7's rollback is ever needed and the issue traces back to something in `.claude.json` (e.g. project trust settings or MCP config Claude Code needs) or `.local` (contains `.local/bin` — the actual hermes launcher script `hermes` binary path — and `.local/state`, which Finding 2's evidence shows the gateway has needed writable before), the "full" backup doesn't have it, and by the time this is discovered `/home/hermes` may already be gone (post-Phase-8).
- **Evidence:**
  ```
  drwx------ 13 hermes hermes 4096 Jul  5 20:21 .
  -rw-------  1 hermes hermes 31235 Jul  5 20:21 .claude.json
  drwxrwxr-x  3 hermes hermes  4096 Jul  3 19:45 .claudekit
  drwxrwxr-x  4 hermes hermes  4096 Jul  4 20:46 .config
  drwxrwxr-x  6 hermes hermes  4096 Jul  3 19:45 .npm
  drwxrwxr-x  6 hermes hermes  4096 Jul  3 09:41 .local
  drwxrwxr-x 12 hermes hermes  4096 Jul  5 14:06 .cache
  ```
  (live `sudo -u hermes bash -c 'ls -la ~'` output) vs. Phase 1 step 2's tar arg list which omits all of the above.
- **Suggested fix:** Either tar the entire `/home/hermes` home directory (simplest, matches the "full" claim), or explicitly narrow the Requirements wording to name the actual 7 items backed up and document why the rest is considered disposable.

## Finding 5: Phase 4's manual edit to ubuntu's shared `~/.ccs/config.yaml` has no structural safety check beyond YAML syntax validity
- **Severity:** Medium
- **Location:** Phase 4, step 3 ("**[HUMAN]** Edit `/home/ubuntu/.ccs/config.yaml`... Validate YAML after editing: `python3 -c "import yaml; yaml.safe_load(...)" && echo VALID`")
- **Flaw:** `yaml.safe_load` only confirms the file parses as YAML — it says nothing about whether `ccs-hermes:` ended up correctly nested as a sibling key under `accounts:` at the right indent level next to `lucas`/`ken`/`luan` (verified live: those three are 2-space-indented children of `accounts:`, e.g. `  lucas:\n    created: ...`). A one-space indentation slip when hand-pasting the extracted block would still produce syntactically valid YAML (e.g. nested one level too deep under `luan:` as a new key, silently shadowing/merging into `luan`'s account block) and the `VALID` check would still print, because valid-YAML and correct-schema are different properties.
- **Failure scenario:** Human free-hand-edits the file (this is explicitly a `[HUMAN]` interactive step, not scripted), fat-fingers the indent, `ccs-hermes:` lands nested inside `luan:` instead of as its own top-level account. `yaml.safe_load` passes. The plan's own mitigation step ("smoke-test `ccs ken -p \"echo ok\"` afterward") would likely still pass since `ken`'s block is untouched, but `luan`'s block now silently has an extra unexpected key — not necessarily caught unless someone runs `ccs luan` specifically right after.
- **Evidence:** live `/home/ubuntu/.ccs/config.yaml`:
  ```
  accounts:
    lucas:
      created: "2026-06-28T16:52:21.045Z"
      ...
    ken:
      created: "2026-06-28T17:08:11.592Z"
      ...
    luan:
      created: "2026-07-03T08:02:40.719Z"
      ...
  ```
  (four 2-space-indented sibling blocks expected after the edit; nothing in Phase 4 checks the resulting structure programmatically, e.g. `python3 -c "import yaml; c=yaml.safe_load(open(...)); assert set(c['accounts']) == {'lucas','ken','luan','ccs-hermes'}"`).
- **Suggested fix:** Replace the free-hand edit + `safe_load` check with a small script that loads the YAML, asserts the exact expected top-level key set for `accounts:` (`{lucas, ken, luan, ccs-hermes}`) and `profiles:` (`{}`), and rewrites the file — removes the human-indentation risk on a file that also serves `ken`/`luan`/`lucas`.

## Finding 6: The plan's own "coordinate timing" caution about the two in-progress parallel plans is not just theoretical — verified live edits landed minutes before this plan's own research snapshot, with no concrete checkpoint mechanism
- **Severity:** Low-Medium
- **Location:** Overview, "This plan supersedes... does not cancel or block..." paragraph; Dependencies section
- **Flaw:** The plan tells the human to "coordinate timing" as prose guidance but defines no concrete check (e.g., "diff `stat -c %Y ~hermes/.ccs/config.yaml` immediately before Phase 1 step 2 against the value recorded during planning; abort if changed"). I verified live that `/home/hermes/.ccs/config.yaml` and `/home/hermes/.ccs/instances/ccs-hermes/` were last modified only ~14 minutes before this review, and that plan `260703-1738-fix-urgent-hermes-delegation-issues`'s overall status is still `in-progress` (its phase-03/phase-05 sub-files show `completed`, but the top-level plan isn't closed) — confirming the collision window described in the Overview is real and was, in fact, active minutes before this review, not a hypothetical edge case.
- **Failure scenario:** Someone runs Phase 1's backup or Phase 3's config-diff snapshot at the same moment `260703-1738`'s remaining work (or `260704-2106`, also in-progress) writes to `~/.ccs/config.yaml` or `~/.hermes/config.yaml` — the plan's own text acknowledges "restoring a mid-edit config" as the risk, but there's no automated guard, just a prose warning read once at plan-start time.
- **Evidence:**
  ```
  # this plan's own recon:
  /home/hermes/.ccs/config.yaml mtime: 1783309476 (2026-07-06 03:44:36 UTC)
  /home/hermes/.ccs/instances/ccs-hermes mtime: 1783309478 (2026-07-06 03:44:38 UTC)
  # this review's wall-clock time:
  Mon Jul  6 03:58:40 AM UTC 2026   →  844s (14 min) after the above mtimes
  ```
  `plans/260703-1738-fix-urgent-hermes-delegation-issues/plan.md:4: status: in-progress`
- **Suggested fix:** Add a one-line automated pre-check to Phase 1 step 1 that records and re-checks `stat -c %Y` on `~hermes/.hermes/config.yaml` and `~hermes/.ccs/config.yaml` immediately before the backup/diff steps in Phases 1 and 3, aborting with a clear message if either changed since the check was first run — rather than relying on the human remembering the prose caution.

## Unresolved Questions
- None of the above required user judgment calls to identify — all are grep/live-host verifiable. Flagging for the planner: Finding 1 (installer flag) is the one I'd block on before Phase 2 executes, since it's the only finding that risks live user-facing bot conflict *before* the planned cutover window even starts.
