# Security Scan Report

**Project:** hermes-optimization-guide
**Scanned:** 2026-07-02
**Scope:** `scripts/` + `.github/scripts/`
**Files checked:** 2 (`scripts/vps-bootstrap.sh`, `.github/scripts/validate_skills.py`)

## Summary
| Category | Critical | High | Medium | Low |
|----------|----------|------|--------|-----|
| Secrets  | 0 | 0 | 0 | 0 |
| Deps     | n/a | n/a | n/a | n/a |
| Code     | 0 | 0 | 1 | 2 |

No dependency manifest in scope (no package.json/requirements.txt under scripts/) so no dep audit run.

## Findings

### MEDIUM
1. **[SUPPLY-CHAIN]** curl-pipe-to-bash, no checksum/signature verification — `scripts/vps-bootstrap.sh:54,97` (also documented usage at line 21)
   - `curl -fsSL https://deb.nodesource.com/setup_20.x | bash -` and `curl -sSL https://install.hermes.nous.ai | bash`
   - Script runs as root; a compromised/MITM'd remote script executes with root (nodesource case) or as the `hermes` user (install.hermes.nous.ai case, already privilege-reduced).
   - Fix: pin to a known script hash (`curl ... | tee installer.sh && sha256sum -c` or GPG-verify), or vendor the installer step.

### LOW
2. **[SUPPLY-CHAIN]** Caddy GPG key fetched via plain HTTPS curl, dearmored directly into keyring — `scripts/vps-bootstrap.sh:63-64`. Standard apt-repo bootstrap pattern (same approach used by Docker/Caddy's own docs); TLS is the only integrity guarantee. Acceptable but note as accepted risk, not upgraded further since it's added to `/usr/share/keyrings` (not directly `apt-key add`, so already following current best practice).
3. **[SUPPLY-CHAIN]** `git clone`/`git pull --ff-only` tracks `main` with no commit/tag pin — `scripts/vps-bootstrap.sh:86,89`. Re-running the bootstrap after a `main` compromise pulls unreviewed content into files later installed as root (`templates/systemd/*.service`, `templates/caddy/Caddyfile`). Low severity here since it's the project's own repo, but worth a comment for anyone forking.

## Good Practices Observed
- `.env` stub is written with blank values only, then `chmod 600` + `chown hermes:hermes` before any secret is filled in (`vps-bootstrap.sh:122-132`).
- Installs Hermes itself as the unprivileged `hermes` user, not root (`vps-bootstrap.sh:95-99`).
- UFW: allow rules for 22/80/443 are added *before* `ufw --force enable` — no SSH self-lockout risk.
- `validate_skills.py` uses `yaml.safe_load` (not `yaml.load`) — no unsafe deserialization.
- No hardcoded secrets, no `eval`/`os.system`/`subprocess` with unsanitized concatenation, no disabled TLS verification, no command/SQL/path-traversal injection patterns found in either file.

## Recommendations
1. Verify remote installers before piping to bash (checksum pin or fetch-then-inspect-then-run) for `nodesource` and `install.hermes.nous.ai` steps.
2. Optional: pin the guide repo clone to a tagged release instead of `main` for the "clone first, run locally" install path.

## Unresolved Questions
- None — scope was small enough to fully review both scripts inline (no sampling).
