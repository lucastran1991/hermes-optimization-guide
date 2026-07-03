# Curator Config Application Research

**Date:** 2026-07-03 | **Task:** Apply Part 5 curator guidance to repo conventions

---

## Summary

**Recommendation: Config-only approach via new `curator:` block in `templates/config/production.yaml`.** No new skill file. Curator is a system feature (invoked via `hermes curator run --dry-run`), not a task-automation skill. No `ALLOWED_TOOLSETS` expansion needed.

---

## Findings

### 1. Skill vs. Config: Should Curator Be a Skill?

**No.** Curator does not belong in `skills/*/SKILL.md`.

**Evidence:**
- Part 5:117–150 documents curator as a **system feature**, not user-created skill. Invocation pattern: `hermes curator run`, `hermes curator enable`, `hermes curator status` (part5:124–132). Contrast with skill creation (`skill_manage` action, part5:59).
- Repo's 14 existing skills are **task-automation skills**: backup, audits, reviews, triage. All are `cron:` invokable workflows. Curator is **meta-infrastructure** about skill hygiene — not itself a task to automate.
- No existing skill documents infrastructure discipline (when/how to create, patch, dedup workflow). File scout confirmed: none of the 14 skills have `curator` or `skill_manage` in their frontmatter or When to Use triggers.
- Architecture pattern: Phase 02 of the prior plan (260703-0347) **added config blocks, not skills**, for `delegation`/`acp`/`sandboxes` (phase-02-config-template-wiring.md:34–35, line 24). Curator follows the same pattern — config, not skill.

**Conclusion:** Curator guidance belongs in `docs/` (new guide chapter or embedded in existing skill-creation docs). Curator *scheduling* belongs in `templates/config/production.yaml`. Both are read-only reference / configuration, not executable skills.

---

### 2. Toolsets: Does ALLOWED_TOOLSETS Need a New `skill_manage` or `curator` Entry?

**No change needed.**

**Evidence:**
- `validate_skills.py:16–31` defines `ALLOWED_TOOLSETS` as a **skill-only validation rule**. Line 88: `skills = sorted(root.rglob("SKILL.md"))` — script only validates files under `skills/`, not config templates.
- Curator is not a skill → never has a `SKILL.md` → never validated by this script → no toolset entry needed.
- Curator is admin-only config (like `cron:`, `security:`, `mcp_servers:`), not a tool/action that requires approval gating or toolset classification.
- Existing skills use category-label toolsets (`github`, `telegram`, `kanban`, `sandbox` per phase-01-ci-toolset-validation.md:11–29), not API-call strings. Curator config doesn't declare toolsets.

**Conclusion:** No `ALLOWED_TOOLSETS` expansion. Curator config is out of validation scope.

---

### 3. Curator YAML Block: Proposed Shape for `templates/config/production.yaml`

**Model:** Follow `cron:` block structure (production.yaml:289–294) for consistency.

**Proposed block** (insert before `telemetry:` block, ~line 277):

```yaml
curator:
  enabled: true
  # Runs automatically per schedule below; disable to require manual
  # `hermes curator run` invocations. See part5-creating-skills.md:117–150.
  schedule: "0 6 * * 0"              # Weekly Sunday 06:00 UTC
  dry_run_schedule: "0 5 * * 1"      # Dry-run first: Monday 05:00 UTC
  # Curator scoring dimensions (part5:135–140):
  # - Freshness: age since last use
  # - Usage: invocation count over trailing 90d
  # - Clarity: SKILL.md completeness vs. checklist
  # - Overlap: content similarity vs. other skills
  # - Safety: toolsets, approval gates, denylist interactions
  scoring:
    freshness_weight: 0.20
    usage_weight: 0.25
    clarity_weight: 0.15
    overlap_weight: 0.25
    safety_weight: 0.15
  pinned_skills:
    # High-value skills never archived even if score drops.
    # These are either irreplaceable or tied to external compliance.
    - coding-agent-delegate
    - nightly-backup
    - audit-mcp
    - rotate-secrets
  auto_archive: true                 # Archive low-scoring agent-created skills
  archive_threshold: 0.35             # Below this composite score, archive
  # Set to false to require confirmation before archive; true to auto-apply.
  notify: telegram_dm                 # Post curator report to this channel
```

**Rationale:**
- **Structure:** Mirrors `cron:` block's `enabled`, `schedule`, `notify` pattern (production.yaml:289–294), low cognitive overhead.
- **Dry-run first:** Part 5:146 recommends "Run `hermes curator run --dry-run` after major upgrades." Separate schedule lets operators preview changes before auto-apply.
- **Weights:** Correspond to Part 5:135–140 (freshness, usage, clarity, overlap, safety). Values are illustrative; operators will tune to local policy.
- **Pinned skills:** Part 5:140 — "Pins important skills so core workflows survive pruning." List the 3–4 non-replaceable runbooks (backup, audit-mcp, rotate-secrets are production-critical; coding-agent-delegate is the delegation skill from the prior plan).
- **Notify:** Keeps curator runs visible; part5:143 ("Curator is a librarian, not a teammate").

**Not in block:** Single-skill dry-run commands (those are manual CLI: `hermes curator run --dry-run --skill audit-mcp`) — config is for scheduled behavior only.

---

### 4. Security-Hardened Template: Does It Need Curator Gating?

**No special gating needed.**

**Evidence:**
- Security-hardened.yaml (line 16) defines a **profile-based quarantine mode** for untrusted-input-facing agents. Profiles gate conversation capabilities (models, tools_allowlist, memory write).
- Curator is **admin-only config**, not a conversation capability. It doesn't run via an untrusted platform or invoke unvetted tools — it's a scheduled system housekeeping task.
- The quarantine profile's `memory: { write: false }` (line 23) applies to conversation-level memory writes, not config scheduling.
- Curator in production.yaml is already admin-only by virtue of being in the config file, which requires manual edits or `hermes configure` (not user-invokable via chat).

**Conclusion:** No changes to security-hardened.yaml. Curator config is out of scope for profile-level security gating.

---

## Citations

- Part 5 curator section: `part5-creating-skills.md:117–150`
- Curator commands: `part5-creating-skills.md:124–132`
- Curator scoring dimensions: `part5-creating-skills.md:135–140`
- Curator operating pattern: `part5-creating-skills.md:143–150`
- Prior plan (precedent for config-only approach): `plans/260703-0347-hermes-coding-agent-delegation-skill/phase-02-config-template-wiring.md:24–35`
- Existing cron block model: `templates/config/production.yaml:289–294`
- Security approval pattern: `templates/config/production.yaml:237–264`
- Validation script scope: `.github/scripts/validate_skills.py:88`
- Existing skills catalog: `skills/README.md` (14 skills, none meta/curator-like)

---

## Unresolved Questions

None. Recommendation is actionable with the citations above. Implementation next step: add `curator:` block to production.yaml and update `docs/` with curator-creation discipline.
