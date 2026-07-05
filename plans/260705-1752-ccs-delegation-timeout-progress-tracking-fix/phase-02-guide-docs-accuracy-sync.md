---
phase: 2
title: "Guide Docs Accuracy Sync"
status: pending
priority: P3
effort: "45m"
dependencies: []
---

# Phase 2: Guide Docs Accuracy Sync

## Overview

Independent of Phase 1's skill rewrite (different files, no runtime
dependency — safe to run concurrently). Two accuracy fixes surfaced during
this plan's research:

1. `part18-coding-agents.md:79`-adjacent language ("streams progress back
   over a single WebSocket") describes the native `delegate_task`/ACP path
   and can be misread as already covering the Tier-1 CLI shell-out path that
   Phase 1 fixes. Add one clarifying line distinguishing the two.
2. CHANGELOG entry for this fix, since it changes documented delegation
   behavior (band-aid timeout bump → background-mode default) that other
   docs/skills may reference.

## Key Insights

- `part18-coding-agents.md:104` ("Hermes runs them in three independent
  subagent slots, streams progress, and aggregates") and `:229` ("The
  `/delegate_task` tool then picks an ACP client based on `delegation.routing`
  rules and streams progress back over a single WebSocket") both describe the
  **native** `delegate_task` subagent-spawning tool — a different mechanism
  from `coding-agent-delegate`'s Tier-1 CLI shell-out (confirmed distinct in
  `plans/260704-2106-.../phase-06-merge-delegation-config-and-docs.md`'s
  finding that the two features share the `delegation:` config key by
  coincidence, not implementation). A reader of `SKILL.md`'s Tier 1 section
  could conflate "streams progress" (real, for native subagents) with "Tier 1
  already streams progress" (false, until Phase 1 ships).

## Requirements

- **Functional:**
  1. `part18-coding-agents.md`: add one sentence near the WebSocket-streaming
     mention clarifying it describes the native `delegate_task` tool, not
     `coding-agent-delegate`'s Tier-1 CLI shell-out (which now uses
     `terminal(background=true)` + `process(poll/log/wait)` per Phase 1,
     surfacing progress via polling and existing session logs rather than a
     WebSocket).
  2. `CHANGELOG.md`: one entry describing the fix — cite the symptom
     (delegated `/ck:*` calls via `ccs`/`claude -p` time out with no output
     on long tasks) and the fix (background+process-loop pattern replaces
     blocking foreground calls in `coding-agent-delegate`'s Tier 1).
     **Use the red-team-corrected 2-line incident timeline** (17:20:32 @90s,
     17:47:58 @120s — see `plan.md` Overview) — an earlier plan draft cited
     a fabricated 3rd timestamp; do not let that propagate into the
     permanent CHANGELOG record.
  3. No changes to `part16-backup-debug.md` / `part11-gateway-recovery.md` —
     their existing `tail ~/.hermes/logs/*.log` guidance is already correct
     and unaffected.
- **Non-functional:** minimal diffs — this is an accuracy patch, not a
  rewrite; follow each file's existing tone/format.

## Related Code Files

- Modify: `part18-coding-agents.md` (one clarifying sentence near existing
  WebSocket-streaming mentions)
- Modify: `CHANGELOG.md` (one new entry, current version section)

## Implementation Steps

1. Read `part18-coding-agents.md` around lines 100-110 and 225-235 to find
   exact insertion points for the clarifying sentence.
2. Insert the clarification without restructuring surrounding prose.
3. Read `CHANGELOG.md`'s current top entry to match its existing format/tense.
4. Add one entry for this fix.
5. Skip vi-docs/* — this repo's translation sync is handled separately per
   existing docs process; not a blocker for this plan (English is the
   source of truth per `docs.maxLoc`/language rules).

## Success Criteria

- [ ] `part18-coding-agents.md` clarifies native-`delegate_task` streaming
      vs. Tier-1 CLI shell-out are different mechanisms.
- [ ] `CHANGELOG.md` has one new entry describing the fix, matching existing
      entry format/style.
- [ ] No unrelated content changed in either file.

## Risk Assessment

- **Risk:** none material — doc-only accuracy patch on files this phase
  owns exclusively; no runtime behavior affected.

## Unresolved Questions

None.
