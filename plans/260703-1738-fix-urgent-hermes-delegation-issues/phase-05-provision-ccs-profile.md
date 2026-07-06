---
phase: 5
title: "Provision CCS Profile"
status: completed
effort: "35m"
---

# Phase 5: Provision CCS Profile

**Priority:** P2 · **Status:** completed · **Effort:** ~35m · **Blocked by:** Phase 4 (needs the `ccs` binary + writable `~/.ccs`) · **Ownership:** host-only, plus a *conditional* one-line `production.yaml` edit

**Completed (2026-07-06):** `templates/config/production.yaml:193` confirmed `ccs_profile: ccs-hermes` (no edit needed, matches recommendation). Smoke-test superseded by a stronger real-task run: `ccs ccs-hermes -p '/ck:brainstorm...' --output-format stream-json ...` exited 0 with a real completed result (model `claude-opus-4-8`, ~111s) — see `plans/260705-1752-ccs-delegation-timeout-progress-tracking-fix/phase-03-live-host-verification.md` Addendum. A full successful task run is stronger proof than the documented `echo ok` smoke test.

## Context Links

- Host verification: `research/live-host-verification-findings.md` §6 (presets + wizard preference), §7 (**never reuse ubuntu's CCS identity**).
- Smoke-test gate + provisioning contract: `skills/dev/coding-agent-delegate/SKILL.md:48,83`.
- Config field: `templates/config/production.yaml:187-193` (provisioning comment + `ccs_profile:`).

## Overview

Create the hermes-dedicated CCS profile the delegation config points at, then pass the mandatory smoke-test gate before `harness: ccs` is usable anywhere. Uses the interactive `ccs api create` wizard (not the `--api-key` form) per the skill's documented preference. The credential MUST be fresh and hermes-only — never the operator's.

## Key Insights

- `ccs api create <name> --preset <glm|km|anthropic|…>` is documented as interactive and prompts for the key, avoiding the shell-history/`ps` leak of the `--api-key` form (findings §6). Both `SKILL.md:48` and `production.yaml:187-192` prefer the wizard — respect it, do not "optimize" to the CLI-arg form.
- **The wizard's actual input UX is UNCONFIRMED** and may not be a masked terminal prompt. `ccs`'s deps (`express`/`ws`/`get-port`/`open`, no masked-input library) suggest a possible local-server/browser flow — and this host is SSH-only with no browser (the same constraint Phase 3 documents for `claude auth login`). If the wizard tries to open a browser and can't, look for a printed-URL fallback; failing that, the documented emergency fallback is `ccs api create <name> --preset <p> --api-key <key> --target claude --yes` (accepting the `ps`/shell-history leak *explicitly* in that case — do not pretend it can't happen). Cleanup command for a partial/aborted create: **`ccs api remove <name>`** (verified in `ccs api --help`; `ccs api list` to inspect).
- **VERIFIED correction to the brief:** `production.yaml:193` is already `ccs_profile: ccs-hermes` — **NOT unset.** `SKILL.md:183` also uses `ccs-hermes`, and prior plan `260703-1041` set it. → **Recommend naming the profile `ccs-hermes`** to match the wired value, so no config edit is needed (DRY). Only if the operator picks a different name does `:193` need a one-line update. (The brief's `hermes-delegate` was an illustrative "e.g.".)
- **CRITICAL (findings §7):** `/home/ubuntu/.ccs/config.yaml` (mode 600, owned by ubuntu/"ken") is the *same* CCS product this planning session runs under — **never copy, export, or import it.** hermes needs a fresh, dedicated credential (separate key/quota/audit trail — plan `260703-1041`'s requirement).
- The smoke-test gate is mandatory: **there is no automatic fallback to `bare` on failure** (`SKILL.md:48,83`). `harness: ccs` stays off until it passes.
- **Category-error correction (Finding 18):** `ReadWritePaths=/home/hermes/.ccs` is a *systemd unit sandboxing* directive — it constrains only processes systemd spawns for `hermes gateway run`. **Phase 5's own steps run via plain `sudo -u hermes bash -c '…'`, which is NOT sandboxed**, so `ReadWritePaths`/`ProtectHome` are irrelevant to Phase 5; plain-shell writes to `~/.ccs` are governed by ordinary DAC (is `~/.ccs` owned/writable by hermes). The RW-path "must be live" requirement applies to **Phase 6** (the actual sandboxed consumer, via the real bot) — moved there. Do NOT chase `ReadWritePaths` if Phase 5's smoke test fails (see Risk Assessment).

## Requirements

A profile (recommended name `ccs-hermes`) exists for the hermes user with a fresh dedicated credential; `production.yaml:193` equals that name; the smoke-test exits 0 with valid JSON.

## Architecture

`[HUMAN]` `ccs api create ccs-hermes --preset <p>` (enter the fresh key at the prompt) → state written under `~/.ccs/` → `[AGENT]` `sudo -u hermes bash -c 'export PATH="$HOME/.local/bin:$PATH"; ccs ccs-hermes -p "echo ok" --output-format json'` exits 0 (PATH-wrapped form required).

## Related Code Files

- **Conditional modify:** `templates/config/production.yaml:193` (`ccs_profile:`) — edit **only if** the chosen profile name ≠ `ccs-hermes`. Default recommendation keeps `ccs-hermes` → no edit. Owned solely by this phase; overlaps no other phase.

## Implementation Steps

1. `[HUMAN]` **Pre-check before invoking the wizard:** have the fresh, hermes-dedicated credential in hand (provision it from the provider console first if needed) — starting the wizard without the key risks a mid-wizard abort that can leave a partial `ccs-hermes` profile. If a create is aborted or partial, clean it up with `ccs api remove ccs-hermes` (then re-create). Confirm the preset that matches the credential's provider.
2. `[HUMAN]` As the hermes user (interactive shell), run `ccs api create ccs-hermes --preset <glm|km|…>`; enter the **fresh hermes key** at the prompt. Do NOT use `--api-key` (leaks via `ps`/history) unless the wizard is unusable on this SSH-only/no-browser host — in which case the documented emergency fallback is `ccs api create ccs-hermes --preset <p> --api-key <key> --target claude --yes`, accepting the leak explicitly. Do NOT reuse anything under `/home/ubuntu/.ccs/`.
3. `[HUMAN or AGENT — human's choice]` Ensure `production.yaml:193` `ccs_profile:` equals the created name. If named `ccs-hermes` (recommended) it already matches → **no edit**. If different → update that one line (repo write; sequence after step 2 since the value depends on the human's choice). Note: this edits the repo *template* only — syncing the `delegation:` block into the **live** `/home/hermes/.hermes/config.yaml` is Phase 6 (the file the running service actually reads).
4. `[AGENT]` Smoke-test gate: `sudo -u hermes bash -c 'export PATH="$HOME/.local/bin:$PATH"; ccs ccs-hermes -p "echo ok" --output-format json'` — MUST exit 0 with valid JSON. `harness: ccs` is NOT usable until this passes.

## Todo List

- [ ] Fresh hermes-dedicated credential in hand BEFORE the wizard (never ubuntu's).
- [ ] Profile created; any partial/aborted create cleaned up via `ccs api remove`.
- [ ] `production.yaml:193` matches the profile name (`ccs-hermes` → no edit needed).
- [ ] Smoke-test exits 0 with valid JSON.
- [ ] Confirmed profile state lands under `~/.ccs` (hermes-owned; DAC-writable — not a sandbox/`ReadWritePaths` concern for this plain-shell step).

## Success Criteria

Smoke-test passes; `production.yaml:193` == the created profile name.

## Risk Assessment

| Risk | L×I | Mitigation |
|------|-----|------------|
| Credential leak via `--api-key`/history | M×H | Use the wizard only (findings §6); never echo the key. Emergency `--api-key` fallback documented as an explicit, acknowledged leak. |
| Reusing the operator's CCS profile (cross-identity contamination) | L×H | findings §7 — explicit "never touch `/home/ubuntu/.ccs`"; fresh key only. |
| No credential ready at wizard time → mid-wizard abort / partial profile | M×M | Pre-check (step 1): credential in hand first; cleanup a partial via `ccs api remove ccs-hermes` before retry. |
| Wizard needs a browser this SSH-only host lacks | M×M | Look for a printed-URL fallback; else the documented `--api-key --yes` emergency fallback (explicit leak trade-off). |
| Profile name ≠ config value | M×M | Default to `ccs-hermes` (already wired) → no mismatch; if renamed, update `:193` in the same change. |
| Smoke-test fails (state not persisting) | M×H | **Debug DAC first, not `ReadWritePaths`** (Phase 5 runs plain-shell, not sandboxed): confirm `~/.ccs` is owned/writable by hermes; watch for the API-profile "falls back to default account dir" caveat (plan `260703-1041` Unresolved Q1) — verify state actually lands under `~/.ccs` on this host. (`ReadWritePaths` only matters for Phase 6's sandboxed path.) |
| Preset mismatches the credential's provider | M×M | Pick `--preset` matching the key you are dedicating. |

## Security Considerations

Fresh, dedicated credential (separate key/quota/audit). Entered via the wizard (no `ps`/history exposure; the `--api-key` emergency fallback is an explicit, acknowledged leak). Never reuse the operator's profile. State lands under `~/.ccs` (hermes-owned via DAC) — and note `~/.ccs` is a broad auto-executing surface (`hooks/`, `mcp/`, `cliproxy/`, `instances/` per the reference install), not just an API-key file; the widened `ReadWritePaths=/home/hermes/.ccs` (Phase 2) covers exactly that surface for the *sandboxed* service. **Open question:** which `--preset`/provider credential will the operator dedicate to the bot?

## Rollback

Delete the profile with **`ccs api remove ccs-hermes`** (or remove its entry under `~/.ccs` as hermes) — this also cleans up a partial/aborted create; revert `production.yaml:193` if it was edited. Because the default `harness` is `bare`, an unused/removed `ccs` profile breaks no delegation. (The live-config `delegation:` block added in Phase 6 is rolled back there.)

## Next Steps

Unblocks Phase 6's end-to-end test (the `harness: ccs` path). Depends on Phase 4 (the `ccs` binary). It does **not** depend on Phase 2's `.ccs` `ReadWritePaths` (Finding 18 — Phase 5's steps are plain-shell, not sandboxed; that RW path matters only for Phase 6's sandboxed consumer), matching the dependency graph (`5 blockedBy 4`, not 2).
