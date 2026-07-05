---
phase: 3
title: "Live-Host Verification"
status: pending
priority: P1
effort: "1.5h"
dependencies: [1]
---

# Phase 3: Live-Host Verification

## Overview

Smoke-test the Phase 1 procedure end-to-end on this actual hermes host — not
a simulated/dry-run check. Prior sessions on this project have repeatedly
found that plans which skip live verification ship fixes that look correct
on paper but fail on the real host (stale `/opt` clone, broken symlinks,
empty env vars — see `plans/reports/scout-260705-1421-...-report.md`). This
phase exists specifically to avoid that pattern here. No file edits expected
unless verification surfaces a bug in Phase 1's procedure, in which case fix
forward in Phase 1's file before closing this phase.

## Key Insights

- `ccs-hermes` CCS profile and `claude` auth are confirmed working today per
  `plans/reports/scout-260705-1421-...-report.md` — this phase is NOT
  expected to be blocked by the still-"Pending" Phase 3/5 in
  `plans/260703-1738-fix-urgent-hermes-delegation-issues/plan.md` (that
  plan's own status just hasn't been refreshed since the scout audit).
- `sudo -n -u hermes` works without a password for read/inspection commands
  used during this plan's research (verified — `ls`, `grep`, `find`, `tail`
  all succeeded). Actually invoking `ccs`/`claude` as hermes needs the
  service's PATH (`/home/hermes/.local/bin` first) — reuse the pattern
  already documented in `SKILL.md:46`:
  `sudo -u hermes env PATH=/home/hermes/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin <cmd>`.
- **Red-team resolved two of this phase's original test targets as moot —
  don't spend verification budget on them:**
  1. `toolsets:` gating (originally Requirements #7 in an earlier draft) —
     confirmed by static source grep in Phase 1 to be decorative, not
     enforced (3 independent reviewer citation chains). No live A/B test.
  2. Background "survives gateway restart" — confirmed FALSE by static
     analysis of `templates/systemd/hermes.service` (no `KillMode=`
     override; child shares the gateway's cgroup). Do NOT deliberately
     restart the gateway mid-delegation on this production host to "prove"
     something already disproven by source — document the limitation
     instead (Phase 1 Requirements #9).
  Redirect that freed budget to the genuinely unverified risk below.
- **New required test (red-team, Critical — Assumption Destroyer #3+#5,
  Failure Mode Analyst #2):** `process(action="wait")` clamps to
  `TERMINAL_TIMEOUT` (180s default) and returns `status: "timeout"`, not a
  completed result, past that point. A short smoke test (e.g. `/ck:scout`)
  finishes well under 180s and would NEVER exercise this — it would falsely
  "prove" the mechanism works for tasks of any size. This phase must include
  one delegation that deliberately runs longer than 180s to prove the
  documented retry-loop actually reaches `status: "exited"` eventually.
  **Confirmed via validation (Session 1, Q1): use a cheap synthetic delay
  command (`sleep 200 && echo done`-style), not a real multi-minute
  `/ck:brainstorm --hard`** — isolates the `wait`-loop mechanism from
  `ccs`/`claude` cost/variability.
- **Repo identity confirmed (red-team delta round, Assumption Destroyer):**
  `NousResearch/hermes-agent` (Requirements item 0's target) is verified the
  SAME repo as this project's `/home/ubuntu/workspace/hermes-agent` source
  — `git remote -v` in that directory shows origin
  `https://github.com/NousResearch/hermes-agent`. Not a same-named,
  different upstream project; no ambiguity to resolve during this phase.
- **Second required test added (red-team delta round, Medium):** the
  original 200s test only proves the `wait`-retry loop reaches
  `status: "exited"` — it never drives Phase 1's new 10-iteration
  (~30min) cap far enough to exercise the cap-exceeded/degraded-status
  path, and never proves `notify_on_complete` still delivers a completion
  message after the polling loop has given up (Phase 1 Requirements item
  7a's resumption path depends on this). **Confirmed via validation
  (this session): extend to a ~33min synthetic delay** (e.g. `sleep 2000
  && echo done`) run as its own isolated test, specifically to drive past
  the cap and observe both the degraded-status message and the eventual
  `notify_on_complete` delivery.

## Requirements

- **Functional:**
  0. **Blocking precondition (research finding, `plans/reports/research-
     community-best-practices-260705-1852-ccs-delegation-timeout-fix-
     report.md`):** before running any live smoke test that could touch a
     real secret, read `NousResearch/hermes-agent#16843` ("Secret redaction
     breaks functional credential use in terminal commands") — confirmed
     the same repo as this project's `hermes-agent` dependency (see Key
     Insights). **Three defined verdict branches (red-team delta round,
     High — original draft only defined 2 of 3 real outcomes):**
     - **Confirmed related** (issue describes redaction failing on
       `stream-json`/`--include-partial-messages`-style structured output):
       escalate to a documented known-risk in Phase 1; do not run this
       phase's tests against a real secret-bearing task until resolved or
       explicitly accepted by the user.
     - **Confirmed unrelated** (e.g. plain-text-only redaction gap, or a
       narrower bug that doesn't touch structured/streamed output): note
       that finding and proceed as originally scoped.
     - **Inconclusive or inaccessible** (vague/stale issue, closed without
       clear resolution, 404/private/rate-limited): **fail-safe — treat the
       same as "confirmed related."** Document as a known-risk pending
       closer review; do not silently proceed on an unverified assumption.
     **Evidentiary bar (red-team delta round, Medium):** the recorded
     verdict must quote the specific issue text (or state "inaccessible: no
     text to quote") and note the issue's open/closed status and last-
     updated date — a bare "unrelated, proceeding" without a citation does
     not satisfy this requirement.
     **Scope note (red-team delta round, Medium):** this phase's actual
     test tasks (item 4's synthetic `sleep`, item 1's small `/ck:scout`)
     don't carry real secrets, so the hard block practically only matters
     if/when this procedure is later used against a real credential-
     touching task — record the verdict regardless so Phase 1 carries
     accurate, cited information forward, not because this phase's own
     tests are at risk.
     **Distinct from the Scope Decision above (red-team delta round, Low):**
     this is a *read*, not a *file-upstream* action — does not conflict
     with `plan.md`'s Validation Log Session 1 Q2 decision to not file
     anything upstream.
  1. Trigger one real backgrounded delegation **through the actual skill
     dispatch path**, not just a bare CLI call (red-team, Medium — a raw
     `sudo -u hermes ccs ...` invocation bypasses Hermes' agent/skill layer
     entirely and would only prove CLI reachability, not that the rewritten
     `SKILL.md` procedure is what an agent-driven session actually follows).
     Prefer sending a real Telegram message that invokes
     `/coding-agent-delegate` (or the closest available equivalent trigger)
     over a small-but-real task (e.g. `/ck:scout` against a small repo).
  2. Confirm `terminal(background=true, notify_on_complete=true)` returns
     immediately with a `session_id` and does NOT hit the foreground
     timeout/exit_code 124 path.
  3. While the task is still running, confirm `process(action="poll",
     session_id=...)` returns partial status without ending the session,
     and that output content is present (not empty — this is the exact
     failure mode the original file-redirect design would have caused; the
     redesigned Phase 1 command has no redirect, so `poll`/`log` should
     show real content).
  4. **Run one delegation deliberately longer than 180s** (red-team,
     Critical — see Key Insights) and drive it through the documented
     `wait`-retry loop: confirm the first `wait()` call returns `status:
     "timeout"` around the ~180s mark (process still running, not killed),
     confirm a subsequent `wait()` call eventually returns `status:
     "exited"` with the final result. This is the one test in this phase
     that actually exercises the bug class from the report (long tasks) —
     do not skip it in favor of only the short smoke test in item 1.
  4a. **Run a second delegation past the 10-iteration cap (~33min)**
      (red-team delta round, Medium — see Key Insights): confirm the
      `wait`-loop stops after the 10th `"timeout"` response and reports the
      degraded status (session_id + "still running") per Phase 1
      Requirements item 7a, instead of erroring or killing the session.
      Then, **without further polling**, confirm `notify_on_complete`
      independently delivers a completion message once the process
      actually finishes — this is the untested assumption Phase 1's
      resumption path depends on. If it does NOT deliver independently,
      that's a real defect in Phase 1's design (the "check back later"
      message would be a dead end) — fix forward in Phase 1 before closing
      this phase.
  5. Tail `~/.ccs/logs/current.jsonl` and (if a Claude Code call is
     involved) `~/.claude/projects/**/*.jsonl` live during the run —
     confirm they grow incrementally. This is the actual "can I tail real
     progress" claim this plan originates from; prove it against the
     pre-existing logs (no new artifact exists per Phase 1's redesign).
  6. Cross-check `~/.ccs/logs/current.jsonl` gained a new entry for the run
     (confirms the CCS-level log claim end-to-end, not just path-exists).
  7. Verify `process(action="list")` shows zero lingering sessions matching
     this test's command pattern after the phase concludes — a hard gate,
     not a reminder (red-team, Medium — the prior draft only had a
     to-do-style mention with no verification step).
- **Non-functional:** keep the smoke-test tasks small/cheap where possible
  (item 4's >180s test can be a cheap synthetic delay rather than a real
  `/ck:brainstorm --hard`); do not deliberately restart the Hermes gateway
  on this production host to test restart behavior — that's already settled
  by static analysis (Key Insights) and not worth the production risk.

## Related Code Files

- None expected to change. If verification finds a defect in Phase 1's
  procedure text, fix it in `skills/dev/coding-agent-delegate/SKILL.md`
  directly (same file Phase 1 owns) rather than creating a new file.

## Implementation Steps

0. Read `NousResearch/hermes-agent#16843` (Requirements item 0). Record one
   of the three defined verdicts — confirmed related / confirmed unrelated /
   inconclusive-or-inaccessible (fail-safe = treat as confirmed) — quoting
   the relevant issue text and its open/closed status, in this phase's
   status notes before proceeding to step 1.
1. Confirm current live state hasn't drifted since the scout audit: re-check
   `ccs-hermes` profile and claude auth work
   (`sudo -u hermes env PATH=... ccs ccs-hermes -p "echo ok" --output-format
   json`).
2. Trigger the Phase 1 background pattern through the real skill-dispatch
   path (Requirements item 1) for a small task, during a quiet window with
   no in-flight user conversation (check `journalctl -u hermes -n 5
   --since "-30s"` first, same discipline as
   `plans/260703-1738-.../phase-02-...md`).
3. Poll and tail logs per Requirements 2-3-5-6.
4. Separately, run the >180s wait-loop test (Requirements item 4) as a
   distinct, isolated `terminal(background=true)` call with a cheap
   synthetic long-running command (e.g. `sleep 200 && echo done`) —
   confirmed via validation (Session 1, Q1): the goal is proving the
   `wait`-loop mechanism itself, not re-testing `ccs`/`claude` reliability,
   so a real multi-minute ck task is not used here.
4a. Run the cap-exceeded test (Requirements item 4a) as its own isolated
    `terminal(background=true)` call with `sleep 2000 && echo done`
    (~33min) — confirmed via validation (this session). Loop `wait()` past
    10 iterations, confirm the degraded-status report fires instead of an
    error/kill, then stop polling and confirm `notify_on_complete` still
    delivers the completion message on its own.
5. Verify `process(action="list")` shows no lingering sessions
   (Requirements item 7) before marking this phase done.
6. Record actual observed latencies/behavior (not assumed) in this phase's
   status notes.
7. If anything in Phase 1's procedure doesn't work as written, fix Phase 1's
   file and re-run this phase's checks before marking done.

## Success Criteria

- [ ] `hermes-agent#16843` read and verdict recorded before the live smoke
      test runs (Requirements item 0) — known-risk escalation applied to
      Phase 1 if confirmed related.
- [ ] Backgrounded delegation runs on the live hermes host, triggered via
      the real skill-dispatch path, without hitting `exit_code 124`.
- [ ] `process(action="poll")` returns mid-run status with real (non-empty)
      output content.
- [ ] A deliberately >180s delegation demonstrates the `wait`-retry loop:
      one `status: "timeout"` response followed by an eventual `status:
      "exited"` with the final result.
- [ ] `~/.ccs/logs/current.jsonl` (and `~/.claude/projects/**/*.jsonl` where
      applicable) observably grow during the run (`tail -f` shown to work,
      not just asserted).
- [ ] `process(action="list")` confirms zero lingering sessions after the
      phase concludes.
- [ ] Cap-exceeded test (~33min) confirms the wait-loop stops after 10
      iterations and reports degraded status (not error/kill), AND
      `notify_on_complete` independently delivers the completion message
      after polling stops.

## Risk Assessment

- **Risk:** live verification against the production hermes host could
  interfere with real user traffic (the bot is actively used — see today's
  Telegram transcript in agent.log).
  **Mitigation:** run the smoke test during a quiet window, use a throwaway
  small task, and confirm no in-flight user conversation is active first
  (same discipline as `plans/260703-1738-.../phase-02-...md`'s restart
  precaution).
- **Risk:** the >180s test (Requirements item 4) and the ~33min cap-exceeded
  test (item 4a) each tie up a `process` slot (`MAX_PROCESSES = 64`,
  `tools/process_registry.py:60`) on a shared production host — item 4a
  specifically for ~33 minutes, longer than originally scoped.
  **Mitigation:** use cheap synthetic `sleep` commands for both tests
  rather than real `ccs`/`claude` calls (near-zero CPU/memory cost, just
  wall-clock), and verify cleanup via item 7. Phase effort bumped to 1.5h
  to reflect this (was 45m).

## Status Notes

### Step 0 — hermes-agent#16843 verdict (2026-07-05)

**Verdict: Confirmed unrelated.** Read via `gh issue view 16843 --repo
NousResearch/hermes-agent` — **CLOSED**, closed/updated `2026-06-21T18:37:18Z`.

Quoted issue text: "The `security.redact_secrets` feature replaces credential
strings with asterisks in both tool output AND command execution contexts.
This creates a functional breakage: when the agent needs to use a password in
a terminal command (e.g., `htpasswd -nb user Passw0rd!`), the redaction
either: 1. Masks the password with `****` in the command itself, breaking
actual command execution 2. Or the raw password appears in chat output,
exposing credentials." Suggested fix: a `security.display_redaction_only`
flag to redact in display/logs only while passing real values to subprocess
execution.

This is a narrower, different bug than what this phase's precondition checks
for — it's about redaction masking secrets *inside the command being
executed* (breaking functionality) or leaking raw secrets in chat display,
not about whether `_redact_process_result` correctly redacts
`stream-json`/`--include-partial-messages` structured/streamed output
returned by `process(action=poll/log/wait)`. No overlap with Phase 1's
command shape or output path. **Proceeding as originally scoped** — no
known-risk escalation to Phase 1 required.

### Steps 1-7 — Live verification results (2026-07-05, ~20:11-21:00 UTC)

**Environment:** `/opt/hermes-optimization-guide/skills/dev/coding-agent-delegate/SKILL.md`
confirmed synced with workspace (frontmatter has `toolsets: [...,terminal]`,
correct trigger `/coding-agent-delegate <task>`). Triggered via
`sudo -n -u hermes hermes chat -q '/coding-agent-delegate ...' repo=...`
(cwd `/home/hermes`, real PATH) — the actual skill-dispatch path, not a bare
CLI call. No Telegram access in this environment; CLI is the closest
available proxy (caveat noted in Unresolved Questions).

**Test 1 — small real skill-dispatched task (Requirements item 1, quiet
window re-confirmed clean via `journalctl -u hermes -n5 --since -30s` before
each trigger below):**
`/coding-agent-delegate "run a trivial read-only scout... list top-level
files" repo=/home/hermes/workspace/kitchen` →
agent chose **foreground**: `claude -p '...' --allowedTools 'Read'
--max-turns 5 --output-format json`, 10.9s, correct result, no
`exit_code 124`. **Correct per decision rule** (tight `--max-turns 5`,
read-only, short) — not a bug; this is the documented foreground-OK
exception firing as designed.

**Test 4 — real Tier-1 background delegation (Requirements items 1-3,
core positive case), framed as invoking a `/ck:*` meta-skill to force the
background branch of the decision rule:**
`/coding-agent-delegate "run /ck:scout to map out this repos top-level
structure..." repo=/home/hermes/workspace/kitchen` →
agent correctly built the exact Tier-1 background command:
`claude -p '...' --allowedTools "Read" --max-turns 20 --output-format
stream-json --verbose --include-partial-messages`, `terminal()` returned in
**0.1s** (no exit_code 124, confirms background mode taken). Single
`process(action="wait")` call blocked **53.0s** then returned with real
content; agent then used `process(action="log")` + `read_file` +
`grep`/`rg` on the result file to extract the final scout report (real,
non-empty, correct — confirms Requirements item 3). One follow-up shell
command (`python3 -c "..."`) was auto-denied after a 60s approval-prompt
timeout (`[BLOCKED: User denied this command]`) since `-q` CLI mode has no
TTY to approve dangerous commands — agent recovered via `tail` instead; not
a Phase 1 defect, but a CLI-testing-methodology note (live Telegram/gateway
sessions may have different approval-prompt handling, not verified here).
Total session 3m37s.

**Test 5 — `harness=ccs` background (Requirements item 6):**
`/coding-agent-delegate "print first 5 lines of README.md"
repo=.../kitchen harness=ccs` → agent correctly built
`ccs "ccs-hermes" -p "..." --allowedTools "Read" --max-turns 20
--output-format stream-json --verbose --include-partial-messages`,
background, 0.1s return. `~/.ccs/logs/current.jsonl` grew **227 → 230
lines** during/after this call — confirms Requirements item 6 end-to-end
(the default `harness: bare` doesn't touch this log at all, so this
dedicated ccs-harness call was necessary to exercise it).

**Test 3 — `parallel=2` (side observation, not a Phase 1 target):**
`/coding-agent-delegate "..." repo=.../kitchen parallel=2` did **not**
route through Tier-1 `terminal()`+`process()` at all — it dispatched via
the native `delegate_task`/ACP mechanism (🔀 icon in trace, "Background 2
tasks running"), a different, pre-existing tier explicitly out of Phase 1's
scope (Requirements item 10). Both subtasks errored ("Interrupted during
API call") — unrelated infra/model flakiness, not investigated further
(out of scope). Flagged only as a methodology note: Phase 1's Success
Criteria item "`parallel=3` example updated to use background mode" may
describe a manually-authored example the model doesn't actually reach for
when a real `parallel=` param is present — not confirmed as a defect, just
unverified. See Unresolved Questions.

**Requirements item 5 — log tailing (`~/.ccs/logs/current.jsonl`,
`~/.claude/projects/**/*.jsonl`) shown to grow live, not just asserted:**
5-second-interval snapshots during Test 4 show
`.../projects/-home-hermes-workspace-kitchen/<uuid>.jsonl` growing
**8 → 13 → 19 → 30 → 38 → 45 → 50 → 53 lines** between 20:21:03 and
20:22:04 UTC, then plateauing (matches the 53s `wait()` call). **Confirmed
live growth, not just path-exists.** Note: the two synthetic `sleep`
tests (2/6, next) never grew these logs at all (227 lines constant, 13
lines constant) — expected, since raw `sleep` never invokes `claude`/`ccs`;
this was the deliberate Session-1-Q1 tradeoff (isolate the wait-loop
mechanism from ccs/claude cost), so items 5/6 needed the dedicated Test 4/5
above to be actually exercised.

**Test 2 — >180s wait-retry loop (Requirements item 4), generic chat (not
`/coding-agent-delegate` — skill wasn't loaded for this synthetic-delay
test, so this exercises Hermes-core's `terminal`/`process` primitives
directly, the same primitives Tier-1 wraps):**
`sleep 200 && echo done-200` backgrounded, then the agent's own wait-retry
loop: **19 consecutive `wait()` calls, each ~10.0s** (agent's own chosen
per-call timeout, not the 180s default — see note below), all
`status=timeout`, then final call returned `status=exited` with
**`done-200`** correctly retrieved. Total 3m58s. **Confirms the core retry
mechanism works** (loop-until-exited, real non-empty final output) but
does NOT specifically demonstrate a single `wait()` blocking ~180s at the
default clamp, since the agent chose to poll every ~10s instead of
leaving `timeout=` unset. Not a bug (correct, if chattier, use of the
primitive) but means the literal "first wait() times out ~180s" success-
criteria wording is not literally what was observed — the loop-until-
exited behavior is what was proven instead.

**Test 6 — ~33min cap-exceeded test (Requirements item 4a, the critical
one):** `sleep 2000 && echo done-2000` backgrounded (started ~20:26:22
UTC), agent told explicitly to cap at 10 `wait()` iterations and report
degraded status without erroring/killing. Result: **10 iterations of
`wait()`, each 30.0s (agent's own choice again — not 180s), total ~5min,
then correctly stopped and reported**:
`Degraded status: the process is still running. session_id:
proc_78371dd2d7a5. ... I did not kill or mark it as an error.`
**PASS for the cap/degraded-status half of Requirements item 4a.**
Important side-finding: because the agent chose 30s/iteration (not the
180s default), the cap fired after **~7 minutes**, not the ~30 minutes the
design assumes (`10 × 180s`) — the "~30min" figure in Phase 1's SKILL.md
assumes the caller leaves `timeout=` unset on each `wait()` call; nothing
enforces that, and in both Test 2 and Test 6 the model chose a shorter,
self-picked interval instead. Not confirmed as a defect (never tested
via the actual `/coding-agent-delegate`-loaded pseudocode), but a real
risk: if this generalizes, the "expected common outcome" cap fires much
earlier than documented, changing UX expectations. Flagged, not fixed.

**notify_on_complete independent-delivery check (Requirements item 4a,
second half — the one open question the whole plan hinges on):**
Waited out the actual `sleep 2000` process to completion (confirmed via
`pgrep`, exited at **20:59:59 UTC**, ~2000s after launch). Checked:
1. `journalctl -u hermes --since -3min` at/after exit — **no entries**.
2. `~/.hermes/logs/agent.log` around 20:59:59 — **no new log lines at all**
   for session `20260705_202622_a69320` after its CLI process's own
   cleanup at 20:33:34 (`CLI cleanup calling memory shutdown for session
   20260705_202622_a69320`). **No independent/spontaneous notification
   fired.**
3. Resumed the same session and asked directly:
   `hermes chat -q "any update on that background task?" --continue
   20260705_202622_a69320` → agent called `process(action="wait",
   session_id="proc_78371dd2d7a5")` → **`status: not_found`, "No process
   with ID proc_78371dd2d7a5"**. The documented fallback ("check back with
   `process(action='poll'|'wait', session_id=<id>)`") **also failed** — the
   session record itself was gone, not just non-notifying.

   **Root-cause evidence:** `agent.log` shows, immediately at the end of
   the *original* CLI turn (20:33:34, ~26 minutes before the sleep actually
   finished): `tools.terminal_tool: Manually cleaned up environment for
   task: default` / `Cleaned 1 environments` / `cli: CLI cleanup calling
   memory shutdown for session 20260705_202622_a69320`. This strongly
   suggests the one-shot `hermes chat -q` CLI invocation tears down its
   process-tracking environment when its single turn ends, orphaning the
   still-running detached child (independently confirmed alive via
   `pgrep -fa "sleep 2000"` at 20:46:29, mid-run) — the background OS
   process keeps running, but the registry record that `poll`/`wait`/`log`
   depend on is gone by the time anyone asks again.

   **CONFIRMED DEFECT (with a scope caveat):** both notify_on_complete's
   spontaneous delivery AND the documented manual "check back later"
   fallback are dead ends once the *originating CLI invocation's own turn
   has ended* — exactly the failure mode Phase 1 Requirements item 7a
   worried about ("the 'check back later' message would be a dead end").
   **Caveat, not yet resolved:** this was tested via `hermes chat -q`
   one-shot CLI calls (per the given test methodology — no live Telegram
   access in this environment), where each invocation's "environment"/
   session appears to be torn down at end-of-turn. It is **not verified**
   whether the same teardown happens in the actual live, persistent
   Telegram/gateway conversation (the `hermes gateway run` daemon,
   PID 3704959, stays up continuously across many turns and Telegram
   messages — no per-turn "CLI cleanup... memory shutdown" event was
   observed for it). This may be a CLI-only limitation, not a live-bot
   limitation — but that is exactly the assumption that still needs a
   real Telegram-session test to close out, and this phase could not run
   one.

**Cleanup / no-lingering-sessions check (Requirements item 7):**
`pgrep -fa "sleep 200\|sleep 2000"` on the hermes user — **empty, clean**.
Full `ps --forest -u hermes` shows only the pre-existing, long-uptime
daemons (`claude daemon run`, `hermes gateway run`, `hermes dashboard`) —
nothing from this phase's tests remains. Note: `process(action="list")`
itself is scoped by `session_key` (confirmed empirically — a fresh session
querying "list any active background sessions" mid-test-6 reported "empty"
while `sleep 2000` was still demonstrably running per `pgrep`) — it is
**not** a global/cross-session view, so the authoritative cleanup check
here is OS-level `pgrep`, not `process(action="list")` from an unrelated
session. Worth noting as a documentation gap if `process(action="list")`
is ever described as a global admin view.

### Success Criteria — verdict

- [x] `hermes-agent#16843` read, verdict recorded (Step 0, pre-existing).
- [x] Backgrounded delegation via real skill-dispatch, no `exit_code 124`
      (Test 4, Test 5; Test 1's foreground choice is correct-per-rule, not
      a failure).
- [x] `process(...)` returns mid-run status with real non-empty content
      (Test 4: `wait`+`log`+`read_file` chain; Test 6: iteration messages).
- [x] >180s delegation demonstrates the retry loop: repeated `timeout`
      responses then eventual `exited` with final result (Test 2 — 19
      iterations then `done-200`; per-call interval was agent-chosen 10s,
      not literally the 180s default, see note above).
- [x] `~/.ccs/logs/current.jsonl` and `~/.claude/projects/**/*.jsonl`
      observably grow during the run, `tail`-able, not just asserted
      (Test 4: 8→53 lines live; Test 5: ccs log 227→230).
- [x] Zero lingering sessions/processes after the phase concludes
      (OS-level `pgrep`/`ps --forest` clean; `process(action="list")` is
      session-scoped, not a valid global check — noted above).
- [ ] **Cap-exceeded (~33min) test: wait-loop stops after 10 iterations
      and reports degraded status (not error/kill) — PASS (Test 6).
      `notify_on_complete` independently delivers the completion message
      after polling stops — FAIL, confirmed dead end (see above), with the
      CLI-vs-live-gateway scope caveat noted.**

**Overall: 6/7 pass, 1 fail (the critical one).** Per this phase's own
Requirements item 4a: "If it does NOT deliver independently, that's a real
defect in Phase 1's design... fix forward in Phase 1 before closing this
phase." Per this session's explicit operating constraints (no `/opt` write
access, told to flag rather than fix), **not fixed here** — see verdict
below.

**NEEDS FIX IN WORKSPACE + RE-SYNC:** Phase 1's `SKILL.md` "Checking
progress on a backgrounded delegation" section currently presents
`process(action="poll"|"wait"|"log")` as a reliable way to "check back
later" after the 10-iteration cap, with no caveat about session lifetime.
Empirically (via CLI, with the live-gateway caveat above unresolved),
that check-back path can return `status: not_found` once the *originating
turn* has ended, making the degraded-status message's own advice
non-actionable. Recommend Phase 1 either (a) add an explicit caveat that
check-back-later is only reliable within the same continuously-running
conversation (matches how the live Telegram/gateway session actually
behaves — never observed to exit its process between messages), not via a
fresh one-shot CLI query, or (b) if a live-Telegram test later shows the
same loss occurs there too, treat this as a Hermes-core session-lifecycle
bug (out of this repo's scope to patch, same category as the existing
session-ownership-gap note) and document it as a known limitation
alongside the restart-survival caveat (Requirements item 9).

## Unresolved Questions

1. Whether `notify_on_complete`'s async delivery path passes output through
   `_redact_process_result` (red-team, not traced) — if this phase's smoke
   test triggers a `notify_on_complete` firing, note whether the delivered
   content looks redacted or raw. **Widened per research finding
   (`plans/reports/research-community-best-practices-260705-1852-ccs-
   delegation-timeout-fix-report.md`):** also check whether redaction holds
   up against `stream-json`/`--include-partial-messages` output generally
   (not just the `notify_on_complete` path) — resolved as a blocking
   precondition, see Requirements item 0 above, not left open past this
   phase.
2. **New — whether the confirmed check-back-later/notify_on_complete dead
   end (see Status Notes above) also occurs in a live, persistent
   Telegram/gateway conversation, or is specific to one-shot `hermes chat
   -q` CLI invocations** (whose "environment"/session is observably torn
   down at end-of-turn, per `agent.log`'s "CLI cleanup calling memory
   shutdown" line — not observed for the long-uptime `hermes gateway run`
   daemon). This phase could not test via real Telegram messages (no
   access in this environment) and could not close this out. Needs a
   dedicated live-Telegram test: start a background delegation from a real
   Telegram message, let it run past the 10-iteration cap, stay idle
   (send no further messages) past actual completion, and check whether
   the bot proactively posts a completion message.
3. **New — whether `parallel=N` on this host actually routes through
   Phase 1's rewritten Tier-1 `terminal()`/`process()` pattern at all**, or
   always dispatches via the native `delegate_task`/ACP mechanism instead
   (observed in Test 3 above — both subtasks errored for an unrelated
   reason, not investigated). If `delegate_task` is what `parallel=`
   always triggers in practice, Phase 1's `parallel=3`-example Success
   Criteria item may be describing a code path the model doesn't actually
   take. Not confirmed as a defect — flagged for a future check.
