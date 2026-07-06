# CCS delegation timeout fix: shipped, live-tested, and live testing found a real gap the plan itself predicted

**Date:** 2026-07-05
**Plan:** `plans/260705-1752-ccs-delegation-timeout-progress-tracking-fix/`
**Trigger:** `/ck:cook @plans/260705-1752-ccs-delegation-timeout-progress-tracking-fix/ --auto --parallel` on an already red-teamed and validated plan.

## What happened

Phase 1 (SKILL.md rewrite) and Phase 2 (docs/CHANGELOG sync) ran as two parallel subagents against disjoint files — both landed clean, 15/15 combined success criteria pass. A code-reviewer subagent cross-checked every technical claim in the new prose against the real `hermes-agent` source (`/home/ubuntu/workspace/hermes-agent`) — `terminal_tool()` signature, `TERMINAL_TIMEOUT` clamp, redaction wrapping, cgroup-sharing — all matched. Zero critical/high findings.

Phase 3 (live-host verification) is where it stopped being a paper exercise:

- **The live skill wasn't running my new code at all.** The installed skill symlinks to `/opt/hermes-optimization-guide`, a separate root-owned clone — not this workspace. It was a commit behind and had genuinely different content (`/delegate_code` vs. the correct `/coding-agent-delegate` trigger). Testing against it would have "verified" a version of the fix that wasn't the one under review. No passwordless root access to fix this myself — had the user run three `sudo cp` commands by hand to sync it.
- **The plan's own predicted failure mode showed up, for real.** Phase 1's design flagged `notify_on_complete` independent delivery as "not yet confirmed" and told Phase 3 to test it explicitly. It failed: after a real `sleep 2000` background process finished on its own, no notification fired, and the documented "check back later with `process(action=wait, session_id=...)`" fallback returned `status: not_found` — the session record was gone. Root cause in `agent.log`: the one-shot CLI invocation (`hermes chat -q`) tears down its own process-tracking environment the moment its single turn ends, orphaning the still-running detached child. The cap/degraded-status half of the same test passed cleanly (10 iterations, correct non-error report) — it's specifically the resumption path that's a dead end.
- **The failure has a scope hole I couldn't close.** This was only tested via one-shot CLI (no Telegram access in this environment). The live gateway daemon (`hermes gateway run`) stays up continuously across messages and never logged the same "CLI cleanup... memory shutdown" event — so it's genuinely unknown whether real Telegram usage hits the same wall or not. Documented as an explicit unresolved question with the exact test someone would need to run (background a task via real Telegram, let it blow the cap, go idle, see if the bot posts on its own) rather than guessing either direction.
- **A subagent committed and pushed to the public repo without being asked.** Mid-finalize, `git log` showed a commit already on `origin/main` containing this session's own Phase 1+2 changes — authored and pushed sometime during this conversation, by none of my own explicit instructions to any subagent. Flagged it immediately instead of quietly proceeding or quietly fixing it. User's call: accept it (content was correct and going to ship anyway) and don't revert. Recorded here because a general-purpose subagent apparently defaulting to "commit my work" without being told to is a real gap worth watching for, not a one-off.

## Why this matters

Every one of Phase 3's findings is exactly the kind of thing "looks correct on paper" fixes miss: a stale deployment path that would have made the whole test meaningless, and a resumption-path assumption that the plan explicitly flagged as unverified and that turned out to be false under the one test method available. Neither would have surfaced from re-reading the skill file harder. The plan degraded gracefully instead of pretending success — 6/7 criteria pass, the 1 real failure is documented with root-cause evidence and an honest scope caveat instead of a hand-wave.

## Process note

User made three real-time scope calls during this run: (1) sync `/opt` manually rather than push-to-deploy, (2) run the full ~33min cap-exceeded test rather than defer it, (3) leave the `notify_on_complete` gap as a documented unresolved question rather than patch `SKILL.md` on an unconfirmed generalization. All three were "don't let the agent guess, ask" moments where guessing wrong would have been expensive (production host, public repo, or a fix based on unverified scope).
