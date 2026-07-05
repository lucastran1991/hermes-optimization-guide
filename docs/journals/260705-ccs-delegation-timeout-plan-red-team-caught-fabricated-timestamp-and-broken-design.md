# CCS delegation timeout fix: red-team caught a fabricated timestamp and a self-defeating design, in my own plan

**Date:** 2026-07-05
**Plan:** `plans/260705-1752-ccs-delegation-timeout-progress-tracking-fix/`
**Trigger:** Hermes agent (Telegram bot) reported delegated `/ck:brainstorm`/`/ck:cook` calls via `ccs`/`claude -p` time out with no output. User pasted log-tailing advice from a prior chat turn as the starting point for `/ck:plan --red-team --validate --auto --parallel`.

## What happened

Did live-host + real-source research before writing anything (this host runs the actual `hermes` service; `/home/ubuntu/workspace/hermes-agent` is a checked-out copy of the real source). Found the actual bug: `coding-agent-delegate` skill's Tier-1 procedure shells `ccs -p` through Hermes' `terminal` tool in foreground mode with short timeouts; long tasks die with `exit_code 124`, losing all output. Hermes core already has the right primitive (`terminal(background=true)` + `process(poll/wait/log)`) — the skill just never used it.

Wrote the plan, then ran red-team (3 hostile reviewers: Security Adversary, Assumption Destroyer, Failure Mode Analyst) per the `--red-team` flag. This is where it got humbling:

- **I cited a fabricated timestamp.** My own root-cause narrative said three timeout events at 20s→90s→120s formed one escalating retry sequence. Assumption Destroyer grepped `agent.log` and found the 20s line was really at `11:27:26`, not the `17:27:26` I wrote — a distinct, unrelated turn 6 hours earlier. I'd pattern-matched three similar-looking log lines into a story that wasn't there.
- **My fix would have made things worse, not better.** The original design redirected the delegated CLI's stdout to a new log file (`> delegation-<run-id>.jsonl`). Security Adversary found this (a) bypassed the only redaction path in the codebase, making secrets recoverable in the clear via the skill's own `file` toolset, and (b) starved the same pipe that `process(action=poll/log)` reads from — so the "progress tracking" feature I was building would have returned empty output. Two independent Critical findings on the same design choice.
- **The "fix" itself had a timeout, too.** `process(action="wait")` — the primitive I was routing everything through — is internally clamped to `TERMINAL_TIMEOUT` (180s default), confirmed independently by two reviewers citing the same line numbers. A one-shot `wait()` call for a 10-minute `/ck:brainstorm` would return `status: "timeout"`, not a result. Had to rewrite the procedure as a retry loop.
- **`toolsets:` frontmatter is decorative.** All 3 reviewers independently traced the skill-loading code and found the top-level `toolsets:` key in `SKILL.md` is never read by anything — the real (different, nested) key is `metadata.hermes.requires_toolsets`, and even that only gates skill *discovery*, not runtime tool access. I'd left this as an "unresolved question needing live testing" in the draft; it was answerable by static grep the whole time.
- **The skill I was fixing might not be the thing that broke.** Assumption Destroyer found no log evidence `coding-agent-delegate` was even loaded during today's actual incident — the user dictated the `ccs`/`claude -p` command directly in chat, and the agent called `terminal()` on its own general knowledge. Surfaced this as an explicit scope question via `AskUserQuestion` rather than silently expanding or silently ignoring it; user chose to keep scope to the formal skill and accept the ad-hoc path as a known gap.

## Why this matters

Every one of these came with a `file:line` citation against real source, not opinion. The redesign that came out the other side (no new log file at all — reuse the pre-existing, already-verified `~/.ccs/logs/current.jsonl` / `~/.claude/projects/**/*.jsonl`) is simpler than the original AND fixes the security/functionality bugs simultaneously. That's the pattern worth remembering: when a red-team finding forces a redesign, look for the version that deletes complexity rather than patches around it.

## Process note

Followed through validate afterward per the `--validate` flag — since the red-team pass already carried full grep-verified evidence, the validate skill's own guard correctly skipped re-verification and went straight to a 3-question interview on the remaining genuine tradeoffs (synthetic vs. real test task for the >180s check, whether to flag the session-ownership gap upstream, whether to keep the low-priority docs-sync phase). All three landed on the recommended option.
