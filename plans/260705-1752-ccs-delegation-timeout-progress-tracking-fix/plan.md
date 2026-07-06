---
title: "Fix CCS/Claude-Code Delegation Timeouts and Progress Tracking"
description: >-
  coding-agent-delegate's Tier-1 procedure shells `ccs`/`claude -p` out through
  Hermes' foreground `terminal` tool with short timeouts; long tasks
  (ck:brainstorm, ck:cook) exceed that and die with exit_code 124, losing all
  output. Fix: route through Hermes' native background+process(poll/wait/log)
  tooling instead, correct a stale log-path claim, verify live on the hermes host.
status: completed-with-known-limitation
priority: P1
effort: "4h45m"
branch: "main"
tags: [skill, delegation, ccs, terminal-tool, observability, bugfix]
blockedBy: []
blocks: []
created: "2026-07-05T17:57:08.113Z"
createdBy: "ck:plan"
source: skill
---

# Fix CCS/Claude-Code Delegation Timeouts and Progress Tracking

## Overview

**Live, active bug** — confirmed in today's `/home/hermes/.hermes/logs/agent.log` (2026-07-05, this session, same host this plan was written on). **Corrected per red-team Finding (Assumption Destroyer #1):** the incident is two `exit_code 124` failures 27 minutes apart, both during the same `/ck:brainstorm` delegation conversation (16:34-17:47):

```
17:20:32 Tool terminal returned error (90.47s): [Command timed out after 90s], exit_code 124
17:47:58 Tool terminal returned error (120.46s): [Command timed out after 120s], exit_code 124
```

(An earlier draft of this Overview also cited an `11:27:26` 20s-timeout line as part of the same "escalating retry" sequence under a fabricated `17:27:26` timestamp — that line is real but is a distinct, unrelated turn 6 hours earlier with no `ccs`/`claude`/`/ck:` context. Dropped from the incident narrative; not part of this bug.)

**Root cause** (verified against real `hermes-agent` source at `/home/ubuntu/workspace/hermes-agent`, not docs):
The agent is invoking `ccs ccs-hermes -p "/ck:brainstorm ..."` through Hermes' `terminal` tool in **foreground mode** with an explicit but insufficient `timeout=` (90s, then 120s on the next attempt — still nowhere near enough for a multi-turn `/ck:brainstorm` or `/ck:cook` run). Foreground mode blocks the whole tool call until the command exits or the timeout fires; on timeout the subprocess is killed and **all output is lost** — no partial result, no way to resume. Default foreground timeout is `TERMINAL_TIMEOUT=180`s (`tools/terminal_tool.py:1297`), hard-capped at `FOREGROUND_MAX_TIMEOUT=600`s (`tools/terminal_tool.py:107-112`, `TERMINAL_MAX_FOREGROUND_TIMEOUT` env var) — raising the timeout is a band-aid, not a fix, because some `/ck:*` meta-skill runs (multi-agent fan-out, red-team, validate) legitimately exceed 600s.

**The fix exists in Hermes core, partially, and is unused by this repo's skill.** `terminal_tool(..., background=True, notify_on_complete=True)` returns a `session_id` immediately with no execution timeout; the native `process` tool (`tools/process_registry.py:2044-2154`, actions `list/poll/log/wait/kill/write/submit/close`) polls status and retrieves output at any point, including mid-run. **Caveat found by red-team (Assumption Destroyer #3 / Failure Mode Analyst #2, both independently, matching line citations):** `process(action="wait")` is itself internally clamped to `TERMINAL_TIMEOUT` (180s default, `tools/process_registry.py:1299-1300,1360-1369`) regardless of the requested timeout — the same limit class this plan exists to escape. It must be called in a retry loop (`status == "timeout"` → call again), not once. `skills/dev/coding-agent-delegate/SKILL.md`'s Tier-1 procedure (`:71-87`) shows only blocking `--output-format json` examples and never mentions `background`/`process` — the skill never told the agent about the tool it needs, and even once it does, the loop pattern must be explicit.

**Scope gap found by red-team (Assumption Destroyer #2, Critical — see `## Red Team Review` below):** there is no log evidence the `coding-agent-delegate` skill was active during today's actual incident. The user dictated the raw `ccs ccs-hermes -p "/ck:brainstorm..."` command directly in chat; the agent called `terminal()` on its own general tool knowledge, never loading the skill. This plan's Phase 1 fix (rewriting `SKILL.md`) does not touch that ad-hoc, non-skill trigger path. **Resolved via explicit scope decision (see `## Scope Decision` below): fix the formal skill only; ad-hoc chat-dictated delegation is an accepted out-of-scope known-gap.**

Secondary finding: the "Yes, bạn có thể tail log thực tế" advice this plan originates from is **partially wrong** — `tail -f /home/hermes/.claude/sessions/*.jsonl` matches **zero files** (verified live: that dir is empty on this host). The real Claude Code transcript path is `~/.claude/projects/<slugified-cwd>/*.jsonl` (verified live: `/home/hermes/.claude/projects/-home-hermes-workspace/4c846a5f-....jsonl`, updated today). `~/.ccs/logs/current.jsonl` and `~/.hermes/logs/{agent,gateway}.log` are correct and verified real. `claude --output-format stream-json --verbose --include-partial-messages` is a real, documented flag combination (verified via `claude --help` on this host).

**Design correction from red-team (Security Adversary #1+#4, Critical, both targeting the same original design):** the original draft of this plan proposed shell-redirecting the delegated CLI's output to a new file (`> delegation-<run-id>.jsonl`). That was wrong on two independent grounds — (a) it bypasses the codebase's only redaction path (`_redact_process_result`, `tools/process_registry.py:2088-2110`), making secrets read by the delegated task recoverable in the clear via the skill's own already-granted `file` toolset; (b) it starves `spawn_local`'s own stdout pipe (`tools/process_registry.py:744-753`), so `process(action=poll/log)` — the mechanism Phase 1 is supposed to deliver — would return empty output. **Fixed:** Phase 1 now does not redirect to a new file at all. Progress/output flows through `process(action=poll/log/wait)` (redacted, in-memory) for near-term checks, and the pre-existing, already-verified-real `~/.ccs/logs/current.jsonl` / `~/.claude/projects/**/*.jsonl` for durable/external tailing. This also eliminates the run-id-collision risk the original design had for `parallel=N` fan-out (Security Adversary #6, Assumption Destroyer #6, Failure Mode Analyst #3 — all three independently flagged this on the now-removed file-redirect design).

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Background-Mode Delegation Procedure](./phase-01-background-mode-delegation-procedure.md) | Completed (12/12 success criteria, code-reviewer clean) |
| 2 | [Guide Docs Accuracy Sync](./phase-02-guide-docs-accuracy-sync.md) | Completed (3/3 success criteria, code-reviewer clean) |
| 3 | [Live-Host Verification](./phase-03-live-host-verification.md) | Completed with known limitation (6/7 success criteria; `notify_on_complete`/check-back-later confirmed dead-end via CLI testing after the 10-iteration cap, scope unconfirmed for live Telegram/gateway sessions — see phase file Unresolved Question #2, deferred per user decision) |

## File-Ownership Matrix (parallel mode)

| Phase | Files owned | Depends on |
|-------|-------------|------------|
| 1 | `skills/dev/coding-agent-delegate/SKILL.md` | none — start immediately |
| 2 | `part18-coding-agents.md`, `CHANGELOG.md` | none — start immediately, parallel with Phase 1 |
| 3 | none (verification only, no file edits unless Phase 1/2 review surfaces a fix) | Phase 1 (needs the new procedure to test); Phase 2 optional |

Phases 1 and 2 touch disjoint files and have no runtime dependency on each other — safe to run concurrently. Phase 3 is a live-host smoke test and must wait for Phase 1's rewritten procedure.

## Research (2026-07-05)

Community/best-practice research conducted — full report:
`plans/reports/research-community-best-practices-260705-1852-ccs-delegation-timeout-fix-report.md`.
Conclusion: background+poll architecture matches industry-standard async-agent
pattern, no redesign needed. Two deltas folded into this plan (both confirmed
via validate, see Validation Log Session 2):
1. Phase 1's `wait`-retry loop now caps at 10 iterations (~30min), degraded-
   status report on cap-exceeded (not error/kill) — community pattern always
   bounds poll loops; real precedent `anthropics/claude-code#68626` (unbounded
   background workers accumulate until OOM).
2. Phase 3 now reads `NousResearch/hermes-agent#16843` (open upstream issue:
   "Secret redaction breaks functional credential use in terminal commands")
   as a **blocking precondition** before the live smoke test — Phase 1's
   command uses `stream-json`/`--include-partial-messages`, the exact
   structured-output shape community sources flag as redaction-fragile.

## Dependencies

- **Not blocked by** `plans/260703-1738-fix-urgent-hermes-delegation-issues/` despite that plan's own Phase 3 (claude auth) / Phase 5 (CCS profile provisioning) still showing "Pending" in its `plan.md` — `plans/reports/scout-260705-1421-hermes-oci-live-host-best-practice-drift-audit-report.md` (today) verified both are actually functional live (`ccs-hermes` profile works, claude auth works). Phase 3 of *this* plan can run now; if it fails on auth grounds, that's new information contradicting the scout report, not an expected blocker.
- **Builds on** `plans/260703-0347-hermes-coding-agent-delegation-skill/` (completed) — same file (`skills/dev/coding-agent-delegate/SKILL.md`), no conflict since that plan is done and this only edits the Tier-1 section.
- **No interaction** with `plans/260704-2106-bootstrap-script-delegation-provisioning-scripts/` (in-progress, scopes `scripts/provision-hermes-delegation/` only) or `plans/260702-0525-oci-vps-bootstrap-variant/` (completed, `scripts/` only) — disjoint file sets.

## Red Team Review

### Session — 2026-07-05

**Findings:** 20 raw across 3 reviewers (Security Adversary, Assumption Destroyer, Failure Mode Analyst) → 14 unique after dedup (16 findings collapsed into 10 net changes; 3 findings fully resolved as a side effect of one design fix; 3 findings independently confirmed the same fact from 3 angles).
**Severity breakdown (deduped):** 5 Critical, 4 High, 5 Medium.

| # | Finding | Severity | Disposition | Applied To |
|---|---------|----------|-------------|------------|
| 1 | plan.md Overview cited a fabricated `17:27:26` timestamp; real incident is 2 lines (17:20:32, 17:47:58), not 3 | Critical | Accept | plan.md Overview |
| 2 | No log evidence `coding-agent-delegate` skill was active during today's incident — real trigger was ad-hoc chat dictation, bypassing the skill entirely | Critical | Accept (flagged, not silently expanded) | plan.md Overview + Unresolved Questions (scope decision deferred to user) |
| 3 | `process(action="wait")` clamped to `TERMINAL_TIMEOUT` (180s) regardless of requested timeout — same limit class this plan escapes | Critical | Accept | Phase 1 (loop pattern), Phase 3 (>180s test) |
| 4 | Proposed file-redirect design bypasses all secret redaction (readable via skill's own `file` toolset) | Critical | Accept | Phase 1 — redesigned to drop the new log file entirely |
| 5 | Same file-redirect design starves `process(action=poll/log)`'s own output buffer, defeating the plan's stated purpose | Critical | Accept | Phase 1 — same redesign as #4 |
| 6 | "Background survives Hermes restarts" is false — child shares the gateway's systemd cgroup (`KillMode=control-group`, no override) and dies with it | High | Accept | Phase 1 (claim removed), Phase 3 (documented as known limitation, not tested destructively on prod) |
| 7 | `process` actions (poll/log/wait/kill/write/submit/close) have no session-ownership check — cross-session hijack/DoS if a session_id leaks | High | Accept (documented as inherent Hermes-core limitation — out of this repo's scope to patch) | Phase 1 |
| 8 | New default hardcodes `Read,Edit,Bash`, dropping the existing no-Bash `Read,Edit` variant for edit-only tasks | High | Accept | Phase 1 |
| 9 | `toolsets:` frontmatter is not read by any skill-loading code path (confirmed independently by all 3 reviewers, 3 different citation chains) — decorative, not an access-control boundary | High | Accept | Phase 1 (resolved as fact, not left open), Phase 3 (live A/B test requirement removed) |
| 10 | `<run-id>` placeholder in the file-redirect design had no generation rule — injection/collision risk under `parallel=N` fan-out | Medium | Accept (moot) | Resolved as a side effect of dropping the file-redirect design (#4/#5) |
| 11 | Unescaped `<task>` interpolation into a shell argument — pre-existing gap, reused in the new higher-privilege background path | Medium | Accept | Phase 1 |
| 12 | No rotation for the (now-removed) new log artifact | Medium | Accept (moot) | Resolved as a side effect of dropping the file-redirect design |
| 13 | Phase 3's `/ck:scout` smoke test finishes under 180s — can't surface the `wait`-clamp bug | Medium | Accept | Phase 3 — added explicit >180s test |
| 14 | Phase 3 had no forced teardown/verification that no background session is left running | Medium | Accept | Phase 3 |
| 15 | Phase 3's steps were raw CLI invocations, not a real skill-dispatch trigger — risked validating CLI reachability, not the actual fix | Medium | Accept | Phase 3 |

### Whole-Plan Consistency Sweep
- Files reread: `plan.md`, `phase-01-background-mode-delegation-procedure.md`, `phase-02-guide-docs-accuracy-sync.md`, `phase-03-live-host-verification.md`.
- Decision deltas checked: 15 (table above).
- Reconciled stale references: removed all `delegation-<run-id>.jsonl` / file-redirect mentions from Phase 1 and Phase 3; removed the "survives Hermes restarts" claim; removed Phase 3's `toolsets:` live A/B test requirement; corrected the plan.md incident timeline everywhere it was referenced (Overview only — Phase 2's CHANGELOG-entry guidance now explicitly says to use the corrected 2-timestamp version).
- Unresolved contradictions: 0 remaining in the plan text itself. 1 scope decision (Finding 2 — whether to also address the ad-hoc/non-skill chat-delegation trigger path) was surfaced to the user via `AskUserQuestion` and resolved same-session — see `## Scope Decision` below.

### Session 2 — 2026-07-05 (research delta)

**Trigger:** `/ck:plan update ... --validate --red-team --auto --parallel` after
community/best-practice research (`plans/reports/research-community-best-
practices-260705-1852-ccs-delegation-timeout-fix-report.md`) surfaced 2 new
additions to review: Phase 1's wait-loop cap, Phase 3's GH-issue blocking
precondition. **Sticky-decision rule applied:** the 15 findings from Session 1
are locked, not re-litigated — only the new delta was reviewed, by 2 parallel
reviewers (1 per addition).

**Findings:** 10 raw (4 on the loop-cap addition, 6 on the GH-issue gate) →
0 Critical/blocking on either addition; both reviewers explicitly stated no
fatal design flaw found.

| # | Finding | Severity | Disposition | Applied To |
|---|---------|----------|-------------|------------|
| 16 | Loop-cap will fire routinely on the plan's actual target workload (`/ck:brainstorm --hard`, `/ck:cook --parallel` routinely exceed 30min), not as a rare edge case — prose read as if rare | Medium-High | Accept | Phase 1 item 7a — reworded to state this is the expected common outcome |
| 17 | Success Criteria's cap-exceeded/degraded-status bullet had no Phase 3 test driving 10 iterations (only 200s test existed) | Medium | Accept | Phase 3 — new item 4a, ~33min synthetic test (confirmed via validate) |
| 18 | Resumption path assumes `notify_on_complete` still delivers independently of a stopped `wait`-loop — never traced/tested | Medium | Accept | Phase 1 item 7a (flagged), Phase 3 item 4a (test added) |
| 19 | Degraded-status message hands back a `session_id` without repeating the item-8 bearer-capability secrecy caveat | Low | Accept | Phase 1 item 7a |
| 20 | GH-issue verdict logic only defined 2 of 3 real outcomes (confirmed/unrelated), no branch for inconclusive/inaccessible | High | Accept | Phase 3 Requirements item 0 — added fail-safe third branch |
| 21 | "Record the verdict" had no evidentiary bar — rubber-stamp risk given research itself didn't read the issue in depth | Medium | Accept | Phase 3 Requirements item 0 — added quote + status requirement |
| 22 | Scope mismatch: gate text implied blocking the whole phase sequence, but only item 4's synthetic tests actually run, carrying no real secrets | Medium | Accept | Phase 3 Requirements item 0 — scope note added |
| 23 | Repo identity (`NousResearch/hermes-agent` vs this project's local clone) not verified as the same repo anywhere in the plan | Low | Accept (verified: `git remote -v` confirms same origin) | Phase 3 Key Insights |
| 24 | No accessibility/timebox fallback if the issue is 404/private/rate-limited | Low | Accept (folded into #20's fail-safe branch) | Phase 3 Requirements item 0 |
| 25 | Potential conflict with Validation Log Session 1 Q2 ("don't file upstream") | Low | Accept (resolved as non-conflict: read ≠ file) | Phase 3 Requirements item 0 |

### Whole-Plan Consistency Sweep (Session 2)
- Files reread: `plan.md`, all 3 `phase-*.md` files, after applying all 10 dispositions above.
- Decision deltas checked: 10 (table above).
- Reconciled stale references: Phase 3 effort bumped 45m → 1.5h (frontmatter), plan.md total effort bumped 4h → 4h45m; Unresolved Questions item 1 updated to point at the now-resolved blocking-precondition process; no other file referenced the old un-capped loop or 2-outcome verdict logic.
- Unresolved contradictions: 0.

## Scope Decision (resolved 2026-07-05, via AskUserQuestion)

**Finding 2 scope question — resolved: fix the skill only.** Today's actual incident (ad-hoc chat-dictated `ccs`/`claude -p` command, never going through `coding-agent-delegate`) is explicitly accepted as an out-of-scope known-gap. This plan's Phase 1 fixes the formal `/coding-agent-delegate` Tier-1 procedure; it does not attempt to change Hermes' own base system-prompt/dispatcher behavior for ad-hoc, non-skill delegation. Not a blocker — do not silently re-expand scope back into Phase 1 without a fresh explicit decision.

## Unresolved Questions

1. ~~Whether `notify_on_complete`'s async delivery path passes output through `_redact_process_result`~~ — **widened and resolved into a blocking precondition** (Phase 3 Requirements item 0): read `hermes-agent#16843` before the live smoke test; escalate to a documented Phase 1 known-risk if it confirms `stream-json` redaction fragility. No longer purely open.
2. **New (Phase 3 live-host verification, 2026-07-05):** confirmed via CLI
   testing that `notify_on_complete`'s spontaneous delivery AND the
   documented "check back later" `process(action=wait/poll)` fallback both
   dead-end once the *originating `hermes chat -q` CLI turn* has ended
   (session record goes `not_found`) — but this was tested via one-shot CLI
   only (no Telegram access in this environment); NOT confirmed whether the
   same teardown happens in a live, persistent Telegram/gateway conversation
   (`hermes gateway run` stays up continuously, no matching "CLI cleanup"
   event observed for it). Per explicit user decision, not fixed in Phase 1
   yet — deferred pending a dedicated live-Telegram test. Full evidence:
   `phase-03-live-host-verification.md` Status Notes + Unresolved Question 2.
3. Whether `metadata.hermes.requires_toolsets` (the schema this repo's `SKILL.md` does NOT use, but two other skills in this repo do) is itself enforced anywhere in the real tool-execution path, or is discovery-listing-only like the top-level `toolsets:` key — not traced by red-team. Not a blocker for this plan (this plan doesn't rely on either key for security), but worth a future note if per-skill tool restriction is ever wanted as a real control.

## Validation Log

### Session 1 — 2026-07-05
**Trigger:** `--validate` flag on original `/ck:plan` invocation. Step 2.5 verification pass skipped per guard rule (`## Red Team Review` above already contains full grep/read-verified evidence).
**Questions asked:** 3

#### Questions & Answers

1. **[Scope/Tradeoff]** Phase 3 needs one delegation that deliberately runs past the 180s `wait()` clamp to prove the retry-loop pattern works. How should that test task be constructed?
   - Options: Cheap synthetic delay (Recommended) | Real multi-minute ck task
   - **Answer:** Cheap synthetic delay
   - **Rationale:** Isolates the `wait`-loop mechanism from `ccs`/`claude` cost/variability; cheapest and safest on a production host. Confirms Phase 3's existing "if too costly" hedge — now the committed approach, not an option.

2. **[Risk]** Red-team found `process(...)` has no session-ownership check in Hermes core. This plan documents it as a skill-level caveat only. Sufficient, or go further?
   - Options: Document only, as planned (Recommended) | Also flag upstream
   - **Answer:** Document only, as planned
   - **Rationale:** This repo doesn't own `hermes-agent` core; filing upstream is a separate, unscoped action the user didn't ask for.

3. **[Scope]** Phase 2 (docs accuracy sync) is P3/independent of the P1 core fix. Keep in this plan or defer?
   - Options: Keep as planned (Recommended) | Defer / drop Phase 2
   - **Answer:** Keep as planned
   - **Rationale:** Small, disjoint-file, ~45min patch; prevents the corrected incident timeline from being lost before it reaches the permanent CHANGELOG record.

#### Confirmed Decisions
- Phase 3's >180s test: synthetic delay command, not a real ck task — committed, not optional.
- Session-ownership gap: documented in skill only, no upstream action.
- Phase 2: in scope, ships alongside Phase 1/3.

#### Action Items
- [ ] Phase 3: tighten wording from "if driving a real multi-minute call is too costly" to a committed synthetic-delay approach.

#### Impact on Phases
- Phase 3: Implementation Steps item 4 — remove the "or" hedge, commit to synthetic delay.

### Whole-Plan Consistency Sweep
- Files reread: `plan.md`, all 3 `phase-*.md` files.
- Decision deltas checked: 3 (table above).
- Reconciled stale references: Phase 3's synthetic-delay wording tightened (see below).
- Unresolved contradictions: 0.

### Session 2 — 2026-07-05 (research delta)
**Trigger:** `/ck:plan update ... --validate --red-team --auto --parallel` after research surfaced 2 gaps in the plan's background/poll design. 4 questions asked total (3 upfront to scope the delta, 1 after red-team surfaced a test-coverage gap).

#### Questions & Answers

1. **[Risk]** Wait-loop cap (Phase 1) has no defined behavior on cap-exceeded — error/kill, or degraded status?
   - Options: Degraded status report (Recommended) | Hard error + kill session
   - **Answer:** Degraded status report
   - **Rationale:** No data loss, session stays resumable; hard error would reintroduce a milder version of today's bug for genuinely slow tasks.

2. **[Scope/Tradeoff]** What cap value?
   - Options: 10 iterations / ~30min (Recommended) | 20 iterations / ~60min
   - **Answer:** 10 iterations (~30min)
   - **Rationale:** Covers the actual `/ck:brainstorm`/`/ck:cook` failure case while bounding worst-case agent-turn time.

3. **[Risk]** Should Phase 3 treat reading `hermes-agent#16843` as a blocking precondition or informational-only?
   - Options: Blocking precondition (Recommended) | Informational only
   - **Answer:** Blocking precondition
   - **Rationale:** Don't run a live secret-bearing smoke test through an already-possibly-known-broken redaction path without checking first.

4. **[Scope/Tradeoff]** (Post-red-team) Phase 3's only long test (200s) never drives the new 10-iteration cap far enough to verify the degraded-status/`notify_on_complete` path. Extend the test, or defer verification?
   - Options: Extend to ~33min (Recommended) | Keep 200s test, mark deferred
   - **Answer:** Extend to ~33min
   - **Rationale:** Cheap synthetic `sleep`, near-zero real cost beyond wall-clock; verifies the actual resumption-path assumption end-to-end instead of shipping it untested.

#### Confirmed Decisions
- Cap-exceeded path: degraded status, not error — committed.
- Cap value: 10 iterations (~30min) — committed.
- GH-issue read: blocking precondition with 3-branch fail-safe verdict logic — committed.
- Phase 3 cap-exceeded test: ~33min synthetic delay, replacing the "deferred" fallback — committed.

#### Impact on Phases
- Phase 1: added item 7a (capped loop + degraded status + secrecy caveat + notify_on_complete caveat).
- Phase 3: added Requirements item 0 (3-branch GH-issue gate + evidentiary bar) and item 4a (~33min cap-exceeded test); effort 45m → 1.5h.
- plan.md: added `## Research` section, updated Unresolved Questions item 1, total effort 4h → 4h45m.

### Whole-Plan Consistency Sweep (Session 2)
- Files reread: `plan.md`, all 3 `phase-*.md` files (final pass after all Session 2 edits applied).
- Decision deltas checked: 4 (table above) + 10 red-team dispositions (Red Team Review Session 2).
- Reconciled stale references: none found — all cap/verdict-logic mentions across the 3 files use the final (capped/3-branch) versions; no file still describes an unbounded wait-loop or a 2-outcome verdict.
- Unresolved contradictions: 0.
