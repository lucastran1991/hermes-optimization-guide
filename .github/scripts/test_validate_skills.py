#!/usr/bin/env python3
"""Unit tests for validate_skills.py's frontmatter validation rules.

Run via: python .github/scripts/test_validate_skills.py [-v]
Exit code 0 = all pass; nonzero = any fail.

Stdlib unittest only (YAGNI) — no pytest, no new pip dependencies.
"""
from __future__ import annotations

import pathlib
import unittest

import yaml

from validate_skills import validate_frontmatter

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SKILLS_DIR = REPO_ROOT / "skills"

VALID_FM = {
    "name": "example",
    "description": "an example skill with a long enough description",
    "when_to_use": ["do the thing"],
    "toolsets": ["terminal", "file"],
}


def _fm_with_toolsets(toolsets: list[str]) -> dict:
    fm = dict(VALID_FM)
    fm["toolsets"] = toolsets
    return fm


class TestValidateFrontmatter(unittest.TestCase):
    def test_unknown_toolsets_rejected(self) -> None:
        """A genuinely-unknown toolset token must still be rejected."""
        errs = validate_frontmatter(_fm_with_toolsets(["bogus_toolset"]))
        self.assertTrue(
            any("unknown toolsets" in e for e in errs),
            f"expected an 'unknown toolsets' error, got: {errs}",
        )

    def test_known_toolsets_accepted(self) -> None:
        errs = validate_frontmatter(_fm_with_toolsets(["terminal", "file"]))
        self.assertEqual(errs, [])

    def test_kanban_sandbox_accepted_after_fix(self) -> None:
        """kanban and sandbox must be allowed toolsets."""
        errs = validate_frontmatter(_fm_with_toolsets(["kanban", "sandbox"]))
        self.assertEqual(errs, [])

    def test_all_existing_skills_still_validate(self) -> None:
        """Regression check: every real skills/**/SKILL.md must still pass."""
        skill_files = sorted(SKILLS_DIR.rglob("SKILL.md"))
        self.assertTrue(skill_files, f"no SKILL.md files found under {SKILLS_DIR}")

        for path in skill_files:
            text = path.read_text(encoding="utf-8")
            fm_match = text.split("---\n", 2)
            self.assertGreaterEqual(
                len(fm_match), 3, f"{path}: missing frontmatter delimiters"
            )
            fm = yaml.safe_load(fm_match[1]) or {}
            errs = validate_frontmatter(fm)
            self.assertEqual(errs, [], f"{path}: {errs}")


if __name__ == "__main__":
    unittest.main()
