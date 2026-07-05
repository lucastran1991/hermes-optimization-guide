---
title: "Repo security re-scan (delta vs the 2026-07-03 10:05 full scan + its remediation)"
date: 2026-07-04
type: security-scan
mode: "--auto --parallel"
baseline: plans/reports/security-scan-260703-1005-full-repo-secrets-code-config-audit-report.md
---

# Security Scan Report

**Project:** hermes-optimization-guide (docs/guide repo — no package.json/requirements.txt/go.mod/Cargo.toml, no dep audit applicable)
**Files checked:** 170 md + 3 sh + 2 py + templates/configs
**Baseline:** a full scan ran 2026-07-03 10:05 and found 5 findings (2 High, 1 Medium, 3 Low... actually 2H/2M/3L per that report) — commit `9fafe6e` fixed all 5 same day. This run re-verifies that fix holds, then reports only what's new since.

## Baseline re-verification (all 5 confirmed still fixed)

| # | 07-03 finding | Re-verified now |
|---|---|---|
| 1 | Fictional `security.*`/`mcp_servers.*.trust` schema vs part19 | `production.yaml:269`, `security-hardened.yaml:93`, `telegram-bot.yaml:68` all now use real `security:`/`approvals:` keys, with comments explaining the old-vs-new schema. **Holds.** |
| 2 | `part21-remote-sandboxes.md` Modal/Daytona missing `ignore:` | Both now have `ignore: [.env]` (lines 126, 171). **Holds.** |
| 3 | NodeSource/Caddy curl\|bash unpinned (root) | Now GPG-signed apt source (`curl \| gpg --dearmor` → keyring, not `curl \| bash`) in both bootstrap scripts. **Holds.** |
| 4 | Caddyfile false "rate-limited" claim | Comment now correctly attributes rate-limiting to Hermes itself (`platforms.webhook.extra.rate_limit`), not Caddy. **Holds.** |
| 5 | `markdown-link-check` action pinned by mutable tag | Now pinned to commit SHA `5c5dfc0ac2e225883c0e5f03a85311ec2830d368`. **Holds.** |

Per `review-audit-self-decision.md` rule 1 (verified decisions are sticky) — no re-litigation, just confirmed with fresh evidence.

## New findings (not present at 07-03 10:05 scan time)

### LOW

1. **[SUPPLY CHAIN]** `scripts/vps-bootstrap-oci.sh:137,139` and `vps-bootstrap.sh:121,123` — `claude.ai/install.sh` and `opencode.ai/install` fetched via `curl -fsSL ... | bash`, run as the unprivileged `hermes` user. Added in commit `7e8c5b8` (2026-07-03 10:12), 7 minutes after the last scan ran — not a miss, genuinely postdates it. Same risk class as the already-accepted `hermes-agent` installer finding (unprivileged blast radius, same pattern) — not re-architected in the 09-fafe6e fix pass since that pass targeted the *root*-run installers only.
   - Fix (optional, same remediation as already applied to NodeSource): pin to a released archive + checksum, or explicitly note as accepted risk alongside the existing hermes-agent installer note.

2. **[REPO HYGIENE]** No `.gitignore` file exists anywhere in the repo root. Not currently exploitable — zero real secrets tracked (verified: only tracked "env-shaped" file is `templates/compose/.env.langfuse.example`, all `CHANGE_ME` placeholders) — but nothing stops a future contributor from `git add`-ing a real `.env`/`credentials.json` by accident.
   - Fix: add a minimal `.gitignore` (`.env`, `.env.*` except `*.example`, `*.pem`, `*.key`, `node_modules/`, `__pycache__/`).

## Not re-flagged (already tracked elsewhere, not a repo-content gap)

- OAuth/CCS credential exfil via same-UID delegated sub-session, `sudo -u hermes` `secure_path` gotcha, `/opt` vs workspace clone drift — all live-host deployment state, already documented as accepted/tracked risk in `Phase 3/6 Security Considerations`, `part19-security-playbook.md`, and `.claude/agent-memory/code-reviewer/*.md`. The repo's own docs already state these accurately; nothing new to flag in the guide content itself.
- Today's session added `IPAddressDeny=169.254.169.254/32` to `templates/systemd/hermes.service` (commit `60a2683`) — closes a live IMDS/instance-principal SSRF path found on the deployed host. Net-positive since the 07-03 baseline, not a new finding.

## Summary

| Category | Critical | High | Medium | Low |
|----------|----------|------|--------|-----|
| Secrets | 0 | 0 | 0 | - |
| Deps | N/A | | | |
| Scripts/config (new since baseline) | 0 | 0 | 0 | 2 |

Clean secret scan (no API keys, private keys, or hardcoded credentials — same patterns as the 07-03 scan, re-run fresh). No `chmod 777`, no TLS-bypass flags, no `eval`/`exec`/`shell=True` in the 2 Python scripts, CI workflow uses `pull_request` (not `_target`), no secrets referenced in workflow.

## Recommendations

1. Add `.gitignore` (finding 2) — 5-minute fix, prevents a future real leak.
2. Optionally pin/checksum the `claude.ai`/`opencode.ai` installers (finding 1) — same treatment already given to NodeSource; low urgency (unprivileged user).

## Unresolved questions

None — both new findings are LOW and self-contained; no source-of-truth ambiguity like the 07-03 report's schema question (already resolved).
