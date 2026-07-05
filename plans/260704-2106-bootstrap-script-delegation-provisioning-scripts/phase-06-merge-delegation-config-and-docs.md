---
phase: 6
title: "Merge Delegation Config And Docs"
status: in-progress
effort: "35m"
---

# Phase 6: Merge Delegation Config And Docs

**Priority:** P2 · **Status:** pending · **Ownership:** `scripts/provision-hermes-delegation/4-merge-delegation-config.sh` (new) + `README.md` + `CHANGELOG.md` · **Run order:** LAST — after a `ccs_profile` exists (Phase 4 or Phase 5)

## Context Links

- Design: `plans/reports/from-brainstorm-to-planner-260704-2053-bootstrap-script-delegation-provisioning-design.md` §B + open items.
- Source of the `delegation:` block: `templates/config/production.yaml`.
- Live config the service reads: `/home/hermes/.hermes/config.yaml`.
- README Repo Map row to mirror: `README.md:72` (`deploy-systemd-units.sh`).
- CHANGELOG today's entry (already exists, DO NOT clobber): `CHANGELOG.md:5` — `## 2026-07-04 — Unit-Drift Prevention Script + ClaudeKit Prerequisite Reframe`.

## Overview

Final step. New numbered script that wires the `delegation:` block into the LIVE `/home/hermes/.hermes/config.yaml` (the file the running service actually reads — distinct from the repo template), plus the docs updates that make the new directory discoverable.

Normally run LAST: `4-merge-delegation-config.sh --ccs-profile=<name>` needs a `ccs_profile` name that only exists after Phase 4 (`ccs-hermes`) OR Phase 5 (a bridge instance name) has run against the host. It does NOT restart `hermes.service` — it prints a reminder that a manual restart is needed to reload (same reasoning as today: fold the reload into the real `/coding-agent-delegate` test, don't double-bounce the service).

**<!-- Corrected 2026-07-04 evening -->** Command name fixed throughout this phase: the real bot command is `/coding-agent-delegate`, not `/delegate_code` (frontmatter `name:`-derived, verified live — see plan.md's correction note and `[[project_hermes-telegram-bot-skill-command-checklist]]`). The restart requirement below is stronger than originally framed: it's not only about `config.yaml` being re-read — `hermes.service`'s in-process skill-command registry (`agent.skill_commands._skill_commands`) is populated lazily and cached until the process restarts, so ANY skill symlink added/changed after the service was already running (not just this phase's config merge) stays undispatchable until restart too.

## Key Insights

- **`GUIDE_DIR` resolution + stale-clone guard (F7).** This script reads `templates/config/production.yaml` from a local checkout, which contradicts the plan's own `curl | sudo bash`-safe constraint if run with no repo present. Mirror `deploy-systemd-units.sh` exactly: `GUIDE_DIR="${GUIDE_DIR:-/opt/hermes-optimization-guide}"`, `[ -f "$GUIDE_DIR/templates/config/production.yaml" ] || die "run from a checkout or set GUIDE_DIR"`, then the stale guard — `git -C "$GUIDE_DIR" fetch --quiet origin` + `behind=$(git -C "$GUIDE_DIR" rev-list --count main..origin/main)`; if `behind > 0` and not `--force`, `die "canonical clone is $behind commit(s) behind origin/main"`. Prevents grafting a stale `delegation:` block.
- **Copy-boundary mechanism, exactly specified (F13).** Source `production.yaml` has `delegation:` at line 168 and the NEXT top-level key `acp:` at 197, with more content after. Extraction must stop BEFORE `acp:`. Use awk with an explicit top-level-key terminator (exclusive): `awk '/^delegation:/{f=1} f && /^[a-zA-Z_][a-zA-Z0-9_]*:/ && !/^delegation:/{exit} f{print}' "$GUIDE_DIR/templates/config/production.yaml"`. Then substitute the profile within the extracted block only: `sed 's/^\( *ccs_profile:\).*/\1 <name>/'`. Do NOT leave the boundary as an unspecified "append the block."
- Backs up the live config to `config.yaml.bak` BEFORE editing (safe rollback).
- **Duplicate-key guard, BEFORE appending (F6b).** A duplicate top-level `delegation:` key is VALID YAML — `yaml.safe_load` silently keeps the last occurrence and does NOT raise (verified: `python3 -c "import yaml; print(yaml.safe_load('a: 1\nb: 2\na: 3\n'))"` → `{'a': 3, 'b': 2}`). So YAML-validity can NEVER be the duplicate detector. Before merging: `grep -c '^delegation:' "$CONFIG"` — if ≥1, REPLACE the existing block (delete the old bounded block, then insert), never blind-append; and assert post-merge `[ "$(grep -c '^delegation:' "$CONFIG")" -eq 1 ]` or restore `.bak` + `die`.
- **YAML-validate needs PyYAML, which is NOT installed on the host (F6a).** The bootstrap apt list has no `python3-yaml`; PyYAML is confirmed present only in CI. Simplest fix (chosen for KISS + zero new bespoke code): guard-install the system package — `python3 -c 'import yaml' 2>/dev/null || apt-get install -y -qq python3-yaml` (idempotent, uses the repo's established apt mechanism) — then the real `python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))'` parse gate works. Rejected alternatives: a grep-only structural check (can't catch a genuinely malformed merge) and `pip install --user pyyaml` (extra per-user state vs. one system package). The parse gate catches gross syntax breaks; the F6b grep-count catches the duplicate-key case parse can't.
- Does NOT restart the service — prints the restart reminder only.
- **<!-- Added 2026-07-04 evening: scope clarification, no plan text was factually wrong -->** The merged `delegation:` block's `routing`/`default`/`ccs_profile` sub-keys are NOT read by any code path in `hermes-agent` — verified: `hermes_cli/config.py:2051-2074`'s `delegation` defaults dict recognizes only `model, provider, base_url, api_key, api_mode, inherit_mcp_toolsets, max_iterations, child_timeout_seconds, reasoning_effort` (that schema backs the UNRELATED native `delegate_task()` sub-agent-spawning tool, a different feature that happens to share the `delegation:` top-level key name). A repo-wide grep of `hermes-agent`'s `.py` source for `files_changed_gte`/`repo_tokens_gte`/`routing table` returns zero hits outside docs/tests — confirmed via `tests/hermes_cli/test_config_drift.py:11-32`, which documents a prior real incident (`delegation.default_toolsets` removed as dead config, "never read"). This script's job is still correct and worth doing (it makes the routing table + `ccs_profile` name discoverable to the agent as config context, which the `coding-agent-delegate` skill's own prose reads and self-applies — same pattern as `repo=`/`escalate=`/`harness=`, see plan.md's correction note) — just don't read "merge the delegation: block" as "activate code-level routing." No script/code in this plan needs to change because of this; it's a documentation-accuracy note for whoever executes/maintains this phase.
- **Docs are FUTURE WORK described here, written at EXECUTION time — NOT now.** This plan does not touch README/CHANGELOG yet.

## Requirements

- Functional: given `--ccs-profile=<name>`, resolve `GUIDE_DIR` + stale-clone guard (F7), ensure PyYAML (F6a), extract the bounded `delegation:` block (F13), back up live `config.yaml` → `.bak`, replace-or-insert the block with that profile name, assert single `delegation:` key (F6b), YAML-validate, print the manual-restart reminder. Plus (at execution): a README Repo Map row for the new dir + a CHANGELOG entry dated 2026-07-04.
- Non-functional: non-interactive, idempotent (re-merge REPLACES the existing `delegation:` block via bounded-block delete, never duplicates), `--force` bypasses the stale-clone guard, `die` + restore backup on duplicate-key OR invalid YAML.

## Architecture

Input: `--ccs-profile=<name>` (required), optional `--force` (bypass stale-clone guard). Transform: resolve GUIDE_DIR → extract bounded block → backup → replace-or-insert → validate. Exit: valid config + printed restart reminder.

Data flow:
```
--ccs-profile=NAME
  → GUIDE_DIR="${GUIDE_DIR:-/opt/hermes-optimization-guide}"; assert production.yaml present (F7)
  → stale-clone guard: git fetch + rev-list --count main..origin/main; behind>0 && !--force → die (F7)
  → ensure PyYAML: python3 -c 'import yaml' || apt-get install -y python3-yaml (F6a)
  → extract bounded delegation: block (F13):
        awk '/^delegation:/{f=1} f && /^[a-zA-Z_][a-zA-Z0-9_]*:/ && !/^delegation:/{exit} f{print}' $GUIDE_DIR/templates/config/production.yaml
      | sed 's/^\( *ccs_profile:\).*/\1 NAME/'
  → cp /home/hermes/.hermes/config.yaml{,.bak}
  → if grep -q '^delegation:' config.yaml: delete the existing bounded block first (F6b — replace, never append)
  → append the extracted+substituted block
  → assert grep -c '^delegation:' == 1 (F6b) → else restore .bak + die
  → python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' config.yaml → on fail: restore .bak + die
  → print "hermes.service needs a manual restart to reload — fold it into your /coding-agent-delegate test"
```

Idempotency: if a `delegation:` block already exists, DELETE the existing bounded block (same awk terminator) then insert — never append a second one. A duplicate top-level key is VALID YAML (parse can't catch it, F6b), so the post-merge `grep -c '^delegation:' == 1` assertion is the real guard, not YAML-validity.

## Related Code Files

- **Create:** `scripts/provision-hermes-delegation/4-merge-delegation-config.sh`.
- **Reads (repo, via `GUIDE_DIR`):** `$GUIDE_DIR/templates/config/production.yaml` (source of the `delegation:` block) — `GUIDE_DIR` defaults to `/opt/hermes-optimization-guide` with a stale-clone guard (F7), not a bare relative path.
- **Writes (host runtime, not repo):** `/home/hermes/.hermes/config.yaml` (+ `.bak`).
- **FUTURE-WORK docs edits (at execution time, NOT now):**
  - `README.md` Repo Map — add ONE row for `scripts/provision-hermes-delegation/`, describing the directory generically (gh-auth, Claude/CCS credential provisioning, config merge) — do NOT enumerate `3-ccs-reuse-bridge.sh` by name or describe what it does; mirror the `deploy-systemd-units.sh` row's style (`:72`). Fork-local tooling framing — NOT upstream-public guidance (decision 3). **<!-- Updated: Validation Session 1 -->** If Phase 4 vs 5 needs framing anywhere user-facing (e.g. either script's own `--help`/usage text), Phase 4 (dedicated profile) is presented as the primary/preferred path and Phase 5 (reuse-bridge) as an explicit last-resort fallback — never as co-equal alternatives.
  - `CHANGELOG.md` — the `## 2026-07-04 — …` entry ALREADY EXISTS (`:5`). ADD to it (or add a second dated block below it) — DO NOT duplicate/clobber. Frame the new dir as fork-local delegation-provisioning tooling; do NOT phrase as public guidance. **<!-- Updated: Validation Session 1 --> Do NOT mention `3-ccs-reuse-bridge.sh` or the credential-reuse-bridge concept at all in CHANGELOG.md** — even internal-only framing creates a discoverable trail in a repo whose remote is public-reachable on GitHub. The CHANGELOG entry should describe only: `0-gh-auth.sh`, `1-claude-auth.sh`, `2-ccs-profile.sh`, `4-merge-delegation-config.sh`, and the Phase 1 bootstrap additions. The reuse-bridge script's only documentation is its own in-script header warning + this plan file.

## Execution Status (2026-07-05)

`scripts/provision-hermes-delegation/4-merge-delegation-config.sh` authored per spec (F7 GUIDE_DIR/stale-clone guard, F6a PyYAML ensure, F13 bounded awk extraction verified live to stop before `acp:`, F6b replace-not-append + duplicate-key assert + auto-restore-on-failure), code-reviewed, `bash -n` clean, executable. README.md Repo Map row and CHANGELOG.md 2026-07-04 entry extension both added — `grep -rni` confirms zero mention of the reuse-bridge script in either, per the explicit full-omission decision. Review added a charset gate on `--ccs-profile` (parity with `3-ccs-reuse-bridge.sh`'s `--instance` gate) and removed a redundant nested `sudo` (script is already meant to run as root). NOT done: baseline capture and post-merge verification against a real hermes host's live `config.yaml`; the manual restart + real `/coding-agent-delegate` end-to-end test remain `[HUMAN]`-only, out of this plan's scope per its own Next Steps.

## Implementation Steps

TDD shape (assert-fails → implement → assert-passes).

1. **Assert-fails (pre-change):** on a host, `grep -q '^delegation:' /home/hermes/.hermes/config.yaml` may exit non-zero (block absent) OR the block has a stale/empty `ccs_profile`. Record baseline. Also: `grep -q 'provision-hermes-delegation' README.md` exits non-zero (no Repo Map row yet).
2. **Implement `4-merge-delegation-config.sh`:**
   - Header: purpose, usage (`--ccs-profile=<name>` [`--force`]), "does NOT restart the service" note, idempotency note.
   - `set -euo pipefail`, `log()/warn()/die()`.
   - Arg loop: `--ccs-profile=`, `--force`; `die` if profile empty.
   - **GUIDE_DIR + stale guard (F7):** `GUIDE_DIR="${GUIDE_DIR:-/opt/hermes-optimization-guide}"`; `[ -f "$GUIDE_DIR/templates/config/production.yaml" ] || die "…set GUIDE_DIR or run from a checkout"`; `git -C "$GUIDE_DIR" fetch --quiet origin` then `behind=$(git -C "$GUIDE_DIR" rev-list --count main..origin/main 2>/dev/null || echo 0)`; `[ "$behind" -gt 0 ] && [ "$FORCE" -ne 1 ] && die "clone $behind behind origin/main — pull or --force"` (mirror `deploy-systemd-units.sh:38,47-57`).
   - **Ensure PyYAML (F6a):** `python3 -c 'import yaml' 2>/dev/null || apt-get install -y -qq python3-yaml`.
   - **Extract bounded block (F13):** `awk '/^delegation:/{f=1} f && /^[a-zA-Z_][a-zA-Z0-9_]*:/ && !/^delegation:/{exit} f{print}' "$GUIDE_DIR/templates/config/production.yaml" | sed 's/^\( *ccs_profile:\).*/\1 '"$PROFILE"'/'` → temp file.
   - Backup `config.yaml` → `.bak`.
   - **Replace-not-append (F6b):** if `grep -q '^delegation:' "$CONFIG"`, delete the existing bounded block (same awk terminator, inverse) BEFORE appending the new one; then append the extracted block.
   - **Duplicate-key assert (F6b):** `[ "$(grep -c '^delegation:' "$CONFIG")" -eq 1 ] || { cp "$CONFIG.bak" "$CONFIG"; die "duplicate delegation: block post-merge"; }`.
   - YAML-validate: `python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' "$CONFIG"`; on failure restore `.bak` + `die`.
   - Print the manual-restart reminder (do NOT restart).
3. **Implement docs (execution-time):** add the README Repo Map row; add/extend the CHANGELOG 2026-07-04 entry (fork-local framing).
4. **Assert-passes (post-change):** `grep '^delegation:' config.yaml` succeeds AND its `ccs_profile:` equals the passed name; YAML validates; the restart-reminder line was printed. `grep -q 'provision-hermes-delegation' README.md` now exits 0.
5. **Idempotency check:** re-run with a different `--ccs-profile` → the single `delegation:` block's `ccs_profile` is replaced, no duplicate block; YAML still valid.
6. **Rollback verify:** restoring `config.yaml.bak` reverts cleanly; feeding invalid input triggers the auto-restore path.

## Success Criteria

- [ ] Baseline captured: pre-change live config lacks a wired `delegation:` block; README lacks the row.
- [ ] `GUIDE_DIR` resolved + stale-clone guard fires when the clone is behind origin/main (F7); `--force` bypasses.
- [ ] PyYAML ensured before validating (`import yaml || apt-get install python3-yaml`, F6a).
- [ ] Block extracted with the bounded awk terminator — does NOT capture the following `acp:` key (F13).
- [ ] Script backs up `config.yaml` → `.bak` before editing.
- [ ] Merges the `delegation:` block with `ccs_profile=<--ccs-profile>`; REPLACES (bounded-block delete) not duplicates an existing block.
- [ ] Post-merge asserts exactly one `^delegation:` key (F6b); restores `.bak` + `die`s on a duplicate.
- [ ] YAML-validates; auto-restores `.bak` + `die`s on invalid YAML.
- [ ] Prints the manual-restart reminder; does NOT restart the service.
- [ ] (Execution-time) README Repo Map row added for `scripts/provision-hermes-delegation/` — generic directory description, no mention of `3-ccs-reuse-bridge.sh` specifically; Phase 4 framed as preferred, Phase 5 (wherever surfaced) as last-resort.
- [ ] (Execution-time) CHANGELOG 2026-07-04 entry extended (not clobbered), fork-local framing, **zero mention of `3-ccs-reuse-bridge.sh`/reuse-bridge concept** (Validation Session 1).
- [ ] Re-run idempotent; backup rollback verified.

## Risk Assessment

| Risk | L×I | Mitigation |
|------|-----|------------|
| Corrupt live config → service won't start | M×H | `.bak` backup + YAML-validate (PyYAML ensured first, F6a) + auto-restore on invalid YAML before finishing. |
| Duplicate `delegation:` top-level key (silent) | M×H | YAML-validity CANNOT catch this (`safe_load` keeps last, F6b). Replace via bounded-block delete + post-merge `grep -c '^delegation:' == 1` assertion → restore `.bak` + `die` on failure. |
| Block extraction over-captures the following `acp:` key | M×H | Bounded awk terminator stops at the next top-level key, exclusive (F13) — not an open-ended "append the block." |
| Stale/absent local checkout → merges wrong block or crashes | M×M | `GUIDE_DIR` default + `git fetch`/`rev-list` stale guard (F7), mirroring `deploy-systemd-units.sh`; `die` if `production.yaml` absent, `--force` to override the behind-origin guard. |
| Service silently not reloaded (stale config AND stale in-process skill-command cache — not just config, see Overview correction) | M×M | Print an explicit restart reminder; do NOT auto-restart (fold into the human `/coding-agent-delegate` test — no double-bounce). |
| CHANGELOG entry clobbers today's existing 2026-07-04 block | M×M | Detect the existing `:5` entry; ADD to it or append a second dated block — never overwrite. |
| Docs frame the fork-local dir as public guidance | L×M | Decision 3 — fork-local framing only; no upstream-public phrasing (esp. re: `3-ccs-reuse-bridge.sh`). |
| `--ccs-profile` name doesn't match a real profile | M×M | The wired name must equal what Phase 4/5 created; the real `/coding-agent-delegate` test (out of scope) is the final proof. |

## Security Considerations

The merged `delegation:` block only names a profile — no credential is written here (credentials live under `~/.ccs`/`.env` from Phases 3–5). Backup file `config.yaml.bak` inherits the config's ownership/mode — ensure it stays hermes-owned, not world-readable. No secret is echoed. The docs updates must NOT leak the reuse-bridge as public guidance (decision 3).

## Next Steps

After this: a MANUAL `hermes.service` restart + a real `/coding-agent-delegate` end-to-end test — both `[HUMAN]`-only, OUT of this plan's scope (same human-gate boundary as the related plan's Phase 6). No script substitutes the live delegation test.
