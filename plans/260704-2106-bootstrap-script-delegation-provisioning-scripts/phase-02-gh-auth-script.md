---
phase: 2
title: "GH Auth Script"
status: in-progress
effort: "25m"
---

# Phase 2: GH Auth Script

**Priority:** P2 · **Status:** pending · **Ownership:** `scripts/provision-hermes-delegation/0-gh-auth.sh` (new) ONLY · **Run order:** normally first among the numbered scripts, after bootstrap

## Context Links

- Design: `plans/reports/from-brainstorm-to-planner-260704-2053-bootstrap-script-delegation-provisioning-design.md` §B.
- Style to mirror: `scripts/deploy-systemd-units.sh` (`set -euo pipefail`, `log()`/`warn()`/`die()`, `--force`-style arg loop, header comment block).
- Why it matters: Phase 1's 6c empty-skills warn points here — `ck init --install-skills` needs hermes's `gh auth` configured to actually fetch skills.

## Overview

New numbered script that authenticates `gh` for the hermes user non-interactively. This unblocks `ck init --install-skills` (Phase 1's known empty-skills gotcha) and any skill that shells out to `gh`. Flag/env gated, `curl | sudo bash`-safe (decision 1).

## Key Insights

- **`gh` is NOT installed by the bootstrap (F4).** `vps-bootstrap-oci.sh`'s apt list (`:58-61`) and section 6b CLI installs (`:124-155`) never install `gh` — a genuinely fresh host (the exact case this plan serves) hits `gh: command not found`. This script MUST install `gh` idempotently before authing, via the repo's established keyring+apt pattern (mirror the NodeSource block at `vps-bootstrap-oci.sh:68-74`): `command -v gh ||` { fetch `https://cli.github.com/packages/githubcli-archive-keyring.gpg` → `/usr/share/keyrings/`, add a `signed-by=` entry to `/etc/apt/sources.list.d/github-cli.list`, `apt-get update`, `apt-get install -y gh` }. Runs as root (before dropping to hermes for auth).
- VERIFIED syntax (`gh auth login --help`): `--with-token` reads the token from STDIN → `echo "$TOKEN" | gh auth login --hostname github.com --with-token`. Minimum scopes: `repo`, `read:org`, `gist`.
- `GH_TOKEN` env var is honored automatically by `gh` for headless use — a valid alternative to `--with-token` (document both).
- Must run AS hermes (`sudo -u hermes -i bash -c '<cmd>'`) — auth state is per-user under `/home/hermes/.config/gh/`. Use the `bash -c '<cmd>'` wrapper form, NOT bare `sudo -u hermes -i gh …` (F12 — this project has twice confirmed the bare-binary form has PATH/quoting gotchas the `bash -c` form avoids).

## Requirements

- Functional: install `gh` idempotently if absent (F4), then, given a PAT via `--token=<PAT>` or `$GH_TOKEN`, authenticate `gh` for hermes; verify via `gh auth status`.
- Non-functional: non-interactive only (no prompts), idempotent (re-auth is safe / no-op if already valid), `die` clearly if no token supplied.

## Architecture

Input: `--token=<PAT>` flag OR `$GH_TOKEN` env (flag wins if both). Transform: pipe token to `gh auth login --with-token` as hermes. Exit: `gh auth status` for hermes exits 0.

Data flow:
```
(root) command -v gh || install gh via cli.github.com keyring+apt (idempotent)
--token / $GH_TOKEN → (stdin) → sudo -u hermes -i bash -c 'gh auth login --hostname github.com --with-token' → ~hermes/.config/gh/hosts.yml → sudo -u hermes -i bash -c 'gh auth status' (verify)
```

Arg loop (mirror `deploy-systemd-units.sh:30-36`): parse `--token=…`; `die "Unknown argument"` on anything else. If neither flag nor `$GH_TOKEN` set → `die` with a usage hint (never prompt).

## Related Code Files

- **Create:** `scripts/provision-hermes-delegation/0-gh-auth.sh`.

## Implementation Steps

TDD shape (assert-fails → implement → assert-passes).

1. **Assert-fails (pre-change):** `sudo -u hermes -i bash -c 'gh auth status'` exits non-zero ("not logged in") on a fresh host. Record baseline.
2. **Implement:** write `0-gh-auth.sh`:
   - Header comment: purpose (gh auth for hermes), usage (`--token=<PAT>` or `GH_TOKEN=… bash 0-gh-auth.sh`), required scopes (`repo`, `read:org`, `gist`), idempotency note.
   - `set -euo pipefail`, `log()/warn()/die()` helpers.
   - **Install gh idempotently (F4), as root, BEFORE auth:** `command -v gh ||` { `curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg`; `chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg`; `echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list`; `apt-get update -qq`; `apt-get install -y -qq gh` }. Mirrors the NodeSource keyring block (`vps-bootstrap-oci.sh:68-74`).
   - Arg loop parsing `--token=`; resolve `TOKEN="${TOKEN:-${GH_TOKEN:-}}"`; `[ -n "$TOKEN" ] || die "supply --token=<PAT> or set GH_TOKEN"`.
   - `printf '%s' "$TOKEN" | sudo -u hermes -i bash -c 'gh auth login --hostname github.com --with-token'` (F12 — `bash -c` wrapper, not bare `-i gh …`).
   - Verify: `sudo -u hermes -i bash -c 'gh auth status'` → `die` on failure.
3. **Assert-passes (post-change):** re-run step 1's command → now exits 0, shows the authenticated account + scopes.
4. **Idempotency check:** re-run the script with the same token → succeeds (gh overwrites/refreshes the host entry cleanly).

## Execution Status (2026-07-05)

`scripts/provision-hermes-delegation/0-gh-auth.sh` authored per spec (idempotent gh install, `--token=`/`$GH_TOKEN` arg handling, `bash -c` wrapper form, F15 note), code-reviewed, `bash -n` clean, executable. NOT done: baseline capture and post-run verification against a real hermes host with a real PAT — inherently a human/operator action.

## Success Criteria

- [ ] `gh` installed idempotently if absent (`command -v gh` guard; keyring+apt mirror of NodeSource block).
- [ ] Baseline captured: pre-change `gh auth status` (as hermes) exits non-zero.
- [ ] Script accepts `--token=` and `$GH_TOKEN`; `die`s with usage if neither present.
- [ ] Runs `gh auth login --with-token` as hermes (no interactive prompt path).
- [ ] Post-change: `gh auth status` (as hermes) exits 0.
- [ ] Re-run is safe (idempotent).

## Risk Assessment

| Risk | L×I | Mitigation |
|------|-----|------------|
| Token leaks via `ps`/shell history | M×M | Two distinct surfaces: (1) `gh`'s own argv — closed by STDIN `--with-token`; (2) the WRAPPER's `--token=` argv — NOT closed by STDIN, only by env-indirection (`GH_TOKEN=… bash …`). See the canonical F15 note below; prefer `$GH_TOKEN` env for the fully-headless path, never inline the PAT. |
| Over-scoped PAT | L×M | Document the MINIMUM scopes (`repo`, `read:org`, `gist`); recommend a fine-grained/expiring token. |
| No token supplied → silent partial state | L×M | `die` early with a usage hint — never prompt, never proceed. |
| Wrong user (auth as root/ubuntu) | L×M | Every `gh` call wrapped in `sudo -u hermes -i` — auth state must land under hermes's home. |

## Security Considerations

The PAT grants repo access for the bot identity. Prefer a fine-grained, expiring, minimally-scoped token dedicated to the bot (not the operator's long-lived classic PAT). STDIN delivery to `gh` avoids `ps`/history exposure of the token *inside gh's own argv*; `$GH_TOKEN` env is the cleanest headless path. Rollback: `sudo -u hermes -i bash -c 'gh auth logout'` clears the credential; revoke the PAT in GitHub settings.

**Canonical argv-exposure note (F15 — cross-referenced by Phases 3, 4, 5).** Every wrapper script in this directory that takes a live credential as a flag (`0-gh-auth.sh --token=`, `1-claude-auth.sh --api-key=`, `2-ccs-profile.sh --api-key=`) exposes that credential in ITS OWN process argv — visible via `ps aux` / `/proc/<pid>/cmdline` to any same-host process for the invocation's whole runtime — and in the invoking shell's history if typed inline. This is the SAME trade-off the repo already accepts for the `--api-key` CLI form of the coding-agent CLIs, but the blast radius is now higher: these flags carry a LIVE working credential (PAT / provider API key), not just an installer input. Accepted, but state it explicitly: prefer the env-indirection paths (`GH_TOKEN=$(cat file) bash …`, or sourcing a `600` env file) over inline flags, and never run these in a shell whose history is shared/persisted. `gh`'s STDIN path removes the token from `gh`'s argv but NOT from the wrapper's argv — only env-indirection at the wrapper level closes that window.

## Next Steps

Unblocks Phase 1's `ck init --install-skills` (re-run it after this) and any `gh`-dependent skill. Independent file — no phase blocks on it.
