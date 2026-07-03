# Security Scan Report

**Project:** hermes-optimization-guide (docs/guide repo, no package manager — no npm/pip audit applicable)
**Scanned:** 2026-07-03
**Files checked:** 122 markdown + 19 code/config files (yaml/yml/py/sh/service/html/Caddyfile)
**Mode:** `--auto --parallel` (3 parallel scan agents: secrets, script vuln patterns, config/infra review)

## Summary

| Category | Critical | High | Medium | Low |
|----------|----------|------|--------|-----|
| Secrets  | 0 | 0 | 0 | - |
| Deps     | N/A (no package.json/requirements.txt/go.mod/Cargo.toml) | | | |
| Scripts (py/sh/CI) | 0 | 0 | 2 | 3 |
| Config/infra (yaml/service/Caddyfile) | 0 | 2 | 1 | 1 |

## Findings

### HIGH

1. **[CONFIG DRIFT]** `security.*` block in `templates/config/production.yaml`, `security-hardened.yaml`, `telegram-bot.yaml` uses a schema (`approval.require_approval`, `denylist`, `approval_channel`, `bypass_subagents`, `mcp_servers.*.trust`, `profiles: {quarantine,trusted}`) that `part19-security-playbook.md:5` explicitly says **does not exist** in real Hermes Agent (real schema: top-level `approvals: {mode,timeout,...}`, no separate approval-channel config, no per-server MCP trust knob). If unknown keys are silently ignored, `security-hardened.yaml` ships **zero** of its advertised hardening.
   - Fix: reconcile — either part19 is stale (old schema still works) or all 3 templates need rewriting to the `approvals:`/`command_allowlist:` shape part19 documents. Needs a source-of-truth check against actual Hermes Agent, not resolvable from docs alone.

2. **[SECRET LEAK VIA SYNC]** `part21-remote-sandboxes.md` — 2 of 3 `sync.push: ~/.hermes` examples have **no `ignore:` list at all**, unlike the SSH `dev-box` example (lines 63-77, just fixed in commit `b7a4689` to exclude `.env`):
   - Modal `modal-big` (lines 110-126) — no `ignore:` block.
   - Daytona `workspace` (lines 158-170) — no `ignore:` block.
   - Both push `~/.hermes` verbatim, which would sync live provider API keys (`~/.hermes/.env`) to the remote sandbox host if followed as-shown. Same class of bug as the SSH example, not yet fixed here.
   - Fix: add the same `ignore: [.git, node_modules, __pycache__, "*.log", .env]` block + warning comment to both examples.

### MEDIUM

3. `scripts/vps-bootstrap.sh:54,66` / `scripts/vps-bootstrap-oci.sh:66` — NodeSource setup script and Caddy gpg key fetched via `curl -fsSL ... | bash`/pipe, run as root, no checksum/signature pin. Standard curl|bash pattern; if the upstream host/TLS is ever compromised → root RCE on the operator's box.
   - Fix: pin to known script hash, or fetch `.deb`/verify via signed apt repo (Caddy's gpg-key route is already the safer half of this).

4. `templates/caddy/Caddyfile:59-76` — comment claims webhook vhost is "rate-limited" but no rate-limit directive exists (stock Caddy has none; needs `caddy-ratelimit` plugin, not referenced anywhere in the repo). Misleading doc/config mismatch, not a live vuln (unenforced claim only).
   - Fix: add the plugin+directive, or drop the claim.

### LOW

5. `scripts/vps-bootstrap.sh:97` / `vps-bootstrap-oci.sh:112` — hermes-agent installer also via `curl|bash`, but runs as unprivileged `hermes` user (lower blast radius than root scripts above).
6. `.github/workflows/ci.yml:16` — `gaurav-nelson/github-action-markdown-link-check@v1` pinned by mutable tag, not commit SHA. Supply-chain hardening gap; low impact (no secrets/elevated `permissions:` in this workflow, public docs repo).
7. `templates/cron/production-crons.yaml` vs. the `cron:` block embedded in `production.yaml` — schedule times and `notify` channel (`telegram_private` vs `telegram_dm`) have drifted apart. Cosmetic inconsistency, not a vuln.

## Clean (verified, no action needed)

- **Secrets:** zero hardcoded credentials anywhere in 122 md + all config/code files. All key-shaped values are `${ENV_VAR}` interpolation, explicit `CHANGE_ME`/`REPLACE_WITH_*` placeholders, or a regex pattern literal inside a secrets-detection config block (`telegram-bot.yaml:69`, not a real key). Only tracked `.env`-named file is `templates/compose/.env.langfuse.example` (all `CHANGE_ME` values, correctly named `.example`).
- `.github/scripts/validate_skills.py` / `test_validate_skills.py` — `yaml.safe_load`, no `eval`/`exec`/`subprocess`/`shell=True`, fixed paths only.
- `docs/wizard/index.html` — no XSS; dynamic output via `.textContent`/`Blob` download, never `innerHTML`/`eval`.
- `.github/workflows/ci.yml` — uses `pull_request` (not `pull_request_target`), no PR-controlled data interpolated into `run:` steps, no secrets referenced.
- File permissions — no `chmod 777`/world-writable anywhere; `.env` correctly locked `600` in both bootstrap scripts; systemd units non-root, `ProtectSystem=strict`, `NoNewPrivileges`, empty `CapabilityBoundingSet`, dashboard bound `127.0.0.1` only.
- `templates/compose/langfuse-stack.yml` — non-root services, no `privileged`/`docker.sock`/host-root mounts, ports bound `127.0.0.1` only.
- Caddyfile basicauth hash / TLS / HSTS — placeholder hash as expected for a template, TLS auto, security headers present.

## Recommendations

1. **Priority fix:** add `ignore: [.env, ...]` to the Modal and Daytona sandbox examples in `part21-remote-sandboxes.md` (finding #2) — same fix pattern already applied to the SSH example in the just-pushed commit `b7a4689`, trivial follow-up.
2. **Needs a decision, not just a docs edit:** reconcile `security.*` template schema vs. `part19-security-playbook.md`'s "none of those keys exist" note (finding #1) — determine against real Hermes Agent behavior which side is stale before editing either.
3. Pin `scripts/vps-bootstrap*.sh` root-run curl|bash steps to a hash/signature, or note the accepted risk explicitly in the script comments.
4. Either implement or remove the Caddyfile "rate-limited" claim.
5. Pin the third-party GitHub Action in `ci.yml` to a commit SHA.
6. Reconcile `templates/cron/production-crons.yaml` schedule/notify-channel drift against `production.yaml`'s embedded `cron:` block (pick one source of truth).

## Unresolved Questions

1. Is the `security.*` block schema (`approval.*`, `mcp_servers.*.trust`, `profiles:`) in `templates/config/*.yaml` actually still supported by current Hermes Agent, or is `part19-security-playbook.md`'s "None of those exist" note correct and the 3 templates are stale? Cannot resolve from docs alone — needs a check against Hermes Agent source/maintainer.
2. Is `security.webhook.{require_signature,max_body_bytes,ttl_seconds}` (seen in the same templates) a real, currently-supported key, or the same class of stale key as the rest of `security.*`?
