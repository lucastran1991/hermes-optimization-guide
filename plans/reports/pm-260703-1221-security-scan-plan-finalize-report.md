# PM Report: Security-Scan Remediation Plan Finalize

Plan: `plans/260703-1017-fix-remaining-security-scan-issues/plan.md`
Status: pending → **completed** (5/5 phases, 100%)

## Phase Status

| Phase | Finding | Sev | Gate | Status |
|---|---|---|---|---|
| 1 Real Security Schema Rewrite | #1 | HIGH | `PHASE 1 GATE PASS` | Done |
| 2 NodeSource Install Hardening | #3 | MEDIUM | `PHASE 2 GATE PASS` | Done |
| 3 Caddyfile Rate-Limit Claim Fix | #4 | MEDIUM | `PHASE 3 GATE PASS` | Done |
| 4 CI Action SHA Pin | #6 | LOW | `PHASE 4 GATE PASS` | Done |
| 5 Cron Drift Reconciliation | #7 | LOW | `PHASE 5 GATE PASS` | Done |

## Verification
- All 5 regression gates reproduced verbatim by independent `code-reviewer` pass (not just the implementing agents' own claim).
- yamllint clean across all touched YAML/cron files (combined run). `bash -n` clean on both bootstrap scripts.
- Zero fictional security keys remain as live YAML in any of the 3 config templates (per-file check, not summed).
- Zero plan-phase/finding-code references leaked into code comments (checked via grep per `review-audit-self-decision.md` rule 5).
- No side effects / regressions found. Verdict: READY TO FINALIZE.

## Docs
- Checked `part19-security-playbook.md` for drift against the new real schema — already correct (line 217 already states no per-server `trust`/`allow_sampling` knobs exist). No doc changes needed.

## Files Changed (8)
`templates/config/production.yaml`, `templates/config/security-hardened.yaml`, `templates/config/telegram-bot.yaml`, `templates/cron/production-crons.yaml`, `scripts/vps-bootstrap.sh`, `scripts/vps-bootstrap-oci.sh`, `templates/caddy/Caddyfile`, `.github/workflows/ci.yml`

## Unresolved Questions
- Plan's own Validation Log: 4 items were auto-decided under `--auto` with no user confirmation (capability-loss framing, `security-hardened.yaml` profiles-scaffold full-fix-vs-disclose, Caddy defense-in-depth rate limiting, cron collision stagger-vs-accept). Not a code defect — carried over from plan.md, needs user sign-off if they want to revisit any of the 4 defaults.
- Separately (not part of this plan): `templates/systemd/hermes.service` has an unrelated pending fix (Bun coding-CLI `sched_setscheduler` seccomp block) from a different /fix session — not yet committed, not yet deployed to the live host (requires user's root access).
