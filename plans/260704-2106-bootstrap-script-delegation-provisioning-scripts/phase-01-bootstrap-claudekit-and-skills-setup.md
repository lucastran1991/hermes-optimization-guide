---
phase: 1
title: "Bootstrap ClaudeKit And Skills Setup"
status: in-progress
effort: "30m"
---

# Phase 1: Bootstrap ClaudeKit And Skills Setup

**Priority:** P2 · **Status:** pending · **Ownership:** `scripts/vps-bootstrap-oci.sh` + `templates/systemd/hermes.service` · **Run order:** FIRST (blocks all verification in this plan — see Step 0)

## Context Links

- Design: `plans/reports/from-brainstorm-to-planner-260704-2053-bootstrap-script-delegation-provisioning-design.md` §A.
- Pattern to mirror: `scripts/vps-bootstrap-oci.sh:123-155` (section 6b — existing unconditional `sudo -u hermes bash -c '…'` coding-agent CLI install).
- **Root-cause report for Step 0 (PATH fix):** `plans/reports/ck-debug-260704-1355-hermes-ccs-auth-profile-access-report.md` — root-causes that `hermes.service` runs on the default systemd PATH with no `~/.local/bin`, so every delegated bare-name CLI call fails `command not found` (exit 127).
- Related manual plan: `plans/260703-1738-fix-urgent-hermes-delegation-issues/phase-04-install-ccs-and-claudekit.md`.

## Overview

Add ClaudeKit + skills-venv provisioning to the OCI bootstrap so a fresh host lands with `ck` installed and skills' Python deps ready — instead of the operator doing it by hand (as happened today). Two new UNCONDITIONAL sections, no flags, auto-run — matching section 6b's existing "install all coding-agent CLIs unconditionally" pattern (decision 4).

**This phase now also carries the PATH fix (Step 0) and is ordered FIRST.** The same-day debug report root-caused that `hermes.service` runs on the default systemd PATH (no `~/.local/bin`), so EVERY delegated `ccs`/`claude`/`ck` call from the REAL sandboxed service fails `command not found` (exit 127) — regardless of every credential Phases 2–6 provision. Every phase's smoke test in this plan uses `sudo -u hermes -i` (a login shell that sources `.bashrc`, which prepends `~/.local/bin`), which MASKS the bug: the smoke tests pass while the service still fails. Nothing else in this plan is verifiable against the real sandboxed PATH until Step 0 lands, so it must go first.

Two files are touched: `scripts/vps-bootstrap-oci.sh` (sections 6c/6d) and `templates/systemd/hermes.service` (Step 0, the `Environment=PATH=` line). `scripts/vps-bootstrap.sh` (generic non-OCI) is OUT of scope (decision 2).

## Key Insights

- `--install-skills` GOTCHA (lived through today): `ck init --global … --install-skills` exits 0 but silently produces an EMPTY `~/.claude/skills/` if hermes has no `gh auth` configured yet. Must detect (`[ -z "$(ls -A ~/.claude/skills 2>/dev/null)" ]`) and `warn`, not falsely claim success.
- CWD GOTCHA (confirmed live today): `skills/install.sh -y` MUST run via `sudo -u hermes -i bash -c '…'`. The `-i` (login shell) is required — a bare `sudo -u hermes bash -c` does NOT chdir to hermes's home, so `install.sh`/`ck` try to write into the CALLER's cwd → EACCES.
- Bootstrap ordering: section 6b installs `ccs`, but `ck` (ClaudeKit) is separate — ClaudeKit is what grants the actual CK harness; routing through CCS alone does not (see `production.yaml` `ccs_profile` comment). 6c/6d slot in AFTER 6b (CLIs present) and BEFORE 7 (skill symlinks).

## Requirements

- Functional: after bootstrap, `sudo -u hermes -i bash -c 'ck doctor'` shows `[PASS] Global CK`; skills venv exists (`~/.claude/skills/.venv/`).
- Non-functional: unconditional (no new flags), idempotent/re-runnable (guard with `command -v ck` / venv-exists checks), non-fatal on failure (warn + continue, matching 6b's `|| warn`).

## Architecture

Data flow: bootstrap runs as root → drops privileges to hermes via `sudo -u hermes` for every install (ClaudeKit + skills are per-user state under `/home/hermes/.claude/`) → warnings surface to bootstrap stdout, never abort the run.

New section 6c (ClaudeKit):
- `sudo -u hermes bash -c 'export PATH="$HOME/.local/bin:$PATH"; command -v ck || npm install -g --prefix "$HOME/.local" claudekit-cli'` (PATH export mirrors 6b `:140` — without it the `command -v ck` guard mis-fires on re-run, F10).
- `sudo -u hermes -i bash -c 'ck init --global --kit engineer --yes --install-skills --skip-setup'`
- empty-skills detection → `warn` with the EXACT recovery sequence (F5): run `bash scripts/provision-hermes-delegation/0-gh-auth.sh --token=<PAT>`, THEN re-run `sudo -u hermes -i ck init --global --kit engineer --yes --install-skills --skip-setup`. Not a vague "re-run ck init" pointer.

New section 6d (skills venv):
- `sudo -u hermes -i bash -c '[ -x "$HOME/.claude/skills/install.sh" ] && "$HOME/.claude/skills/install.sh" -y'` (login shell → correct cwd).

## Related Code Files

- **Modify (Step 0, do first):** `templates/systemd/hermes.service` — add the `Environment=PATH=/home/hermes/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin` line to the `[Service]` Environment block (after `EnvironmentFile=` so it wins over a stale `.env`), AND widen `ReadWritePaths=` to add `/home/hermes/.claude` (F11, fix-now per Validation Session 1). Needs live deploy via the existing `scripts/deploy-systemd-units.sh` (do NOT hand-edit the live unit; that tool syncs template→`/etc/systemd/system/` + `daemon-reload` + restart-if-changed) — check for in-flight activity and announce before restart.
- **Modify:** `scripts/vps-bootstrap-oci.sh` — insert sections 6c + 6d between existing section 6b (`:155`) and section 7 (`:157`).

## Implementation Steps

TDD shape (bash-adapted: assert-absent → implement → assert-present).

0. **Step 0 — PATH fix (DO FIRST, blocks everything else in this plan).** Root cause: `hermes.service` runs on the default systemd PATH with no `~/.local/bin`, so bare-name `ccs`/`claude`/`ck` calls from the sandboxed service fail exit 127 (`ck-debug-260704-1355...report.md:9-21`). Fix:
   - **Assert-fails (real-sandbox reproduction, NOT `-i`):** `sudo -u hermes env -i HOME=/home/hermes PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin ccs api list` → `command not found` (exit 127). This mirrors the service's real PATH; do NOT use `sudo -u hermes -i` (it sources `.bashrc` and masks the bug).
   - **Implement:** add `Environment=PATH=/home/hermes/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin` to `templates/systemd/hermes.service`'s `[Service]` block, placed AFTER `EnvironmentFile=-/home/hermes/.hermes/.env` so it authoritatively overrides any stale/absent `.env` PATH. (The `.env` scaffold at `vps-bootstrap-oci.sh:187-190` also sets PATH, but only for freshly-scaffolded `.env` files — an already-provisioned host whose `.env` predates that scaffold gets no PATH from EnvironmentFile; the unit-level value is the EnvironmentFile-independent guarantee that also repairs existing hosts.)
   - **<!-- Updated: Validation Session 1 - fix EROFS now, same Step 0 pass -->** Also widen `ReadWritePaths=` on the same line to add `/home/hermes/.claude` (F11, user explicitly chose fix-now over defer): `ReadWritePaths=/home/hermes/.hermes /home/hermes/.ccs /home/hermes/.claude /tmp`.
   - **<!-- Updated: Validation Session 1 - explicit restart discipline --> Pre-deploy safety check (mirrors the discipline already used twice today for this exact file's IMDS/seccomp fixes):** before deploying, check for in-flight activity (`journalctl -u hermes --since "5 minutes ago"` — look for an active delegated task) and announce the restart before running it. Downtime is best-case ~2-5s, worst-case ~90s if a restart lands mid-tool-call (no `TimeoutStopSec=` override on this unit).
   - **Deploy:** on the live host, `bash scripts/deploy-systemd-units.sh` (existing tool — syncs template → `/etc/systemd/system/hermes.service` + `daemon-reload` + restart-if-changed). Do NOT reinvent or hand-edit the live unit.
   - **Assert-passes:** re-run the `env -i … ccs api list` reproduction → now exits 0 (systemd unit PATH baked in). Also verify: `sudo -u hermes env -i HOME=/home/hermes PATH=<systemd-default> touch ~/.claude/.write-test && rm ~/.claude/.write-test` now succeeds (was `EROFS` pre-widen). Only after both does any Phase 2–6 smoke test verify against the real sandboxed environment.
1. **Assert-fails (pre-change, already true — confirmed live):** `sudo -u hermes -i bash -c 'ck --version'` prints "No ClaudeKit installation found" (or `ck: command not found`). Record this as the failing baseline.
2. **Implement 6c:** add the ClaudeKit section — section-comment banner matching the repo convention (`# ---…`, `# 6c. ClaudeKit (as hermes user)`, `# ---…`). The `sudo -u hermes bash -c '…'` block MUST `export PATH="$HOME/.local/bin:$PATH"` as its first line, exactly like section 6b (`vps-bootstrap-oci.sh:140`) — otherwise the non-login `bash -c` never sees `~/.local/bin` and the `command -v ck` idempotency guard returns false on every re-run, re-installing `ck` each time (F10). Then: `command -v ck || npm install -g --prefix "$HOME/.local" claudekit-cli`, then `ck init --global --kit engineer --yes --install-skills --skip-setup` via `sudo -u hermes -i`. Add empty-skills detection + `warn` (reuse the script's existing `warn()` helper) — the warn message MUST give the exact recovery command sequence, not a vague pointer: `"skills empty — run: bash scripts/provision-hermes-delegation/0-gh-auth.sh --token=<PAT>  then re-run:  sudo -u hermes -i ck init --global --kit engineer --yes --install-skills --skip-setup"` (F5).
3. **Implement 6d:** add the skills-venv section — banner, guard (skip if `.venv` already present), run `install.sh -y` via `sudo -u hermes -i bash -c '…'`. Wrap with `|| warn '…'` (non-fatal, matches 6b).
4. **Assert-passes (post-change):** on a host after running the amended bootstrap, `sudo -u hermes -i bash -c 'ck doctor'` shows `[PASS] Global CK`; `[ -d /home/hermes/.claude/skills/.venv ]` is true. If `gh auth` not yet done, the 6c empty-skills warn fires as designed (not a failure).
5. **Idempotency check:** re-run the whole bootstrap — 6c/6d skip cleanly via their guards (no reinstall, no error).

## Execution Status (2026-07-05)

File-authoring done, code-reviewed, `bash -n` clean: `ReadWritePaths=` widened with `/home/hermes/.claude` in `templates/systemd/hermes.service` (PATH line was already in from a prior session); sections 6c/6d inserted into `scripts/vps-bootstrap-oci.sh` between 6b and 7, matching the existing banner/idempotency/non-fatal-warn style. NOT done (human-gated, needs a live host): the pre-deploy in-flight check, `deploy-systemd-units.sh` run, service restart, and every live assert-passes/baseline check below that requires executing against the real hermes host.

## Success Criteria

- [ ] **Step 0 (PATH + RWPaths fix, first):** `Environment=PATH=…` added AND `ReadWritePaths=` widened with `/home/hermes/.claude` (F11) in `templates/systemd/hermes.service`; in-flight check done, restart announced; deployed via `deploy-systemd-units.sh`; `sudo -u hermes env -i HOME=/home/hermes PATH=<systemd-default> ccs api list` now exits 0 (was exit 127); a write test under `~/.claude` (systemd-default env) now succeeds (was `EROFS`).
- [ ] Baseline captured: pre-change `ck --version` = "No ClaudeKit installation found".
- [ ] Section 6c added: `ck` installed for hermes + `ck init` run, unconditional, no new flag.
- [ ] Empty-skills detection fires a `warn` (not silent success) when `~/.claude/skills` is empty post-init.
- [ ] Section 6d added: `install.sh -y` via `sudo -u hermes -i` (login shell, correct cwd).
- [ ] Post-change: `ck doctor` = `[PASS] Global CK`; skills `.venv` exists.
- [ ] Re-running bootstrap is a clean no-op (idempotent guards hold).

## Risk Assessment

| Risk | L×I | Mitigation |
|------|-----|------------|
| `--install-skills` silently empties `~/.claude/skills` (no gh auth) | H×M | Explicit detection + `warn` pointing at `0-gh-auth.sh` and manual `ck init --global --install-skills` re-run — never claim false success. |
| `install.sh` EACCES from wrong cwd | H×M | Use `sudo -u hermes -i` (login shell) — confirmed fix today; never bare `sudo -u hermes bash -c`. |
| npm/`ck init` network failure aborts bootstrap | M×M | Wrap in `|| warn`, non-fatal — mirrors 6b's `|| warn` (delegation tiers degrade, host still boots). |
| Double-run reinstalls / errors | L×L | `command -v ck` and `.venv`-exists guards make both sections idempotent. |
| `~/.claude` writes hit `EROFS` at real delegation runtime (F11) | M×M→L×L | **<!-- Updated: Validation Session 1 - fix now, not deferred -->** User explicitly chose to fix now over deferring (against the red-team's own "don't widen RWPaths" default recommendation) — add `/home/hermes/.claude` to `templates/systemd/hermes.service`'s `ReadWritePaths=` line (same Step 0 edit pass as the PATH fix, same file, same deploy). This is a deliberate, acknowledged reversal of the repo's general "don't widen RWPaths" posture for THIS specific, now-confirmed gap (ClaudeKit itself is being freshly installed by this very phase, unlike the still-open `~/.npm` EROFS gap elsewhere, which stays deferred). Do not read this as license to widen RWPaths elsewhere without the same explicit user confirmation. |

## Next Steps

**Ordered FIRST.** Step 0 (PATH fix) is a hard prerequisite for verifying every other phase against the real sandboxed PATH — until it lands, all Phase 2–6 smoke tests give false positives (the `sudo -u hermes -i` login shell masks the exit-127 bug). The 6c/6d ClaudeKit work is standalone; its empty-skills warn hands off to Phase 2 (`0-gh-auth.sh`) as the documented remediation for the gh-auth-missing case.
