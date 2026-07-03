# Part 7 Memory System Application Research

**Date:** 2026-07-03 | **Task:** Apply Part 7 memory discipline guidance to repo conventions; coordinate with Part 5 curator precedent

---

## Summary

**Recommendation: Doc-only for memory tier discipline + config audit block for `/journey` pruning operationalization.** No new skill. Add a `memory_audit:` block to `templates/config/production.yaml` (parallel to Part 5's `curator:` block) to schedule monthly `/journey` review reporting, but pruning remains manual (operator-judged, unlike curator's auto-archive).

---

## Findings

### 1. Part 7 Skill vs. Config vs. Docs: Apply as What?

**Answer: (c) Doc-only for memory tier discipline; config audit block for `/journey` scheduling.**

**Evidence:**

- Part 7:117–138 documents `memory` / `session_search` / `skill_manage` as **tool discipline** (what to save, when to use each tier), not new infrastructure features like Part 5's curator.
- Part 5 precedent (researcher-260703-0915-curator-config-application-report.md): curator is a **system feature** (`hermes curator run`), not a skill — implemented as config-only. Memory tools follow the same pattern: they're built-in system commands (`memory()`, `session_search()`, `skill_manage()`, `/journey`, `/learn`), not task-automation skills.
- Repo's skill catalog (14 skills): all are task-automation workflows (backup, audit, triage). None document infrastructure discipline. Memory hygiene guidance belongs in **docs**, not a 15th skill.
- Part 7:123 says "Do a `/journey` pruning pass monthly." This is **operator hygiene**, not a scheduled auto-task. Unlike curator (which auto-archives low-score skills per a scoring function), memory pruning requires human judgment: "a wrong memory gets injected into every future session and compounds" — only the operator knows if a stored fact is wrong.

**Conclusion:** 
- Memory tier discipline (`memory` vs. `session_search` vs. `skill_manage` rules) → new doc file or embedded in `docs/code-standards.md`.
- Monthly `/journey` pruning schedule → new `memory_audit:` config block (non-destructive reporting, not auto-deletion).
- No new skill file.

---

### 2. Memory Toolset Usage in Existing Skills: Do Any State Save/Don't-Save Rules?

**Finding: Only 1 of 3 expected skills actually declares memory toolset; that skill has no inline discipline.**

**Evidence:**

**Discrepancy:** User premise listed 3 skills using memory toolset (`meeting-prep`, `nightly-backup`, `spam-trap`). Actual audit:
- `meeting-prep/SKILL.md:7–11`: **YES**, `toolsets: [email, slack, classify, memory]` ✓
- `nightly-backup/SKILL.md:8–10`: **NO**, `toolsets: [terminal, file]` only.
- `spam-trap/SKILL.md:7–9`: **NO**, `toolsets: [classify]` only.

**Meeting-prep guidance gap:** The skill mentions memory in output shape (line 54: "pulled from memory if relevant") and procedure (line 68: `/search` with meeting title + attendee names), but provides **no save/don't-save rules**. No guidance on: "After meetings, save attendee patterns to memory" OR "Don't save task lists, use session_search instead." This is exactly the gap Part 7 is designed to fill.

---

### 3. Should `/journey` Monthly Pruning Be Operationalized as Cron Config?

**Recommendation: Yes, as a `memory_audit:` reporting block (non-destructive), not auto-deletion.**

**Rationale:**

- Part 7:123 mandates monthly pruning discipline, but it's not auto-pruning — it's manual review + operator delete (via `/journey delete`).
- **Model:** Follow curator block pattern (part5-creating-skills.md:143–150), but report-only:

```yaml
memory_audit:
  enabled: true
  schedule: "0 2 1 * *"              # Monthly 1st, 02:00 UTC
  dry_run_before_auto: false          # Unlike curator, no auto-delete — all manual
  # Detection: highlight suspicious entries for human review
  stale_threshold_days: 180           # Flag facts >6mo old, no usage
  suspicious_patterns:
    - 'TODO\|task\|progress'          # Part 7:29 anti-pattern: task progress in memory
    - 'date-specific.*next\s+(week|month)'  # Volatile temporal facts (Part 7:30)
    - 'temporary\|temp\|WIP'          # Explicit temp flags
  report:
    stale_count: true
    suspicious_sample: 3              # Show 3 examples for review
  notify: telegram_dm
```

**Why non-destructive:** curator auto-archives because skill scoring is deterministic (freshness, usage, clarity metrics). Memory correctness is episodic: a fact can be unused for 6mo, then suddenly critical. Operator must judge.

---

### 4. CI/Toolset Validation: Does ALLOWED_TOOLSETS Need Entry for `/journey`, `/learn`, or `session_search`?

**Answer: No change needed.**

**Evidence:**

- Prior researcher (validator-260703-0915): "toolsets only gate skill validation, not admin config" (part5:16–31: `ALLOWED_TOOLSETS` validates skills via grep on `skills/*/SKILL.md`, not config).
- `/journey`, `/learn`, `session_search`, `memory` are **built-in commands/tools**, not declared by skills in frontmatter. They don't go in skill `toolsets:` lists.
- If they were exposed as MCP tools in `mcp_servers:` (unlikely), they'd need gating. But they're Hermes-native.
- No new `ALLOWED_TOOLSETS` entry.

---

## Citations

- Part 7 memory system overview: `part7-memory-system.md:1–138`
- Memory tier discipline (what to save): `part7-memory-system.md:27–33` (memory), `:44–64` (session_search), `:66–98` (skill_manage)
- Anti-patterns table: `part7-memory-system.md:125–134`
- `/journey` + `/learn` v0.18: `part7-memory-system.md:116–123`
- Monthly pruning mandate: `part7-memory-system.md:123`
- Part 5 curator precedent: `researcher-260703-0915-curator-config-application-report.md:15–39` (system feature, config-only, no skill)
- Existing memory block (backend config): `templates/config/production.yaml:118–126`
- Existing cron block model: `templates/config/production.yaml:289–294`
- Meeting-prep skill memory gap: `skills/dev/meeting-prep/SKILL.md:7–11, 54, 68`
- Skill-only validation scope: `.github/scripts/validate_skills.py:88`

---

## Unresolved Questions

1. **Config block naming:** Should it be `memory_audit:`, `journey_audit:`, or `memory_discipline:`? Curator sets precedent with present-tense noun (`curator:`). Suggest `memory_discipline:` to parallel curator's vibe (system admin feature, not a skill task).

2. **Stale threshold tuning:** The `stale_threshold_days: 180` is illustrative. Should this be configurable per fact category (e.g., environment facts: 365d, project facts: 90d), or one global threshold? Needs guidance from operators who use `/journey` in production.

3. **Docs location:** Should memory tier discipline (Part 7) sit in new file `docs/memory-system-guide.md`, or embedded in `docs/code-standards.md`? Curator guidance went into docs/ implicitly (update in phase-02-docs of prior plan). Follow that lead.
