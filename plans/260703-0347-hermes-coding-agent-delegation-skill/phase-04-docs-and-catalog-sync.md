---
phase: 4
title: Docs and Catalog Sync
status: completed
priority: P3
effort: 20m
dependencies:
  - 2
  - 3
---

# Phase 4: Docs and Catalog Sync

## Context Links

- Catalog: `skills/README.md` (## Catalog table — `dev` rows present)
- Changelog: `CHANGELOG.md` (dated `## YYYY-MM-DD — ...` sections with `### Added/Changed/Removed`)
- Rule: `documentation-management.md` "After Feature Implementation"; repo `CLAUDE.md` commit-message rule (no emoji, no AI-authorship refs — applies to doc entries in the same spirit)

## Overview

Priority: P3. Status: Pending. `blockedBy: [2, 3]` — needs the skill file to exist (catalog row) and knowledge of Phase 2's config changes (accurate changelog line).

Two surgical doc edits: one catalog row, one changelog entry. No file rewrites.

## Requirements

- Functional: `skills/README.md` catalog gains one `dev` row for `coding-agent-delegate`; `CHANGELOG.md` gains one entry describing the skill + config-template changes.
- Non-functional: match existing table/section formatting exactly; no emoji; no AI-authorship references; touch nothing else.

## Architecture

Docs only — no runtime. The catalog table is the human-facing index of installable skills; the changelog is the dated guide-update log. Both are append-style edits.

## Related Code Files

**Create:** none.

**Modify:**
- `skills/README.md` — add one row to the `## Catalog` table.
- `CHANGELOG.md` — add one entry.

**Delete:** none.

## Implementation Steps

### 0. Precondition: re-verify Phase 3 before publishing

`blockedBy: [2, 3]` is plan-level metadata, not an enforced gate. Before writing the catalog row or changelog entry, re-run `python .github/scripts/validate_skills.py` and confirm `skills/dev/coding-agent-delegate/SKILL.md` still reports `ok`, and skim the file once more for any last-minute change. There is no changelog-amend convention in this repo (`CHANGELOG.md` is append-only dated sections) — publishing a catalog row + changelog entry that reference a Phase 3 file which is later found wrong has no clean rollback, only a follow-up correction entry. Catching it here, before publishing, is cheaper than after.

### 1. Catalog row (`skills/README.md`)

1. Add a single row to the `## Catalog` table, same column order as existing rows (`| Category | Skill | What it does |`):
   ```
   | **dev** | `coding-agent-delegate` | Delegates a coding task to a CLI agent, escalating to a durable Kanban lane or a remote sandbox as the work demands |
   ```
   Place it near the other `dev` rows. Do NOT rewrite or reorder the table; add the one row only.

### 2. Changelog entry (`CHANGELOG.md`)

2. Check current format first (it's dated sections `## YYYY-MM-DD — <title>` with `### Added`, newest at top under the intro line). Add a new dated section for today (`## 2026-07-03 — Coding-Agent Delegation Skill`) directly below the intro paragraph (line ~3), above the newest existing section, with an `### Added` list:
   - one bullet: new `dev/coding-agent-delegate` skill — tiered delegation (print mode → Kanban lane → remote sandbox).
   - one bullet: `templates/config/production.yaml` gains `delegation`, `acp`, and `sandboxes` blocks, plus `security.approval.require_approval` entries for the new toolsets (describe what Phase 2 actually added — confirm against the merged Phase 2 change, including the `.env`-exclusion fix and the approval-gate wiring).
   No emoji, no AI-authorship references, plain descriptive prose matching neighboring entries.

### 3. Verify

3. The new catalog row itself adds no new markdown links (plain table cell). That does NOT mean `skills/README.md` is exempt from link-checking — the repo's `check-modified-files-only: 'yes'` CI setting (`ci.yml:21`) re-scans the *entire* content of any touched file, not just the new row. Run the local equivalent directly rather than asserting nothing needs checking: `npx -y markdown-link-check skills/README.md` (per `CONTRIBUTING.md`'s local-preview instructions). `skills/README.md` currently has exactly one link (`../CONTRIBUTING.md`) — confirm it still resolves.
4. Eyeball table pipe/column alignment against neighbors (exact pipe alignment not required by CI, but keep column order identical).

## Success Criteria

- [ ] Step 0 precondition re-check passes (`validate_skills.py` still reports `ok` for the Phase 3 file) before publishing.
- [ ] `skills/README.md` catalog has exactly one new `dev` / `coding-agent-delegate` row; nothing else changed.
- [ ] `CHANGELOG.md` has one new dated section describing the skill + config changes (including the `.env`-exclusion and approval-gate additions from Phase 2); no emoji, no AI refs.
- [ ] Changelog line about config matches what Phase 2 actually merged.
- [ ] `npx -y markdown-link-check skills/README.md` run locally and passes (not just asserted as unnecessary).
- [ ] Table column order matches existing rows.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Changelog describes config that differs from what Phase 2 shipped | Med | Med | `blockedBy: [2]`; verify against merged `production.yaml` before writing the line |
| Phase 3 content found wrong after this phase already published the catalog+changelog references | Was unaddressed (red-team High) | Med | Step 0 re-validates Phase 3 immediately before publishing; no changelog-amend convention exists, so catching it here is the only real mitigation |
| Accidental broad edit / table reorder | Low | Med | Single-row append; diff-review before commit |
| Emoji / AI-authorship slips into doc entry | Low | Low | Repo CLAUDE.md rule; final read-through |
| Assuming the touched file needs no link-check because the new row itself has no links | Was unaddressed (red-team Medium) | Low | Step 3 now runs the actual local `markdown-link-check` command instead of asserting it's unnecessary |

## Security Considerations

None — documentation only.

## Next Steps

Final phase. On completion the plan is done; consider a `docs impact: minor` note. No push without explicit user confirmation (repo memory: never push to remote).
