# Security-Scan Remediation Plan — 5 Phases Completed, All Gates Pass

**Date**: 2026-07-03
**Component**: Config templates (`production.yaml`, `security-hardened.yaml`, `telegram-bot.yaml`), bootstrap scripts, Caddyfile, CI workflow, cron templates
**Status**: Implemented + code-reviewed, uncommitted pending user go-ahead

## What Happened

Executed `plans/260703-1017-fix-remaining-security-scan-issues/plan.md` via `/ck:cook --parallel --tdd --auto` — 5 phases, each with its own baseline/refactor/verify/regression-gate steps written into the plan up front. Dispatched as 4 parallel `fullstack-developer` agents: Phase 2, Phase 3, Phase 4 independently, and Phase 1+Phase 5 sequentially in one agent (both touch `production.yaml`, in disjoint regions). All 5 regression gates passed. A separate `code-reviewer` pass independently reproduced all 5 gates and verdict READY TO FINALIZE — no side effects, no regressions.

**Phase 1 (HIGH)** — `templates/config/{production,security-hardened,telegram-bot}.yaml` advertised a `security.*`/`mcp_servers.*.trust`/`platforms.*.trust_label` schema that hermes-agent never implements (silently-ignored keys). Rewrote to the real schema: top-level `approvals: {mode, timeout, cron_mode, mcp_reload_confirm, destructive_slash_confirm}`, `command_allowlist: []`, and a real `security:` block (`allow_private_urls`, `redact_secrets`, `tirith_*`, `website_blocklist`, `acked_advisories`, `allow_lazy_installs`). Documented 5 capability losses inline (no per-tool approval matrix, no custom denylist regex, no approval-channel routing, no per-server `tools_allowlist`, no per-platform `trust_label`), plus a standalone disclosure that `security-hardened.yaml`'s entire `profile:`/`profiles: {quarantine,trusted}` scaffold has zero backing in hermes-agent (not just its nested `security:` key).

**Phase 2 (MEDIUM)** — Both `scripts/vps-bootstrap*.sh` installed Node via `curl -fsSL .../setup_20.x | bash -` as root (remote-script-exec-as-root). Replaced with GPG-key fetch (`deb.nodesource.com/gpgkey/nodesource-repo.gpg.key`) dearmored to `/usr/share/keyrings/nodesource.gpg`, signed apt source, `apt-get install nodejs` — styled to match the existing Caddy install block in the same files.

**Phase 3 (MEDIUM)** — `templates/caddy/Caddyfile`'s webhook vhost comment claimed Caddy rate-limits the endpoint; false (no rate-limit directive loaded). Reworded to correctly attribute: Hermes itself rate-limits post-proxy (`platforms.webhook.extra.rate_limit`, 30/min default), Caddy only adds the pre-auth 1MB body cap.

**Phase 4 (LOW)** — `.github/workflows/ci.yml` pinned `gaurav-nelson/github-action-markdown-link-check` by mutable tag `@v1`. Pinned to commit SHA `5c5dfc0ac2e225883c0e5f03a85311ec2830d368 # v1`. Worth noting: the plan's own research pass had originally transcribed the wrong SHA (`499c1e7f...`, the annotated tag's *object* SHA, not the commit it points to) — caught by red-team review before this session via the GitHub API, corrected in the plan before cook ran.

**Phase 5 (LOW)** — `templates/cron/production-crons.yaml` and `production.yaml`'s embedded `cron:` block had drifted: channel name (`telegram_private` vs `telegram_dm`), schedules on 3 overlapping jobs, and job sets. Reconciled via union + source-of-truth-wins: channel unified to `telegram_dm` (including a commented-out example line), overlapping jobs realigned to `production.yaml`'s schedule (`weekly-mcp-audit`→10am, `weekly-cost-report`/`weekly-dep-audit`→9am, `monthly-secret-rotation`→renamed `monthly-rotate`), 2 reminder jobs added, 3 `production-crons.yaml`-only jobs kept (`weekly-bypass-audit`, `daily-injection-sweep`, `disk-watchdog`).

## Notable

This plan had already been through 2 red-team review passes before cook started (12 defects caught and fixed in the plan itself — including the Phase 4 SHA mistake above, and a false "telegram-bot.yaml has no security block" claim that was checked and rejected). Cook's job was pure execution against an already-hardened plan, and code-review found nothing new — a good sign the pre-cook review investment paid off rather than pushing defect-finding into implementation.

One self-caught issue during implementation (per the Phase-1+5 agent's own report): its first draft of the capability-loss comments accidentally contained literal substrings the strict regression-gate grep matches on (e.g. `tools_allowlist:` inside a backticked reference, bare `denylist`) — caught and reworded before the gate was declared passing. Worth remembering for future plans with grep-based regression gates: the grep doesn't distinguish live YAML keys from prose describing them.

## Status

All 5 phases + code review are done. **Nothing has been committed** — plan.md and all 5 phase files are updated to `status: completed` locally, but the actual config/script changes are uncommitted pending explicit user confirmation (repo convention: never commit without being asked).

## Unresolved Questions

1. Plan's own Validation Log: 4 items were auto-decided under `--auto` with no user confirmation (capability-loss framing acceptance, whether `security-hardened.yaml`'s whole `profiles:` scaffold needs a full rewrite now vs. documented gap, whether Caddy-layer rate limiting is still wanted as defense-in-depth, cron-collision stagger-vs-accept). All defaulted to the lowest-scope "(Recommended)" option — needs user sign-off if they want to revisit any.
2. Should the 5 documented capability losses also get a mention in `docs/` (e.g. system-architecture or a config guide), or is inline-comment disclosure in the templates sufficient?
