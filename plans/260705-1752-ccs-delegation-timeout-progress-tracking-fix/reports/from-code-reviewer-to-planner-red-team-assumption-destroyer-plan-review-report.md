---
title: "Red-Team Assumption-Destroyer Review — CCS Delegation Timeout/Progress-Tracking Fix Plan"
reviewer: code-reviewer
target_plan: plans/260705-1752-ccs-delegation-timeout-progress-tracking-fix/
---

# Red-Team Review: CCS Delegation Timeout Fix Plan

Verified against live host (`sudo -n -u hermes` read commands), real `hermes-agent` source at `/home/ubuntu/workspace/hermes-agent`, and this repo's `SKILL.md`/`part18-coding-agents.md`/`CHANGELOG.md`.

## Finding 1: Root-cause narrative misquotes the incident timeline — one of three cited log lines is from an unrelated turn 6 hours earlier
- **Severity:** Critical
- **Location:** plan.md, Overview, lines 27-31 (the three-line `agent.log` excerpt) and line 33-34 ("bumped it 20s → 90s → 120s across retries")
- **Flaw:** The Overview presents three `exit_code 124` lines as one continuous escalating-retry sequence: `17:27:26` (20s timeout), `17:20:32` (90s), `17:47:58` (120s). The `17:27:26` timestamp does not exist in `agent.log`. The real 20.28s/20s-timeout line is timestamped `2026-07-05 11:27:26` — 6 hours before the 17:18-17:47 brainstorm-delegation incident, in a completely different Telegram turn (`msg='All'`, following up on a `check lại skill coding_age...` message about CCS, not a `/ck:brainstorm` delegation).
- **Failure scenario:** The plan's causal story ("someone/something bumped it 20s → 90s → 120s across retries, still nowhere near enough") implies a single delegation attempt was retried three times with increasing timeouts. That never happened — the 11:27 event is unrelated (no `ccs`/`claude -p`/`/ck:` string appears anywhere in `agent.log` between 11:20-11:27), and the two real brainstorm-incident failures (17:20:32 @90s, 17:47:58 @120s) are separated by 27 minutes with unrelated tool activity (a successful `error_max_turns` result, two successful terminal completions) in between — not a tight retry loop. If the planner or a future reader takes the "escalating retries" framing literally when deciding how urgently to ship this fix or when writing the CHANGELOG entry (Phase 2), the incident description will be factually wrong.
- **Evidence:**
  ```
  $ sudo -n -u hermes grep -n "20.28s\|timed out after 20s" /home/hermes/.hermes/logs/agent.log
  2930:2026-07-05 11:27:26,197 WARNING [...] Tool terminal returned error (20.28s): {"output": "[Command timed out after 20s]", "exit_code": 124, "error": null}
  ```
  vs. the real incident window confirmed separately:
  ```
  3503:2026-07-05 17:20:32,407 WARNING [...] Tool terminal returned error (90.47s): ... exit_code 124
  3602:2026-07-05 17:47:58,625 WARNING [...] Tool terminal returned error (120.46s): ... exit_code 124
  ```
  No `17:27:26` line exists anywhere in the file (`grep -c "17:27:26"` → 0 matches for exit_code lines).
- **Suggested fix:** Correct the Overview's log excerpt to cite only the two lines that are actually part of the same incident (17:20:32, 17:47:58), or explicitly separate the 11:27:26 line as a distinct, unrelated prior event if it's meant to establish "this class of failure recurs."

## Finding 2: No evidence the `coding-agent-delegate` skill's Tier-1 procedure was even active during the incident this plan fixes
- **Severity:** Critical
- **Location:** plan.md Overview (root-cause claim), Phase 1 Overview ("Rewrite ... Tier 1 procedure ... instead of a blocking foreground call")
- **Flaw:** The plan assumes the agent that produced today's `exit_code 124` failures was following `SKILL.md`'s Tier-1 procedure. Log evidence shows otherwise. The skill WAS explicitly invoked several times earlier in the day (07-04 21:43, 21:50; 07-05 11:12) — each producing a `Skill security warning for 'coding-agent-delegate'` line and a `[IMPORTANT: The user has invoked the "coding-agent-delegate" skill...]` system message. Between the session's history-reset (`tool_turns` drops from 49→31, `history` drops from 194→132 around 16:32) and the actual incident (16:34-17:47), there is **zero** occurrence of `skill_view`, `Skill security warning`, or `has invoked the` in that window. Instead: at `16:40:17` the user tells the agent in plain chat "Rule #1 is: Hermes Agent NEVER do the coding, brainstorm... [must delegate]", and at `17:18:48` the user literally dictates the command: `msg='No it\'s should be ccs ccs-hermes -p "/ck:brainstorm is the backend is optimized '`. The agent then calls `terminal()` directly with that exact command.
- **Failure scenario:** Phase 1 rewrites `SKILL.md` prose. If the real-world trigger for this bug class is a user dictating a raw command in chat (as it was today) rather than invoking `/coding-agent-delegate`, the agent never reads the rewritten Tier-1 section at all — it just calls `terminal()` per its own general tool knowledge/system prompt (`tools/terminal_tool.py:945-955`, which already documents background+notify_on_complete as "the right choice for almost every long task"). The fix could ship, pass Phase 3's smoke test (which explicitly invokes the skill), and the exact incident scenario from today (ad-hoc chat delegation) could still regress to foreground+124, because that path was never touched.
- **Evidence:**
  ```
  $ sudo -n -u hermes grep -n "skill_view\|Skill security warning\|has invoked the" agent.log | grep "2026-07-05 1[6-7]:"
  (no output)
  $ sudo -n -u hermes grep -n "history=1[3-9][0-9]|Turn ended" agent.log | grep "2026-07-05 1[2-7]:"
  3040: ...history=183 msg='Review the conversation above...'   # 12:07
  3462: ...history=132 msg='Ok giờ brainstorm xem thử backend...'  # 16:34 — history dropped 183→132, i.e. reset/compact occurred
  3481: ...history=137 msg='Rule #1 is: Hermes Agent NEVER do the coding...'  # 16:40
  3496: ...history=139 msg='No it\'s should be ccs ccs-hermes -p "/ck:brainstorm...'  # 17:18
  ```
- **Suggested fix:** Add a Phase 1 (or new Phase) task to also address the non-skill path — e.g. update Hermes' own system-prompt-level guidance or `terminal_tool`'s docstring examples for `ccs`/`claude -p` shell-outs specifically, since today's actual trigger bypassed the skill file entirely. At minimum, flag this as an Unresolved Question rather than asserting the SKILL.md rewrite is "the actual fix" (phase-01.md:18).

## Finding 3: `process(action="wait")` is internally clamped to `TERMINAL_TIMEOUT` (180s default) regardless of the caller's requested timeout — the same limit class the plan is trying to escape
- **Severity:** Critical
- **Location:** Phase 1, Requirements #5 ("`process(action='wait', session_id=...)` when the caller can afford to block"); Phase 3, Success Criteria #4 ("Final result retrieved via `wait`/`notify_on_complete`")
- **Flaw:** `ProcessRegistry.wait()` computes `default_timeout = int(os.getenv("TERMINAL_TIMEOUT", "180"))`, then `max_timeout = default_timeout`, and clamps: `if requested_timeout and requested_timeout > max_timeout: effective_timeout = max_timeout`. There is no higher ceiling analogous to `FOREGROUND_MAX_TIMEOUT` (600s) for `wait` — every single `wait()` call, no matter what `timeout=` value is passed, is capped at ~180s. On expiry it returns `{"status": "timeout", "output": <last 1000 chars>, "timeout_note": "Waited Xs, process still running"}` — the process itself is NOT killed (verified: no kill call in the timeout branch), so this isn't full data loss like the foreground case, but a single `wait()` call cannot "deliver the final result" for anything longer than ~180s as Phase 1/3 imply.
- **Failure scenario:** The agent calls `process(action="wait", session_id=...)` once per Phase 1's documented pattern for a `/ck:brainstorm` task that runs 10+ minutes. It gets back `status: timeout` after 180s, not the final result. Phase 1 never documents re-issuing `wait` in a loop (only a flat bullet list of poll/wait/log as independent one-shot actions), so a model naively following the skill's prose could treat `status: timeout` as an error/failure rather than "call wait again."
- **Evidence:** `tools/process_registry.py:1299` (`default_timeout = int(os.getenv("TERMINAL_TIMEOUT", "180"))`), `:1300` (`max_timeout = default_timeout`), `:1305-1311` (clamp logic), `:1358-1367` (timeout branch returns `status: timeout` with `"process still running"` note, no kill call).
- **Suggested fix:** Phase 1 must document `wait` as a call-in-a-loop-until-`status=exited` pattern (or default to `process(action="poll")` + sleep/re-check cadence instead of a single blocking `wait`), and Phase 3's Success Criteria #4/#5 must be updated to test a task that exceeds 180s specifically to catch this — not just confirm `wait` "delivers the final result" in the general case.

## Finding 4: The `toolsets:` frontmatter key Phase 1 edits is not read by any code path for gating OR discovery under that name — the plan's own hedge undersells a fact that's grep-resolvable, not genuinely unresolved
- **Severity:** High
- **Location:** Phase 1, Key Insights (`toolsets:` frontmatter list ..., "Unresolved whether a skill's declared `toolsets:` actually gates tool availability at runtime or is descriptive metadata only"); Unresolved Question 1
- **Flaw:** Grepped the actual skill-loading code path (`agent/skill_commands.py::_load_skill_payload` → `_build_skill_message` → `_inject_skill_config`): none of it reads a top-level `toolsets:` frontmatter key. The only toolset-conditional frontmatter field the codebase recognizes at all is `metadata.hermes.requires_toolsets` (nested under `metadata: hermes:`, a **different key path** than `coding-agent-delegate/SKILL.md`'s top-level `toolsets: [delegate_task, kanban, sandbox, file]`), extracted via `agent/skill_utils.py:551-552` (`extract_skill_conditions`) and consumed **only** by `_skill_should_show()` (`agent/prompt_builder.py:1383-1408`) to decide whether to list the skill in the discovery/system-prompt index — not to gate which tools a loaded skill's session can call. Two other skills in this repo (`skills/productivity/maps/SKILL.md:12`, `skills/research/research-paper-writing/SKILL.md:15`) use the correct nested `metadata: hermes: requires_toolsets:` schema; `coding-agent-delegate/SKILL.md` uses neither that schema nor a schema the code reads at all.
- **Failure scenario:** Phase 1 adds `terminal` to the top-level `toolsets:` list, believing it's either inert-if-unread or effective-if-enforced. It's actually neither of the two options the plan considers — the key isn't read at all under that name, so it can't grant runtime access (there's nothing to grant; `enabled_toolsets` is a session-level parameter set at agent init in `run_agent.py`/`cli.py`, not something a loaded skill amends). Today's incident already proves this empirically: the main session called `terminal` directly without ever loading `coding-agent-delegate` (Finding 2), so `terminal` availability is clearly session-scoped, not skill-scoped. Phase 3's plan to "confirm empirically" (Unresolved Question 1) is chasing a question the static code already answers — no live A/B test is needed, and Phase 3 Requirements #7 wastes verification budget on a non-question while under-verifying the real risk in Finding 3.
- **Evidence:**
  ```
  $ grep -n "toolsets" agent/skill_utils.py agent/skill_commands.py
  agent/skill_utils.py:551:  "fallback_for_toolsets": hermes.get("fallback_for_toolsets", []),
  agent/skill_utils.py:552:  "requires_toolsets": hermes.get("requires_toolsets", []),
  # (skill_commands.py: zero matches for "toolsets")
  $ grep -n "toolsets:" skills/dev/coding-agent-delegate/SKILL.md
  8:toolsets:
  9:  - delegate_task
  # top-level key, not nested under metadata.hermes — never read by extract_skill_conditions()
  ```
- **Suggested fix:** Downgrade Phase 1's Unresolved Question 1 to a resolved fact ("`toolsets:` at this schema position has zero effect; drop the requirement to add `terminal` there, or migrate to the correct `metadata: hermes: requires_toolsets:` schema used elsewhere in this repo if the intent is discovery-gating"). Remove Phase 3 Requirements #7's live A/B test — redirect that verification time to Finding 3's 180s-wait-clamp risk instead.

## Finding 5: Phase 3's smoke test cannot surface Finding 3's `wait`-clamp bug because `/ck:scout` likely finishes inside the 180s window
- **Severity:** Medium
- **Location:** Phase 3, Requirements #1 ("a short-but-multi-turn task, e.g. `/ck:scout`... avoid a full `/ck:brainstorm --hard`"), Implementation Steps #6 ("the small-task smoke test is sufficient evidence the mechanism works, and the mechanism doesn't care about task size")
- **Flaw:** Phase 3's own claim that "the mechanism doesn't care about task size" is false given Finding 3: `process(action="wait")`'s internal clamp is a hard 180s ceiling independent of `background=true` even succeeding. A short `/ck:scout` smoke test that finishes in well under 180s will make `wait()` return `status: exited` on the first call every time, never exercising the clamp/retry-loop path that a real multi-minute `/ck:brainstorm`/`/ck:cook` (the actual tasks named in the bug report, plan.md:5-6) would hit.
- **Failure scenario:** Phase 3 is marked complete with all Success Criteria checked (background mode works, poll works, log tails, wait "delivers the final result"), but the specific failure mode from the bug report — long `/ck:*` meta-skill runs — is never actually re-tested end-to-end. The fix ships with unverified behavior for exactly the class of task it was written to fix.
- **Evidence:** `tools/process_registry.py:1299-1300` (clamp is time-based, not size-based — confirmed in Finding 3); Phase 3 explicitly avoids running a task long enough to trigger it (Implementation Steps #6: "Do not run a full `/ck:brainstorm --hard`... here").
- **Suggested fix:** Add one Phase 3 check using a deliberately >180s task (e.g. `sleep 200 && echo done` wrapped the same way, or a `--max-turns` bound chosen to exceed 180s) specifically to exercise the `wait`-timeout/retry path before marking Phase 3 done, without needing the cost of a real `/ck:brainstorm --hard`.

## Finding 6: New `delegation-<run-id>.jsonl` artifact overlaps `~/.ccs/logs/current.jsonl` with no defined relationship, and `<run-id>` has no generation rule — risking a same-name overwrite race in the very `parallel=3` case Phase 1 targets
- **Severity:** Medium
- **Location:** Phase 1, Requirements #2 (the `terminal(...)` code block with `delegation-<run-id>.jsonl`), Success Criteria bullet "`parallel=3` example updated to use background mode"
- **Flaw:** (a) Scope/dedup: `~/.ccs/logs/current.jsonl` already exists, is actively written by every `ccs` invocation (verified: 80811 bytes, mtime 17:54 today, growing), and per the plan's own Overview is "correct and verified real" for this exact tail-progress use case. The plan introduces a second, overlapping artifact (`delegation-<run-id>.jsonl`) without stating whether it's redundant with, a superset of, or independent from `current.jsonl` — Phase 3 Requirements #6 checks `current.jsonl` gained an entry but never reconciles the two logs against each other. (b) Concurrency: `<run-id>` is a bare placeholder in Phase 1's code block with no specified generation rule (timestamp? uuid? provided by caller?). The redirect uses `>` (truncate), not `>>` (append). The `parallel=3` fan-out that Phase 1 explicitly must update (Success Criteria) launches 3 concurrent `ccs -p` calls; if the agent reuses the same literal `<run-id>` value (or a low-resolution one, e.g. a truncated timestamp) across the fan-out, two subtasks' `> delegation-<run-id>.jsonl` redirects race and the loser's file is silently truncated by the winner's open, losing that subtask's transcript — the exact "lose all output" failure this plan is meant to eliminate, just moved from foreground-timeout to filename-collision.
- **Failure scenario:** Phase 1 ships with the `<run-id>` placeholder un-specified; the model, at delegation time, picks something plausible-but-not-guaranteed-unique (e.g. current epoch second, which two fan-out branches launched in the same second would share); one of three parallel subtasks' logs gets clobbered mid-run.
- **Evidence:**
  ```
  $ sudo -n -u hermes ls -la /home/hermes/.ccs/logs/current.jsonl
  -rw------- 1 hermes hermes 80811 Jul  5 17:54 current.jsonl
  ```
  Phase 1 code block (`phase-01-....md:70-78`) uses `> /home/hermes/.hermes/logs/delegation-<run-id>.jsonl 2>&1` with no run-id generation instructions anywhere in Requirements or Implementation Steps. The existing `parallel=3` example already solves an analogous uniqueness problem for worktrees (`devin/claude-code-<ts>-subtask-N`, SKILL.md:181) — Phase 1 doesn't reference or reuse that pattern for the log filename.
- **Suggested fix:** Either drop the new log file and rely solely on `current.jsonl` (already verified real/working, avoids the dedup question entirely) or specify `<run-id>` as `<ts>-subtask-N`-style per Phase 1 Implementation Steps, reusing the existing worktree-naming convention, and use `>>` or a registry-tracked unique session id instead of a caller-guessed value.

## Unresolved Questions
1. If Finding 2 is confirmed (skill wasn't in play during today's incident), does the planner want a second phase targeting the non-skill/ad-hoc chat-delegation path, or is "fix the skill, accept ad-hoc chat delegation as out of scope" the intended boundary? Needs explicit scoping decision, not left implicit.
2. Should Phase 2's CHANGELOG entry cite the corrected two-timestamp incident (Finding 1) or the original three-timestamp version — recommend correcting before it's committed to a permanent changelog record.
