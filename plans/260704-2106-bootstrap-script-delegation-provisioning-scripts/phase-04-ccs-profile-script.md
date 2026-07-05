---
phase: 4
title: "CCS Profile Script"
status: in-progress
effort: "30m"
---

# Phase 4: CCS Profile Script

**Priority:** P2 · **Status:** pending · **Ownership:** `scripts/provision-hermes-delegation/2-ccs-profile.sh` (new) ONLY · **Run order:** after `1-claude-auth.sh`; alternative to Phase 5's bridge

## Context Links

- Design: `plans/reports/from-brainstorm-to-planner-260704-2053-bootstrap-script-delegation-provisioning-design.md` §B.
- **Established risk analysis (cross-reference, do NOT re-derive):** `plans/260703-1738-fix-urgent-hermes-delegation-issues/phase-05-provision-ccs-profile.md` — full CCS-profile Security/Risk analysis (fresh-dedicated-credential, never-reuse-ubuntu's, smoke-test gate).
- Wired config value: `templates/config/production.yaml` `delegation.ccs_profile: ccs-hermes` — the name this script hardcodes to.

## Overview

New numbered script that provisions the hermes-dedicated CCS API profile the delegation config points at (`ccs-hermes`), non-interactively, then passes the mandatory smoke-test gate. This is the DEDICATED-credential path (a real, separate key/quota/audit trail for the bot) — contrast Phase 5's internal-fork-only credential-reuse bridge. Pick ONE of Phase 4 / Phase 5 per host.

## Key Insights

- Syntax (the form the sibling plan actually verified live — `plans/260703-1738-.../research/live-host-verification-findings.md:34-37`): `ccs api create <name> --preset <preset-id> --api-key <key> --target <claude|droid|codex> --yes`. Valid presets include `anthropic`, `glm`, `km`, `openrouter`, `deepseek`, `qwen`, more. Rollback/cleanup: `ccs api remove <name>`. Verify: `ccs api list`.
- **`--force` is NOT verified (F8).** No `ccs api create --help` transcript in this repo's plan history documents a `--force` flag or its overwrite semantics — the only actually-verified idempotency mechanism is `ccs api remove <name>` then `ccs api create …`. Do NOT rely on `--force`. Idempotency = remove-if-exists then create (see Architecture). If a later live `--help` check confirms `--force`, it can be adopted then — until then it is unverified and unused.
- **Name hardcoded to `ccs-hermes`** — no flag needed. It matches `production.yaml`'s existing `delegation.ccs_profile: ccs-hermes`, so no config edit is required (DRY — same reasoning as related phase-05's "recommend `ccs-hermes`, no `:193` edit"). The script accepts a `--preset=` PASSTHROUGH (don't hardcode a preset — providers differ) and `--api-key=`.
- Non-interactive `--api-key --yes` form is the documented EMERGENCY/scriptable form. It leaks the key via `ps`/history — this is the accepted, explicitly-acknowledged trade-off for a `curl | sudo bash`-safe script (decision 1). Note it loudly; the interactive wizard (safer but browser/prompt-bound) is NOT scriptable and stays the manual alternative.
- Runs AS hermes; state lands under `/home/hermes/.ccs/`. Smoke-test gate is MANDATORY — `harness: ccs` is unusable until it passes; there is NO auto-fallback to `bare`.

## Requirements

- Functional: given `--preset=<id> --api-key=<key>` (both required), run `ccs api create ccs-hermes --preset <p> --api-key <key> --target claude --yes` as hermes; then the smoke test `ccs ccs-hermes -p "echo ok" --output-format json` MUST exit 0.
- Non-functional: non-interactive, idempotent via verified `ccs api remove ccs-hermes` (ignore-if-absent) THEN create (F8 — not `--force`, which is unverified), `die` if either flag missing OR smoke-test fails.

## Architecture

Input: `--preset=<id>`, `--api-key=<key>` (both required). Transform: `ccs api create` as hermes. Gate: smoke-test exit 0.

Data flow:
```
--preset,--api-key → sudo -u hermes -i bash -c 'ccs api remove ccs-hermes 2>/dev/null || true'   (idempotent reset, ignore-if-absent)
                   → sudo -u hermes -i bash -c 'ccs api create ccs-hermes --preset … --api-key … --target claude --yes'
                   → ~hermes/.ccs/ (profile state)
                   → smoke test: sudo -u hermes -i bash -c 'ccs ccs-hermes -p "echo ok" --output-format json'  (must exit 0)
```

Arg loop parses `--preset=` + `--api-key=`; `die` if either empty. Name is a constant `ccs-hermes` (matches production.yaml — DRY, no name flag). Idempotency (F8): `ccs api remove ccs-hermes` (ignore failure if absent) THEN `ccs api create …` — the verified sequence, NOT the unverified `--force`. All `ccs` calls use the `sudo -u hermes -i bash -c '<cmd>'` wrapper form (F12), never bare `-i ccs …`. Never echo the key.

## Related Code Files

- **Create:** `scripts/provision-hermes-delegation/2-ccs-profile.sh`.
- **No repo config edit** — `production.yaml` already says `ccs-hermes` (DRY).

## Implementation Steps

TDD shape (assert-fails → implement → assert-passes).

1. **Assert-fails (pre-change):** `sudo -u hermes -i bash -c 'ccs api list' | grep -q ccs-hermes` exits non-zero (no profile yet). Record baseline.
2. **Implement:** write `2-ccs-profile.sh`:
   - Header: purpose (dedicated CCS profile for hermes), usage (`--preset=<id> --api-key=<key>`), the `ps`/history leak acknowledgement, idempotency note, name-is-hardcoded rationale.
   - `set -euo pipefail`, `log()/warn()/die()`.
   - Arg loop: `--preset=`, `--api-key=`; `die` if either empty.
   - Idempotent reset (F8): `sudo -u hermes -i bash -c 'ccs api remove ccs-hermes' 2>/dev/null || true`.
   - `sudo -u hermes -i bash -c 'ccs api create ccs-hermes --preset "'"$PRESET"'" --api-key "'"$KEY"'" --target claude --yes'` (F12 — `bash -c` wrapper; no unverified `--force`).
   - Smoke-test gate: `sudo -u hermes -i bash -c 'ccs ccs-hermes -p "echo ok" --output-format json'` → `die "smoke-test failed — harness: ccs not usable; check credential/preset"` on non-zero.
3. **Assert-passes (post-change):** step 1's grep now finds `ccs-hermes`; the smoke test exits 0 with valid JSON.
4. **Idempotency check:** re-run with the same flags → `ccs api remove` clears the prior profile, `ccs api create` recreates it cleanly, smoke test still passes.
5. **Rollback verify:** `ccs api remove ccs-hermes` removes it; smoke test then fails (expected) — confirms clean teardown.

## Execution Status (2026-07-05)

`scripts/provision-hermes-delegation/2-ccs-profile.sh` authored per spec (F8 remove-then-create idempotency, F12 wrapper form, mandatory smoke-test gate), code-reviewed, `bash -n` clean, executable. **Code review caught a shell-command-injection bug** (not one of the plan's own F1-F15 findings): `--preset`/`--api-key` were originally string-concatenated into the `bash -c` source, letting a value containing a quote or `$(...)` execute arbitrary code as hermes when the inner shell re-parsed it. Fixed same-session via env-var indirection (`env CCS_PRESET=... CCS_API_KEY=... bash -c '... "$CCS_PRESET" ...'`); closure verified live with a harmless PoC (`touch`-based) confirming the injection no longer fires. NOT done: baseline capture and post-run smoke test against a real hermes host with a real preset/key.

## Success Criteria

- [ ] Baseline captured: pre-change `ccs api list` has no `ccs-hermes`.
- [ ] Script requires `--preset=` + `--api-key=`; `die`s if either missing.
- [ ] Creates `ccs-hermes` (name hardcoded — matches production.yaml, no config edit).
- [ ] Smoke-test gate runs and `die`s on failure (no false success).
- [ ] Post-change: `ccs ccs-hermes -p "echo ok" --output-format json` exits 0.
- [ ] Re-run idempotent via `ccs api remove` + recreate (NOT `--force`); `ccs api remove ccs-hermes` cleanly rolls back.

## Risk Assessment

| Risk | L×I | Mitigation |
|------|-----|------------|
| Key leak via `--api-key`/`ps`/history | M×H | Explicitly acknowledged trade-off of the scriptable form; document env-indirection for the key; on-disk `.ccs` state is hermes-owned. Wizard (no leak) noted as the manual alternative. |
| Reusing operator's CCS identity | L×H | This script CREATES a fresh dedicated profile — it never touches `/home/ubuntu/.ccs/` (cross-ref related phase-05 §7). Phase 5's bridge is the deliberate-reuse path, walled off separately. |
| Smoke-test fails (bad key/preset, state not persisting) | M×H | Gate `die`s — never claims success. Debug DAC/ownership of `~/.ccs` first (plain-shell, not sandboxed — per related phase-05 Finding 18), then key/preset validity. |
| Preset mismatches the key's provider | M×M | `--preset` is a required passthrough — operator picks the one matching the dedicated key. |
| Re-run duplicates/corrupts profile | L×M | Verified `ccs api remove ccs-hermes` (ignore-if-absent) THEN `ccs api create` — the confirmed idempotency path; `--force` is unverified and NOT used (F8). |

## Security Considerations

Cross-reference `plans/260703-1738-fix-urgent-hermes-delegation-issues/phase-05-provision-ccs-profile.md` Security Considerations — fresh/dedicated credential (separate key/quota/audit), never reuse the operator's profile, `~/.ccs` is a broad auto-executing surface. NOT re-derived here.

**Net-new for this script:** the non-interactive `--api-key --yes` form is a deliberate, acknowledged `ps`/history leak accepted in exchange for `curl | sudo bash` scriptability. The safer interactive wizard is not scriptable → documented as the manual alternative, not the default. Rollback: `ccs api remove ccs-hermes` + revoke the key at the provider.

**Argv exposure (F15):** `--api-key=` sits in this wrapper's own argv (`ps`/history) for the run's duration — see the canonical F15 note in `phase-02-gh-auth-script.md` → Security Considerations. Prefer env-indirection over an inline flag; this is a live provider credential.

## Next Steps

Produces the `ccs-hermes` profile Phase 6's `4-merge-delegation-config.sh` wires into the live config. Alternative to Phase 5. Independent file.
