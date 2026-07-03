---
phase: 1
title: "Real Security Schema Rewrite"
status: completed
effort: "3.5h"
---

# Phase 1: Real Security Schema Rewrite

## Context Links

- Research (ground truth): `research/researcher-real-hermes-schema-and-fix-verification-report.md` (§ "HIGH #1")
- Scan finding: `plans/reports/security-scan-260703-1005-full-repo-secrets-code-config-audit-report.md` (HIGH #1)
- hermes-agent source cited by research: `hermes_cli/config.py:2348-2367` (`approvals:`), `:2372` (`command_allowlist:`), `:2412-2438` (`security:`), `tools/approval.py:1114`, `hermes_cli/webhook.py:120`, `hermes_cli/mcp_security.py::validate_mcp_server_entry`, `gateway/platforms/webhook.py:145,148-149` (real rate_limit/max_body_bytes), `tools/mcp_tool.py:44` (real nested `sampling:` schema), `hermes_cli/profiles.py` (real, unrelated directory-based profile mechanism)
- In-repo doc that already flagged the drift: `part19-security-playbook.md:5,33,135`
- Red-team reviews (2026-07-03): `reports/from-code-reviewer-to-planner-red-team-security-adversary-plan-review-report.md`, `reports/from-code-reviewer-to-planner-red-team-assumption-destroyer-plan-review-report.md`, `reports/from-code-reviewer-to-planner-red-team-failure-mode-analyst-plan-review-report.md`

## Overview

**Priority:** HIGH (finding #1). **Status:** Pending.

Three config templates advertise a `security.*` schema that hermes-agent does not implement — the keys are silently ignored, so `security-hardened.yaml` ships **zero** of its advertised hardening. Rewrite every `security:` block (plus the nested per-profile one and the fictional `mcp_servers.*.trust` fields) to the real, enforced schema, preserving the operator's *intent* in comments and explicitly documenting the capabilities that have **no real equivalent** so users are not misled a second time.

**Scope expanded by red-team review (2026-07-03):** the original scope (3 `security:` blocks + `mcp_servers.*.trust`) missed sibling fictional keys in the exact same stanzas (`trust_label`, `tools_allowlist`, `allow_sampling`) and understated `security-hardened.yaml`'s core problem — its ENTIRE `profile:`/`profiles:` scaffold is fictional, not just the nested `security:` key inside it. Both are now in scope (see Key Insights, Related Code Files, Implementation Steps). Capability-loss disclosures grew from 3 to 5 items accordingly.

## Key Insights

- Fictional keys (grep confirms **zero** hits in hermes-agent source): `security.approval.*`, `security.secrets.*`, `security.webhook.*`, `security.mcp.*`, `mcp_servers.<name>.trust`, and the `profiles: {quarantine,trusted}` per-profile `security:` override.
- Real approval controls are **top-level** keys (`approvals:`, `command_allowlist:`), NOT nested under `security:`. Sourced from `hermes_cli/config.py:2348-2367` (`approvals:`), `:2372` (`command_allowlist:`) — corrected by red-team review 2026-07-03, original citation pointed at the wrong line range.
- Real `security:` block is a fixed set: `allow_private_urls`, `redact_secrets`, `tirith_*`, `website_blocklist`, `acked_advisories`, `allow_lazy_installs` (`hermes_cli/config.py:2412-2438`).
- Webhook signature validation is real but env/route-driven (`WEBHOOK_SECRET` env var or per-route `secret:`), not a `security.webhook.*` config block. **Correction (red-team review 2026-07-03): `max_body_bytes` and rate limiting ARE real, just wrong namespace/wrong claim.** `gateway/platforms/webhook.py:145,148-149` implements `platforms.webhook.extra.rate_limit` (default 30/min) and `platforms.webhook.extra.max_body_bytes` (default 1MB) — hermes-agent enforces both itself, independent of Caddy. Only `ttl_seconds` has no config-schema equivalent (internal hardcoded TTL only). See Implementation Steps for the corrected comment wording.
- MCP trust is **automatic** (`validate_mcp_server_entry` force-disables suspicious servers), not a user-set `trust:` tier — so `mcp_servers.*.trust` and `security.mcp.default_trust` are both no-ops.
- The `profiles:` block's per-profile `security:` override is also fictional; the real `approvals:`/`security:` live once at top level and govern the whole process. **Correction (red-team review 2026-07-03, Critical): this understates the problem.** The ENTIRE `profile:`/`profiles: {quarantine,trusted}` scaffold in `security-hardened.yaml` — not just its nested `security:` sub-key — has zero backing in `hermes_cli/config.py` DEFAULT_CONFIG (`grep -n '"profiles"\|"profile"'` → 0 hits as a config-schema key; the only real `profiles` feature is `hermes_cli/profiles.py`'s unrelated directory-based `hermes -p <name>` mechanism). The file's own referenced `/trusted` slash command also doesn't exist (zero hits). This phase's scope is expanded below to disclose this explicitly, not just patch the nested key.
- **Correction (red-team review 2026-07-03, High): `trust_label:` (8x in production.yaml's `platforms:` block + 1x telegram-bot.yaml, zero hits as a config-schema key anywhere), `mcp_servers.*.tools_allowlist` (zero hits, no real per-server tool-restriction mechanism exists at all), and `mcp_servers.*.allow_sampling` (zero hits as a flat bool — but a real NESTED equivalent exists: `sampling: { enabled, model, max_tokens_cap, ... }` per `tools/mcp_tool.py:44`) were originally left untouched with the reasoning "not flagged by research → out of scope." That reasoning was wrong — these are exactly as fictional as `mcp_servers.*.trust`, one line away in the same stanza. Now in scope (see Implementation Steps).

## Requirements

**Functional**
- Every `security:` block in the 3 files uses only real, enforced hermes-agent keys.
- Operator intent from the old fictional keys is preserved as descriptive comments.
- The 5 capability losses are called out inline so users don't re-assume protection they don't have.
- `mcp_servers.*.trust` fields removed (no-op), replaced with a one-line comment on the automatic mechanism.
- `mcp_servers.*.tools_allowlist` (no real equivalent) removed with capability-loss comment; `mcp_servers.*.allow_sampling: false` remapped to the real nested `sampling: { enabled: false }`.
- `platforms.*.trust_label` (8x production.yaml, 1x telegram-bot.yaml) removed with capability-loss comment (no real equivalent).
- `security-hardened.yaml`'s `profile:`/`profiles:` scaffold gets an explicit disclosure comment stating the whole mechanism (not just its nested `security:` key) is non-functional today.

**Non-functional**
- All 3 files remain valid YAML (yamllint clean).
- Comments describe the *invariant/reason*, never plan phases or finding codes.

## Architecture

Data flow: operator edits `~/.hermes/config.yaml` (copied from a template) → hermes-agent loads it against `DEFAULT_CONFIG` → **unknown keys are silently dropped** (the failure mode this phase fixes) → only real keys take effect. The rewrite aligns the template's key namespace with what the loader actually reads, so what the file *says* equals what the agent *enforces*.

Real schema to apply (transcribed from research, do not re-derive):

```yaml
# hermes-agent approval controls are TOP-LEVEL keys, not nested under `security:`.
approvals:
  mode: manual              # manual | smart | off  (off == --yolo, session-scoped)
  timeout: 60               # seconds before an unanswered request auto-rejects
  cron_mode: deny           # deny | approve — dangerous command inside a cron job
  mcp_reload_confirm: true
  destructive_slash_confirm: true

# Allow-list ONLY (root-level). Entries here PERMANENTLY allow a pattern the
# operator already approved once. There is NO user-editable denylist/regex.
command_allowlist: []

security:
  allow_private_urls: false
  redact_secrets: true        # single on/off toggle (built-in detectors); NOT user-editable regex
  tirith_enabled: true        # external pre-exec scanner (own binary + rule file)
  tirith_path: tirith
  tirith_timeout: 5
  tirith_fail_open: true      # true = allow on scanner error; false = fail-closed
  website_blocklist:
    enabled: false
    domains: []
    shared_files: []
  acked_advisories: []
  allow_lazy_installs: true
```

Intent-mapping (fictional → real) to bake into comments:

| Old fictional intent | Real handling |
|---|---|
| `approval.require_approval` per-tool matrix (github/terminal/email/…) | `approvals.mode` global gate — **no per-tool matrix exists** |
| `approval.bypass_subagents` (named jobs skip approval) | `approvals.cron_mode` (global for all cron jobs) — no per-named-job bypass |
| `approval.auto_approve_read: true` | closest real tier is `approvals.mode: smart` (light-touch); exact policy owned by hermes-agent |
| `approval.denylist` regex patterns | **nothing** — built-in dangerous-cmd detector (not config) + optional `tirith` + OS controls |
| `approval.approval_channel: telegram_dm` | **nothing** — approvals route to the channel the message came from |
| `secrets.redaction_patterns` / `*_redaction` | `security.redact_secrets: true` (single toggle) |
| `webhook.{require_signature,ttl_seconds}` | `WEBHOOK_SECRET` env var / per-route `secret:` (signature); **no** `ttl_seconds` equivalent |
| `webhook.max_body_bytes` | **real, different namespace:** `platforms.webhook.extra.max_body_bytes` (default 1MB) — corrected 2026-07-03, originally miscategorized as fictional |
| (new, red-team 2026-07-03) rate-limiting intent implied by "webhook" hardening | **real:** `platforms.webhook.extra.rate_limit` (default 30/min) — hermes-agent enforces this itself, independent of Caddy |
| `security.mcp.default_trust` / `mcp_servers.*.trust` | automatic (`validate_mcp_server_entry` force-disables suspicious servers) |
| `mcp_servers.*.tools_allowlist` (red-team 2026-07-03) | **nothing** — no per-server tool-restriction mechanism exists |
| `mcp_servers.*.allow_sampling: false` (red-team 2026-07-03) | **real, different shape:** nested `sampling: { enabled: false }` (`tools/mcp_tool.py:44`) |
| `platforms.*.trust_label` (red-team 2026-07-03) | **nothing** — no per-platform trust tier exists |
| `profiles.*.security` override | **nothing** — top-level `approvals:`/`security:` govern the whole process |
| `profile: quarantine` / `profiles: {quarantine,trusted}` scaffold itself, incl. `/trusted` slash command (red-team 2026-07-03, Critical — bigger than the row above) | **nothing** — zero backing in DEFAULT_CONFIG; the real (unrelated) `profiles` feature is `hermes_cli/profiles.py`'s directory-based `hermes -p <name>` mechanism, not a runtime trust-tier switch |

## Related Code Files

**Modify:**
- `templates/config/production.yaml` — remove `trust:` from 4 `mcp_servers` entries (~139/151/158/167); remove `tools_allowlist:` from the same entries (no real equivalent, add capability-loss comment); remap `allow_sampling: false` → `sampling: { enabled: false }` on the same entries; remove `trust_label:` from all 8 `platforms:` entries (~68-116, no real equivalent, add capability-loss comment); replace `security:` block (~237-275) with real `approvals:`+`command_allowlist:`+`security:`. **Do NOT touch the `cron:` block (289-302) — Phase 5.**
- `templates/config/security-hardened.yaml` — add an explicit disclosure comment on the `profile:`/`profiles:` scaffold (~17-31) stating the whole selector+dict mechanism is non-functional (not just its nested `security:` key) and pointing at the real, unrelated `hermes -p <name>` directory-based feature; rewrite nested `profiles.quarantine.security.*` (~24-29) to a comment pointing at the real top-level block; replace top-level `security:` (~60-95) with real schema (`mode: manual`).
- `templates/config/telegram-bot.yaml` — replace `security:` block (~45-69) with real schema (`mode: smart` to preserve the light-touch intent); remove `trust_label:` (~33, no real equivalent, add capability-loss comment).

**Create / Delete:** none.

## Implementation Steps

### Tests Before (baseline — capture current state)

```sh
# Fictional keys currently present (expect non-zero counts):
grep -Ec 'approval_channel|require_approval|denylist|redaction_patterns|default_trust' \
  templates/config/production.yaml templates/config/security-hardened.yaml templates/config/telegram-bot.yaml
grep -c 'trust: trusted' templates/config/production.yaml          # expect 4
grep -c 'trust_label:' templates/config/production.yaml            # expect 8
grep -c 'trust_label:' templates/config/telegram-bot.yaml          # expect 1
grep -c 'tools_allowlist:' templates/config/production.yaml        # expect >=1
grep -c 'allow_sampling:' templates/config/production.yaml         # expect >=1
# Real keys currently ABSENT (expect 0):
grep -Ec '^approvals:|^command_allowlist:|redact_secrets|tirith_enabled' \
  templates/config/production.yaml templates/config/security-hardened.yaml templates/config/telegram-bot.yaml
grep -c '^security:' templates/config/telegram-bot.yaml            # expect 1 (file HAS a security: block today — verify before assuming otherwise)
# Baseline yamllint (should already pass — proves we start green):
yamllint -c .github/yamllint.yml templates/config/production.yaml templates/config/security-hardened.yaml templates/config/telegram-bot.yaml
```

### Refactor (the change)

1. **production.yaml** — delete the `trust:`, `tools_allowlist:` lines from each of the 4 `mcp_servers` entries (use `replace_all: true` for `trust: trusted` — all 4 occurrences are byte-identical and a single-shot unique-match `Edit` will reject a non-unique `old_string`); remap `allow_sampling: false` → `sampling: { enabled: false }` on the same entries; add one comment at the top of `mcp_servers:` noting trust/sampling/tool-restriction are either automatic or unsupported. Remove `trust_label:` from all 8 `platforms:` entries with a capability-loss comment. Replace the whole `security:` block with the real `approvals:`/`command_allowlist:`/`security:` from Architecture above; add a trailing comment that webhook signing is via `WEBHOOK_SECRET` env var, and that hermes-agent's own webhook adapter (not Caddy) enforces `platforms.webhook.extra.rate_limit`/`max_body_bytes` when a `platforms.webhook` section is configured (this template doesn't configure one today — noting the real mechanism, not adding the section, is in scope).
2. **security-hardened.yaml** — add a disclosure comment directly above the `profile: quarantine` line stating the entire selector + `profiles: {quarantine,trusted}` dict + referenced `/trusted` command are non-functional today (zero backing in hermes-agent's config loader); point at the real, unrelated `hermes -p <name>` directory-based profile feature for anyone who wants actual multi-instance isolation. Inside `profiles.quarantine`, replace the `security: { approval: {...} }` sub-block with a comment: hermes has no per-profile security override; the top-level `approvals:`/`security:` below govern all profiles. Replace the top-level `security:` block with the real schema, `approvals.mode: manual` (strict intent). Preserve the "strict / quarantine" intent in comments.
3. **telegram-bot.yaml** — replace the `security:` block with the real schema, `approvals.mode: smart` (preserves the auto-approve-reads / sensible-defaults intent), with a comment that `smart` is the light-touch tier (exact policy owned by hermes-agent). Remove `trust_label:` with a capability-loss comment.
4. In all 3, add the **5 capability-loss comments** inline (per-tool matrix, custom denylist regex, approval-channel routing, per-server tools_allowlist, per-platform trust_label) plus the standalone `profiles:`-scaffold disclosure in security-hardened.yaml — phrased as invariants, not finding codes.

Example inline capability-loss comment style (copy-paste-safe — no phase/finding refs):

```yaml
# NOTE: hermes-agent has no per-tool approval matrix, no user-editable denylist
# regex, no separate approval-channel, no per-server tool allowlist, and no
# per-platform trust tier. Prior versions of this file implied all of these;
# they were silently ignored. Real defenses: the global approvals.mode gate
# above, the built-in dangerous-command detector, optional tirith, MCP-server
# auto-disable on suspicious entries, and OS-level isolation ("the only real
# security boundary is the OS").
```

### Tests After (verify the change)

```sh
# Fictional keys gone (expect 0 for every file):
grep -Ec 'approval_channel|require_approval|denylist|redaction_patterns|default_trust|trust_label:|tools_allowlist:' \
  templates/config/production.yaml templates/config/security-hardened.yaml templates/config/telegram-bot.yaml
grep -c 'trust: trusted' templates/config/production.yaml          # expect 0
grep -c 'allow_sampling:' templates/config/production.yaml         # expect 0 (remapped to sampling: {enabled})
grep -c 'sampling:' templates/config/production.yaml               # expect >=1 (real remap present)
# Real keys present — PER FILE, not summed (red-team correction 2026-07-03: a
# combined-sum check across all 3 files can pass while one file is untouched):
grep -q '^approvals:' templates/config/production.yaml
grep -q '^approvals:' templates/config/security-hardened.yaml
grep -q '^approvals:' templates/config/telegram-bot.yaml
grep -q 'redact_secrets' templates/config/production.yaml
grep -q 'redact_secrets' templates/config/security-hardened.yaml
grep -q 'redact_secrets' templates/config/telegram-bot.yaml
# Still valid YAML:
yamllint -c .github/yamllint.yml templates/config/production.yaml templates/config/security-hardened.yaml templates/config/telegram-bot.yaml
```

### Regression Gate (must all pass before phase is done)

Red-team correction (2026-07-03, reproduced live): the original gate summed fictional-key counts across all 3 files and only checked `^approvals:` on `production.yaml` — an implementer could fully skip `security-hardened.yaml` or `telegram-bot.yaml` and still see `PHASE 1 GATE PASS`. Every file now gets its own explicit positive assertion:

```sh
yamllint -c .github/yamllint.yml templates/config/production.yaml templates/config/security-hardened.yaml templates/config/telegram-bot.yaml \
  && test "$(grep -Ec 'approval_channel|require_approval|denylist|redaction_patterns|default_trust|trust: trusted|trust_label:|tools_allowlist:' templates/config/production.yaml templates/config/security-hardened.yaml templates/config/telegram-bot.yaml | awk -F: '{s+=$2} END{print s}')" = "0" \
  && grep -q '^approvals:' templates/config/production.yaml \
  && grep -q '^approvals:' templates/config/security-hardened.yaml \
  && grep -q '^approvals:' templates/config/telegram-bot.yaml \
  && grep -q 'redact_secrets' templates/config/production.yaml \
  && grep -q 'redact_secrets' templates/config/security-hardened.yaml \
  && grep -q 'redact_secrets' templates/config/telegram-bot.yaml \
  && test "$(grep -c 'allow_sampling:' templates/config/production.yaml)" = "0" \
  && echo "PHASE 1 GATE PASS"
```

## Todo List

- [x] production.yaml: remove 4 `mcp_servers.*.trust` lines (`replace_all: true`) + add automatic-trust comment
- [x] production.yaml: remove `tools_allowlist:` (capability-loss comment) + remap `allow_sampling: false` → `sampling: { enabled: false }` on the 4 `mcp_servers` entries
- [x] production.yaml: remove `trust_label:` from all 8 `platforms:` entries (capability-loss comment)
- [x] production.yaml: replace `security:` block with real `approvals:`/`command_allowlist:`/`security:`
- [x] security-hardened.yaml: add whole-`profiles:`-scaffold disclosure comment above `profile: quarantine`
- [x] security-hardened.yaml: rewrite nested `profiles.quarantine.security.*` to pointer-comment
- [x] security-hardened.yaml: replace top-level `security:` block (`mode: manual`)
- [x] telegram-bot.yaml: replace `security:` block (`mode: smart`)
- [x] telegram-bot.yaml: remove `trust_label:` (capability-loss comment)
- [x] Add 5 capability-loss inline comments across all 3 files (per-tool matrix, denylist, approval-channel, tools_allowlist, trust_label) + the standalone profiles-scaffold disclosure
- [x] Run Regression Gate → `PHASE 1 GATE PASS`

## Success Criteria

- All 3 files contain only real hermes-agent keys in their security-related blocks (grep count of fictional keys == 0), checked **per file**, not as a combined sum.
- yamllint clean on all 3.
- The 5 capability losses AND the whole-`profiles:`-scaffold gap are documented inline in operator-facing language.
- Old operator intent is still legible via comments (nothing silently dropped without explanation).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Rewrite removes hardening operators believed they had | High | High | The hardening was never active (keys ignored) — this fixes a false sense of security, not a regression. Document the capability losses inline. |
| Full-file rewrite collides with Phase 5's cron edit | Med | Med | Use scoped `Edit` on the `security:`/`mcp_servers`/`platforms:` regions only; never `Write` the whole file. `telemetry:` block separates the two regions. |
| `mode: smart`/`manual` mapping doesn't match operator's original UX | Med | Low | Mapping documented in the intent table + comments; final call belongs to unresolved item 1. |
| `profiles:` scaffold still non-functional after rewrite (disclosed, not fixed) | Confirmed (red-team 2026-07-03) | Med | Explicit disclosure comment added above the scaffold; full rewrite/removal deferred to unresolved item 2 — this is bigger than a nested-key gap, needs a user decision, not a unilateral rewrite of the file's stated core feature. |
| 4 byte-identical `trust: trusted` lines make a single scoped `Edit` ambiguous (confirmed by red-team reproduction: a unique-match `Edit` tool rejects a 4-way match) | Confirmed | Low | Refactor step 1 now explicitly instructs `replace_all: true` for this removal (safe — string is unique to trust lines). |

**Unresolved (needs `/ck:plan validate` decision — reproduced verbatim from research; also tracked in plan.md; expanded from 3 to 4 items by red-team review 2026-07-03):**

1. Phase 1 capability loss (no per-tool approval granularity, no custom denylist, no per-server tools_allowlist, no per-platform trust_label) — confirm user accepts the accuracy-over-aspiration tradeoff.
2. Phase 1 — should `security-hardened.yaml`'s whole `profiles:`/`profile:` scaffold fix (not just its nested `security:` key) block this plan's sign-off, or ship as a documented known-gap alongside the other 4 capability losses?
3. Phase 3 — now that hermes-agent itself rate-limits webhooks post-proxy (30/min default), is Caddy-layer rate limiting (via `xcaddy` + `caddy-ratelimit`) still wanted as pre-auth defense-in-depth, or does the corrected comment (no plugin) fully close this finding?
4. Phase 5 — one-time sync vs. structural dedup to prevent re-drift, AND how to handle the 2 same-time cron collisions the sync itself introduces (stagger vs accept-as-is).

## Security Considerations

- **This phase does not weaken security** — the fictional keys enforced nothing. It corrects a *documentation-level* false-positive that could lead an operator to skip real OS-level controls (`part19-security-playbook.md:33`: "the only real security boundary is the OS").
- No secrets touched; `${ENV_VAR}` interpolation and `WEBHOOK_SECRET` guidance preserved.
- `tirith_fail_open: true` is the upstream default (kept) — note in comment that `false` = fail-closed for stricter deployments.
- Rate limiting and body-cap enforcement are NOT solely Caddy-side — hermes-agent's own webhook adapter enforces both independently (`platforms.webhook.extra.rate_limit`/`max_body_bytes`). This phase's comments must reflect that; see Phase 3 for the Caddyfile-side correction of the same misattribution.

## Next Steps

- Independent of Phases 2/3/4. Coordinate `production.yaml` edit ordering with Phase 5 (apply Phase 1 first; scoped Edits only).
- After merge, `docs-manager` should confirm `part19-security-playbook.md` still matches (it already documents the real schema — likely no change).
- Unresolved item 2 (whole `profiles:` scaffold) may spawn a follow-up task to rewrite `security-hardened.yaml`'s header/scaffold entirely, depending on validate-workflow's answer.
