# Red-Team Review: Failure Mode Analyst — Fix Urgent Hermes Delegation Issues

Reviewer role: Flow Tracer (verify behavioral/causality claims against actual host + repo state). All findings below are backed by live read-only verification on lucas-oracle-instance (NOPASSWD `sudo -u hermes`, `systemctl {start,stop,restart,status} hermes*`, `daemon-reload`, `journalctl -u/-k hermes*`) or repo grep/diff. No mutating command was run against `hermes.service`, `hermes-dashboard.service`, or any hermes-owned state; the one live experiment (systemd namespace behavior) used a disposable `--user`-scope transient unit under the `ubuntu` account, fully isolated from hermes.

One hypothesis I investigated and **disproved** (noting for transparency, not as a finding): I suspected Phase 2's `ReadWritePaths=/home/hermes/.hermes /home/hermes/.ccs /tmp` (line 45) might fail unit start or silently no-op if `/home/hermes/.ccs` doesn't yet exist (confirmed currently absent). Empirical test (`systemd-run --user`, disposable path, race-created mid-run) showed the unit starts fine AND a directory created *after* the sandboxed process starts becomes visible/writable inside it without a restart. I'm flagging the residual uncertainty (system-level `User=hermes` unit vs. my `--user`-scope test may differ in namespace privilege) but am not filing this as a finding since my own evidence contradicts the failure hypothesis.

## Finding 1: Phase 2's "[AGENT] Verify (all NOPASSWD)" claim is factually false for half its checks

- **Severity:** Critical
- **Location:** Phase 2, section "Implementation Steps" step 3 (`phase-02-deploy-p0-systemd-fix.md:51-56`), also asserted at line 26 ("`systemctl show`/`status`/`restart hermes*`, `daemon-reload`, `journalctl -u/-k` are NOPASSWD → `[AGENT]` verification")
- **Flaw:** The plan labels the entire post-deploy verification block `[AGENT]` and explicitly parenthesizes "(all NOPASSWD)". Three of its six checks are not covered by the actual sudoers grant.
- **Failure scenario:** An autonomous `/ck:cook --parallel` agent (no TTY, no password) executes Phase 2 step 3 verbatim. `systemctl show hermes.service -p SystemCallFilter`, `systemctl show hermes.service -p ReadWritePaths`, and `journalctl -k --since "<ts>"` each hit a sudo password prompt and fail non-interactively — the agent cannot confirm the two most important facts (filter re-allow landed, RW path landed) using the commands the plan tells it to use. It either reports false success (skipping the failed checks) or blocks needing a human, contradicting the phase's own `[AGENT]` designation.
- **Evidence:**
  ```
  $ sudo -n -l
  User ubuntu may run the following commands on lucas-oracle-instance:
      (hermes) NOPASSWD: ALL
      (root) NOPASSWD: /bin/systemctl start hermes*, /bin/systemctl stop hermes*,
          /bin/systemctl restart hermes*, /bin/systemctl status hermes*,
          /bin/systemctl daemon-reload, /usr/bin/journalctl -u hermes*

  $ sudo systemctl show hermes.service -p ReadWritePaths -p SystemCallFilter
  sudo: a terminal is required to read the password; either use the -S option ...

  $ sudo -n journalctl -k -n 5
  sudo: a password is required
  ```
  `show` is a different subcommand than `status` and isn't matched by `/bin/systemctl status hermes*`; `-k` is a different flag than `-u hermes*` and isn't matched by `/usr/bin/journalctl -u hermes*`. Only `sudo systemctl status hermes.service`, `journalctl -u hermes -n 50`, and `sudo -u hermes claude/opencode --version` (bullets 3-5 of the six) are genuinely NOPASSWD.
- **Suggested fix:** Replace `systemctl show -p X` with `systemctl cat hermes.service | grep X` (the installed unit is 0644 world-readable — Phase 1 itself notes this — so plain `cat`/`grep`, no sudo, works) or `systemctl status hermes.service` output parsing. Drop the `journalctl -k` check from the `[AGENT]` list or explicitly re-tag it `[HUMAN]`.

## Finding 2: Rollback procedure omits `systemctl reset-failed` — fails exactly when needed most (StartLimitBurst=5)

- **Severity:** Critical
- **Location:** Phase 2, section "Rollback" (`phase-02-deploy-p0-systemd-fix.md:86`); unit directives at `templates/systemd/hermes.service:21-22`
- **Flaw:** The template sets `StartLimitInterval=300` / `StartLimitBurst=5` (5 restart attempts per 5 min). If the deploy triggers *any* crash loop — related or not to the seccomp fix (e.g. a typo in a hand-edited unit, a permissions issue) — systemd stops permitting starts once the burst is hit, and this state is **independent of which unit file is currently on disk**. The documented rollback command chain doesn't clear it.
- **Failure scenario:** Deploy causes 5 crash/restart cycles within 5 minutes → unit enters `failed (Result: start-limit-hit)` → human runs the documented rollback (`cp .bak && daemon-reload && restart`) → the final `systemctl restart hermes.service` is refused ("start request repeated too quickly") because the start-limit counter was never reset → service stays down → the plan gives no indication this is even possible, so the human has no next step documented.
- **Evidence:**
  ```
  $ man systemd.unit | grep -A20 StartLimitIntervalSec=
  Note that units which are configured for Restart=, and which reach
  the start limit are not attempted to be restarted anymore; however,
  they may still be restarted manually or from a timer or socket at a
  later point, after the interval has passed. ... systemctl reset-failed will [reset the counter]

  $ man systemctl | grep -A10 "reset-failed \[PATTERN"
  ... if a unit's start limit (as configured with StartLimitIntervalSec=/StartLimitBurst=)
  is hit and the unit refuses to be started again, use this command to make it startable again.
  ```
  Also confirmed `reset-failed` is absent from the NOPASSWD grant (Finding 1's `sudo -n -l` dump) — even if an agent tried to self-heal, it can't; only a human with their full sudo password can.
- **Suggested fix:** Add `sudo systemctl reset-failed hermes.service` as the first command in the rollback chain (idempotent/harmless if the limit wasn't hit), and add a Risk Assessment row for "start-limit-hit strands the rollback."

## Finding 3: Phase 6's "true completion gate" has a mechanism-free, self-defeating fallback that will fire in exactly the run mode this plan targets

- **Severity:** High
- **Location:** Phase 6, section "Implementation Steps" step 1 (`phase-06-integration-verification-and-docs.md:48`), contradicting its own "Key Insights" (`:25`)
- **Flaw:** Key Insights states plainly: "A plain-shell pass does not prove the sandboxed service path works... The true gate is a real bot delegation." Step 1 then defines the primary path as `[HUMAN preferred]` triggering a task "via the bot (Telegram / admin panel)" — no bot command, chat ID, script, or API call is specified, just "confirm it completes" with no defined completion signal. It then offers an `[AGENT]` fallback that is verbatim the thing Key Insights just said is insufficient: "re-run the plain-shell checks from Phases 2/3/5."
- **Failure scenario:** This plan is explicitly a `--parallel` `/ck:cook` plan (per the brief). An autonomous agent executing Phase 6 has no Telegram client, no admin-panel session, and no defined API to hit — "isn't practical at execution time" is true by default for a headless agent, not an edge case. The agent takes the documented fallback, re-runs the Phase 2/3/5 shell proxies (which never exercise `ProtectHome=read-only`/`ReadWritePaths` for the actual sandboxed process), and reports Phase 6 (and thus the whole plan) DONE having verified nothing beyond what Phases 2/3/5 already verified individually. The one thing Phase 6 exists to catch — a sandbox-only failure — goes uncaught, silently.
- **Evidence:** Quoted above; also Phase 5's own smoke test (`ccs ccs-hermes -p "echo ok" ...`) and Phase 3's auth check both run via `sudo -u hermes bash -c '...'` (plain shell, not the systemd unit) per those phases' own Architecture sections — so "Phases 2/3/5 checks" really are 100% plain-shell, confirming the fallback is a strict subset of already-completed work, not new verification.
- **Suggested fix:** Define a concrete agent-executable mechanism (e.g., a documented Hermes admin CLI/API endpoint or a specific Telegram bot command + chat ID the agent can hit non-interactively) as the actual primary path, or explicitly mark step 1 `[HUMAN]`-only (no agent fallback) so `/ck:cook --parallel` blocks on it rather than silently downgrading.

## Finding 4: Phase 2's fix doesn't cover `~/.npm` — a live, currently-reproducing sandbox failure that can sink Phase 6's real-task gate for an unrelated reason

- **Severity:** High
- **Location:** Phase 2 Requirements/Architecture (`phase-02-deploy-p0-systemd-fix.md:29-35`); `templates/systemd/hermes.service:45`
- **Flaw:** The new `ReadWritePaths=/home/hermes/.hermes /home/hermes/.ccs /tmp` still excludes `/home/hermes/.npm` (npm's cache dir; confirmed via `npm config get cache` → `/home/hermes/.npm`, no `.npmrc` override). Under `ProtectHome=read-only`, any `npm install`/`npm ci`/`npm test`-with-install-step run *by the sandboxed service itself* (not a delegated child's target repo alone — the global npm cache is shared) still hits EROFS after Phase 2 deploys.
- **Failure scenario:** This is not hypothetical — it already happened today, live, under the *current* (unfixed) unit:
  ```
  Jul 03 09:48:43 ... hermes[3276211]: WARNING agent.tool_executor: Tool terminal returned error (1.18s):
  {"output": "npm error code EROFS\nnpm error syscall open\nnpm error path /home/hermes/.npm/_cacache/tmp/cf0bc129\nnpm error errno EROFS ..."}
  ```
  Phase 2's fix only re-allows the `sched_setscheduler` syscall and widens RW to `.ccs` — neither touches this. Phase 6's "real `/delegate_code` task" (the plan's stated completion gate) has a realistic chance of failing on this exact, still-unfixed EROFS wall if the delegated coding task needs any dependency install — a failure the plan will misattribute to "the fix didn't work" when it's an entirely separate, pre-existing, un-scoped gap.
- **Evidence:** Live journalctl excerpt above; `grep -n ReadWritePaths templates/systemd/hermes.service` → line 45, no `.npm` entry; confirmed npm cache path via `sudo -u hermes npm config get cache` → `/home/hermes/.npm`.
- **Suggested fix:** At minimum, flag this as a known-unfixed gap in Phase 2's Security Considerations / Phase 6's Risk Assessment (it already has a similar entry for layer-4b state writes — this is the same class of issue, already reproducing, not "untested"). Consider adding `/home/hermes/.npm` to `ReadWritePaths` or redirecting `npm_config_cache` under `.hermes/` (same pattern as the `XDG_STATE_HOME` workaround at line 31).

## Finding 5: No in-flight-task check before Phase 2's restart; the "~5s downtime" estimate has no config backing and an unaddressed tail risk

- **Severity:** High
- **Location:** Phase 2 Overview (`phase-02-deploy-p0-systemd-fix.md:20`), Risk Assessment (`:76`); `plan.md:78`
- **Flaw:** The plan states "~5s of bot downtime on restart" as if it were a guaranteed bound, and its only mitigation for "restart downtime surprises users" is "announce ~5s downtime; run off-peak if practical" — no check for whether the gateway is mid-task before pulling the trigger.
- **Failure scenario:** The unit sets no `TimeoutStopSec=`, so the systemd-wide default applies (`/etc/systemd/system.conf`: `#DefaultTimeoutStopSec=90s`, i.e. 90s is the compiled-in default). Live logs from today show the gateway routinely runs long blocking tool calls — `Tool terminal returned error (30.28s): {"output": "[Command timed out after 30s]"...}` at 10:59:42, and multi-second tool_executor calls throughout the day. If `systemctl restart` lands mid-tool-call, worst case is up to 90s (not 5s) before SIGKILL, and whatever the in-flight Telegram/task state was doing gets cut mid-way with no documented recovery. The empirical fast case *is* real (one observed restart today went `Stopping...09:41:16` → `Started...09:41:18`, ~2s) but that instance happened to catch the process idle — nothing in the plan guarantees Phase 2's restart will get so lucky.
- **Evidence:**
  ```
  $ grep -i timeout templates/systemd/hermes.service   # (none — no override)
  $ grep TimeoutStopSec /etc/systemd/system.conf
  #DefaultTimeoutStopSec=90s
  $ sudo journalctl -u hermes.service --since "2026-07-03 10:59:00" --until "2026-07-03 11:00:00"
  ... Tool terminal returned error (30.28s): {"output": "[Command timed out after 30s]", "exit_code": 124 ...}
  ```
- **Suggested fix:** Add a pre-restart check (e.g., poll a "gateway busy" indicator if one exists, or simply check `journalctl -u hermes -n 5 --since "-30s"` for recent tool-executor activity) and note the 90s worst-case explicitly rather than asserting "~5s" as fact.

## Finding 6: Phase 5's claimed dependency on Phase 2's `ReadWritePaths` is a category error, and isn't in the dependency graph anyway

- **Severity:** Medium
- **Location:** Phase 5, "Key Insights" (`phase-05-provision-ccs-profile.md:28`) and Risk Assessment (`:66`); contrast with `plan.md`'s dependency table (`5 | 4 | B`, no `2` listed)
- **Flaw:** Phase 5 states "`ReadWritePaths=/home/hermes/.ccs` must be live for the profile's state to persist — Phase 2's deploy already lands it; re-confirm there," and its risk table tells a debugger to "verify `ReadWritePaths` includes `/home/hermes/.ccs`" if the smoke test fails. But both the `ccs api create` step and the smoke test run via `sudo -u hermes bash -c '...'` — a plain shell, not the systemd-sandboxed `hermes gateway run` process. Per the plan's own findings (`research/live-host-verification-findings.md:15`, restated in Phase 3's Key Insights): "Only `hermes gateway run` (the service) is sandboxed; a plain `sudo -u hermes` shell is not." `ReadWritePaths=`/`ProtectHome=` are systemd unit sandboxing directives that only constrain processes systemd itself spawns for that unit — they have zero effect on an interactively-invoked `sudo -u hermes bash -c` process.
- **Failure scenario:** Not a hard blocker (Phase 5's steps will succeed via normal DAC permissions regardless of Phase 2's status), but two real consequences: (a) the dependency table doesn't list Phase 2 as a blocker for 5, yet Phase 5's own prose implies a same-phase ordering requirement that doesn't actually exist for its own steps — inconsistent internal documentation; (b) if the smoke test fails for an unrelated reason (bad preset, wrong key, wizard bug), the documented debugging step points at `ReadWritePaths`, a setting that is provably irrelevant to a plain-shell invocation — wasted debugging effort chasing the wrong layer.
- **Evidence:** `phase-05-provision-ccs-profile.md:36` Architecture: `` `[HUMAN]` `ccs api create ccs-hermes --preset <p>` ... `` and `:46` step 3: `` sudo -u hermes bash -c 'export PATH=...; ccs ccs-hermes -p "echo ok" ...' `` — both plain-shell forms; `research/live-host-verification-findings.md:15` confirms the sandboxing/plain-shell split.
- **Suggested fix:** Correct Phase 5's Key Insight to state the RW path matters for Phase 6's *sandboxed* delegation, not for Phase 5's own provisioning; move the "must be live" language to Phase 6 where it actually applies.

## Finding 7: The plan's concurrency model only considers two humans — the live bot is already a third, uncontrolled actor probing the exact same surface

- **Severity:** Medium
- **Location:** Plan-wide gap; closest explicit treatment is `plan.md:76-80` "Execution Strategy" (frames Phase 2 as independent/ASAP, no mention of the live gateway's own tool-execution loop as a concurrent writer)
- **Flaw:** I checked the specific scenario posed — "two humans run Phase 2 and Phase 5's `[HUMAN]` steps at the literally same time" — and traced it fully: Phase 2's `install`/`daemon-reload`/`restart` never touches `/home/hermes/.ccs` (confirmed via `diff` against the template, and functionally `daemon-reload` only reparses unit files), so the two named humans genuinely don't collide. But the plan never considers the actual live actor that does share Phases 3/4/5's exact file targets (`~/.local`, `~/.npm`, `~/.claude`, `~/.ccs`, and the `ccs`/`claude`/`ck` binaries themselves): **the running Hermes gateway's own agentic tool_executor**, which already has Bash/terminal tool access and is demonstrably already trying to invoke the very tools this plan is mid-installing.
- **Failure scenario:** If a real user (or the bot's own multi-turn planning) issues a `/delegate_code ... harness=ccs` request while Phase 4's `npm install -g --prefix "$HOME/.local" @kaitranntt/ccs@8.7.0` is mid-flight, or before Phase 5's `ccs api create` has run, the live invocation hits a half-installed binary or a nonexistent profile — an unhandled, foreseeable transient the plan doesn't mention as an expected side effect of the rollout window. `harness: ccs`'s "no automatic fallback to bare on failure, opt in only after smoke-test passes" (`SKILL.md:48`) is a **documentation-level** policy, not a code-enforced gate as far as anything in this repo shows (the actual gateway/`hermes-agent` is an external project) — nothing stops a live request from specifying `harness=ccs` mid-rollout.
- **Evidence:**
  ```
  Jul 03 12:21:14 ... hermes[3276211]: WARNING agent.tool_executor: Tool terminal returned error (0.23s):
  {"output": "/usr/bin/bash: line 3: 3348570 Bad system call (core dumped) /home/hermes/.local/bin/claude --version", "exit_code": 159...}
  Jul 03 12:22:28 ... hermes[3276211]: WARNING agent.tool_executor: Tool terminal returned error (0.05s):
  {"output": "/usr/bin/bash: line 3: ccs: command not found", "exit_code": 127...}
  ```
  74 seconds apart: the live gateway attempted `claude --version` (SIGSYS) then `ccs` (not found) — i.e., it is *already*, today, probing exactly the delegation paths Phases 2 and 4 are provisioning, unprompted by this plan.
  ```
  $ diff <(sudo cat /etc/systemd/system/hermes.service) templates/systemd/hermes.service | grep ccs
  # confirms Phase 2 never touches .ccs — the named 2-human race is benign
  ```
- **Suggested fix:** Note the live gateway as a concurrent actor in the plan's risk assessment; consider a maintenance-mode flag (or at minimum, timing Phase 4/5 for a window with low recent tool_executor activity, checked via `journalctl -u hermes --since "-2min"`).

## Finding 8: Phase 1's deploy script has no dry-run or per-unit targeting — a single "fix the urgent bug" run also sweeps up any other drifted unit

- **Severity:** Medium
- **Location:** Phase 1, "Overview" and "Architecture" (`phase-01-deploy-drift-prevention-tooling.md:22,41-43`)
- **Flaw:** The script iterates *every* `templates/systemd/*.service` and restarts *any* that are both changed and active, in one unconfirmed pass, with no `--unit=`/`--dry-run` option. Right now `hermes-dashboard.service` is verified in sync (`diff` clean), so today this is latent, not triggered — but the design has no guard against the general case.
- **Failure scenario:** Someone runs `bash scripts/deploy-systemd-units.sh` specifically to push a `hermes.service` fix (the exact motivating incident for this phase) while `templates/systemd/hermes-dashboard.service` independently has unrelated, uncommitted, half-finished edits sitting in the working tree (e.g., a teammate mid-edit on a different fix). The script has no way to distinguish "the unit I meant to deploy" from "any unit that happens to differ" — it deploys and restarts the dashboard too, an unintended bounce of a currently-healthy, unrelated service, with no confirmation step.
- **Evidence:** `phase-01-deploy-drift-prevention-tooling.md:43` Architecture flow: "shopt -s nullglob over templates/systemd/*.service → per unit: if live absent or ! diff -q → sudo install ... and record as changed → after loop, if any changed: sudo systemctl daemon-reload, then per changed unit is-active? restart" — unconditional over the whole glob, no per-unit selection; confirmed via `ls templates/systemd/` that exactly 2 units exist today (`hermes.service`, `hermes-dashboard.service`), so the blast radius is currently small but structural, not eliminated.
- **Suggested fix:** Add an optional `--unit=<name>` filter and/or a `--dry-run` preview-then-confirm step, at least for the interactive `[HUMAN]`-run path.

## Finding 9: Phase 4's install-success verification is too weak to catch a partial `--install-skills` failure

- **Severity:** Medium
- **Location:** Phase 4, "Implementation Steps" step 4 and Todo List (`phase-04-install-ccs-and-claudekit.md:48,58`)
- **Flaw:** The only mandatory check is `ls ~/.claude/skills | wc -l` > 0 — true even if only 1 of many skills installed before a network drop mid-`ck init --install-skills`. `ck doctor`, the check that would actually validate health, is explicitly marked "(optional)" in both the Verify step and the Todo List.
- **Failure scenario:** Network drops partway through `ck init --global --kit engineer --yes --install-skills --skip-setup`. `~/.claude/skills/` ends up with a handful of entries (count > 0 → passes). Phase 4 is marked done. Phase 5/6 later fail in a confusing way (missing a skill file `harness: ccs` or the delegate flow actually needs), and nothing in the plan's own checklist flags Phase 4 as the suspect, because its stated success criterion already passed.
- **Evidence:** `phase-04-install-ccs-and-claudekit.md:31` Requirements: "`~/.claude/skills` is non-empty; optionally `ck doctor` reports healthy" (optional, not required); `:58` Todo List: "(optional) `ck doctor` healthy" — the plan itself designed the strong check as skippable.
- **Suggested fix:** Make `ck doctor` (or an explicit expected-skill-count check) mandatory in Phase 4's Success Criteria, not optional.

---

**Status:** DONE
**Summary:** 9 findings — 2 Critical (Phase 2's "[AGENT] all-NOPASSWD" verification claim is empirically false for 3/6 checks; Phase 2's rollback omits `systemctl reset-failed` and will itself fail if `StartLimitBurst=5` trips), 3 High (Phase 6's real-task gate has a mechanism-free fallback that reduces to already-done proxy checks; Phase 2 doesn't fix a live, currently-reproducing `~/.npm` EROFS failure that can sink Phase 6; no in-flight-task check before Phase 2's restart plus an unverified "~5s" downtime claim against a 90s systemd default), 4 Medium (Phase 5's Phase-2-dependency claim is a sandboxed-vs-plain-shell category error and isn't even in the dependency graph; the plan's concurrency analysis misses the live gateway itself as a third actor already probing the same binaries/paths — confirmed via live logs; Phase 1's deploy script has no dry-run/per-unit targeting; Phase 4's verification is too weak to catch a partial install). All findings backed by live host commands or repo diff/grep, cited inline.
