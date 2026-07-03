---
phase: 4
title: "Docs and Catalog Sync"
status: completed
priority: P3
effort: "0.5h"
dependencies: [1, 2, 3]
---

# Phase 4: Docs and Catalog Sync

## Context Links

- Target: `part18-coding-agents.md` ("Mode 1: Print Mode" section, `:58-104`;
  "Parallel Delegation" subsection `:81-92`)
- Catalog row: `skills/README.md:42`
- Changelog format precedent: `CHANGELOG.md:1-20` (dated entries, most-recent-first,
  `### Added`/`### Changed` subsections)
- Depends on Phases 1-3's shipped content (this phase documents what actually
  shipped, not a pre-implementation draft)

## Overview

Priority: P3. Status: Pending. Parallel group C — runs last, after Phases 1-3 land.

Sync the guide's narrative docs with the shipped skill: add a CCS full-harness
routing subsection + a same-agent-type parallel example to
`part18-coding-agents.md`, tighten the `skills/README.md` catalog row, add a
`CHANGELOG.md` entry.

## Key Insights

- `part18-coding-agents.md`'s existing "Parallel Delegation" example
  (`:81-92`) fans out across *different* agent types (claude-code/codex/gemini-cli).
  This phase adds a second example: same agent type (claude-code), multiple
  subtasks, one CCS profile, each in its own git worktree — the new capability,
  not a replacement for the existing example.
- Do not name any external/private example repo in the shipped guide text — the
  guide is public-facing; describe the CCS pattern generically ("if you already use
  ClaudeKit + CCS for human Claude Code sessions, route delegation the same way"),
  not by referencing a specific unrelated codebase.
- **[Red-team, Medium, accepted] Be honest that `harness: ccs` is opt-in and needs
  a separate ClaudeKit install** — Phase 3 flipped the default to `bare` and added
  an explicit "does not by itself grant harness" caveat; this phase's prose must
  match that, not describe `ccs` routing as a drop-in harness upgrade.
- **[Red-team, Medium, accepted] `part18-coding-agents.md`'s top-level
  Prerequisites block (`:22-39`) currently only lists `claude`/`codex`/`gemini`/
  `opencode`/`aider` auth steps.** Leaving it unedited while adding CCS content
  deeper in the "Mode 1" section creates a top-to-bottom contradiction for a
  reader who stops at Prerequisites. Add a `ccs` line there too (marked "only if
  using `harness: ccs`").
- **[Red-team, Medium, accepted] `vi-docs/part18-coding-agents.md` (Vietnamese
  mirror, added one day before this plan, commit `f9e137b`) is explicitly OUT OF
  SCOPE for this phase** — no CI/CONTRIBUTING.md rule requires vi-docs to stay in
  sync with English content edit-for-edit, and this repo already has other
  English-only doc updates. Stating this explicitly (rather than silently letting
  it drift) is the accepted fix — no vi-docs file is touched by this plan.

## Requirements

- Functional: `part18-coding-agents.md` documents the CCS routing mode and the
  same-agent-type parallel pattern; `skills/README.md` row reflects the new
  capability; `CHANGELOG.md` has a new dated entry.
- Non-functional: no broken relative links introduced (this repo's link-check
  re-scans touched files, per sibling plan's Phase 4 precedent).

## Architecture

Docs-only, no runtime component.

## Related Code Files

**Modify:**
- `part18-coding-agents.md`
- `skills/README.md` (line 42)
- `CHANGELOG.md`

**Create:** none. **Delete:** none.

## Implementation Steps

### 0. Precondition (rollback-safety, per sibling plan's Phase 4 precedent)

1. Confirm Phases 1-3 landed as specified — re-read their final `SKILL.md`/
   `production.yaml`/bootstrap-script content before drafting doc prose, so this
   phase describes what actually shipped, not the plan's draft.

### 1. Implement

2. In `part18-coding-agents.md`'s top-level Prerequisites block (`:22-39`), add a
   `ccs` line (marked "only if using `harness: ccs`" — see step 2b).
2b. After the "From a Skill (Recommended)" subsection (`:62-79`) and before
   "Parallel Delegation" (`:81`), add a new subsection "CCS Routing (Optional,
   Claude Code Only)": explain that `coding-agent-delegate`'s `claude-code` branch
   supports an opt-in `harness: ccs` mode (default stays `harness: bare`) that
   routes through `ccs <profile> -p "..."` for a scoped delegation identity; state
   plainly that this alone does NOT grant ClaudeKit harness — that requires
   separately installing ClaudeKit on the delegating host (out of this guide's
   scope); link to `skills/dev/coding-agent-delegate/SKILL.md`'s Prerequisites for
   the one-time CCS profile setup and smoke-test gate.
3. In the "Parallel Delegation" subsection (`:81-92`), add a second worked example
   directly after the existing one: 3 subtasks, same agent (claude-code), one CCS
   profile, each in its own git worktree, concurrent — cite this repo's shipped
   skill example (Phase 3, step 6) rather than re-deriving it; include the
   throughput-unverified caveat from Phase 3.
4. `skills/README.md:42` — append to the existing row description: currently
   "Delegates a coding task to a CLI agent, escalating to a durable Kanban lane or a
   remote sandbox as the work demands"; append "; optional CCS-routed identity for
   Claude Code".
5. `CHANGELOG.md` — add a new entry above the current top entry
   (`## 2026-07-03 — Curator + Memory Hygiene Reminders & Meeting-Prep Memory
   Discipline`):
   ```markdown
   ## 2026-07-03 — CCS-Routed Coding-Agent Delegation (Opt-In)

   ### Added
   - `skills/dev/coding-agent-delegate/SKILL.md` gains `harness` (`bare` default /
     `ccs` opt-in) and `parallel` parameters: Tier 1's `claude-code` branch can
     optionally route through `ccs <profile> -p` for a scoped delegation identity
     (note: this alone does not grant ClaudeKit harness — that needs a separate,
     out-of-scope ClaudeKit install on the host), plus a same-agent-type parallel
     worked example using isolated git worktrees.
   - `templates/config/production.yaml` gains `delegation.ccs_profile`.
   - `scripts/vps-bootstrap.sh`/`-oci.sh` install `ccs` as a 5th coding-agent CLI
     (pinned `@8.7.0`); `templates/systemd/hermes.service` `ReadWritePaths`
     extended to `~/.ccs` (documented as an accepted, unresolved trust widening —
     see the skill's Security Considerations).

   ### Changed
   - `part18-coding-agents.md` documents optional CCS routing + the
     same-agent-type worktree-isolated parallel pattern.
   ```

### 2. Verify (link-check equivalent to sibling plan's Phase 4 step)

6. Re-scan the 3 touched files for relative links introduced/modified — confirm
   `skills/dev/coding-agent-delegate/SKILL.md` link (if added in part18) resolves.

## Success Criteria

- [x] `part18-coding-agents.md`'s top-level Prerequisites block mentions `ccs`
      (scoped to "only if using `harness: ccs`").
- [x] `part18-coding-agents.md` has a "CCS Routing (Optional, Claude Code Only)"
      subsection + a same-agent-type worktree-isolated parallel example, both
      describing what Phases 1-3 actually shipped (re-verified per step 1), and
      both stating CCS-routing alone does not grant harness.
- [x] `skills/README.md:42` row mentions optional CCS routing.
- [x] `CHANGELOG.md` has the new dated entry, correctly ordered (above the current
      top entry), reflecting the `bare`-default / `ccs`-opt-in framing.
- [x] No broken relative links in any touched file.
- [x] No private/unrelated example repo named in shipped guide text.
- [x] `vi-docs/part18-coding-agents.md` explicitly untouched — declared out of
      scope, not silently skipped.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Doc prose drifts from what Phases 1-3 actually shipped (plan vs. implementation) | Low | Med | Step 1 precondition: re-read final phase content before drafting, don't copy this plan's draft verbatim |
| Changelog entry placed in the wrong chronological position | Low | Low | Step 5 explicitly anchors "above the current top entry" |
| Guide text accidentally references a private/internal example repo | Low | Low | Key Insights explicitly flags this; step 2 keeps the pattern generic |

## Security Considerations

None — docs-only phase, no runtime/config surface.

## Next Steps

Terminal phase — no further phases depend on this one. Whole-plan consistency sweep
(mandatory per `verification-roles.md`) runs after red-team/validate edit any phase.
