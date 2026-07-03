---
phase: 1
title: production.yaml curator and memory_audit config blocks
status: completed
effort: 1h
---

# Phase 1: production.yaml curator and memory_audit config blocks

## Context Links

- Source guide: `part5-creating-skills.md:117-150` (Curator), `part7-memory-system.md:116-134` (audit/journey + anti-patterns)
- Research: `plans/reports/researcher-260703-0915-curator-config-application-report.md`, `plans/reports/researcher-260703-0917-memory-system-part7-application-report.md`
- Style precedent: `plans/260703-0347-hermes-coding-agent-delegation-skill/phase-02-config-template-wiring.md`
- Model blocks in target file: `cron:` (`templates/config/production.yaml:289-294`), `security.approval` (`:237-264`), `memory:` LightRAG (`:118-126`), `telemetry:` (`:277-287`)

## Overview

**Priority:** P1 (largest surface, blocks Phase 3 changelog). **Status:** Pending.

<!-- Updated: Red Team Session 2 (adversarial, 3 hostile reviewers) — Findings RT2-1/RT2-2 -->
**Design changed after adversarial red-team review.** The original design (top-level
`curator:`/`memory_audit:` config blocks with `schedule`/`auto_archive`/`stale_threshold_days`/
`suspicious_patterns` fields) was **fabricated** — 3 independent hostile reviewers confirmed
via grep that neither `part5-creating-skills.md` nor `part7-memory-system.md` documents any
YAML-configurable engine for Curator or `/journey`. Both are described **only** as interactive
CLI/TUI/desktop commands (`hermes curator run --dry-run`, `hermes curator enable`, `/journey`
opened by a human — `part5:121-132`, `part7:120-123`, `part26-moa-verification.md:98,101,168`).
Shipping an invented schema risks the block being silently inert (unknown keys ignored) while
the operator believes hygiene is now automated, and stops doing the guide's actual mandated
manual passes. See Red Team Review in `plan.md` for full adjudication.

**Revised approach:** add two entries to the **existing, already-proven** `cron:` list
(`templates/config/production.yaml:289-294` — real infra, used by 5 entries today) that send a
**scheduled reminder** to run the real documented commands manually. This is not automation of
Curator/`/journey` — it is a calendar nudge, matching exactly what Part 5/7 actually prescribe
("run `hermes curator run --dry-run` after major upgrades", "Do a `/journey` pruning pass
monthly"). No new top-level YAML key, no invented engine, no schema risk beyond what the other
5 `cron:` entries already carry.

No new skill file. No `ALLOWED_TOOLSETS` change (both researchers confirmed: `validate_skills.py` only validates `skills/**/SKILL.md`, not config). No `security-hardened.yaml` change in this phase — deferred as a documented follow-up (see Risk Assessment), not a silent omission, since the reminder-only design would be equally cheap/safe to add there too.

## Key Insights

- **Curator and `/journey` are CLI/interactive-only, never YAML-configurable in the guide.** `grep -rn "curator:" part*.md` and equivalent for `/journey` scheduling both return zero matches for an engine config schema. Any `curator:`/`memory_audit:` top-level key is invented, not sourced (Red Team RT2-1, RT2-2 — 3/3 reviewers independently confirmed).
- **Memory pruning is NOT auto-pruning** — `part7:123` mandates a *monthly human review*; a wrong memory "gets injected into every future session and compounds", so only the operator can judge correctness. The revised design never claims automated scanning — it only reminds the operator to run `/journey` themselves.
- **Do not fabricate a scoring formula or a regex classifier.** `part5:137` names five scoring dimensions (freshness, usage, clarity, overlap, safety) but assigns **no numeric weights** — and `part7` describes memory anti-patterns in prose, never as a regex/pattern list. The prior design's `*_weight` floats, `archive_threshold`, and `suspicious_patterns` regexes were all invented. Cut entirely (YAGNI + honesty; RT-1 from session 1, RT2-1/RT2-2 from session 2).
- **`pinned_skills` targeted the wrong category.** `part5:141` (uncited in the original design) says Curator "Focuses on agent-created skills first, not bundled/vendor skills" — the four names proposed (`coding-agent-delegate`, `nightly-backup`, `audit-mcp`, `rotate-secrets`) are this repo's own bundled/vendor skills, exactly what Curator already deprioritizes. Cut; the reminder-only design has no pin mechanism to misapply (RT2-3, 3/3 reviewers).
- **Reusing `cron:`'s proven list-of-maps shape** (not inventing a new top-level scalar-block shape) resolves the Contract Verifier concern about whether any real Hermes engine consumes an unproven schema — the `cron:` engine is the one piece of scheduling infra this file already demonstrably uses correctly.

## Requirements

Functional:
- Two new entries appended to the existing `cron:` list (`templates/config/production.yaml:289-294`) — no new top-level YAML key.
- Every field traces to a cited guide line (see mapping table below). No invented engine schema, scoring floats, or regex patterns.

Non-functional:
- Comments cite `part5-creating-skills.md:NNN` / `part7-memory-system.md:NNN` (matches Phase 2 convention of prior plan).
- `notify:` reuses the existing `telegram_dm` channel token used by every other `cron:` entry — no new channel type invented (RT-2, still holds under the revised design).

## Architecture / Data Flow

```
Scheduler (Hermes cron engine — the SAME one already driving the other 5 `cron:` entries)
   ├── monthly-skill-curator-reminder → notify telegram_dm: "run `hermes curator run --dry-run`
   │                                     then `hermes curator run`" — operator executes manually
   └── monthly-journey-reminder       → notify telegram_dm: "open `/journey`, prune stale/wrong
                                         memories" — operator executes manually
```

Data in: none (these are reminder strings, not scans). Data out: two Telegram DM reminder
messages/month. Neither entry mutates the skill registry or memory store — both are pure
scheduled notifications that hand off to a human running the real, documented CLI/TUI command.
This eliminates the entire "does an automated scanner exist" question the red team raised,
because there is no scanner — only a calendar nudge.

## Related Code Files

- Modify: `templates/config/production.yaml` (only file this phase touches).
- Read for style: same file `:118-126`, `:237-264`, `:289-294`.
- Do NOT touch: `templates/config/security-hardened.yaml`, `.github/scripts/validate_skills.py`, any `skills/**`.

## Implementation Steps

1. Open `templates/config/production.yaml`. Locate the `cron:` list (starts line 289, 5 existing entries ending at line 294).
2. Append two new entries to the end of the `cron:` list. Fields and traceability:

   | Field | Value | Traces to |
   |-------|-------|-----------|
   | `name` | `monthly-skill-curator-reminder` | matches existing `cron:` naming convention |
   | `schedule` | `"0 8 1 * *"` (monthly, 1st 08:00 UTC) | `part5:146` ("run `--dry-run` after major upgrades"); monthly cadence chosen since no guide-specified schedule exists for Curator beyond "weekly" for the CLI's own optional scheduler (`part5:128`) — this is a *reminder* cadence, not a claim about Curator's own schedule |
   | `task` | reminder string naming the real CLI commands | `part5:123-125` (`hermes curator run --dry-run`, `hermes curator run`) |
   | `notify` | `telegram_dm` | matches every other `cron:` entry |
   | `name` | `monthly-journey-reminder` | matches existing `cron:` naming convention |
   | `schedule` | `"0 8 2 * *"` (monthly, 2nd 08:00 UTC — offset one day from the curator reminder so they don't collide in one DM) | `part7:123` ("Do a `/journey` pruning pass monthly") |
   | `task` | reminder string naming `/journey` | `part7:123` |
   | `notify` | `telegram_dm` | matches every other `cron:` entry |

   Exact lines to append (inside the existing `cron:` list, same style as the 5 entries above them):

   ```yaml
     # Part 5/7 hygiene reminders. Curator and /journey are interactive CLI/TUI
     # commands (hermes curator run --dry-run/run; /journey) — the guide never
     # documents a headless/automated mode for either, so these are scheduled
     # REMINDERS to run them manually, not automated scans or auto-pruning.
     # See part5-creating-skills.md:117-150, part7-memory-system.md:116-123.
     - { name: monthly-skill-curator-reminder, schedule: "0 8 1 * *", task: "Reminder: run `hermes curator run --dry-run` then `hermes curator run` to review skill-library duplicates/stale skills.", notify: telegram_dm }
     - { name: monthly-journey-reminder,       schedule: "0 8 2 * *", task: "Reminder: open `/journey` and prune any wrong or stale memory entries.", notify: telegram_dm }
   ```

3. Verify YAML parses: `python3 -c "import yaml,sys; yaml.safe_load(open('templates/config/production.yaml')); print('OK')"` (or `ck`/`hermes config validate` if available).
4. Confirm no accidental edit outside the appended lines: `git diff templates/config/production.yaml` shows only two new `cron:` list entries, no changes to the 5 existing entries or any other block.

## Todo List

- [ ] Append `monthly-skill-curator-reminder` entry to the existing `cron:` list
- [ ] Append `monthly-journey-reminder` entry to the existing `cron:` list
- [ ] Both entries' comments cite part5/part7 line numbers
- [ ] No new top-level YAML key (`curator:`/`memory_audit:`) introduced
- [ ] No scoring weights, `stale_threshold_days`, `suspicious_patterns`, or `pinned_skills` present anywhere
- [ ] `notify` uses existing `telegram_dm` token only
- [ ] YAML parses clean
- [ ] `git diff` shows only two new list entries, no other changes

## Success Criteria

- [ ] Two new entries exist in `templates/config/production.yaml`'s `cron:` list, valid YAML, no new top-level key.
- [ ] Neither entry claims or implies automated scanning/pruning — both are reminder-only task strings pointing at real CLI/TUI commands.
- [ ] Every field has an inline `partN:line` citation OR matches an existing `cron:` convention (name/notify style).
- [ ] No fabricated engine config (scoring weights, regex patterns, thresholds, pin lists) present anywhere in the diff.
- [ ] No change to `security-hardened.yaml`, `validate_skills.py`, or any `SKILL.md`.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Operator reads the reminder as "Curator/journey now run automatically" | Low | Med | Task strings are explicit imperative reminders ("Reminder: run...", "Reminder: open...") addressed to a human, not declarative engine config; block comment states outright there is no headless mode. |
| `security-hardened.yaml` doesn't get the same reminders | Med | Low | **Accepted, documented deferral** (RT2-C from red team) — this file is the one other template with its own `cron:` block (`security-hardened.yaml:110-119`), so adding the same two lines there later is a trivial 2-line follow-up, not a redesign. Deferred to keep this plan's file-count at 3 (YAGNI); noted here so it isn't a silent gap. |
| Two reminders both fire same-day and get missed in Telegram noise | Low | Low | Offset by one calendar day (1st vs 2nd of month) specifically to avoid collision — no other mitigation needed for a manual reminder. |

## Security Considerations

- Both entries are **admin-only config** (edited on host, not chat-invokable) and, after the redesign, carry **zero automation** — no approval-gate wiring needed, unlike Phase 2 of the prior plan which added *write-capable tool* surfaces (`delegate_task`/`kanban`/`sandbox`) to `security.approval.require_approval`. A reminder string is not a tool call surface.
- Neither entry mutates the skill registry or memory store, reads secrets, or introduces new egress — `notify: telegram_dm` reuses the already-configured channel. The original design's redaction/report-content concern (RT2 Assumption Destroyer/Failure Mode Analyst findings) is moot: there is no report content, only a static reminder string.

## Next Steps

Blocks Phase 3 (changelog must describe the exact fields shipped — cron reminder entries, not config blocks). Independent of Phase 2 (different file) — run in parallel group A.
