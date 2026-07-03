---
phase: 1
title: CI Toolset Validation
status: completed
priority: P1
effort: 1h
dependencies: []
---

# Phase 1: CI Toolset Validation

## Context Links

- Report: `research/researcher-ci-tdd-report.md` (Q1 approach, Q2 code sketches, Q3 file-change table)
- Source: `.github/scripts/validate_skills.py:16-29` (`ALLOWED_TOOLSETS`), `:46-72` (`validate()`)
- CI: `.github/workflows/ci.yml:34-45` (`skill-frontmatter` job)

## Overview

Priority: P1. Status: Pending. Parallel group A (no deps, runs alongside Phase 2).

Allow `kanban` and `sandbox` in the skill-frontmatter validator so Phase 3's skill can declare them, and add a stdlib-`unittest` test file gating the validator in CI. Done TDD-style: refactor for testability, write tests first, confirm red→green on the capability add.

## Requirements

- Functional: `kanban` and `sandbox` accepted by `validate_skills.py`; a unit test file proves it and guards regressions.
- Non-functional: zero new pip dependencies (PyYAML already installed at `ci.yml:43`); no pytest — stdlib `unittest` only (YAGNI). Refactor must not change behavior for existing skills.

## Architecture

No runtime architecture. The validator is a CI gate. Refactor extracts a pure function `validate_frontmatter(fm: dict) -> list[str]` from `validate(p: pathlib.Path)` so the frontmatter rules are unit-testable without temp files. `validate()` keeps its file I/O (read + `extract_frontmatter`) and delegates rule-checking to the new helper. Test file lives in the same dir (`.github/scripts/`) so `from validate_skills import validate_frontmatter` resolves when run as `python .github/scripts/test_validate_skills.py` (Python puts the script's dir on `sys.path`).

## Related Code Files

**Create:**
- `.github/scripts/test_validate_skills.py` — stdlib `unittest`, 4 test cases (~90 lines; red-team added `test_all_existing_skills_still_validate`).

**Modify:**
- `.github/scripts/validate_skills.py` — extract `validate_frontmatter` helper; add `"kanban"`, `"sandbox"` to `ALLOWED_TOOLSETS`.
- `.github/workflows/ci.yml` — add a test `run:` step before the validator step in the `skill-frontmatter` job.

**Delete:** none.

## Implementation Steps (TDD)

### 1. Tests Before (red)

1. Refactor `validate_skills.py`: move the rule-checks currently in `validate()` (`.github/scripts/validate_skills.py:52-72` — missing-keys, toolsets, when_to_use, description) into a new pure function `def validate_frontmatter(fm: dict) -> list[str]`. Leave `validate(p)` doing the file read + `extract_frontmatter`, then `return validate_frontmatter(fm)`. This is a behavior-preserving refactor — do it first so the tests can import the helper.
2. Create `.github/scripts/test_validate_skills.py` with the 3 cases from the report:
   - `test_unknown_toolsets_rejected` — **characterization test** (NOT a bug to fix): asserts `["kanban","sandbox"]` currently yields an "unknown toolsets" error. Documents the pre-change behavior. This one PASSES immediately and keeps passing until step 2 below, at which point it must be updated/removed (see step 4 note).
   - `test_known_toolsets_accepted` — GREEN baseline: `["terminal","file"]` yields `[]`.
   - `test_kanban_sandbox_accepted_after_fix` — the true RED test: asserts `["kanban","sandbox"]` yields `[]`. Run `python .github/scripts/test_validate_skills.py` now and confirm THIS test FAILS (red) — that failure is the proof the capability is missing.

### 2. Refactor / Implement (green)

3. Add `"kanban"` and `"sandbox"` to `ALLOWED_TOOLSETS` (`.github/scripts/validate_skills.py:16-29`).

### 3. Tests After (confirm green)

4. Re-run `python .github/scripts/test_validate_skills.py`. `test_kanban_sandbox_accepted_after_fix` and `test_known_toolsets_accepted` now PASS. Note: after the ALLOWED_TOOLSETS edit, `test_unknown_toolsets_rejected` (which asserted kanban/sandbox are rejected) will now FAIL because they are accepted — so in this same step, change that test to assert rejection of a genuinely-unknown token (e.g. `["bogus_toolset"]` → "unknown toolsets"). Keeps a real negative-path test without contradicting the new capability. End state: 3 tests, all passing. **This rewrite is a required part of step 4, not optional cleanup — see the matching Success Criteria line below.**
5. Add a 4th test, `test_all_existing_skills_still_validate`, that globs every real `skills/**/SKILL.md` in the repo (not synthetic dicts) and asserts `validate_frontmatter` (or `validate`) returns `[]` for each — this is the actual regression check for "the 13 other skills still pass," which step 6 below only re-runs as a script, not as an assertable test.
6. Run `python .github/scripts/test_validate_skills.py -v` (verbose) and confirm the output explicitly shows `Ran 4 tests` — do not rely on exit code alone. CI here pins Python 3.11 (`ci.yml:41`), and `unittest.main()` only fails on zero-collected-tests starting Python 3.12; a typo'd test method name on 3.11 would silently report 0 tests found but still exit 0 if other tests in the file still ran. Asserting the test count in the verbose output (or grepping for `Ran 4 tests`) is the guard against that.

### 4. Regression Gate

7. Wire the test into CI: in `.github/workflows/ci.yml` `skill-frontmatter` job, insert before the existing validator step (`ci.yml:44-45`):
   ```yaml
   - name: Run validator unit tests
     run: python .github/scripts/test_validate_skills.py
   ```
   Tests gate the validator (fail-fast if the validator logic regresses). This is the same check CI runs — steps 6 and 8 already run its local equivalent directly, so this phase is verifiable without waiting on a push.
8. Run `python .github/scripts/validate_skills.py` — confirm all existing skills still report `ok` (refactor introduced no regressions; this is the local-runnable form of step 5's "13 skills still pass" claim, now also covered by the `test_all_existing_skills_still_validate` unit test).

## Success Criteria

- [ ] `python .github/scripts/test_validate_skills.py -v` exits 0 and shows `Ran 4 tests` (not 3 — see step 5's added test; count is asserted explicitly, not just exit code, per the Python 3.11 zero-tests caveat in step 6).
- [ ] `test_unknown_toolsets_rejected` asserts rejection of a token that is NOT `kanban`/`sandbox` (e.g. `bogus_toolset`) after step 4's rewrite — this is a required edit, not optional cleanup.
- [ ] `test_all_existing_skills_still_validate` passes against every real `skills/**/SKILL.md` (not just synthetic dicts).
- [ ] `python .github/scripts/validate_skills.py` exits 0 (no regression on existing skills).
- [ ] `"kanban"` and `"sandbox"` present in `ALLOWED_TOOLSETS`.
- [ ] `ci.yml` `skill-frontmatter` job runs the test step before the validator step.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Refactor changes validation behavior for existing skills | Low | High | Behavior-preserving extraction; step 8 and the new `test_all_existing_skills_still_validate` test both re-run the full validator as a regression check |
| Test import fails in CI (path resolution) | Low | Med | Test + validator in same dir; run form `python .github/scripts/test_validate_skills.py` puts dir on `sys.path` |
| `test_unknown_toolsets_rejected` left contradicting the new capability | Med | Low | Step 4 explicitly rewires it to a genuinely-unknown token; restated as its own Success Criteria line so it isn't missed by a checklist-only read |
| Python 3.11's `unittest.main()` silently exits 0 on a typo'd/uncollected test method | Low | Med | Step 6 asserts the exact test count in verbose output, not just exit code |

## Security Considerations

Widening `ALLOWED_TOOLSETS` is a whitelist expansion documented by the guide chapters (part21/part23), and by itself has no runtime surface. However, it is the only capability-allowlist gate this repo has for skill toolsets — it does not, on its own, guarantee the new `delegate_task`/`kanban`/`sandbox` surfaces are approval-gated in a running Hermes instance. That gating is `security.approval.require_approval` (`templates/config/production.yaml:183-188`), which Phase 2 updates to include these tools — see Phase 2's Security Considerations.

## Next Steps

Unblocks Phase 3 (skill frontmatter can now declare `kanban`/`sandbox`).
