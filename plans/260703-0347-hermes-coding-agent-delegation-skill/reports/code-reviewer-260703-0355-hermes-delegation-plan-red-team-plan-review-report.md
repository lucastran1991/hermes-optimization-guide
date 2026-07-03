# Red-Team Review: Hermes Coding-Agent Delegation Skill Plan

Reviewer role: Contract Verifier (line/content citation verification against live repo).
Scope: `plan.md` + 4 phase files in `plans/260703-0347-hermes-coding-agent-delegation-skill/`.

## Finding 1: Phase 2's `acp` block citation is wrong and would drop the `acp:`/`enabled:`/`server:` keys

- **Severity:** Critical
- **Location:** Phase 2, section "Implementation Steps" step 3 (`phase-02-config-template-wiring.md:55`)
- **Flaw:** The plan cites `part18-coding-agents.md:195-206` as the source for the `acp` block ("the CLI client bindings ... that `delegation.routing` agent names resolve to"). Verified against the live file with `cat -n part18-coding-agents.md`: the actual `acp:` yaml fence runs lines 188-204. Lines 188-194 contain the fence open, the `acp:` top-level key, `enabled: true`, and `server: { listen: 127.0.0.1:41212 }` — all of which sit *outside* the cited 195-206 range. Lines 195-206 only cover the `clients:` sub-mapping (claude-code/codex/gemini-cli) plus a trailing prose sentence at 206 that isn't YAML at all.
- **Failure scenario:** An implementer following the plan literally ("Add `acp` block from `part18-coding-agents.md:195-206`") copies only the `clients:` entries, omitting the parent `acp:` key, `enabled: true`, and the `server.listen` field. Result: either invalid/orphaned YAML (indented client mappings with no parent key) or, if the implementer "fixes" the indentation ad hoc, a config that's missing the ACP-server capability (`enabled`, `server.listen`) part18 explicitly documents as half of what `acp` does ("Hermes supports ACP as both client and server"). This directly contradicts Phase 2's own success criterion "internally consistent with part18/part21 examples."
- **Evidence:**
  ```
  188  ```yaml
  189  # ~/.hermes/config.yaml
  190  acp:
  191    enabled: true
  192    server:
  193      listen: 127.0.0.1:41212          # Accept inbound ACP from editors
  194    clients:
  195      claude-code:                      <- cited range starts HERE
  ...
  204  ```
  205
  206  The `/delegate_task` tool then picks an ACP client based on ...
  ```
  (phase-02-config-template-wiring.md:15 cites the same wrong range in "Context Links": `part18-coding-agents.md:195-206`)
- **Suggested fix:** Correct the citation to `part18-coding-agents.md:188-204` in both the Context Links section and step 3, and explicitly require the `enabled: true` / `server:` keys in the block, not just `clients:`.

## Finding 2: plan.md's file-count claim is arithmetically wrong

- **Severity:** High
- **Location:** plan.md, "Overview" (`plan.md:20`)
- **Flaw:** States "Total surface: 6 files (2 new, 4 modified)". Actual modified-file count summed across phases' "Related Code Files → Modify" sections is 5, not 4: `.github/scripts/validate_skills.py` + `.github/workflows/ci.yml` (Phase 1, `phase-01-ci-toolset-validation.md:38-40`), `templates/config/production.yaml` (Phase 2, `phase-02-config-template-wiring.md:39-40`), `skills/README.md` + `CHANGELOG.md` (Phase 4, `phase-04-docs-and-catalog-sync.md:37-39`). New files: `.github/scripts/test_validate_skills.py` (Phase 1) + `skills/dev/coding-agent-delegate/SKILL.md` (Phase 3) = 2. Real total = 7 files, not 6.
- **Failure scenario:** Low direct execution risk, but this scope statement is used to justify "intentionally minimal per YAGNI" — an inaccurate headline count undermines the plan's own scope-tracking credibility and could mislead a reviewer auditing "did we touch only what we said we'd touch."
- **Evidence:** Modify lists at `phase-01-ci-toolset-validation.md:38-40`, `phase-02-config-template-wiring.md:39-40`, `phase-04-docs-and-catalog-sync.md:37-39`; Create lists at `phase-01-ci-toolset-validation.md:35-36`, `phase-03-coding-agent-delegation-skill.md:35-36`.
- **Suggested fix:** Update plan.md:20 to "7 files (2 new, 5 modified)".

## Finding 3: Cross-phase dependency (`blockedBy: [1]`) has no verification gate, only prose

- **Severity:** High
- **Location:** Phase 3, frontmatter `dependencies: [1]` (`phase-03-coding-agent-delegation-skill.md:7`) and Overview (`phase-03-coding-agent-delegation-skill.md:20`)
- **Flaw:** The plan states Phase 3 is "blockedBy: [1]" and that Phase 3 must not start "until Phase 1 merges" — but this is asserted only as YAML frontmatter metadata and prose in the Risk Assessment table (`phase-03-coding-agent-delegation-skill.md:126`: "Mitigation: `blockedBy: [1]` — do not start until Phase 1 merges"). There is no step in Phase 3's Implementation Steps that actually re-checks `ALLOWED_TOOLSETS` in the live `validate_skills.py` before authoring the SKILL.md frontmatter. Step 7 ("Validate") only runs the validator *after* the whole file is already written.
- **Failure scenario:** Plan.md explicitly designs Phase 1 and Phase 2 to run in parallel ("Group A ... can run concurrently", `plan.md:22,44`), implying multiple concurrent agent sessions. If whatever orchestrates phase execution advances to Phase 3 based on a task-tracker status flip (e.g., "Phase 1 marked done") rather than confirming the actual merged/current state of `.github/scripts/validate_skills.py`, Phase 3 could be authored against a stale `ALLOWED_TOOLSETS` that still lacks `kanban`/`sandbox`, and the frontmatter-fail wouldn't be caught until step 7 or CI — at which point the whole skill file needs rework, not just a one-line unblock.
- **Evidence:** `plan.md:37-44` dependency matrix is documentation-only prose (a markdown table), not an enforced gate; `phase-03-coding-agent-delegation-skill.md:126` risk mitigation is "do not start" (a human/process instruction), no automated precondition check specified anywhere in the phase's numbered Implementation Steps (`phase-03-coding-agent-delegation-skill.md:40-113`).
- **Suggested fix:** Add an explicit precondition step 0 to Phase 3: `grep -q '"kanban"' .github/scripts/validate_skills.py && grep -q '"sandbox"' .github/scripts/validate_skills.py || abort` before writing the SKILL.md file.

## Finding 4: "kanban"/"sandbox" toolset identifiers are invented, contradicting the plan's own "verbatim only" success criterion

- **Severity:** Medium
- **Location:** Phase 3, Success Criteria (`phase-03-coding-agent-delegation-skill.md:120`) and Frontmatter (`phase-03-coding-agent-delegation-skill.md:53-57`); Phase 1 `ALLOWED_TOOLSETS` addition (`phase-01-ci-toolset-validation.md:39,56`)
- **Flaw:** Phase 3's success criteria explicitly state "No invented identifiers — only verbatim names from report section 3." But the referenced research report (`research/researcher-skill-style-report.md`) section 3 only documents the toolset name as `` `kanban_*` `` (with the wildcard, quoting part23:36 verbatim: "Workers use the `kanban_*` toolset"). Neither the report nor any guide chapter establishes a bare, single-word `kanban` or `sandbox` string as a canonical toolset identifier — Phase 1 invents these exact strings for `ALLOWED_TOOLSETS`, and Phase 3 reuses them in `toolsets:`.
- **Failure scenario:** Not a CI-blocking issue (the validator only checks membership in the set the plan itself defines), but it's a self-contradiction: the plan asserts a "verbatim-only, no invention" rule as a hard success criterion, then violates it in the very toolset names central to the whole feature. This matters because it was raised as "Unresolved question 1" in the research report (`research/researcher-skill-style-report.md:75`) and the plan's "resolves report open-question 1" footnote (`phase-03-coding-agent-delegation-skill.md:72`) only addresses the *timing* (kanban/sandbox now exist in `ALLOWED_TOOLSETS` by the time Phase 3 lands) — it does not address the *naming* mismatch the same open question implicitly raises.
- **Evidence:** `research/researcher-skill-style-report.md:53` ("Kanban tool names (`part23-tenacity-stack.md:36`)... Workers use the `kanban_*` toolset"); `part23-tenacity-stack.md:36` (confirmed verbatim); vs. `phase-01-ci-toolset-validation.md:39` ("add `\"kanban\"`, `\"sandbox\"` to `ALLOWED_TOOLSETS`") and `phase-03-coding-agent-delegation-skill.md:55-56` (`toolsets: [..., kanban, sandbox, ...]`).
- **Suggested fix:** Either relax the "verbatim only" success criterion to explicitly allow toolset-category shorthand (consistent with existing entries like `github`, `telegram` which are also category names, not literal tool-call names), or document the naming decision inline instead of citing an unmet "verbatim" bar.

## Finding 5: Phase 1's TDD test-rewrite step is buried in prose, not restated in Success Criteria

- **Severity:** Medium
- **Location:** Phase 1, "Implementation Steps" step 4 (`phase-01-ci-toolset-validation.md:60`)
- **Flaw:** Step 4 requires rewriting `test_unknown_toolsets_rejected` mid-flow (from asserting `["kanban","sandbox"]` is rejected, to asserting a fabricated `["bogus_toolset"]` is rejected) once `ALLOWED_TOOLSETS` is updated — otherwise this test becomes permanently self-contradicting with the new capability (it would assert kanban/sandbox are still rejected, which is now false). This rewrite requirement exists only as inline prose in step 4; it is not listed as its own checklist item in "Success Criteria" (`phase-01-ci-toolset-validation.md:72-77`), which only checks aggregate outcomes ("3 tests passing", "kanban/sandbox present").
- **Failure scenario:** Low risk in practice since CI would catch a forgotten rewrite (the old assertion would fail once `ALLOWED_TOOLSETS` is widened, so `exits 0 with 3 tests passing` would fail) — this is self-correcting, not silent. Flagging as Medium because it's still an avoidable ambiguity: a literal reading of the checklist alone (without reading step 4's prose closely) under-specifies a required file edit.
- **Evidence:** `phase-01-ci-toolset-validation.md:60` vs. `phase-01-ci-toolset-validation.md:74` (checklist item doesn't name the rewrite).
- **Suggested fix:** Add an explicit Success Criteria line: "`test_unknown_toolsets_rejected` asserts rejection of a token that is NOT `kanban`/`sandbox` (e.g. `bogus_toolset`)."

## Finding 6: Phase 4's "no new links to validate" claim is only true for the row itself, not the file as a whole

- **Severity:** Medium
- **Location:** Phase 4, "Implementation Steps" step 3 (`phase-04-docs-and-catalog-sync.md:62`)
- **Flaw:** States "Confirm the new catalog row adds no new links ... so `markdown-link-check` has nothing new to validate here." The CI job (`ci.yml:10-22`) runs with `check-modified-files-only: 'yes'`, which means the *entire content* of any file touched in the diff gets scanned for links (not just the changed lines/rows). `skills/README.md` and `CHANGELOG.md` are both modified files under this plan, so both get fully re-scanned by markdown-link-check as part of this PR, not just the new row/entry.
- **Failure scenario:** Currently low real risk — verified `skills/README.md` has exactly one existing link (`skills/README.md:48`, to `../CONTRIBUTING.md`) and it resolves. But the plan's stated reasoning ("adds no new links... nothing new to validate") is imprecise: it implies the file's link-check surface is unaffected by touching it, when in fact touching *any* file makes its *entire* pre-existing link set part of this PR's CI gate. If either file had a stale link today, this PR — not the PR that introduced the stale link — would be blamed for the CI failure.
- **Evidence:** `ci.yml:21` (`check-modified-files-only: 'yes'`); `skills/README.md:48`.
- **Suggested fix:** Reword the claim to "the new row itself adds no links; confirm no pre-existing links in `skills/README.md`/`CHANGELOG.md` are currently broken before merging, since touching these files re-triggers whole-file link-check."

## Unresolved Questions

1. Should Finding 4 (naming) be resolved by relaxing the "verbatim identifiers only" rule, or by finding/inventing an authoritative single-word toolset name elsewhere in the guide before Phase 1 lands? Current plan does neither.
2. Finding 1 (acp citation) changes what Phase 2 actually ships — should the `enabled`/`server` fields be included even though the skill (Phase 3) never references Hermes-as-ACP-server behavior, only Hermes-as-ACP-client? If not needed by the skill, the plan should say so explicitly rather than silently truncating the source block via a bad line range.
