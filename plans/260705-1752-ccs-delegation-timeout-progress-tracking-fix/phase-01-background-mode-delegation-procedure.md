---
phase: 1
title: "Background-Mode Delegation Procedure"
status: pending
priority: P1
effort: "1.5h"
dependencies: []
---

# Phase 1: Background-Mode Delegation Procedure

## Overview

Rewrite `skills/dev/coding-agent-delegate/SKILL.md`'s Tier-1 procedure so any
`ccs`/`claude -p` delegation that isn't a trivial one-liner runs via Hermes'
native `terminal(background=true, notify_on_complete=true)` + `process(action=
poll/log/wait)` tooling instead of a blocking foreground call with a short
timeout. This is the actual fix — see plan.md Overview for the verified root
cause (today's live `exit_code 124` failures at 20s/90s/120s).

## Key Insights

- `terminal_tool(command, background: bool=False, timeout: int|None=None,
  session_id, notify_on_complete: bool=False, watch_patterns)` —
  `tools/terminal_tool.py:1968-1979`. `notify_on_complete` and
  `watch_patterns` are mutually exclusive (`:1992-1993`); for a delegation
  whose only interesting event is "done", `notify_on_complete=true` is correct
  — `watch_patterns` is for mid-run string signals on servers, not one-shot
  batch jobs.
- Foreground timeout: default `TERMINAL_TIMEOUT=180`s, hard cap
  `FOREGROUND_MAX_TIMEOUT=600`s (`tools/terminal_tool.py:107-112,1297`).
  Requesting `timeout>600` in foreground mode is **rejected outright** with an
  error telling the caller to use `background=true`
  (`tests/tools/test_terminal_foreground_timeout_cap.py:31-45`) — i.e. Hermes
  core already actively steers callers toward background mode for long
  commands; the skill just never told the agent to listen.
- `process` tool actions: `list, poll, log, wait, kill, write, submit, close`
  (`tools/process_registry.py:2044-2154`). `poll` = status + new output since
  last poll; `log` = full/windowed output.
  **`wait` is NOT unbounded (red-team, Critical, confirmed independently by
  2 reviewers with matching citations):** `ProcessRegistry.wait()` clamps to
  `default_timeout = int(os.getenv("TERMINAL_TIMEOUT", "180"))`
  (`tools/process_registry.py:1299-1300`) regardless of the `timeout=` value
  requested; on expiry it returns `{"status": "timeout", "output": <last
  1000 chars>, ...}` — the process is NOT killed, but this is not "block
  until done." A single `wait()` call cannot deliver a final result for a
  `/ck:brainstorm`/`/ck:cook` run that legitimately takes 10+ minutes. **The
  procedure below documents `wait` as a call-in-a-loop primitive, not a
  one-shot block.**
- Neither `~/.hermes/.env` on this host sets `TERMINAL_TIMEOUT` nor
  `TERMINAL_MAX_FOREGROUND_TIMEOUT` (verified empty grep) — code defaults
  (180s/600s) are what's actually active.
- **`toolsets:` frontmatter is decorative, not enforced (red-team, resolved
  as fact — confirmed independently by all 3 reviewers via 3 different code
  paths, no live testing needed):** `skills/dev/coding-agent-delegate/
  SKILL.md`'s frontmatter `toolsets:` list is `[delegate_task, kanban,
  sandbox, file]` — no `terminal`. Grepping the actual skill-loading path
  (`agent/skill_commands.py` → `agent/skill_utils.py:541-555`'s
  `extract_skill_conditions`) shows it never reads a top-level `toolsets:`
  key at all — it only reads `metadata.hermes.requires_toolsets` (a
  different, nested key path used by two *other* skills in this repo,
  `skills/productivity/maps/SKILL.md:12` and
  `skills/research/research-paper-writing/SKILL.md:15`), and that field
  feeds `_skill_should_show()` (`agent/prompt_builder.py:1383-1408`) — a
  discovery/listing gate, not a runtime tool-access boundary. Actual tool
  availability (`enabled_toolsets`) is a session-level parameter set once at
  agent init (`model_tools.py:354-372`), not something a loaded skill
  amends. This is independently proven by this plan's own bug evidence:
  today's incident shows `terminal` was already reachable in a live session
  despite never being declared in this skill's `toolsets:` list. **Adding
  `terminal` to the list below is kept for documentation/discoverability
  only — it is not a security or access-control change, and no live
  verification of "does it gate access" is needed (dropped from Phase 3).**
- Raising the foreground timeout further is explicitly **not** the fix:
  even the 600s hard cap is short for a `/ck:cook --parallel` or
  `/ck:brainstorm --hard` run with multiple researcher subagents.
- **Background does NOT survive a Hermes gateway restart (red-team,
  High):** `templates/systemd/hermes.service` has no `KillMode=` override,
  so systemd's default `KillMode=control-group` applies on
  `stop`/`restart` — it signals every process in the unit's cgroup, and the
  unit's own comment (line 81) confirms delegated sub-sessions share "same
  UID/cgroup as this service." `process_registry.spawn_local`'s
  `start_new_session=True` (setsid) detaches the process group for signal
  routing but does not move the child to a different cgroup — it dies with
  the gateway. Do not claim background mode makes a delegation
  restart-proof; it only removes the artificial short-timeout kill, not a
  real gateway restart kill. This is a known, accepted limitation (documented
  in Phase 3), not something this phase can fix without deeper systemd/scope
  plumbing that's out of scope here.
- **Session IDs are bearer capabilities, not access-controlled (red-team,
  High, inherent Hermes-core limitation, not fixable from this repo):**
  `process(action=poll|log|wait|kill|write|submit|close)` takes only a bare
  `session_id` with no ownership check against the caller
  (`tools/process_registry.py:2131-2147`) — unlike `list`, which does filter
  by `session_key` (`:1538-1560`). Any concurrent Hermes session with
  `terminal`/`process` access that learns a `session_id` (echoed in a log,
  Kanban comment, error message, etc.) can poll/kill/read another
  delegation's in-flight output. Document this so `session_id` values are
  never echoed outside the originating session/conversation — this plan
  cannot patch `hermes-agent` core (a separate, upstream project) to add the
  missing ownership check.

## Requirements

- **Functional:**
  1. Add `terminal` to the skill's `toolsets:` frontmatter list
     (documentation/discoverability only — see Key Insights; not a security
     boundary, don't over-claim it in the file).
  2. Rewrite Tier 1 (`SKILL.md:52-87`) so the default invocation pattern for
     any delegation expected to run more than ~1-2 minutes (this includes
     every `/ck:*` meta-skill call, `parallel=` fan-out, and anything without
     a tight `--max-turns` bound) uses:
     ```
     terminal(
       command='ccs "<ccs_profile_or_bare-claude>" -p "<shell-escaped task>" \
         --allowedTools "<Read,Edit | Read,Edit,Bash — pick per task, see below>" \
         --max-turns 20 \
         --output-format stream-json --verbose --include-partial-messages',
       background=true,
       notify_on_complete=true
     )
     ```
     **No shell redirect to a new file** (red-team, Critical — the original
     draft's `> delegation-<run-id>.jsonl 2>&1` both bypassed all secret
     redaction via the skill's own `file` toolset AND starved
     `spawn_local`'s stdout pipe so `process(action=poll/log)` returned
     empty output, defeating the point). Letting the command's stdout/stderr
     go to the pipe `process_registry` already wires up means
     `process(action=poll/log)` gets real (redacted) content, and the
     already-existing, already-verified-real `~/.ccs/logs/current.jsonl` and
     `~/.claude/projects/**/*.jsonl` remain the durable/external-tail
     channel — no new artifact, no run-id, no rotation burden, no collision
     risk under `parallel=N`.
  3. `<task>` must be shell-escaped before interpolation into `-p "..."`
     (pre-existing gap, `SKILL.md:73,77,85`, reused unchanged by the current
     draft — red-team Medium). State explicitly: quote/escape the task text
     (e.g. single-quote with `'"'"'` escaping) before building the command
     string; never interpolate raw Telegram-origin text into a double-quoted
     shell argument.
  4. Keep the Bash-vs-no-Bash choice **orthogonal** to the
     foreground-vs-background choice (red-team, High — the original draft's
     single code block hardcoded `Read,Edit,Bash` for every background call,
     silently dropping the existing `Read,Edit` no-Bash option for edit-only
     long tasks like the `parallel=3` "add tests" example). Keep both
     existing allowlist variants (`SKILL.md:71-78`), and for each, show both
     a foreground-short and background-long invocation shape.
  5. Keep the existing blocking-foreground example only for genuinely short,
     single-file, tightly-bounded tasks (e.g. `--max-turns 5` bugfixes) —
     labeled explicitly as the exception, not the default.
  6. Add a short decision rule: "single-file bugfix, `--max-turns` ≤ 10 →
     foreground OK. Anything invoking a `/ck:*` meta-skill, `parallel=`, or
     without a tight turn bound → background, no exceptions." (Independent
     of the Bash/no-Bash choice — item 4.)
  7. Document the follow-up procedure as a **loop, not one-shot calls**
     (red-team, Critical — `process(action="wait")` clamps to
     `TERMINAL_TIMEOUT`/180s regardless of requested timeout,
     `tools/process_registry.py:1299-1300,1360-1369`):
     - `process(action="poll", session_id=...)` — cheap status + new-output
       check, call anytime.
     - `process(action="wait", session_id=...)` — blocks up to ~180s, then
       returns `status: "timeout"` (process still running, not an error) or
       `status: "exited"` (done). **Loop: call again on `"timeout"` until
       `"exited"`.** Do not treat a single `wait` timeout as failure.
     - `process(action="log", session_id=...)` — pull output without ending
       the session.
  7a. **Cap the wait-retry loop at 10 iterations (~30 min wall-clock)**
      (research finding, `plans/reports/research-community-best-practices-
      260705-1852-ccs-delegation-timeout-fix-report.md` — community
      async-agent pattern always bounds poll loops so a genuinely hung
      subprocess can't make the *caller* poll forever; confirmed by a real
      precedent in this tool family, `anthropics/claude-code#68626`, where
      unbounded background workers accumulated until OOM). **On cap
      exceeded: do NOT kill the session or error.** Report a degraded
      status back to the user/caller — e.g. "still running after ~30min,
      session_id=<id>, check back with `process(action='poll'|'wait',
      session_id=<id>)`" — and stop actively looping. The background
      process keeps running; this only bounds how long *this agent turn*
      blocks on it. (Decision confirmed via validate — see plan.md
      Validation Log Session 2.)
      **Set expectations correctly (red-team delta round, Medium-High):**
      this cap is expected to trigger **routinely**, not as a rare edge
      case — the Key Insights above already note "even the 600s hard cap
      is short for a `/ck:cook --parallel` or `/ck:brainstorm --hard` run,"
      and today's real incident (`plan.md` Overview) spanned ~73 minutes.
      Hitting the cap on a large `/ck:*` fan-out is the *expected common
      outcome*, not a failure — it differs from the original bug because
      no data is lost and the process is resumable, but don't write or
      read this as a rare fallback path.
      **Degraded-status message must carry the same secrecy caveat as
      item 8 below** (red-team delta round, Low): the `session_id` handed
      back in the "still running" message is a bearer capability — safe
      only within the same private conversation/session, never pasted into
      a group chat, Kanban comment, or other shared surface.
      **Resumption depends on an unverified assumption (red-team delta
      round, Medium):** the only way a caller who stops polling ever learns
      the task finished is if `notify_on_complete=true` (set at spawn time)
      delivers independently of the `wait`-loop having given up. This is
      NOT yet confirmed — Phase 3 must explicitly verify that stopping the
      poll loop does not also silently drop the completion notification
      (see Phase 3 Requirements, cap-exceeded test).
  8. Document `session_id` as a bearer capability (red-team, High — no
     ownership check exists on `poll/log/wait/kill/write/submit/close`,
     `tools/process_registry.py:2131-2147`): never echo a `session_id` into
     a Kanban comment, shared log, or any surface another concurrent session
     could read it from.
  9. State plainly (not as an open question) that background mode does
     **not** survive a Hermes gateway restart — the child shares the
     gateway's systemd cgroup and dies with it (red-team, High). This is an
     accepted limitation: the fix removes the artificial short-timeout kill,
     not a real restart kill.
  10. Do not change Tier 2 (Kanban) or Tier 3 (sandbox) sections — out of
      scope, unaffected by this bug.
- **Non-functional:** preserve the skill's existing YAML frontmatter schema
  (only add `terminal` to `toolsets:`); no new parameters; stay under the
  file's current structure (Procedure → Escalation tiers → Examples → See
  also); keep kebab-case / kept under repo's doc conventions.

## Architecture

No system architecture change — this is a prose/procedure fix to an
LLM-interpreted skill file. The "architecture" is the decision the agent
makes at delegation time, on two independent axes (turn-bound → fg/bg;
task needs shell → allowlist):

```
delegation call requested
  ├─ single-file bugfix, --max-turns ≤ 10 ──────────► foreground terminal()
  │                                                     --allowedTools "Read,Edit[,Bash]"
  └─ everything else (/ck:* meta-skill, parallel=,
     open-ended turns) ───────────────────────────────► terminal(background=true,
                                                          notify_on_complete=true)
                                                          --allowedTools "Read,Edit[,Bash]"
                                                          (no file redirect)
                                                          → loop: process(action="wait")
                                                            until status != "timeout"
                                                          → process(action="poll"/"log")
                                                            for interim checks
```

## Related Code Files

- Modify: `skills/dev/coding-agent-delegate/SKILL.md` (Tier 1 procedure,
  `toolsets:` frontmatter, escalation-tiers table if it references timeout
  behavior)

## Implementation Steps

1. Read current `SKILL.md` in full (already done during planning — see
   plan.md Overview for verified line citations).
2. Add `terminal` to `toolsets:` frontmatter (line ~8-12) — one line,
   documentation-only per Key Insights.
3. Rewrite the Tier 1 section (`:52-87`) per Requirements above: background
   pattern as default (no file redirect), foreground kept as the explicit
   short-task exception, Bash/no-Bash kept orthogonal, decision rule stated
   plainly, task-string escaping called out explicitly.
4. Add a "Checking progress on a backgrounded delegation" subsection with
   the `poll`/`log`/`wait`-loop pattern from Requirements item 7 — show the
   loop explicitly (pseudocode: `while wait(...).status == "timeout": keep
   polling`), not three independent one-shot examples.
5. Add the `session_id`-as-capability caveat (Requirements item 8) and the
   restart-does-not-survive caveat (Requirements item 9) as short notes near
   the background pattern, not buried in prose.
6. Update the "Example invocation" section (`:170-186`) to show one
   background example (replacing or augmenting the existing `parallel=3`
   example, which is exactly the kind of task that needs this fix) —
   without a file-redirect/run-id (removed per Requirements item 2).
7. Self-review: confirm no other section still implies delegation is always
   blocking/synchronous (e.g. re-check "streams progress back over a single
   WebSocket" language at `:79` — clarify in Phase 2 that this describes the
   native `delegate_task`/ACP path, not the Tier-1 CLI shell-out path this
   phase fixes).

## Success Criteria

- [ ] `toolsets:` includes `terminal` (documented as non-security metadata).
- [ ] Tier 1 procedure's default example uses `background=true,
      notify_on_complete=true` for any non-trivial task, with NO file
      redirect in the command string.
- [ ] Explicit decision rule present distinguishing foreground-OK vs
      background-required cases, kept orthogonal to the Bash/no-Bash choice.
- [ ] `process(action="poll"|"log"|"wait")` documented, with `wait`
      explicitly shown as a retry-on-`"timeout"` loop, not a one-shot call.
- [ ] Wait-retry loop caps at 10 iterations (~30min); cap-exceeded path
      reports degraded status (session_id + "still running") instead of
      erroring or killing the session.
- [ ] `session_id`-as-capability-token caveat present.
- [ ] "Does not survive gateway restart" stated plainly, not as an open
      question.
- [ ] `<task>` shell-escaping guidance present.
- [ ] Both `Read,Edit` and `Read,Edit,Bash` allowlist variants preserved for
      both foreground and background shapes.
- [ ] `parallel=3` example updated to use background mode (it fans out 3
      concurrent `ccs -p` calls — exactly the scenario that times out today)
      — no run-id/file-collision concern since no new file is introduced.
- [ ] No foreground `timeout=` value above 600s appears anywhere (would be
      silently rejected by `FOREGROUND_MAX_TIMEOUT`).
- [ ] File still passes basic Markdown/YAML frontmatter sanity (valid YAML,
      no broken internal links).

## Risk Assessment

- **Risk:** background mode changes user-visible latency — the Telegram bot
  now returns "started" quickly instead of a blocking wait, which changes UX.
  **Mitigation:** document this as an explicit tradeoff in the skill (return
  an immediate ack + how to check back), not a silent behavior change.
- **Risk:** `process`'s lack of session-ownership checks (Key Insights) means
  any concurrent session with `terminal`/`process` access could
  poll/kill/read another delegation once this becomes the default mechanism.
  **Mitigation:** documented as a `session_id`-secrecy requirement
  (Requirements item 8); the underlying gap is in `hermes-agent` core, out of
  this repo's scope to patch — flagged, not silently accepted without
  mention.
- **Risk:** a naive one-shot `wait()` call (ignoring the documented loop
  requirement) would appear to "fail" on any task over ~180s, reintroducing
  a milder version of today's bug.
  **Mitigation:** Requirements item 7 and Success Criteria make the loop
  requirement explicit and testable; Phase 3 adds a dedicated >180s test.

## Unresolved Questions

None specific to this phase — the two red-team-raised questions that
originally lived here (`toolsets:` gating, `wait` boundedness) are resolved
as facts above, not open questions. The one open item from this plan's red
team pass (whether to also address the ad-hoc/non-skill chat-delegation
trigger path) is a plan-level scope decision — see `plan.md`'s Unresolved
Questions.
