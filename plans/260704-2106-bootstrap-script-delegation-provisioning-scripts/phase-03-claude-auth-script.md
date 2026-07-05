---
phase: 3
title: "Claude Auth Script"
status: in-progress
effort: "25m"
---

# Phase 3: Claude Auth Script

**Priority:** P2 · **Status:** pending · **Ownership:** `scripts/provision-hermes-delegation/1-claude-auth.sh` (new) ONLY · **Run order:** after `0-gh-auth.sh`

## Context Links

- Design: `plans/reports/from-brainstorm-to-planner-260704-2053-bootstrap-script-delegation-provisioning-design.md` §B.
- **Established risk analysis (cross-reference, do NOT re-derive):** `plans/260703-1738-fix-urgent-hermes-delegation-issues/phase-03-claude-auth-for-hermes.md` — its Security Considerations + Risk Assessment cover the OAuth-exfil accepted-risk and seat-ownership analysis in full.
- Target file the script writes: `/home/hermes/.hermes/.env` (`ANTHROPIC_API_KEY=`), scaffolded by `scripts/vps-bootstrap-oci.sh:178-194`.

## Overview

New numbered script that gives the hermes user a Claude Code credential the fully-scriptable way: write `ANTHROPIC_API_KEY=<key>` into hermes's `~/.hermes/.env`. This is the simplest `curl | sudo bash`-safe path. The real interactive OAuth (`claude auth login`, a dedicated subscription seat) needs a browser/loopback callback and CANNOT be scripted — it stays a DOCUMENTED MANUAL ALTERNATIVE in the script's header comment, not scripted (decision 1 + phase-03 of the related plan).

## Key Insights

- Two orthogonal credential mechanisms (per related phase-03): `ANTHROPIC_API_KEY` env (headless, direct billing, scriptable) vs `claude auth login` OAuth seat (browser, NOT scriptable). This script does the FORMER; documents the latter as manual.
- **API-key path has a SMALLER blast radius than a full OAuth seat.** A scoped, independently-revocable API key limits exposure to that key's spend/scope; a full OAuth account seat, if exfiltrated by a same-UID delegated sub-session (the accepted risk in related phase-03's Security Considerations), yields account-level impersonation. State this explicitly as a genuine advantage of the API-key default — it is not merely "the easy path", it is also the lower-blast-radius path.
- `.env` already exists post-bootstrap with an empty `ANTHROPIC_API_KEY=` line (`vps-bootstrap-oci.sh:181`), mode 600, hermes-owned. The script updates that line in place (or appends if absent), preserving mode 600.

## Requirements

- Functional: given `--api-key=<key>`, validate it (F14: `sk-ant-` prefix gate + non-fatal `claude -p` functional smoke), set `ANTHROPIC_API_KEY=<key>` in `/home/hermes/.hermes/.env` (update-in-place if the key exists, append if not); preserve `chmod 600` + hermes ownership.
- Non-functional: non-interactive, idempotent (re-running with a new key replaces the line, not duplicates), `die` if no key supplied.

## Architecture

Input: `--api-key=<key>` (required). Transform: rewrite the `ANTHROPIC_API_KEY=` line in `.env`. Exit: line present with the key; file still mode 600, hermes:hermes.

Data flow:
```
--api-key → (update-in-place) → /home/hermes/.hermes/.env  [ANTHROPIC_API_KEY=…]  → chmod 600, chown hermes:hermes → verify line present
```

In-place update: if `.env` missing, `die` with a hint to run bootstrap section 7 first (it scaffolds `.env`). Replace an existing `^ANTHROPIC_API_KEY=` line rather than blindly appending (avoids duplicate keys — last wins in most loaders but duplicates are a smell). Never echo the key to stdout.

Header MANUAL-ALTERNATIVE block: document the OAuth path (`sudo -u hermes -i bash -c 'claude auth login'`, or `claude setup-token` for a headless long-lived token) as the human-run alternative when a dedicated subscription seat is preferred over an API key — mirroring related phase-03's fallback chain. Note the browser/SSH-only caveat. (`bash -c` wrapper form per F12, consistent with the scripted invocations.)

## Related Code Files

- **Create:** `scripts/provision-hermes-delegation/1-claude-auth.sh`.
- **Reads/writes (host runtime, not repo):** `/home/hermes/.hermes/.env` — not a repo file; the script edits live host state.

## Implementation Steps

TDD shape (assert-fails → implement → assert-passes).

1. **Assert-fails (pre-change):** `sudo -u hermes -i bash -c 'grep -q "^ANTHROPIC_API_KEY=.\+" ~/.hermes/.env'` exits non-zero (the bootstrap-scaffolded line is empty). Record baseline.
2. **Implement:** write `1-claude-auth.sh`:
   - Header: purpose, usage (`--api-key=<key>`), the MANUAL OAuth alternative block (with the smaller-blast-radius note), idempotency note.
   - `set -euo pipefail`, `log()/warn()/die()`.
   - Arg loop parsing `--api-key=`; `die` if empty.
   - `ENV=/home/hermes/.hermes/.env`; `[ -f "$ENV" ] || die "run bootstrap section 7 first (scaffolds .env)"`.
   - **Validity gate (F14) — before writing:** reject a malformed key with `[[ "$KEY" =~ ^sk-ant- ]] || die "key doesn't look like an Anthropic key (expected sk-ant- prefix)"`. This is the cheap, deterministic parity check with Phase 4/5's smoke-test gate (a bare non-empty grep would pass a truncated/wrong-provider key that only fails at the human end-to-end test).
   - In-place: replace `^ANTHROPIC_API_KEY=.*` (e.g. via a temp-file rewrite, not `sed -i` on a key value with slashes — use a safe substitution), append if the key line is absent.
   - `chmod 600 "$ENV"; chown hermes:hermes "$ENV"`.
   - Verify (write landed): grep the non-empty key line → `die` on failure. Never print the key.
   - **Functional smoke (F14, non-fatal `warn`):** `sudo -u hermes -i bash -c 'export PATH="$HOME/.local/bin:$PATH"; claude -p "echo ok" --output-format json'` — surfaces a revoked/wrong-scope key here (not at the deferred `[HUMAN]` end-to-end test). `warn` (not `die`): `claude`'s key pickup may need more than `.env` alone, so a failure here is a signal, not a hard block. Mirrors the PATH-wrapped form the related plan's phase-03 established.
3. **Assert-passes (post-change):** step 1's grep now exits 0; `stat -c '%a %U' "$ENV"` == `600 hermes`.
4. **Idempotency check:** re-run with a different key → the single `ANTHROPIC_API_KEY=` line is replaced (not duplicated).

## Execution Status (2026-07-05)

`scripts/provision-hermes-delegation/1-claude-auth.sh` authored per spec (F14 `sk-ant-` validity gate, in-place `.env` rewrite via temp-file not `sed -i`, `chmod 600`/`chown`, non-fatal smoke test, manual-OAuth-alternative doc block), code-reviewed, `bash -n` clean, executable. NOT done: baseline capture and post-run verification against a real hermes host with a real Anthropic key.

## Success Criteria

- [ ] Baseline captured: pre-change `ANTHROPIC_API_KEY=` line is empty.
- [ ] Validity gate (F14): rejects a key without the `sk-ant-` prefix (`die`); runs the non-fatal `claude -p "echo ok"` functional smoke (`warn` on failure).
- [ ] Script sets a non-empty `ANTHROPIC_API_KEY=` in `.env`, in place (no duplicate lines).
- [ ] File remains mode 600, hermes:hermes.
- [ ] Header documents the manual OAuth alternative (not scripted) + the smaller-blast-radius rationale.
- [ ] `die`s cleanly if `--api-key` missing or `.env` absent.
- [ ] Re-run replaces rather than duplicates.

## Risk Assessment

| Risk | L×I | Mitigation |
|------|-----|------------|
| API key leaks via `ps`/history | M×M | Key passed as a flag lands in the CALLER's history — document using an env indirection / a here-doc, and that the on-disk `.env` is 600. STDIN not available for `--api-key` here; note the trade-off explicitly. |
| Duplicate `ANTHROPIC_API_KEY=` lines | L×L | In-place replace of the existing line, not blind append. |
| `.env` clobbered / mode widened | L×M | Rewrite only the one line; re-assert `chmod 600` + `chown` after write. |
| Operator expects OAuth seat, gets API key | L×M | Header documents the manual OAuth alternative prominently; this script is the API-key path by deliberate default (smaller blast radius). |

## Security Considerations

Cross-reference `plans/260703-1738-fix-urgent-hermes-delegation-issues/phase-03-claude-auth-for-hermes.md` Security Considerations for the full OAuth-exfil accepted-risk analysis — NOT re-derived here.

**Net-new point for this script:** the API-key default is the LOWER-blast-radius credential. A same-UID delegated sub-session can still read `.env` (same `hermes` UID, `Read,Bash` allowlist), so the key IS exfiltratable — but a scoped, independently-revocable API key bounds the damage to that key's spend/scope and can be rotated without touching a subscription account, whereas exfiltration of a full OAuth account seat yields account-level impersonation until manually revoked. The API-key path is therefore the safer default, not just the easier one. Key stored 600, hermes-owned. Rollback: blank the `ANTHROPIC_API_KEY=` line (or `1-claude-auth.sh --api-key=` guard-rejected → manual edit) and revoke the key in the Anthropic console.

**Argv exposure (F15):** `--api-key=` sits in this wrapper's own argv (`ps`/history) for the run's duration — see the canonical F15 note in `phase-02-gh-auth-script.md` → Security Considerations. Prefer env-indirection over an inline flag; this key is a live credential, not an installer input.

## Next Steps

Provides the Claude credential the delegated `claude -p` path needs. Independent file. The OAuth manual alternative, if chosen, is a `[HUMAN]` step outside this script.
