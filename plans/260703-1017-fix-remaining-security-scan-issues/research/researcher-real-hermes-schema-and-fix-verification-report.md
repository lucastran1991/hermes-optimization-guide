# Research: Real Hermes Agent Schema + Fix Verification

Source report: `plans/reports/security-scan-260703-1005-full-repo-secrets-code-config-audit-report.md`
Ground truth: `/home/ubuntu/workspace/hermes-agent` (git clone, origin `NousResearch/hermes-agent`, HEAD `b699d27a` @ 2026-06-28 — 5 days old, current).

## Scope confirmed (5 fixable items; 6th LOW item needs no action)

| # | Report finding | Verdict | Fix location |
|---|---|---|---|
| HIGH #1 | `security.*` schema drift in 3 templates | CONFIRMED FICTIONAL — see below | Phase 1 |
| HIGH #2 | secret leak via Modal/Daytona sync | ALREADY FIXED (commit `e3c50b4`) | none — drop from scope |
| MEDIUM #3 | curl\|bash unpinned, root | CONFIRMED — only the NodeSource line, not Caddy's | Phase 2 |
| MEDIUM #4 | Caddyfile "rate-limited" claim false | CONFIRMED — only `request_body{max_size}` exists, no rate limit | Phase 3 |
| LOW #5 | hermes-agent installer curl\|bash, unprivileged user | report says no action needed | out of scope, no phase |
| LOW #6 | ci.yml action pinned by tag | CONFIRMED | Phase 4 |
| LOW #7 | cron schedule/channel drift | CONFIRMED, and WORSE than reported (see Phase 5) | Phase 5 |

## HIGH #1 — real Hermes Agent config schema (verified in source, not docs)

Templates affected: `templates/config/production.yaml:237-275`, `templates/config/security-hardened.yaml:24-29,60-95`, `templates/config/telegram-bot.yaml:45-70` (exact line ranges will shift after edits — grep `^security:` to relocate).

Fictional keys used by templates (grep confirms **zero** references anywhere in hermes-agent source):
- `security.approval.*` (bypass_subagents, auto_approve_read, denylist, require_approval list w/ per-tool granularity, approval_channel, approval_timeout_seconds)
- `security.secrets.*` (redaction_patterns, memory_write_redaction, log_redaction)
- `security.webhook.*` (require_signature, max_body_bytes, ttl_seconds)
- `security.mcp.*` (default_trust, require_allowlist)
- `mcp_servers.<name>.trust`
- `profiles: {quarantine, trusted}` with per-profile `security:` override block

Real schema (verified `hermes-agent/hermes_cli/config.py:2348-2367` (`approvals:`), `:2372` (`command_allowlist:`), `:2412-2438` (`security:`) DEFAULT_CONFIG + `tools/approval.py:1114`). Corrected by red-team review 2026-07-03 — original citation `2408-2434` only covers unrelated `platform_hints`/`hooks` keys, not this block:

```yaml
# Top-level, sibling of `security:` — NOT nested under it.
approvals:
  mode: manual          # manual | smart | off (off == --yolo, session/process-scoped only)
  timeout: 60           # seconds before auto-reject
  cron_mode: deny        # deny | approve — dangerous command inside a cron job
  mcp_reload_confirm: true
  destructive_slash_confirm: true

# Root-level list (sibling of `approvals:`), NOT `security.approval.denylist`.
# Allow-list ONLY — there is no user-configurable denylist/regex block.
# The dangerous-command detector is built into tools/approval.py and is not
# config-editable; command_allowlist only ever *permanently allows* specific
# patterns a user already approved once ("Always Approve").
command_allowlist: []

# Real `security:` block (hermes_cli/config.py:2410-2434):
security:
  allow_private_urls: false
  redact_secrets: true        # replaces security.secrets.{redaction_patterns,*_redaction} —
                               # it's a single on/off toggle, not user-editable regex patterns
  tirith_enabled: true        # external pre-exec scanner binary, own rule format, not this yaml
  tirith_path: tirith
  tirith_timeout: 5
  tirith_fail_open: true
  website_blocklist:
    enabled: false
    domains: []
    shared_files: []
  acked_advisories: []
  allow_lazy_installs: true
```

Webhook signature validation is real but NOT a `security.webhook.*` block — it's the `WEBHOOK_SECRET` env var (global HMAC secret, `hermes_cli/config.py:4040`) or a per-route `secret:` field (`hermes_cli/webhook.py:120`). `ttl_seconds` has no config-schema equivalent (only internal hardcoded TTLs, e.g. `gateway/platforms/webhook.py:140`, not exposed).

**Correction (red-team review 2026-07-03): `max_body_bytes` IS real, just wrong namespace.** `gateway/platforms/webhook.py:148-149` reads `config.extra.get("max_body_bytes", 1_048_576)`, enforced at `:474`, documented at `website/docs/user-guide/messaging/webhooks.md:420-425` as `platforms.webhook.extra.max_body_bytes`. Same file also enforces **request-rate limiting** hermes-agent-side: `:145` `self._rate_limit = config.extra.get("rate_limit", 30)  # per minute`, enforced via `_record_rate_limit_hit` (`:316-339`, checked at `:511`), documented at `webhooks.md:398-410`. The original "no config exists anywhere" / "Caddy is the only enforcement point" framing below is WRONG for these two — fixed in Phase 1/3. `templates/config/production.yaml` has no `platforms.webhook` section today, so these real keys aren't yet exposed in any template (optional follow-up, not required for the accuracy fix).

MCP server trust: no `trust` field on `mcp_servers.<name>` entries. Real mechanism is automatic — `hermes_cli/mcp_security.py::validate_mcp_server_entry` flags suspicious entries and the CLI force-disables them (`entry["enabled"] = False`), not a user-set trust tier.

**Correction (red-team review 2026-07-03): the fictional-key list above was scoped too narrowly — sibling keys in the exact same stanzas are equally fictional and were wrongly left "out of scope, not flagged":**
- `mcp_servers.<name>.tools_allowlist` and `mcp_servers.<name>.allow_sampling` (flat bool) — zero hits anywhere in hermes-agent `.py` source. `tools_allowlist` has **no real equivalent** (no per-server tool-restriction mechanism exists at all — zero hits for `allowed_tools`/`tool_filter` in `tools/mcp_tool.py`). `allow_sampling` DOES have a real equivalent, just differently shaped: `tools/mcp_tool.py:44` docstring shows a real nested `sampling: { enabled, model, max_tokens_cap, timeout, max_rpm, allowed_models, max_tool_rounds, log_level }` dict — `allow_sampling: false` should map to `sampling: { enabled: false }`.
- `platforms.<name>.trust_label` (8 occurrences across `production.yaml`'s telegram/discord/slack/google_chat/teams/line/simplex/email entries, 1 in `telegram-bot.yaml`) — zero hits as a config-schema key anywhere in `.py` source. Its only real use is an unrelated skill-marketplace display field (`hermes_cli/skills_hub.py`). **No real equivalent** for a per-platform trust tier.
- These must be treated with the same "confirmed fictional" verdict as `mcp_servers.*.trust` (which Phase 1 already deletes one line above `tools_allowlist`/`allow_sampling` in the same stanza) — "not flagged by the original scan report" is not the same as "verified real."

**Bigger correction (red-team review 2026-07-03): `security-hardened.yaml`'s entire `profile:`/`profiles:` mechanism is fictional, not just its nested `security:` sub-key.** The file's header (lines 1-17) markets "Quarantine mode as default" via `profile: quarantine` selecting into a `profiles: {quarantine, trusted}` dict with per-profile `models`/`tools_allowlist`/`memory: {write,read}`, plus a referenced `/trusted` slash command. `grep -n '"profiles"\|"profile"' hermes_cli/config.py` → **zero hits** in DEFAULT_CONFIG (the only real `profiles` feature is `hermes_cli/profiles.py`'s unrelated directory-based `hermes -p <name>` multi-instance mechanism); `grep -rn "'/trusted'"` across all `.py` → zero hits. This is a bigger capability gap than any single nested key: the file's headline protection (auto-tiering untrusted conversations into a restricted profile) does not exist at all, not just its approval sub-block. Originally filed as a Med/Low risk row ("`profiles:` block still fictional after rewrite") — elevate to its own explicit disclosure, not a footnote.

**Capability loss to call out explicitly in the plan (cannot be silently dropped — needs a validate-workflow question):**
- Per-tool granular `require_approval` (e.g. gate only `github.merge_pr` + `terminal.exec`, auto-approve everything else) has **no real equivalent**. Real `approvals.mode` is global (manual/smart/off) with no per-tool/per-action matrix.
- Custom regex `denylist` patterns (e.g. blocking `curl.*|.*bash`, IMDS IP, `~/.ssh` reads) have **no real config equivalent**. Closest real mechanisms: (a) built-in non-configurable dangerous-command detector, (b) `tirith` external scanner (separate binary + its own rule file, out of scope for a `config.yaml` template), (c) OS-level controls (the guide's own stated principle per `part19-security-playbook.md:33`: "the only real security boundary is the OS").
- `approval_channel` (routing approvals to a specific bot/DM) has no real equivalent — `part19-security-playbook.md:135` says approvals route to whatever channel the message came from; there's no separate approval-channel config.
- `tools_allowlist` (per-MCP-server tool restriction) and `platforms.*.trust_label` (per-platform trust tier) have **no real equivalent** (added above, red-team review).
- **The whole `security-hardened.yaml` "quarantine vs trusted" profile-switching premise** has no real equivalent (added above, red-team review) — this is the largest single gap, bigger than any nested key.

Recommended rewrite approach: keep the templates' *intent* documented in comments (what the user was trying to achieve) but implement with real keys, and add an explicit comment block stating the capability gaps above so users don't think they still have per-tool denylist protection.

## MEDIUM #3 — NodeSource curl\|bash (verified against upstream NodeSource docs, not memory)

Only `scripts/vps-bootstrap.sh:55` / `scripts/vps-bootstrap-oci.sh:68` (`curl -fsSL https://deb.nodesource.com/setup_20.x | bash -`) are in scope. The Caddy gpg-key line in the same files (`curl -fsSL .../gpg.key | gpg --dearmor -o ...`) is **not** `curl|bash` — report itself calls it "the safer half," not a target for this phase.

Verified current official manual method (NodeSource wiki, fetched 2026-07-03, `github.com/nodesource/distributions/wiki/Repository-Manual-Installation`):

```sh
sudo apt-get install -y ca-certificates curl gnupg
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "Types: deb
URIs: https://deb.nodesource.com/node_20.x/
Suites: nodistro
Components: main
Signed-By: /etc/apt/keyrings/nodesource.gpg" | sudo tee /etc/apt/sources.list.d/nodesource.sources
sudo apt-get update
sudo apt-get install -y nodejs
```

This mirrors the Caddy GPG-key + apt-source pattern already used two lines below in the same script (same trust model: signed apt repo, no remote script execution). `ca-certificates`, `curl`, `gnupg` are already installed by the earlier `apt-get install` block in both scripts — no new package deps.

## MEDIUM #4 — Caddyfile rate-limit claim

`templates/caddy/Caddyfile:59`: comment says "rate-limited"; only Caddy-level directive present is `request_body { max_size 1MB }` (body-size cap, not a request-rate limit at the Caddy layer).

**Correction (red-team review 2026-07-03): the original "no rate limit is enforced" framing is false.** The vhost proxies to `127.0.0.1:8766`, hermes-agent's own webhook listener, which enforces its own rate limit (`platforms.webhook.extra.rate_limit`, default 30 req/min, `gateway/platforms/webhook.py:145,316-339,511`) and body cap (`platforms.webhook.extra.max_body_bytes`, default 1MB, `:148-149,474`) independent of Caddy. The comment fix must say rate limiting IS enforced — just by hermes-agent post-proxy, not by Caddy pre-proxy. Whether Caddy-layer rate limiting is still wanted as defense-in-depth against a pre-auth flood (before the request reaches hermes-agent) is now a narrower, optional question — not "is there any rate limiting at all." Adding a caddy-side `caddy-ratelimit` plugin would still require a custom `xcaddy` build (this repo's install path uses stock Caddy from Cloudsmith), so it remains a bigger lift than a comment fix regardless.

## LOW #6 — ci.yml action SHA

**Correction (red-team review 2026-07-03): original SHA was the wrong git-object type.** `git ls-remote` on an annotated tag returns TWO lines: the tag object's own SHA (bare `refs/tags/v1`) and the commit it points to (`refs/tags/v1^{}`). `gaurav-nelson/github-action-markdown-link-check@v1` is an annotated tag:
```
499c1e7f3637c131334fa8e937c45144f79d72d2  refs/tags/v1        <- tag object, NOT what we want
5c5dfc0ac2e225883c0e5f03a85311ec2830d368  refs/tags/v1^{}     <- the actual commit, USE THIS
```
Confirmed via GitHub API: `GET /repos/gaurav-nelson/github-action-markdown-link-check/git/tags/499c1e7f...` → `200`, `{"object": {"sha": "5c5dfc0ac2e225883c0e5f03a85311ec2830d368", "type": "commit"}}`; `GET .../git/commits/499c1e7f...` → `404`. Pin `uses:` to **`5c5dfc0ac2e225883c0e5f03a85311ec2830d368`** (the peeled commit), not `499c1e7f...` — a tag-object pin is reachable only via the `v1` ref and becomes GC-eligible if that ref is ever deleted/moved, and SHA-audit tooling (Dependabot, `pin-github-action`, OpenSSF Scorecard) resolves via the commits API and won't recognize a tag-object SHA as pointing at `v1`.

## LOW #7 — cron drift (worse than report's "cosmetic" label — still LOW severity, no security impact, but content divergence not just naming)

`templates/cron/production-crons.yaml` and the embedded `cron:` block in `templates/config/production.yaml` (`templates/config/production.yaml:289-302`) are **two independently-maintained job lists**, not just a channel-name typo:
- Different `notify` target: `telegram_private` vs `telegram_dm`.
- Different schedule times for overlapping jobs (weekly-mcp-audit 9am vs 10am, weekly-dep-audit noon vs Monday-9am, etc).
- Different job sets: `production-crons.yaml` has `weekly-bypass-audit`, `daily-injection-sweep`, `disk-watchdog` (no-agent mode) that `production.yaml`'s embedded block lacks; `production.yaml` has `monthly-skill-curator-reminder` / `monthly-journey-reminder` (added in commit `f8948a8`, 2026-07-03) that `production-crons.yaml` lacks.

`production-crons.yaml`'s own header says it's meant to be pasted into `~/.hermes/cron.yaml` or included via `cron_files:` — i.e. it's a legitimate *separate* modular-cron artifact, not a pure duplicate to delete. `production.yaml`'s embedded block looks like the actively-maintained one (received the newest additions same day). Recommend: `production.yaml`'s cron list is the source of truth; sync `production-crons.yaml`'s content (schedule + notify channel) to match it, and note in a comment that both must be updated together — doesn't eliminate future drift risk, so surface the long-term dedup approach as a validate-workflow question (sync-only vs restructure so one file includes/generates the other) rather than deciding unilaterally.

The `# notify: telegram_private` inside the commented-out `morning-digest` example block (line 54) is a 9th occurrence beyond the 8 active-job hits — must be included in the sync scope (a "replace every notify: telegram_private" refactor that skips comments leaves this one behind and fails a naive gate).

**Correction (red-team review 2026-07-03): the reconciliation itself creates two new same-time collisions.** `production.yaml`'s source-of-truth cron block already has `weekly-dep-audit` and `weekly-cost-report` both at `"0 9 * * 1"` (Monday 9am) — a pre-existing collision in the file being treated as canonical. Separately, aligning `production-crons.yaml`'s `weekly-mcp-audit` to `"0 10 * * 1"` (per production.yaml) collides with `production-crons.yaml`'s own `weekly-bypass-audit`, already at `"0 10 * * 1"` and kept unchanged (it's one of the 3 jobs unique to this file). Post-sync, `production-crons.yaml` ends up with 2 same-minute job pairs. Not a security issue, but a real operational one (concurrent cron-triggered LLM sessions, possible cost/rate-limit spike) the phase should at least flag, even if the resolution is "accept as-is."

## Unresolved / needs user input (surface at validate-workflow, not decided here)

1. Phase 1 capability loss (no per-tool approval granularity, no custom denylist, no per-server tools_allowlist, no per-platform trust_label) — confirm user accepts the accuracy-over-aspiration tradeoff.
2. Phase 1 — should the `security-hardened.yaml` whole `profiles:`/`profile:` scaffold fix (not just its nested `security:` key) block this plan's Phase 1 sign-off, or ship as a documented known-gap?
3. Phase 3 — now that hermes-agent itself rate-limits webhooks post-proxy, is Caddy-layer rate limiting (via `xcaddy` + `caddy-ratelimit`) still wanted as pre-auth defense-in-depth, or does rewording the comment (no plugin) fully close this finding?
4. Phase 5 — one-time sync vs. structural dedup to prevent re-drift, AND how to handle the 2 same-time cron collisions the sync itself introduces (stagger vs accept-as-is).
