---
phase: 3
title: Coding Agent Delegation Skill
status: completed
priority: P1
effort: 1h15m
dependencies:
  - 1
---

# Phase 3: Coding Agent Delegation Skill

## Context Links

- Report: `research/researcher-skill-style-report.md` — section 1 (frontmatter), 2 (procedure conventions), 3 (verbatim identifiers), 4 (cross-link depth)
- Style match: `skills/dev/pr-review/SKILL.md` (closest structural sibling — also a delegate-to-coding-agent skill)
- Guide sources: `part18-coding-agents.md`, `part23-tenacity-stack.md`, `part21-remote-sandboxes.md`

## Overview

Priority: P1. Status: Pending. `blockedBy: [1]` — the frontmatter declares `kanban`/`sandbox` toolsets, which only pass CI after Phase 1 adds them to `ALLOWED_TOOLSETS`. Not blocked by Phase 2 (content comes from guide chapters, not the template file).

Author the new file `skills/dev/coding-agent-delegate/SKILL.md`. Its `## Procedure` presents the three-tier escalation in the exact order the user asked: tier 1 print-mode (part18) → tier 2 Kanban lane (part23) → tier 3 remote sandbox (part21). This is content ordering within one file, not three phases.

## Requirements

- Functional: valid frontmatter (passes `validate_skills.py`); `## Procedure` covers all three tiers in order; `## Escalation tiers` documents the decision logic with verbatim config snippets; `## Example invocation` + `## See also` with 3 working relative links.
- Non-functional: mirrors pr-review's structure (report section 2); concise. Prefer verbatim identifiers from report section 3 wherever the guide names one; the two toolset category labels `kanban`/`sandbox` are an accepted exception (see Requirements note below) — everything else (CLI flags, config keys, tool names like `kanban_create`) must be copied verbatim, not paraphrased.

**Red-team note on toolset naming:** the guide only ever names the granular `kanban_*` tool family (`part23-tenacity-stack.md:36`) and the `/sandbox` slash command, never a bare `kanban`/`sandbox` toolset category string. Phase 1 introduces these two category labels into `ALLOWED_TOOLSETS` by necessity — this repo's own `toolsets:` field is a category list, not a literal tool-call list, and existing entries like `github`/`telegram` are category names too, not literal API calls. Treat `kanban`/`sandbox` the same way: a category label for "this skill uses the Kanban toolset" / "this skill uses the sandbox toolset," consistent with the other 12 published skills' `toolsets:` blocks. Do not invent any *other* identifiers beyond this one accepted category-naming pattern.

## Architecture

The skill composes with three existing Hermes subsystems described in the guide (no new runtime): (1) the `delegate_task`/ACP dispatch layer + `delegation.routing` cost table (part18); (2) the Kanban worker-lane board `~/.hermes/kanban.db` via `kanban_*` tools + `/goal` completion contracts (part23); (3) the remote-sandbox backends from the `sandboxes:` config (part21). The skill is the decision layer that routes a task to the lowest sufficient tier and escalates on defined signals.

## Related Code Files

**Create:**
- `skills/dev/coding-agent-delegate/SKILL.md` (only file in this phase).

**Modify / Delete:** none.

## Implementation Steps

### 0. Precondition check (do this before writing anything)

`blockedBy: [1]` is plan-level metadata only — it is not mechanically enforced by any CI job or task runner in this repo. Before authoring the frontmatter below, verify Phase 1 has actually landed:
```bash
grep -q '"kanban"' .github/scripts/validate_skills.py && grep -q '"sandbox"' .github/scripts/validate_skills.py
```
If this fails, STOP — do not author the SKILL.md file yet (an early start would produce a file that fails CI and needs rework, not just a one-line unblock).

Write the complete file with this structure (mirror `skills/dev/pr-review/SKILL.md`):

### 1. Frontmatter

```yaml
name: coding-agent-delegate
description: <verb-first, >=10 chars, e.g. "Delegate a coding task to a CLI agent, escalating to a Kanban lane or remote sandbox">
when_to_use:
  - User invokes /delegate_code <task>
  - A Kanban card is assigned to a coding-agent lane
  - A task needs isolated or remote execution (heavy compute / untrusted deps)
toolsets:
  - delegate_task
  - kanban
  - sandbox
  - file
parameters:
  task:
    type: string
    description: "What to build/fix, in one line"
    required: true
  repo:
    type: string
    description: "Target repo/worktree path or owner/repo"
    required: true
  escalate:
    type: string
    enum: [auto, print, kanban, sandbox]
    default: auto
```
Note: `toolsets` declares real toolsets (resolves report open-question 1 — by the time this file lands, Phase 1 has added `kanban`/`sandbox`).

### 2. H1 + security-note blockquote

- H1: `# coding-agent-delegate — Tiered Coding-Agent Delegation`.
- Security-note blockquote right after H1 (resolves report open-question 2 — warranted, not decorative: unlike pr-review's read-only case, this skill hands agents Bash/Write/Edit access, which is higher risk). Content: delegated sub-sessions may get write/exec tools; scope the tool allowlist to the minimum per tier; isolate each delegation on its own branch/worktree; never pass writable production credentials into a sub-session.

### 3. `## Procedure` (numbered, bold lead phrase per step)

1. **Parse the task** — read `task`, `repo`, `escalate`; classify intent (refactor / bugfix / explore / dependency_audit).
2. **Tier 1 — print mode (default)** — pick an agent via the `delegation.routing` cost table (quote `part18-coding-agents.md:108-123`), invoke print-mode CLI (quote `part18-coding-agents.md:72-77`: `claude -p "..." --allowedTools "Read,Edit,Bash" --max-turns 20 --output-format json`); `/delegate_task` selects the ACP client per routing (`part18:206`). **Red-team addition:** the security blockquote (step 2 below) says "scope the tool allowlist to the minimum per tier," but this is the only worked example and it's the maximally-permissive one (full `Bash`). Pair it with a scoped-down variant for tasks that don't need shell access, mirroring pr-review's read-only pattern (`skills/dev/pr-review/SKILL.md:49`, `--allowedTools "Read"` with no Edit/Bash/Write): `claude -p "..." --allowedTools "Read,Edit" --max-turns 20 --output-format json` for edit-only tasks (no Bash), reserving the full `Read,Edit,Bash` allowlist for tasks that explicitly need to run commands (tests, builds).
3. **Detect escalation signals** — long-running / needs human review / multi-handoff → tier 2; needs isolation / heavy compute / untrusted deps → tier 3.
4. **Tier 2 — Kanban lane** — create a durable card: `/kanban create "..." --assignee codex-worker --workspace worktree` (quote `part18:130-133` / `part23:20-24`); workers use `kanban_*` (`kanban_create`, `kanban_show`, `kanban_complete`, `kanban_block`, `kanban_comment`, ...) per `part23:36`; attach a `/goal` completion contract so the card only closes when conditions are demonstrated (`part23:87`).
5. **Tier 3 — remote sandbox** — `/sandbox start <name>` (from `sandboxes:` config, `part21:79`), delegate inside it, `/sandbox stop <name>` to sync changes back (`part21:81`).
6. **Git hygiene** — isolate one branch/worktree per delegation (per part18's "Git Hygiene When Agents Share a Workspace" section) so parallel agents never clobber each other.

### 4. `## Escalation tiers`

- Decision table: signal → tier → mechanism.
- Quote the tier-1 `delegation.routing` yaml (`part18:108-123`), the tier-2 `/kanban create` form, and the tier-3 `sandboxes:` yaml (`part21:54-74`) verbatim.

### 5. `## Example invocation`

Fenced block, pr-review style:
```
/delegate_code "fix flaky checkout tests" repo=myorg/app
/delegate_code "refactor src/auth to JWT rotation" repo=myorg/app escalate=kanban
/delegate_code "run full e2e suite" repo=myorg/app escalate=sandbox
```

### 6. `## See also`

- `- [Part 18: Coding Agents](../../../part18-coding-agents.md)`
- `- [Part 23: Tenacity Stack](../../../part23-tenacity-stack.md)`
- `- [Part 21: Remote Sandboxes](../../../part21-remote-sandboxes.md)`

(3-levels-up relative depth confirmed for `skills/<cat>/<name>/SKILL.md` — report section 4.)

### 7. Validate

Run `python .github/scripts/validate_skills.py`; confirm the new file reports `ok`.

## Success Criteria

- [ ] Step 0 precondition check passes (`kanban`/`sandbox` confirmed present in the live `ALLOWED_TOOLSETS`) before the file is authored.
- [ ] `validate_skills.py` reports `ok  skills/dev/coding-agent-delegate/SKILL.md`.
- [ ] File follows pr-review structural conventions (report section 2).
- [ ] Procedure presents tiers in order: print mode → Kanban lane → sandbox.
- [ ] Tier-1 procedure step includes both a scoped (`Read,Edit`) and a Bash-enabled (`Read,Edit,Bash`) print-mode example, not only the maximally-permissive one.
- [ ] All 3 `## See also` links resolve (`../../../partN-*.md`).
- [ ] No invented identifiers beyond the accepted `kanban`/`sandbox` category-label exception — everything else matches verbatim names from report section 3.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Frontmatter fails CI (kanban/sandbox not yet allowed) | Was Med (red-team: Critical — `blockedBy` is prose, not enforced) | High | Step 0's grep precondition check is a real, executable gate, not just frontmatter metadata |
| Broken relative cross-links | Low | Med | Use exact `../../../` depth (report section 4); markdown-link-check CI catches it |
| Invented/misspelled tool names | Med | Med | Copy identifiers verbatim from report section 3; `kanban`/`sandbox` category labels are the one documented exception |
| Security note treated as boilerplate | Low | Med | Explicitly cover write/exec tool scoping + per-delegation branch isolation |
| Only worked example is maximally-permissive (`Bash` enabled) | Was unaddressed (red-team High) | Med | Step 2 of Procedure now pairs a scoped `Read,Edit` example with the `Read,Edit,Bash` one |

## Security Considerations

Higher risk than pr-review: delegated agents may receive Bash/Write/Edit. Enforce least-privilege tool allowlists per tier (default to the scoped `Read,Edit` example unless the task needs to run commands), per-delegation branch/worktree isolation, and never inject writable production credentials into a sub-session (call this out in the security blockquote, step 2). Cross-reference Phase 2's `security.approval.require_approval` update: this skill's `delegate_task`/`kanban`/`sandbox` toolsets are gated there the same way `terminal` is — the skill body should not claim these tools are ungated. Also note (do not attempt to fix in this phase): `security.approval.denylist` is a regex over terminal exec strings and does not see structured `kanban_*`/`sandbox`/`delegate_task` invocations — this is a known limitation of the existing approval layer, not something this skill can compensate for on its own.

## Next Steps

Unblocks Phase 4 (catalog row needs the file to exist).
