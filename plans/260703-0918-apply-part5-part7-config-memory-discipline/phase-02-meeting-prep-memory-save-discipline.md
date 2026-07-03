---
phase: 2
title: meeting-prep memory save discipline
status: completed
effort: 45m
---

# Phase 2: meeting-prep memory save discipline

## Context Links

- Source guide: `part7-memory-system.md:17-33` (Tier 1 what/what-NOT to save), `:44-64` (session_search vs memory), `:125-134` (anti-patterns table)
- Research: `plans/reports/researcher-260703-0917-memory-system-part7-application-report.md:33-44`
- Target skill: `skills/dev/meeting-prep/SKILL.md`

## Overview

**Priority:** P2. **Status:** Pending.

`meeting-prep` is the **only** skill in the repo that declares the `memory` toolset (`SKILL.md:7-11`) — grep-verified across all `skills/**/SKILL.md`. It *reads* memory (line 46 "pulled from memory if relevant", line 68 `/search`) but documents **zero** save/don't-save discipline. Part 7 exists to close exactly this gap.

Add a short `## Memory discipline` section inline in the skill, applying Part 7 Tier-1/Tier-2 rules to the meeting-prep context. No behavioral change to the skill's procedure — it's a discipline note so that if the agent *is* tempted to write memory after a meeting, it knows what belongs (durable attendee facts) vs. what does not (this meeting's task list → `session_search`).

## Key Insights

- The audit corrected the user's premise: only **1 of 3** presumed memory-toolset skills actually declares it. `nightly-backup` and `spam-trap` mention the word "memory" in prose but do **not** list it in `toolsets:` (verified: `awk` over `toolsets:` block matched only `meeting-prep`). So this phase touches exactly one file — do not scope-creep into the other two.
- `meeting-prep.security.notes` already says "Does not write" (`SKILL.md:20-21`). That refers to *email/Slack/calendar* writes. The `memory` toolset is still granted and *can* write. The discipline note must reconcile this: reads are the norm; any memory *write* is the narrow durable-fact exception, never task state.
- <!-- Updated: Red Team Session 2 (adversarial) — Finding RT2-D --> **The skill has THREE sections between `## Meeting: {title}` and `## Related`, not two.** `grep -n "^## " skills/dev/meeting-prep/SKILL.md` confirms: `## Procedure` (line 57), `## Triggering 15 min before each meeting` (line 77, contains a `cron:` YAML example), then `## Tips` (line 88). All 3 red-team reviewers independently caught that the original insertion instructions ("after Procedure line 75, before Tips line 88") skipped over `## Triggering`, which would have wedged the new section between Procedure and its own triggering config. Corrected below.

## Requirements

Functional:
- New `## Memory discipline` section added to `skills/dev/meeting-prep/SKILL.md`.
- States: what TO save (durable attendee/relationship facts), what NOT to save (this meeting's agenda/asks/task state → use `session_search` instead), citing Part 7 rules.
- Placed after `## Triggering 15 min before each meeting` (ends line 86) and before `## Tips` (line 88) — NOT immediately after `## Procedure` (line 75), which would wedge it ahead of the triggering config.

Non-functional:
- Under ~12 lines. This is a discipline note, not a rewrite.
- No change to frontmatter, `toolsets:`, procedure steps, or output shape.

## Related Code Files

- Modify: `skills/dev/meeting-prep/SKILL.md` (only file this phase touches).
- Read for context: `part7-memory-system.md:17-33,125-134`.
- Do NOT touch: `nightly-backup/SKILL.md`, `spam-trap/SKILL.md` (they do not declare the memory toolset — no gap to close), `skills/README.md` (catalog row unchanged — the skill's one-line description is still accurate).

## Implementation Steps

1. Open `skills/dev/meeting-prep/SKILL.md`. Locate the end of `## Triggering 15 min before each meeting` (line 86, closing the ```` ``` ```` of its `cron:` example) and the start of `## Tips` (line 88). Do not insert right after `## Procedure` (line 75) — that would land the new section ahead of `## Triggering` (lines 77-86), splitting the procedure from its own invocation config.
2. Insert this section between them:

   ```markdown
   ## Memory discipline

   This skill holds the `memory` toolset, so apply Part 7's save rules
   deliberately — a wrong or transient memory is injected into every future
   session and compounds.

   **Save to memory** (durable, still true in 6 months):
   - Stable attendee facts: role/title, timezone, communication style, standing
     preferences ("prefers async updates").
   - Recurring-relationship context that improves *every* future brief.

   **Do NOT save to memory** — recall with `session_search` instead:
   - This meeting's agenda, open asks, or action items (task state, changes weekly).
   - Anything one-off or date-specific ("follow up next Tuesday").

   Default is read-only (see `security.notes`). Writing memory is the narrow
   exception for durable relationship facts, never per-meeting task state.
   ```

3. Confirm the wording maps to guide lines: "durable facts / still true in 6 months" → `part7:64`; "what to save: preferences/stable conventions" → `part7:21-26`; "what NOT to save: task progress, temporary state → use session_search" → `part7:27-30,129`.
4. Verify no other section changed: `git diff skills/dev/meeting-prep/SKILL.md` shows a single additive section, frontmatter untouched.

## Todo List

- [ ] Insert `## Memory discipline` between `## Triggering 15 min before each meeting` and `## Tips` (NOT between `## Procedure` and `## Triggering`)
- [ ] Save/don't-save rules present, each traceable to a part7 line
- [ ] `session_search` named as the alternative for transient recall
- [ ] Frontmatter / toolsets / procedure unchanged
- [ ] Confirm no other memory-toolset skill exists (grep) — none to also patch

## Success Criteria

- [ ] `## Memory discipline` section exists in `meeting-prep/SKILL.md` with both a save list and a don't-save list.
- [ ] The don't-save list routes transient recall to `session_search` (Tier 2), matching `part7:64,129`.
- [ ] Frontmatter, `toolsets:`, output shape, and the 5 procedure steps are byte-identical to before.
- [ ] No edit to `nightly-backup` or `spam-trap` SKILL.md (they lack the memory toolset).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Discipline note contradicts existing `security.notes` "Does not write" | Med | Med | Note explicitly reconciles: default read-only; memory write is the narrow durable-fact exception. Both statements coexist. |
| Scope-creep into patching skills that only mention "memory" | Med | Low | Verified via `awk` on `toolsets:` block — only meeting-prep declares it. Phase scope is one file. |
| Over-long note bloats a "read-in-60-seconds" skill | Low | Low | Capped ~12 lines, placed after procedure so it never delays the brief. |

## Security Considerations

- Reinforces least-privilege on a granted-but-mostly-unused capability: the skill *has* `memory` write but should almost never use it. Documenting the boundary reduces accidental persistence of meeting content (which may include sensitive attendee/deal context) into always-injected memory.
- Complements `security.memory_write_redaction: true` (`production.yaml:272`) — redaction catches secrets; this note catches *category* mistakes (task state) that redaction won't.

## Next Steps

Independent of Phase 1 (different file) — parallel group A. Feeds Phase 3 changelog (the skill-hygiene line).
