# Red-Team Failure-Mode Review — Hermes Coding-Agent Delegation Skill Plan

Reviewer: code-reviewer (Failure Mode Analyst persona)
Plan: `plans/260703-0347-hermes-coding-agent-delegation-skill/`

## Fact-check ledger (claims verified against codebase)

| Claim | Result |
|---|---|
| 13 pre-existing `SKILL.md` files (before Phase 3 adds a 14th) | VERIFIED — `find skills -name SKILL.md` returns exactly 13 files |
| `validate_skills.py:16-29` = `ALLOWED_TOOLSETS` | VERIFIED — dict spans lines 16-29 exactly |
| `validate_skills.py:46-72` = `validate()` | VERIFIED |
| `ci.yml:34-45` = `skill-frontmatter` job, `:44-45` = validator step | VERIFIED |
| `ci.yml` has `needs:` between jobs (dependency enforcement) | FAILED — zero `needs:` keys in the file; all 4 jobs run independently |
| `CONTRIBUTING.md:25`/`:27` (comment fields / no-secrets rule) | VERIFIED via `grep -n` |
| `production.yaml:1-220` (no delegation/acp/sandboxes yet) | VERIFIED (file is 219 lines, blocks absent) |
| `part18-coding-agents.md:108-123` (delegation.routing yaml) | VERIFIED — fence-to-fence exact |
| `part18-coding-agents.md:195-206` (acp clients block) | UNVERIFIED/FAILED as a precise "whole acp block" citation — see Finding 6 |
| `part21-remote-sandboxes.md:54-74`, `:79/:81` | VERIFIED |
| `part23-tenacity-stack.md:20-24/:36/:87` | VERIFIED |
| `../../../partN-*.md` relative link depth from `skills/dev/coding-agent-delegate/SKILL.md` | VERIFIED — identical pattern in `skills/dev/pr-review/SKILL.md:89-90` |
| CI pins Python 3.11 (`ci.yml:41`) | VERIFIED |

## Finding 1: Cross-phase dependency (`blockedBy`) is documentation-only, not mechanically enforced

- **Severity:** Critical
- **Location:** plan.md:37-44 (dependency matrix); phase-03-coding-agent-delegation-skill.md:7,20,126
- **Flaw:** The only thing stopping Phase 3 from starting before Phase 1 actually lands is a YAML `dependencies: [1]` field and prose ("do not start until Phase 1 merges"). Grep of `.github/workflows/ci.yml` shows zero `needs:` keys — no CI-level or scheduler-level gate exists.
- **Failure scenario:** Phase 3's frontmatter declares `toolsets: [..., kanban, sandbox, ...]` (phase-03-coding-agent-delegation-skill.md:53-57). `kanban`/`sandbox` are absent from `ALLOWED_TOOLSETS` (`validate_skills.py:16-29`, confirmed) until Phase 1's edit lands. If the orchestrating agent/session dispatches Phase 3 concurrently with, or before, Phase 1 actually completes (e.g. group-A/B table misread, or Phase 1 stalls mid-refactor), the new SKILL.md fails `validate_skills.py` with `unknown toolsets: ['kanban', 'sandbox']` and nothing in the repo prevents that state from being committed.
- **Evidence:** `.github/workflows/ci.yml` (full file grepped, no `needs:` anywhere); `phase-03-coding-agent-delegation-skill.md:126` risk row treats this purely as a documentation discipline problem ("`blockedBy: [1]` — do not start until Phase 1 merges").
- **Suggested fix:** Either serialize phases 1→3 for real (single session, in order) instead of calling it "parallel," or add a pre-flight check step to Phase 3 that runs `python .github/scripts/validate_skills.py` on a throwaway file declaring `kanban`/`sandbox` before authoring the real skill, failing fast if Phase 1 hasn't actually landed in the working tree.

## Finding 2: Plan's regression safety net is CI, but repo policy means CI never runs during execution

- **Severity:** Critical
- **Location:** phase-01-ci-toolset-validation.md (Risk Assessment, "Regression Gate" step 5-6); phase-02-config-template-wiring.md:46 ("the TDD regression gate is the repo's actual CI lint gate"); phase-03-coding-agent-delegation-skill.md:127 ("markdown-link-check CI catches it"); phase-04-docs-and-catalog-sync.md:86
- **Flaw:** Three of the four phases explicitly lean on GitHub Actions CI (`skill-frontmatter`, `yaml-lint`, `markdown-link-check` jobs) as their verification/regression mechanism. Phase 4's own "Next Steps" states: "No push without explicit user confirmation (repo memory: never push to remote)." CI in this repo only triggers `on: push`/`pull_request` (`ci.yml:3-7`) — it cannot run on local, unpushed commits.
- **Failure scenario:** All 4 phases get executed and locally committed in one session (as the plan's parallel-group structure implies), but per repo policy nothing is pushed. Phase 2 calls the yaml-lint job its "regression gate" and Phase 3 calls markdown-link-check its safety net for broken cross-links — but neither ever actually executes, because there is no push. The plan proceeds phase-to-phase trusting a gate that never fired, and any real defect (bad YAML, broken relative link, frontmatter regression) is caught only if a human remembers to run the CLI-equivalent locally — which the plan does specify for Phase 1/2 (yamllint, validate_skills.py) but explicitly NOT for Phase 3's markdown-link-check claim (no local markdown-link-check invocation is listed in Phase 3's Implementation Steps).
- **Evidence:** `phase-04-docs-and-catalog-sync.md:86`; `.github/workflows/ci.yml:3-7` (`on: push / pull_request` only); phase-03 step list (Implementation Steps 1-7) contains no local link-check command.
- **Suggested fix:** For any phase claiming "CI catches this," add the equivalent local command as an explicit step (e.g. `npx markdown-link-check` locally for Phase 3, since no push is expected to happen).

## Finding 3: CI's Python version lacks the "zero tests silently pass" guard — false-green risk is concrete, not hypothetical

- **Severity:** High
- **Location:** phase-01-ci-toolset-validation.md:64-70 (CI wiring), Success Criteria line 74; `.github/workflows/ci.yml:41` (`python-version: '3.11'`)
- **Flaw:** `unittest.main()` only started returning a non-zero exit code (5) for "no tests ran" starting in Python 3.12 (confirmed by testing locally: Python 3.12.3 returns exit 5 for a TestCase with zero `test_*` methods; this behavior does not exist in 3.11). CI pins `python-version: '3.11'` at `ci.yml:41`. The plan's success criterion ("`python .github/scripts/test_validate_skills.py` exits 0 with 3 tests passing," phase-01:74) is never mechanically checked for *test count* — only exit code, which stdlib `unittest` under 3.11 will report as 0 even if all 3 tests fail to be collected (e.g. a typo like `def tests_kanban_sandbox...` instead of `test_kanban_sandbox...`, or a class not inheriting `unittest.TestCase`).
- **Failure scenario:** Implementer makes a typo in a test method name during Phase 1 step 2 (create `test_validate_skills.py`). All three "tests" silently fail to be discovered. `python .github/scripts/test_validate_skills.py` exits 0 (Python 3.11 behavior). CI's new "Run validator unit tests" step (phase-01:66-67) reports green. The validator itself could have any bug (including accepting/rejecting the wrong toolsets) and nothing would flag it — a genuine false-green CI outcome, and it's precisely the failure mode the review brief asked about.
- **Evidence:** Local repro: `python3` (3.12.3) exits 5 for zero collected tests; documented Python 3.12 changelog behavior (confirmed via web search) — the guard is new in 3.12 and does not exist in 3.11. `ci.yml:41` pins `'3.11'`.
- **Suggested fix:** Add `-v` verbose mode and grep the output for `Ran 3 tests`, or switch the CI step to `python -m unittest -v .github.scripts.test_validate_skills` and assert test count explicitly, independent of exit code.

## Finding 4: "13 other skills still pass" regression check is a manual, unenforced step

- **Severity:** High
- **Location:** phase-01-ci-toolset-validation.md:70 (Implementation Steps, "Regression Gate" step 6)
- **Flaw:** The only verification that the `validate_frontmatter` extraction refactor didn't silently change behavior for the 13 pre-existing skills is: "Run `python .github/scripts/validate_skills.py` — confirm all existing skills still report `ok`." This is a free-text instruction, not gated by the new unit test file (which only covers synthetic `fm` dicts, not the real 13 files), and not listed as a blocking precondition before moving to step 5 (CI wiring) — it's listed *after* CI wiring in the numbered steps.
- **Failure scenario:** The refactor accidentally changes behavior for an edge case not covered by the 3 new unit tests (e.g. a skill with `toolsets` as `None` instead of a list, or a missing `when_to_use` key) — none of the 13 real files are asserted against in the test suite. If the implementer skips or misreads step 6 (it's presented as a confirmatory afterthought, not a numbered Success Criterion gate blocking phase completion — though it does appear as a checkbox in Success Criteria), a regression ships silently into the working tree, and — per Finding 2 — CI won't catch it either without a push.
- **Evidence:** phase-01-ci-toolset-validation.md:58-70 step ordering; Success Criteria phase-01:75 does list it as a checkbox, but nothing enforces checkbox completion order relative to "done."
- **Suggested fix:** Add a 4th unit test that runs `validate_frontmatter` against every real `skills/**/SKILL.md`'s extracted frontmatter and asserts zero errors, so the regression check is executable and gated by the same CI step Phase 1 already wires in — not a separate manual command.

## Finding 5: No rollback / partial-completion procedure if Phase 3 content is wrong after Phase 4 publishes

- **Severity:** High
- **Location:** phase-04-docs-and-catalog-sync.md (entire Risk Assessment table, lines 72-78); CHANGELOG.md structure
- **Flaw:** `CHANGELOG.md` uses append-only dated sections (verified: `## 2026-07-01 — ...` at the top, newest-first, no "amend previous entry" convention anywhere in the file). Phase 4's risk table only considers "changelog describes config that differs from what Phase 2 shipped" — it never considers "Phase 3's skill file is later found substantively wrong (bad quoted config, wrong tier logic) after Phase 4 already added the catalog row and changelog bullet referencing it."
- **Failure scenario:** Phase 3 lands (marked done in `plan.md`'s Phases table). Phase 4 proceeds per its `blockedBy: [2,3]` gate and publishes the catalog row (`skills/README.md`) and a dated CHANGELOG.md entry. A later review (or CI run, if ever pushed) discovers Phase 3's skill has a real defect — e.g. an incorrect quoted routing rule, or the security blockquote omitted. There is no defined procedure: does the fix get squashed into the still-unpushed Phase 3 commit, or does it require a *second* dated changelog section (contradicting the "one entry per change" implied by Phase 4's own success criteria, phase-04:67-70)? The plan has no phase for "post-publish correction," and Phase 4's "Next Steps" (line 84-86) declares "Final phase. On completion the plan is done" — closing the loop before any such check occurs.
- **Evidence:** `CHANGELOG.md:1-20` (append-only, dated, no amend pattern); `phase-04-docs-and-catalog-sync.md:72-78` (risk table silent on this scenario); `phase-04-docs-and-catalog-sync.md:84-86`.
- **Suggested fix:** Add an explicit Phase 4 precondition step: re-run `python .github/scripts/validate_skills.py` and a manual content read-through of Phase 3's file immediately before writing the catalog/changelog rows (not just relying on Phase 3's own internal "done" status), and document that any post-publish fix to Phase 3's content must land in the *same* dated changelog section (edit, not new section) since nothing has been pushed/released yet.

## Finding 6: Parallel Phase 1 + Phase 2 both write to the single shared `plan.md` phase-status table with no update protocol

- **Severity:** Medium
- **Location:** plan.md:24-31 (Phases status table); phase-01-ci-toolset-validation.md:1-8, phase-02-config-template-wiring.md:1-8 (both `status: pending`, both group A)
- **Flaw:** Phase 1 and Phase 2 are declared to "run in parallel (group A, no shared files)" (plan.md:44) — true for the *implementation* files (`validate_skills.py` vs `production.yaml`, no overlap, confirmed by their respective "Related Code Files" sections). But both phases still need to flip their own row in `plan.md`'s single shared Phases table (plan.md:26-31) and their own frontmatter `status:` field from `pending` to `done` when finished. No section of the plan describes an update protocol (who writes plan.md, in what order, how conflicting concurrent edits to the same file are resolved) for this genuinely shared file.
- **Failure scenario:** If Phase 1 and Phase 2 are literally two concurrent agent sessions (as "parallel group" implies), both attempting to update `plan.md`'s status table around the same time risk a last-write-wins clobber of each other's status flip — e.g. Phase 1 finishes and marks its row done, Phase 2 (working from a stale in-memory copy of plan.md) finishes seconds later and writes back the whole file, silently reverting Phase 1's status update. Phase 3's "blockedBy: [1]" check (whatever mechanism reads that status) could then see Phase 1 as still "Pending" or vice versa.
- **Evidence:** plan.md:26-31 (single shared table, one row per phase, no per-row ownership annotation); no "plan.md update protocol" section anywhere in the 4 phase files.
- **Suggested fix:** Either have a single coordinating session own all `plan.md` status writes (workers report completion via message, not direct file edit), or move per-phase status into per-phase frontmatter (`phase-0X-*.md:4` `status:` field, which already exists) and treat `plan.md`'s table as a generated/read-only summary regenerated once at the end, not concurrently hand-edited.

## Finding 7: Phase 2's `acp` block citation range excludes the block's own wrapper keys

- **Severity:** Medium
- **Location:** phase-02-config-template-wiring.md:55 ("Add `acp` block from `part18-coding-agents.md:195-206`")
- **Flaw:** The actual `acp:` block in the source guide starts at line 190 (`acp:`) and includes `enabled: true` (191), `server: { listen: ... }` (192-193), and `clients:` (194) before the `claude-code:`/`codex:`/`gemini-cli:` entries the plan quotes. Line 195 is `    claude-code:`, not the top of the block. Line 206 is a prose sentence ("The `/delegate_task` tool then picks an ACP client...") that falls two lines *after* the closing ` ``` ` fence (line 204), not the block itself.
- **Failure scenario:** If Phase 2 is implemented literally per the instruction ("Add acp block from `part18-coding-agents.md:195-206`"), an implementer who copies exactly that line range gets a YAML fragment starting at `claude-code:` with no parent `acp:`/`clients:` keys and no `enabled`/`server` fields, plus a trailing prose sentence that isn't YAML at all. Pasted as-is into `production.yaml`, this either produces invalid YAML (dangling prose line) or a structurally incomplete `acp` block (missing the ACP server `listen` config entirely, which Phase 3's skill description depends on for "the CLI client bindings `delegation.routing` agent names resolve to").
- **Evidence:** `sed -n '190,206p' part18-coding-agents.md` shows `acp:` at 190, `clients:` at 194, closing fence at 204; grep confirms `claude-code:` client entry is at line 195, not the block start.
- **Suggested fix:** Correct the citation to `part18-coding-agents.md:190-204` (full `acp:` block, fence-to-fence) and explicitly note the `enabled`/`server` fields must be included, not just the `clients:` mapping.

## Unresolved Questions

1. Does any external orchestrator (outside this repo) actually enforce `blockedBy` sequencing mechanically, or is it purely a convention read by whichever agent picks up the next phase? Not visible from the plan or repo — flagged in Finding 1.
2. Is this plan intended to be executed by 4 genuinely separate concurrent Claude sessions/worktrees, or by one session working phase-by-phase in the given order? The "parallel group" framing (plan.md:44) only makes sense — and only introduces the risks in Findings 1 and 6 — under a true multi-session model; the plan doesn't state which model applies.
