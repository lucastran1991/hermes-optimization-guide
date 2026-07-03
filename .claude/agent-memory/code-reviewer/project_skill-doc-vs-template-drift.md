---
name: skill-doc-vs-template-drift
description: This repo's SKILL.md files quote guide chapters verbatim, which can drift from security-hardened templates/config/*.yaml — check both when reviewing.
metadata:
  type: project
---

In hermes-optimization-guide, `skills/**/SKILL.md` files are written to quote the
guide chapters (`partNN-*.md`) verbatim for config snippets (plan convention:
"cite accurately, quote verbatim"). Separately, `templates/config/production.yaml`
(and siblings) sometimes carry security hardening on top of the raw guide example
(e.g. an added `.env` exclusion in `sandboxes.*.sync.ignore` to stop leaking
`~/.hermes/.env` to remote sandbox hosts).

**Why:** found 2026-07-03 reviewing the `coding-agent-delegate` skill: the
red-team-fixed `.env` exclusion landed correctly in `templates/config/production.yaml`
`sandboxes.dev-box.sync.ignore`, but `skills/dev/coding-agent-delegate/SKILL.md`'s
own "Tier 3 sandbox config" example (quoting `part21-remote-sandboxes.md:54-74`
verbatim, per the plan's own instruction) reproduces the pre-fix version without
`.env` — because the guide chapter itself (`part21-remote-sandboxes.md`) was never
updated with the fix. A reader who copies the SKILL.md's own example, not the
production.yaml, recreates the vulnerability.

**How to apply:** when reviewing any new/changed skill that documents a security-
sensitive config block (sandboxes, secrets, approval gates), diff that skill's
embedded example against both (a) the guide chapter it cites and (b) the actual
hardened `templates/config/production.yaml` block for the same feature. A fix
applied to the template only, without also patching the underlying guide chapter
prose the skill quotes from, produces this drift. Flag it even if the plan's own
phase criteria only asked for template accuracy — self-consistency across the
guide's own docs is a real content-correctness bar in this repo.
