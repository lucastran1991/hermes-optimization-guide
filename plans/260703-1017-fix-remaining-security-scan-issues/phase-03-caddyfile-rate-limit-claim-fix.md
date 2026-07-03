---
phase: 3
title: "Caddyfile Rate-Limit Claim Fix"
status: completed
effort: "0.25h"
---

# Phase 3: Caddyfile Rate-Limit Claim Fix

## Context Links

- Research (ground truth): `research/researcher-real-hermes-schema-and-fix-verification-report.md` (§ "MEDIUM #4")
- Scan finding: `plans/reports/security-scan-260703-1005-full-repo-secrets-code-config-audit-report.md` (MEDIUM #4)

## Overview

**Priority:** MEDIUM (finding #4). **Status:** Pending.

The webhook vhost comment at `templates/caddy/Caddyfile:59` claims the endpoint is "rate-limited," but the only **Caddy-level** directive present is `request_body { max_size 1MB }` — a body-size cap, not a Caddy request-rate limit. Stock Caddy has no built-in rate-limiting plugin loaded here.

**Red-team correction (2026-07-03): the vhost IS actually rate-limited — just not by Caddy.** This vhost reverse-proxies to `127.0.0.1:8766`, hermes-agent's own webhook listener, which enforces its own rate limit post-proxy (`platforms.webhook.extra.rate_limit`, default 30 req/min, `gateway/platforms/webhook.py:145,316-339,511`) and its own body cap (`platforms.webhook.extra.max_body_bytes`, default 1MB, `:148-149,474`) independent of Caddy. The original plan drafted a replacement comment saying "no request-RATE limit is enforced" — that would have been a NEW false claim, worse than the one it replaces. **Fix: reword to say rate limiting is enforced by hermes-agent (not Caddy), and Caddy only adds the pre-auth body cap.**

## Key Insights

- No live vulnerability — this is a doc/config accuracy mismatch (misattributed enforcement point, not a missing control).
- Whether Caddy-layer rate limiting is *also* wanted as pre-auth defense-in-depth (before a flood even reaches the hermes-agent process) is now a narrower, optional question (unresolved question 3) — not "is there any rate limiting at all." Adding it would still need a custom `xcaddy` build (this repo's install path uses stock Caddy from Cloudsmith apt) — a bigger lift than a comment fix regardless of the answer.
- Caddyfile is not YAML → yamllint does not apply; `caddy validate` requires caddy installed (not guaranteed here) → grep + manual read is the gate.

## Requirements

**Functional**
- Comment on the webhook vhost accurately attributes each control: rate limiting (hermes-agent, post-proxy) vs body cap (Caddy, pre-proxy) vs signature validation (hermes-agent). No false "Caddy rate-limits this" claim AND no false "nothing rate-limits this" claim.

**Non-functional**
- Caddyfile stays syntactically valid (visual/`caddy validate` if available).
- Comment describes reality, not finding codes/phases.

## Architecture

No behavioral change — comment-only edit. The `request_body { max_size 1MB }` directive (lines ~64-66) and `reverse_proxy` stay as-is. Only the descriptive comment on line ~59 changes so the doc matches the enforced config.

Recommended reworded comment (copy-paste-safe):

```
# Webhooks — no basicauth (Hermes validates the signature via WEBHOOK_SECRET).
# Request-rate limiting is enforced by Hermes itself (platforms.webhook.extra.rate_limit,
# default 30/min), not by Caddy. Caddy only adds the 1MB pre-auth body cap below —
# a defense-in-depth layer for a caddy-ratelimit plugin (xcaddy build) is optional,
# not required, since the request is already rate-limited once it reaches Hermes.
```

## Related Code Files

**Modify:**
- `templates/caddy/Caddyfile` — comment line ~59 only. Leave `request_body`/`reverse_proxy`/`log` blocks untouched.

**Create / Delete:** none.

## Implementation Steps

### Tests Before (baseline)

```sh
grep -c ', but rate-limited' templates/caddy/Caddyfile  # expect 1 (the old false "Caddy rate-limits" claim)
grep -c 'max_size 1MB' templates/caddy/Caddyfile        # expect 1 (must stay after)
```

### Refactor

1. Replace the line `# Webhooks — no basicauth (signature-validated in Hermes), but rate-limited` with the reworded comment above (or an equivalent that drops "rate-limited" and describes the 1MB cap).

### Tests After

```sh
grep -c ', but rate-limited' templates/caddy/Caddyfile   # expect 0 (old false "Caddy rate-limits" claim gone)
grep -c 'max_size 1MB' templates/caddy/Caddyfile         # expect 1 (unchanged)
grep -c 'enforced by Hermes itself' templates/caddy/Caddyfile   # expect >=1 (correct attribution present)
grep -c 'no request-RATE limit is enforced\|no request-rate limit is enforced' templates/caddy/Caddyfile   # expect 0 — must NOT ship the other false claim
```

### Regression Gate

```sh
test "$(grep -c ', but rate-limited' templates/caddy/Caddyfile)" = "0" \
  && test "$(grep -Ec 'no request-RATE limit is enforced|no request-rate limit is enforced' templates/caddy/Caddyfile)" = "0" \
  && grep -q 'max_size 1MB' templates/caddy/Caddyfile \
  && grep -q 'enforced by Hermes itself' templates/caddy/Caddyfile \
  && echo "PHASE 3 GATE PASS"
# Optional if caddy present: caddy validate --config templates/caddy/Caddyfile --adapter caddyfile
```

## Todo List

- [x] Reword webhook vhost comment (correct attribution: Hermes rate-limits, Caddy caps body size)
- [x] Confirm `request_body`/`reverse_proxy` blocks unchanged
- [x] Run Regression Gate → `PHASE 3 GATE PASS`

## Success Criteria

- Zero "Caddy rate-limits this" claims and zero "nothing rate-limits this" claims; comment accurately attributes rate limiting to Hermes and body cap to Caddy.
- No behavioral directive changed.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Operator still wants Caddy-layer rate limiting as pre-auth defense-in-depth | Med | Low | Surfaced as unresolved question 3 for validate-workflow — do not decide unilaterally; now framed correctly as "defense-in-depth" not "the only rate limit." |
| Comment edit accidentally breaks Caddyfile block structure | Low | Low | Comment-only line; gate confirms directive lines intact. |
| Shipping a corrected comment that still misattributes enforcement (red-team caught this once already) | Low (now corrected) | Med | Gate explicitly asserts both the old false claim AND the alternate false claim are absent, and the correct attribution is present. |

## Security Considerations

- Corrects a misleading claim. Original text said Caddy rate-limits (false — Caddy has no rate-limit directive loaded); a naive fix would have said nothing rate-limits it (also false — hermes-agent's webhook adapter does, post-proxy, 30/min default). Final text attributes each control to its real enforcement point so an operator can correctly judge whether additional defense-in-depth is needed.
- No secrets, no behavioral change to signature validation (still `WEBHOOK_SECRET`-driven in Hermes) or to the real rate limit/body cap (both remain hermes-agent defaults, unchanged by this phase).

## Next Steps

- Fully independent file. If unresolved question 3 resolves toward "still want Caddy-layer defense-in-depth," that becomes a separate, larger follow-up (xcaddy build in bootstrap scripts) — optional, not required, since Hermes already rate-limits.
