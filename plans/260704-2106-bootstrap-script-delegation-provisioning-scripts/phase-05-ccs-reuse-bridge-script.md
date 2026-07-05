---
phase: 5
title: "CCS Reuse Bridge Script"
status: in-progress
effort: "30m"
---

# Phase 5: CCS Reuse Bridge Script (INTERNAL-FORK-ONLY)

**Priority:** P3 · **Status:** pending · **Ownership:** `scripts/provision-hermes-delegation/3-ccs-reuse-bridge.sh` (new) ONLY · **Run order:** alternative to Phase 4; after `1-claude-auth.sh`

## Context Links

- Design: `plans/reports/from-brainstorm-to-planner-260704-2053-bootstrap-script-delegation-provisioning-design.md` §B + decision 3.
- Shared-credential risk memory: `[[hermes-temporarily-shares-ubuntu-personal-claude-credential]]` (auto-memory, out of repo) — the exact risk this script industrializes.
- What it automates: today's manual copy of `/home/ubuntu/.ccs/instances/ken/` into hermes's home.

## Overview

**INTERNAL-FORK-ONLY.** New numbered script that copies an EXISTING personal CCS instance's credentials to hermes as a stopgap — reusing a real person's CCS identity (e.g. "ken") instead of provisioning a dedicated bot account (Phase 4). This exists ONLY because this repo is a personal fork (`lucastran1991/hermes-optimization-guide`); it will NEVER be upstreamed to the public `OnlyTerp/hermes-optimization-guide`. It ships with a large, unmissable in-script header warning block (decision 3).

Choose Phase 4 (dedicated profile, clean) OR Phase 5 (reuse bridge, stopgap) per host — not both. Phase 4 is strongly preferred; Phase 5 is the "we don't have a bot account yet" bridge.

## Key Insights

- Reuse means SHARED quota + IMPERSONATION risk: hermes-delegated tasks consume the personal account's usage/quota and act under that identity's credential — mirroring the accepted-but-flagged risk in `[[hermes-temporarily-shares-ubuntu-personal-claude-credential]]`.
- **DECISION (was open in the design doc, now resolved): require BOTH `--instance=<name>` AND an explicit `--i-understand-the-risk` flag.** Cheap to add, prevents muscle-memory / accidental future runs of a credential-reuse script that lives in a repo. Without `--i-understand-the-risk`, the script prints the warning and `die`s WITHOUT copying anything.
- **Copy ONLY the credential files, NOT the whole instance tree (F2).** `/home/ubuntu/.ccs/instances/<name>/` also contains `history.jsonl` (69KB of real conversation transcripts/PII), `.claude.json` (session config), `projects/`, `session-env/` (45 session dirs), `plans-registries/`, `file-history/`. A blanket `cp -a` would export a real person's chat history into a service account's home — a far larger blast radius than "credential reuse." Copy only the files CCS needs to route the profile: `.credentials.json` and `.claude.json`. Exclude everything else (transcripts, projects, session-env, plans-registries, file-history).
- **Validate `--instance=<name>` before building any path (F3).** The value is spliced into `/home/ubuntu/.ccs/instances/$INSTANCE` and the script runs as root — an unsanitized `../../../etc` would turn this into a root-privileged arbitrary-directory read+re-own primitive. Gate with `[[ "$INSTANCE" =~ ^[a-zA-Z0-9_-]+$ ]] || die "invalid instance name"` before it touches a path.
- **Profile-name resolution NEEDS the root `~/.ccs/config.yaml` entry, not just the instance dir (F9) — VERIFIED live, no longer open.** Read hermes's own `~/.ccs/config.yaml` directly: it has a top-level `accounts:` block (NOT `instances:` — that's just the directory name) with exactly this shape per entry:
  ```yaml
  accounts:
    ken:
      created: "2026-06-28T17:08:11.592Z"
      last_used: "2026-07-04T21:12:12.794Z"
      context_mode: isolated
  ```
  Confirmed hermes's config already has `lucas`, `ken`, AND `luan` entries (artifact of the earlier full-file `.ccs/config.yaml` copy bridge) — so `ccs <name> -p` resolution is NOT pure disk-scan; the script MUST merge a `accounts.<name>:` entry (same 3-key shape) into hermes's `~/.ccs/config.yaml` if missing, not just copy the instance directory.
- All `ccs` calls use the `sudo -u hermes -i bash -c '<cmd>'` wrapper form (F12), never bare `-i ccs …`.

## Execution Status (2026-07-05)

`scripts/provision-hermes-delegation/3-ccs-reuse-bridge.sh` authored per spec: loud INTERNAL-FORK-ONLY header, dual-flag risk gate, F3 charset validation before path build, F2 scoped copy (only `.credentials.json`/`.claude.json`, verified via grep — no `cp -a`/blanket copy), F9 profile registration merge into the `accounts:` block. Code-reviewed, `bash -n` clean, executable. Review added a `chmod 600` on the two copied credential files (not in the original spec, but consistent with `1-claude-auth.sh`'s pattern — the source file's permissions shouldn't be blindly inherited). NOT done: baseline capture, refusal-path check, and smoke test against a real hermes host with a real instance name.

## Requirements

- Functional: given `--instance=<name> --i-understand-the-risk`, validate the name (F3), copy ONLY the credential files (`.credentials.json`, `.claude.json` — F2) to hermes's `.ccs/instances/<name>/`, register the profile in hermes's root `~/.ccs/config.yaml` if resolution needs it (F9), re-own to hermes, and pass the smoke test `ccs <name> -p "echo ok" --output-format json` (exit 0).
- Non-functional: non-interactive, idempotent (re-copy overwrites), reject an invalid `--instance` charset (F3), refuse to act (print warning + `die`) unless BOTH flags present, `die` if the source instance dir is absent.

## Architecture

Input: `--instance=<name>` + `--i-understand-the-risk` (both required). Transform: recursive copy + re-own. Gate: smoke-test exit 0.

Data flow:
```
--instance=NAME (+ --i-understand-the-risk)
  → guard: both flags present? else print WARNING + die (no copy)
  → guard (F3): [[ NAME =~ ^[a-zA-Z0-9_-]+$ ]]? else die "invalid instance name"
  → guard: /home/ubuntu/.ccs/instances/NAME exists? else die
  → mkdir -p /home/hermes/.ccs/instances/NAME
  → copy ONLY credential files (F2): cp /home/ubuntu/.ccs/instances/NAME/.credentials.json
                                       /home/ubuntu/.ccs/instances/NAME/.claude.json
                                       → /home/hermes/.ccs/instances/NAME/
     (NOT cp -a — excludes history.jsonl, projects/, session-env/, plans-registries/, file-history/)
  → register profile in root config if needed (F9): merge NAME's entry from
     /home/ubuntu/.ccs/config.yaml into /home/hermes/.ccs/config.yaml  [UNVERIFIED shape — see Unresolved Qs]
  → chown -R hermes:hermes /home/hermes/.ccs/instances/NAME  (+ config.yaml if touched)
  → smoke: sudo -u hermes -i bash -c 'ccs NAME -p "echo ok" --output-format json'  (exit 0)
```

**Top-of-file warning block (in the script itself, not just this plan file):** a boxed comment stating: INTERNAL-FORK-ONLY, NOT for upstream, reuses a personal CCS identity (shared quota + impersonation), use `2-ccs-profile.sh` for a dedicated bot account instead. Loud and unmissable.

Arg loop: `--instance=`, `--i-understand-the-risk` (boolean). If `--i-understand-the-risk` absent → print the warning + `die "refusing to reuse a personal CCS identity without --i-understand-the-risk"`.

## Related Code Files

- **Create:** `scripts/provision-hermes-delegation/3-ccs-reuse-bridge.sh` (with the loud header block).

## Implementation Steps

TDD shape (assert-fails → implement → assert-passes).

1. **Assert-fails (pre-change):** `sudo -u hermes -i bash -c 'ls ~/.ccs/instances/ken' ` (or chosen name) exits non-zero (not copied yet). Record baseline.
2. **Implement:** write `3-ccs-reuse-bridge.sh`:
   - LOUD header warning block (see Architecture) — first thing in the file.
   - `set -euo pipefail`, `log()/warn()/die()`.
   - Arg loop: `--instance=`, `--i-understand-the-risk`.
   - Risk gate: `[ "$UNDERSTOOD" = 1 ] || { warn "<the risk paragraph>"; die "refusing without --i-understand-the-risk"; }`.
   - **Name validation (F3, BEFORE building any path):** `[[ "$INSTANCE" =~ ^[a-zA-Z0-9_-]+$ ]] || die "invalid instance name: $INSTANCE"`.
   - Source-exists gate: `SRC=/home/ubuntu/.ccs/instances/$INSTANCE; [ -d "$SRC" ] || die "no such instance: $SRC"`.
   - **Scoped copy (F2, NOT `cp -a`):** `DST=/home/hermes/.ccs/instances/$INSTANCE; mkdir -p "$DST"`; copy only `"$SRC/.credentials.json"` and `"$SRC/.claude.json"` into `"$DST/"` (`[ -f "$SRC/.credentials.json" ] || die "no credential file in source instance"`). Explicitly do NOT copy `history.jsonl`, `projects/`, `session-env/`, `plans-registries/`, `file-history/`.
   - **Profile registration (F9):** if `ccs` resolves the profile via the root config (verify first — see Unresolved Qs), merge `$INSTANCE`'s entry from `/home/ubuntu/.ccs/config.yaml` into `/home/hermes/.ccs/config.yaml`. If resolution is pure disk-scan of `instances/<name>/`, skip.
   - `chown -R hermes:hermes "$DST"` (and `/home/hermes/.ccs/config.yaml` if merged).
   - Smoke: `sudo -u hermes -i bash -c 'ccs "'"$INSTANCE"'" -p "echo ok" --output-format json'` → `die` on non-zero.
3. **Assert-passes (post-change):** step 1's `ls` now succeeds; smoke test exits 0.
4. **Refusal check:** run WITHOUT `--i-understand-the-risk` → prints warning, `die`s, copies nothing (verify dest still absent).
5. **Idempotency check:** re-run with both flags → re-copy overwrites cleanly, smoke test still passes.

## Success Criteria

- [ ] Baseline captured: pre-change dest instance dir absent.
- [ ] Loud INTERNAL-FORK-ONLY warning block present at the top of the SCRIPT (not just the plan).
- [ ] Requires BOTH `--instance=` and `--i-understand-the-risk`; refuses (warn + `die`, no copy) without the latter.
- [ ] `die`s if the source instance dir is absent.
- [ ] Rejects an invalid `--instance` name (F3): `--instance=../../etc` → `die`, no path built.
- [ ] Copies ONLY `.credentials.json` + `.claude.json` (F2); dest contains NO `history.jsonl`/`projects`/`session-env`/`plans-registries`/`file-history`.
- [ ] Profile resolves by name (F9): if root-config registration was needed, it was merged; smoke test exits 0.
- [ ] Copies + re-owns to hermes; smoke test exits 0.
- [ ] Re-run idempotent; refusal path verified.

## Risk Assessment

| Risk | L×I | Mitigation |
|------|-----|------------|
| Personal identity impersonation + shared quota | H×H | Deliberate stopgap; loud header + `--i-understand-the-risk` gate; Phase 4 (dedicated) is the preferred path. Documented, matches `[[hermes-temporarily-shares-ubuntu-personal-claude-credential]]`. |
| Script accidentally upstreamed to public repo | M×H | INTERNAL-FORK-ONLY header block; decision 3 records never-upstream; **Phase 6's CHANGELOG.md entry and README.md row must NOT mention this script at all** (Validation Session 1 — not just "avoid public-guidance framing," full omission). Its only documentation is this plan file + its own in-script header. |
| Muscle-memory accidental run later | M×M | Double-flag gate — `--instance=` alone does nothing without `--i-understand-the-risk`. |
| Source instance absent / wrong name | L×M | Source-exists `die` before any copy. |
| Over-copy of personal chat history / PII (F2) | H×H→L×M | Copy ONLY `.credentials.json` + `.claude.json`, never `cp -a` the tree — `history.jsonl` (69KB transcripts), `projects/`, `session-env/`, `plans-registries/`, `file-history/` are explicitly excluded. Blast radius drops from "whole personal conversation history in a service account" to "one scoped credential pair." |
| Path traversal via unsanitized `--instance` (F3) | L×H→L×L | Root-privileged script; charset allowlist `^[a-zA-Z0-9_-]+$` gate BEFORE any path is built — rejects `..`/`/`, kills the arbitrary-dir read+re-own primitive. |
| Profile fails to resolve by name (F9) | M×M | If `ccs` needs a root-`config.yaml` entry (verify first), merge it; else disk-scan of `instances/<name>/` suffices. Smoke test is the catch — a "profile not found" failure points here, not at the credential. |
| Copied creds outlive their welcome (no rotation) | M×M | Stopgap only; document that migrating to `2-ccs-profile.sh` (dedicated) is the exit path; removal = delete the copied instance dir. |

## Security Considerations

This script INDUSTRIALIZES a known, flagged risk (`[[hermes-temporarily-shares-ubuntu-personal-claude-credential]]`): reusing a personal CCS identity for the bot. Consequences — the bot's delegated tasks bill/attribute to the personal account and can act under its credential; a same-UID delegated sub-session can read the copied credential. This is ACCEPTED only as a temporary bridge, gated behind `--i-understand-the-risk`, and walled off as internal-fork-only. The correct end state is Phase 4's dedicated `ccs-hermes` profile.

**Scoped copy (F2)** materially bounds the leak: only `.credentials.json` + `.claude.json` land in hermes's home — NOT the personal conversation history (`history.jsonl`), project data, or session state. A same-UID sub-session can still read the copied credential pair (unavoidable given the reuse premise), but it can no longer read the operator's chat transcripts/PII, which a blanket `cp -a` would have exported.

**Argv exposure (F15):** unlike Phases 2–4, this script takes no credential FLAG (the credential is read from disk, not passed as `--api-key=`), so the wrapper-argv leak does not apply here. The canonical F15 note (`phase-02-gh-auth-script.md` → Security Considerations) is referenced for consistency across the directory but has no live-credential-in-argv surface in this script.

Rollback: `rm -rf /home/hermes/.ccs/instances/<name>` (as hermes) + rotate/revoke the shared credential at the provider if it was ever exposed.

## Next Steps

Alternative credential source for Phase 6's `4-merge-delegation-config.sh` (`--ccs-profile=<instance-name>`). Independent file. Never upstreamed.

## Unresolved Questions

None remaining — both prior `[UNVERIFIED]` items resolved via live host inspection during `/ck:plan validate` (2026-07-04): (1) root-config `accounts:` registration confirmed required, exact shape captured above; (2) instance dir confirmed to contain both `.credentials.json` (471 bytes) AND `.claude.json` (42240 bytes) — matches the scoped-copy file list already specified in Implementation Steps, no change needed there.
