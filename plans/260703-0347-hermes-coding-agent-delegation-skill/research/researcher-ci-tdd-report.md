---
name: ci-tdd-approach-research
description: Research and recommendation for TDD-style testing of skill-frontmatter validator without new test framework
---

# CI TDD Approach Research: validate_skills.py Refactor

## Q1: Recommended Testing Approach

**Recommendation: Option (b) — separate `.github/scripts/test_validate_skills.py` with stdlib `unittest`.**

**Justification:** This repo already installs PyYAML in CI (`.github/workflows/ci.yml:43`); no new pip dependency required. Stdlib `unittest` is idiomatic Python CI for repos without pytest infrastructure. Separates test code cleanly from validator logic and integrates into existing skill-frontmatter job with a single added `run:` step. YAGNI-compliant: adds one file, zero framework dependencies.

---

## Q2: Code Sketches (Red→Green States)

**Minimal refactor of `.github/scripts/validate_skills.py`:**

Extract `validate_frontmatter(fm: dict)` helper (lines 52–72 move into new function):

```python
def validate_frontmatter(fm: dict) -> list[str]:
    """Validate frontmatter dict. Returns list of error strings (empty = pass)."""
    errs: list[str] = []
    missing = REQUIRED_KEYS - set(fm.keys())
    if missing:
        errs.append(f"missing required keys: {sorted(missing)}")
    
    toolsets = fm.get("toolsets", [])
    if not isinstance(toolsets, list):
        errs.append("toolsets must be a list")
    else:
        unknown = [t for t in toolsets if t not in ALLOWED_TOOLSETS]
        if unknown:
            errs.append(f"unknown toolsets: {unknown}")
    
    when = fm.get("when_to_use", [])
    if not isinstance(when, list) or not when:
        errs.append("when_to_use must be a non-empty list")
    
    desc = fm.get("description", "")
    if not isinstance(desc, str) or len(desc) < 10:
        errs.append("description must be a >=10-char string")
    
    return errs

def validate(p: pathlib.Path) -> list[str]:
    fm = extract_frontmatter(p)
    if fm is None:
        return ["missing or unparseable frontmatter"]
    return validate_frontmatter(fm)
```

**Test file `.github/scripts/test_validate_skills.py`:**

```python
import unittest
import tempfile
import pathlib
from validate_skills import validate_frontmatter

class TestValidateToolsets(unittest.TestCase):
    def test_unknown_toolsets_rejected(self):
        """RED: kanban/sandbox currently rejected."""
        fm = {
            "name": "test-skill",
            "description": "A test skill description",
            "when_to_use": ["example"],
            "toolsets": ["kanban", "sandbox"]
        }
        errs = validate_frontmatter(fm)
        self.assertTrue(
            any("unknown toolsets" in e for e in errs),
            f"Expected rejection, got: {errs}"
        )
    
    def test_known_toolsets_accepted(self):
        """GREEN: known toolsets pass (baseline)."""
        fm = {
            "name": "test-skill",
            "description": "A test skill description",
            "when_to_use": ["example"],
            "toolsets": ["terminal", "file"]
        }
        errs = validate_frontmatter(fm)
        self.assertEqual(errs, [])
    
    def test_kanban_sandbox_accepted_after_fix(self):
        """GREEN: kanban/sandbox accepted after ALLOWED_TOOLSETS update."""
        fm = {
            "name": "test-skill",
            "description": "A test skill description",
            "when_to_use": ["example"],
            "toolsets": ["kanban", "sandbox"]
        }
        errs = validate_frontmatter(fm)
        self.assertEqual(errs, [], f"Expected pass, got: {errs}")

if __name__ == "__main__":
    unittest.main()
```

---

## Q3: File Changes Required

| File | Lines | Change |
|------|-------|--------|
| `.github/scripts/validate_skills.py` | 46–72 | Extract `validate_frontmatter(fm: dict)` helper; `validate()` calls it |
| `.github/scripts/validate_skills.py` | 16–29 | Add `"kanban"` and `"sandbox"` to `ALLOWED_TOOLSETS` set |
| `.github/scripts/test_validate_skills.py` | NEW | Create test file (80 lines) |
| `.github/workflows/ci.yml` | 44 (insert before) | Add step: `- name: Test validator\n  run: python .github/scripts/test_validate_skills.py` |

---

## Unresolved Questions

- None. Approach is clear; refactor is minimal and improves code testability.
