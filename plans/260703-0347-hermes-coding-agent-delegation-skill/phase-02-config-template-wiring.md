---
phase: 2
title: Config Template Wiring
status: completed
priority: P2
effort: 45m
dependencies: []
---

# Phase 2: Config Template Wiring

## Context Links

- Report: `research/researcher-skill-style-report.md` section 3 (verbatim snippets + line numbers)
- Sources: `part18-coding-agents.md:108-123` (`delegation`), `:188-204` (`acp` block — corrected from an earlier `195-206` citation that dropped the `acp:`/`enabled:`/`server:` keys and only covered the `clients:` sub-mapping), `part21-remote-sandboxes.md:54-74` (`sandboxes`)
- Target: `templates/config/production.yaml`
- Repo rule: `CONTRIBUTING.md:25` (comment every non-obvious field), `:27` (no secrets, `${VAR}` placeholders)
- Lint config: `.github/yamllint.yml`
- Existing gate to wire into: `production.yaml:183-188` (`security.approval.require_approval`) — currently lists `github`/`terminal`/`email`/`twilio`/`any_mcp`; does not cover `delegate_task`/`kanban`/`sandbox`
- Existing invariant to respect: `part19-security-playbook.md:196` — "The agent cannot read `~/.hermes/.env` — keys stay on the host"

## Overview

Priority: P2. Status: Pending. Parallel group A (no deps, runs alongside Phase 1).

Add three config blocks to `production.yaml` so the template documents the full delegation stack the new skill relies on: `delegation` (tier-1 routing), `acp` (the CLI agent bindings `delegation.routing` names), and `sandboxes` (tier-3 backend) — plus one targeted edit to the existing `security.approval.require_approval` list so the new delegation surfaces are gated like other write-capable tools. Content quoted from the guide chapters, every non-obvious field commented.

## Requirements

- Functional: `delegation`, `acp`, `sandboxes` blocks present, internally consistent with part18/part21 examples, with the agent names cross-referenced (routing agents exist as acp clients), and with the sandbox sync path never exposing `~/.hermes` secrets; `security.approval.require_approval` extended to cover the new tools.
- Non-functional: yamllint-clean before and after; no secrets (`${VAR}` / non-secret paths only); minimal (3 new top-level blocks + 1 targeted edit to an existing list, all in one file — YAGNI).

## Architecture

Config-only. The three blocks map 1:1 to the skill's escalation tiers: `delegation` → tier 1 (print-mode routing), `acp` → the client bindings tier 1 dispatches through, `sandboxes` → tier 3. Tier 2 (Kanban) needs no config block here (it uses the `kanban_*` toolset + `~/.hermes/kanban.db`, not template config). Check the file first: no `delegation`/`acp`/`sandboxes` currently exist (confirmed absent, `production.yaml:1-220`), so no duplication risk.

## Related Code Files

**Create:** none.

**Modify:**
- `templates/config/production.yaml` — append `delegation`, `acp`, `sandboxes` blocks (logical placement: after `routing:` block, before `platforms:`, or grouped near `mcp_servers:` — pick the spot that reads cleanly; do not reorder existing blocks).

**Delete:** none.

## Implementation Steps (TDD — adapted for a YAML-only phase)

This repo has no application tests; the TDD regression gate is the repo's actual CI lint gate (`yaml-lint` job, `ci.yml:24-32`). State this substitution explicitly rather than forcing a Python test structure that does not fit a YAML template.

### 1. Tests Before (baseline)

1. Run `yamllint -c .github/yamllint.yml templates/` — confirm exit 0 (current file is clean; establishes the green baseline).

### 2. Implement

2. Add `delegation` block, quoting `part18-coding-agents.md:108-123` verbatim (default + routing match/agent rules). Comment each `match` rule's intent (e.g. `# large refactors → Claude Code`).
3. Add `acp` block sourced from `part18-coding-agents.md:188-204` (cite the FULL fence — **not** the previously-cited `195-206`, which drops the parent `acp:` key, `enabled: true`, and `server: { listen: 127.0.0.1:41212 }` — cite accurately even though this step ships a trimmed subset, see next sentence). Per validation decision (see `plan.md` Validation Log), ship **client-only**: include `acp.clients` (`claude-code`/`codex`/`gemini-cli` → `command` + `args: ["--acp"]`), and add a comment explicitly noting the guide's `enabled`/`server.listen` fields (inbound ACP-server mode) are intentionally omitted because this skill only ever dispatches as an ACP *client*, never accepts inbound ACP connections — e.g. `# Client-only: this template omits acp.enabled/server (inbound ACP-server mode) since coding-agent-delegate never accepts inbound ACP — see part18-coding-agents.md:188-194 for the full server-mode block if you need it`. Comment: `# /delegate_task picks an ACP client per delegation.routing`.
4. Add `sandboxes` block from `part21-remote-sandboxes.md:54-74` — at least one named backend (`dev-box: { backend: ssh, ... }`). Keep `${VAR}`/non-secret paths (`identity_file: ~/.ssh/...` is a path, not a secret). **Critical fix:** the verbatim `sync.ignore` list from the guide (`.git`, `node_modules`, `__pycache__`, `*.log`) does NOT exclude `.env` — `~/.hermes/.env` sits directly inside the `push: ~/.hermes` root and holds live provider API keys (`part19-security-playbook.md:196` states keys must stay host-only). Add `.env` (and any other credential-bearing filename used elsewhere in this repo's templates) to `sync.ignore` before shipping this block. Comment `backend`, `sync.pull_on_teardown`, `sync.pull_paths`, and the `.env` exclusion with a one-line rationale.
5. Ensure agent names are consistent across blocks: every `agent:` in `delegation.routing` has a matching key under `acp` (internal-consistency success criterion).
6. Add `delegate_task`, `kanban`, and `sandbox` to `security.approval.require_approval` (`production.yaml:183-188`, currently `github`/`terminal`/`email`/`twilio`/`any_mcp`) so the new delegation surfaces are gated the same way existing write-capable tools are. Note in a comment that `security.approval.denylist` (`production.yaml:176-182`) is a regex match over terminal exec strings and does NOT see structured `kanban_*`/`sandbox`/`delegate_task` calls — this gap is a known limitation to flag, not fix in this phase.

### 3. Tests After (regression gate)

7. Re-run `yamllint -c .github/yamllint.yml templates/` — confirm still exit 0.
8. Grep the file for accidental secrets (no literal keys/tokens; only `${VAR}` or non-secret paths). Also grep specifically for `.env` inside every `sandboxes.*.sync.ignore` list added in step 4.

## Success Criteria

- [ ] `yamllint -c .github/yamllint.yml templates/` exits 0 (before and after).
- [ ] `delegation`, `acp`, `sandboxes` blocks present and match part18/part21 shapes.
- [ ] `acp` block ships `clients:` only (client-only per validation decision); citation for the source range is accurate (`part18-coding-agents.md:188-204`, not `195-206`) even though only a subset is shipped, with a comment explaining the intentional omission of `enabled`/`server`.
- [ ] Every `delegation.routing` agent name has a matching `acp` client key.
- [ ] `sandboxes.*.sync.ignore` excludes `.env` (or any credential-bearing file) — never syncs `~/.hermes` secrets to a remote sandbox.
- [ ] `security.approval.require_approval` includes `delegate_task`, `kanban`, `sandbox`.
- [ ] No secrets embedded — `${VAR}` placeholders / non-secret paths only.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| yamllint failure from indentation/flow-map nits | Med | Low | `yamllint.yml` relaxes indentation/colons/commas; run lint before commit (step 7) |
| Accidentally embedding a real secret | Low | High | CONTRIBUTING `${VAR}` rule; step 8 grep; SSH identity is a path not a key |
| Duplicating an existing block | Low | Low | Confirmed none exist (`production.yaml:1-220`); re-check before adding |
| Agent names drift between `delegation` and `acp` | Med | Med | Step 5 consistency pass + success criterion |
| Verbatim `sandboxes.sync` block uploads `~/.hermes/.env` to third-party sandbox infra on every `/sandbox start` | Was High (red-team Critical) | High | Step 4 mandates a `.env` exclusion in `sync.ignore` before this block ships — do not copy the guide's `ignore:` list verbatim without this addition |
| New delegation toolsets bypass the existing approval gate | Was unaddressed (red-team High) | Med | Step 6 adds them to `security.approval.require_approval` |

## Security Considerations

Template ships no live credentials. `sandboxes` SSH block references a key *path*, not key material. Follow `CONTRIBUTING.md:27` — `${VAR}` for anything sensitive. **Red-team addition:** the guide's own `sandboxes.sync.ignore` example is insufficient on its own — it excludes `.git`/`node_modules`/`__pycache__`/`*.log` but not `.env`, and `push: ~/.hermes` includes `~/.hermes/.env` by default. This phase's step 4 fix is a hard requirement, not optional hardening: shipping the block without it contradicts `part19-security-playbook.md:196`'s stated invariant that agent-accessible surfaces never see `~/.hermes/.env`. Also wire `delegate_task`/`kanban`/`sandbox` into `security.approval.require_approval` (step 6) — these are structured, write-capable invocation surfaces equivalent in risk to `terminal`, which is already gated.

## Next Steps

Unblocks Phase 4 (changelog line must describe what this phase added). Independent of Phase 3 (skill derives content from guide chapters, not from this template).
