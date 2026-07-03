---
phase: 2
title: "Config Template Wiring"
status: completed
priority: P2
effort: "0.5h"
dependencies: []
---

# Phase 2: Config Template Wiring

## Context Links

- Brainstorm: `plans/reports/brainstorm-260703-1034-ccs-full-harness-delegation-skill-report.md` (assumption 4, corrected in `plan.md` Overview)
- Existing block to extend: `templates/config/production.yaml:171-185` (`delegation:`)
- Existing gate (already covers this, confirmed no change needed):
  `templates/config/production.yaml:251-263` (`security.approval.require_approval`
  already lists `{ tool: delegate_task, actions: [dispatch] }`)
- CCS profile-type reference (verified live, `ccs help profiles` / `ccs api --help`,
  this session, no public URL to cite): API profiles (`ccs api create --preset
  anthropic --api-key <key> --target claude --yes`) vs account profiles (`ccs auth
  create <name>` — needs interactive OAuth login)
- Repo rule: `CONTRIBUTING.md:25` (comment every non-obvious field), `:27` (no
  secrets, `${VAR}` placeholders)
- Lint config: `.github/yamllint.yml`

## Overview

Priority: P2. Status: Pending. Parallel group A (no deps, runs alongside Phase 1).

Add one field, `delegation.ccs_profile`, to the existing `delegation:` block in
`templates/config/production.yaml` — the CCS profile name Tier 1 delegates as when
routing through CCS (Phase 3). Document, in a comment, the one-time manual setup
command and why an API profile (not an account profile) is recommended. No other
config block changes needed — verified `security.approval.require_approval` already
gates `delegate_task` dispatch (see Context Links); this phase does not touch it.

## Key Insights

- `ccs auth create <name>` = "Create new profile and login" — requires an
  interactive OAuth browser flow at creation time. Not scriptable for a headless
  service without a human completing that login once.
- `ccs api create --preset anthropic --api-key <key> --target claude --yes` creates
  a fully non-interactive, `ANTHROPIC_API_KEY`-backed profile (`--yes` skips all
  confirmation prompts) that still targets the `claude` binary (`--target claude`)
  — zero interactive OAuth login step, avoiding the account-profile blocker. This
  is the recommended profile *type* for `delegation.ccs_profile` over a human
  account profile like `lucas`/`ken`/`luan`. **Does NOT by itself grant "the
  harness"** — see `phase-01-bootstrap-ccs-prerequisites.md` Key Insights: harness
  depends on `~/.claude/` existing on the host, unrelated to profile creation.
- The field only names WHICH already-provisioned CCS profile to delegate as. Profile
  creation itself (`ccs api create ...`) stays a documented one-time manual step
  (Phase 3's Prerequisites section), not something the config schema or bootstrap
  script automates — mirrors how `claude auth login`/`codex auth login` are already
  documented as manual one-time steps in `part18-coding-agents.md:26-40`, not
  scripted.
- **[Red-team, High, accepted] `--api-key <key>` on a create command line leaks the
  real key via shell history and `/proc/<pid>/cmdline`/`ps` to co-resident users.**
  Verified live (`ccs api --help`): `--api-key <key>` is the only key-supplying
  flag; no env-var/stdin alternative exists. `ccs api create` (no flags) is a
  documented interactive wizard alternative that avoids this exposure — prefer it
  for the actual one-time provisioning; the `--api-key` form below is kept only as
  a copy-pasteable illustration with an explicit exposure caveat.
- **[Red-team, Medium, accepted] This field has no consumer in this repo (A6).**
  Like every other `delegation.*`/`acp.*` field already in this template,
  `delegation.ccs_profile` is read by the operator's own (closed-source) Hermes
  gateway, not by anything here — `yamllint` passing proves well-formed YAML, not
  that any runtime honors the field. State this explicitly, don't imply green CI
  validates the feature.

## Requirements

- Functional: `delegation.ccs_profile` field present, commented, with a placeholder
  default (`ccs-hermes` — not a real human's profile name) and a comment showing the
  exact one-time provisioning command.
- Non-functional: yamllint-clean before and after; no secrets (the field is a
  profile *name*, never an API key); minimal — one field added to an existing
  block, no new top-level block (YAGNI).

## Architecture

Config-only. `delegation.ccs_profile` sits inside the existing `delegation:` block
(sibling to `default:`/`routing:`), read by Phase 3's Tier-1 CCS branch to build the
invocation string `ccs <ccs_profile> -p "<task>" ...`. No interaction with `acp:` or
`sandboxes:` blocks (those are unrelated tiers/mechanisms).

## Related Code Files

**Modify:**
- `templates/config/production.yaml` (~line 171-185, inside `delegation:`).

**Create:** none. **Delete:** none.

## Implementation Steps (TDD — adapted for a YAML-only phase, per sibling
Phase 2's precedent: this repo's actual regression gate for templates is the
`yaml-lint` CI job, not application tests)

### 1. Tests Before (baseline)

1. Run `yamllint -c .github/yamllint.yml templates/` — confirm exit 0 (green
   baseline).

### 2. Implement

2. Inside `delegation:` (`production.yaml:171-185`), after the `routing:` list, add:
   ```yaml
     # CCS profile Tier 1 delegates as when coding-agent-delegate routes through CCS
     # (see skills/dev/coding-agent-delegate/SKILL.md — `harness: ccs`). Getting
     # actual CK harness ALSO requires ClaudeKit installed on this host (out of
     # this guide's scope) — routing through CCS alone does not grant it. Must be
     # an already-provisioned profile; provision once with the interactive wizard
     # (`ccs api create` — prompts for the key, avoids leaking it via shell
     # history/ps) or, less safely, non-interactively:
     #   ccs api create --preset anthropic --api-key <ANTHROPIC_API_KEY> \
     #     --target claude --yes ccs-hermes   # visible in `ps`/history — prefer the wizard
     # An API profile (not an account profile like ccs auth create) avoids the
     # interactive OAuth login step account profiles require.
     ccs_profile: ccs-hermes
   ```

### 3. Tests After (regression gate)

3. Re-run `yamllint -c .github/yamllint.yml templates/` — confirm still exit 0.
4. Grep the file for accidental secrets — confirm no literal API key was pasted
   into the comment (placeholder `<ANTHROPIC_API_KEY>` only).
5. Confirm `security.approval.require_approval` (`~line 251-263`) is unchanged and
   still lists `{ tool: delegate_task, actions: [dispatch] }` — this phase adds no
   new approval-gate entries because none are needed (delegate_task dispatch is
   already gated regardless of invocation string).

## Success Criteria

- [x] `yamllint -c .github/yamllint.yml templates/` exits 0 (before and after).
- [x] `delegation.ccs_profile: ccs-hermes` present with the provisioning-command
      comment.
- [x] No literal API key/secret in the file — placeholder only.
- [x] `security.approval.require_approval` confirmed unchanged at implementation
      time (already covers this surface); note: an unrelated, already in-flight
      security-hardening change later restructured this gate under a top-level
      `approvals:` key — orthogonal to this phase's diff, see code-review report.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Default profile name (`ccs-hermes`) collides with a real operator's existing profile | Low | Low | It's a template default, documented as needing one-time provisioning before use — operators overriding `~/.hermes/config.yaml` naturally replace it |
| Someone copies the comment's placeholder as a literal, pastes a real key | Low | Med | Comment uses angle-bracket placeholder (`<ANTHROPIC_API_KEY>`) matching this repo's existing `${VAR}` convention elsewhere |
| yamllint failure from comment indentation | Low | Low | Match existing `delegation:` block's 2-space nesting exactly |
| Operator copies the non-interactive `--api-key` example verbatim, exposing the real key via `ps`/shell history | Med | Med | Comment leads with the interactive-wizard recommendation and marks the `--api-key` line as less-safe |

## Security Considerations

The field stores a profile *name* only, never a credential — the actual API key
lives in CCS's own profile store (`~/.ccs/`, gated by Phase 1's systemd
`ReadWritePaths`), not in this template. `security.approval.require_approval`
already treats `delegate_task` dispatch as gated (verified, unchanged by this
phase) — CCS-routed and bare-`claude`-routed Tier-1 calls carry identical approval
posture. The provisioning comment's non-interactive `ccs api create --api-key`
form exposes the key via `ps`/`/proc/<pid>/cmdline`/shell history on the
provisioning host — the wizard form avoids this; document both, recommend the
wizard.

## Next Steps

Unblocks Phase 3 (needs the confirmed `delegation.ccs_profile` field name for its
Tier-1 invocation example). Independent of Phase 1 (different files).
