---
title: "Red-team: Scope & Complexity Critic — bootstrap-script-delegation-provisioning-scripts plan"
date: 2026-07-04
type: code-review
role: scope-complexity-critic + contract-verifier
---

# Scope & Complexity Critic — Red Team Review

Reviewed: plan.md + phase-01..06 + design doc (`from-brainstorm-to-planner-260704-2053-...design.md`).
Not relitigating: 5-separate-scripts decision, flag/env-only interaction model, Phase-5 internal-fork-only status — all user-confirmed via AskUserQuestion.

## Finding 1: Phase 6's YAML-validate safety gate depends on a Python module never installed anywhere in this host's provisioning chain

- **Severity:** Critical
- **Location:** Phase 6, "Key Insights" / Implementation Steps step 2 ("YAML-validates after the edit (`python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))'`) — `die` + restore `.bak` on invalid YAML")
- **Flaw:** `python3 -c 'import yaml...'` requires PyYAML. `grep -n "apt-get install" scripts/vps-bootstrap-oci.sh` shows only `curl ca-certificates gnupg jq git python3-venv python3-pip age rclone fail2ban unattended-upgrades debian-keyring debian-archive-keyring apt-transport-https` — no `python3-yaml`/PyYAML anywhere. The only place in this repo PyYAML is confirmed installed is CI (`plans/260703-0347-.../research/researcher-ci-tdd-report.md:12`: "PyYAML already installed at `ci.yml:43`") — a GitHub Actions runner, not the live OCI host these scripts run on. ClaudeKit's skills venv (Phase 1, section 6d) is a separate per-skill virtualenv under `~/.claude/skills/.venv/`, not the system `python3` the merge script invokes as hermes.
- **Failure scenario:** operator runs `4-merge-delegation-config.sh --ccs-profile=ccs-hermes` on a freshly bootstrapped host. `python3 -c 'import yaml...'` raises `ModuleNotFoundError: No module named 'yaml'` → non-zero exit → script's own logic ("on failure restore `.bak` + `die`") fires on every single run, indistinguishable from a real invalid-YAML condition. The one safety gate this phase exists to provide (don't ship broken config) never actually validates anything — it either crashes before checking, or (if the script author doesn't distinguish ImportError from a YAML parse error) always "fails closed," blocking a perfectly valid merge from ever landing.
- **Suggested fix:** Add `python3-yaml` (or `pip install --user pyyaml` for hermes) to the same install call, or replace the check with a tool guaranteed present (`ck`/`hermes` doesn't ship one; a minimal Python `tokenize`-free grep-based structural check, or shelling to `yq` if it's ever added). Verify the exact command actually runs clean on a fresh host before shipping this as a "gate."

## Finding 2: Phase 1's "unconditional, no-flag" ClaudeKit automation is guaranteed to hit its own failure path on every fresh host, and nothing closes the loop

- **Severity:** High
- **Location:** Phase 1, section 6c + plan.md "Real-world run order"
- **Flaw:** plan.md's own documented run order is `1 (bootstrap) → 0-gh-auth → 1-claude-auth → ...` — i.e. gh-auth (Phase 2) runs *after* bootstrap (Phase 1). But Phase 1's section 6c (`ck init --global ... --install-skills`) runs unconditionally *during* bootstrap, before gh-auth has ever executed. Phase 1's own "Key Insights" documents that `--install-skills` silently no-ops without prior `gh auth` — so on a genuinely fresh host, section 6c's `warn` path fires 100% of the time, not as an edge case.
- **Failure scenario:** operator runs the amended bootstrap expecting "fresh host lands with `ck` installed and skills ready" (Phase 1 Overview). It doesn't — `~/.claude/skills` is empty every time, a `warn` is printed pointing at `0-gh-auth.sh`. No phase in this plan then re-invokes `ck init --global --install-skills` after gh-auth completes — Phase 2's "Next Steps" only says "(re-run it after this)" as prose, not a script step or a call from any of the 5 numbered scripts. The operator must remember and manually retype the exact `ck init` command from Phase 1's Implementation Steps a second time, on every fresh host, forever — the thing this whole plan exists to stop happening (see plan.md Overview: "so re-provisioning ... doesn't require redoing every manual step from memory").
- **Suggested fix:** Either have `0-gh-auth.sh` end by re-running `ck init --global --install-skills` (if ClaudeKit is present) as its own last step, or move the `ck init --install-skills` invocation out of bootstrap entirely into a numbered script that runs after gh-auth (section 6c installs `ck` + runs `ck init` *without* `--install-skills`; a later script does the skills fetch once gh is authed).

## Finding 3: `0-gh-auth.sh` reinvents a whole credential-provisioning script to fix a problem this exact host already fixed with a 2-line copy — and its second justification has zero matching consumers

- **Severity:** Medium
- **Location:** Phase 2, Overview + Context Links ("Why it matters")
- **Flaw:** Phase 2's justification is twofold: (a) unblock `ck init --install-skills`, (b) "any skill that shells out to `gh`." For (b): `grep -rln "gh auth\|gh api\|gh pr\|gh issue\|gh repo" skills/` returns **zero files** — no skill in this repo shells out to `gh`. For (a): `plans/reports/live-host-verification-260704-2009-hermes-delegation-plan-phase-status-audit-report.md:19` documents the ACTUAL fix already applied on this exact host today: "copy the skill+agent collections from ubuntu's own `~/.claude/{skills,agents}` into hermes's `~/.claude/{skills,agents}`" — a two-command `cp` + `chown`, no new credential, no new attack surface, already proven to work.
- **Failure scenario:** none technically — the script would work. The complaint is proportionality: building a full numbered script with PAT-scope documentation, STDIN-piping hygiene, `GH_TOKEN` env precedence rules, and a dedicated Security Considerations section, to solve a problem whose only real-world instance on this host was already solved today by a 2-line local copy from an existing populated directory on the SAME box. For a single-operator personal host, the copy approach has a strictly smaller blast radius (no new PAT, no new revocable credential to manage) than minting and storing a GitHub PAT for hermes.
- **Suggested fix:** Document the local-copy alternative in Phase 2's header as the "if ubuntu's `~/.claude` is already populated" fast path, and gate the full gh-auth flow as the fallback for genuinely-fresh boxes where no populated `~/.claude` exists to copy from.

## Finding 4: Phase 6 builds bespoke idempotent YAML-block-replace logic for a script normally invoked exactly once per host

- **Severity:** Medium
- **Location:** Phase 6, "Architecture" / "Idempotency" ("if a `delegation:` block already exists in the live config, replace it rather than append... detect + replace")
- **Flaw:** Phase 6's own header states "Run order: LAST — after a `ccs_profile` exists," and its Next Steps say the very next action after this script is the one-time, `[HUMAN]`-only `/delegate_code` test — i.e., this script is designed to run once per host, immediately followed by a human-supervised smoke test. Building bash/sed-level "detect an existing top-level `delegation:` key, delimit its extent, replace only that block, leave the rest of the YAML untouched" logic is real complexity (YAML doesn't have unambiguous "block extent" without an indentation-aware parser) for a re-run case (rotating to a different `ccs_profile` name) that a single operator, who already gets a `.bak` and is told to manually restart the service by hand, could just as easily open in an editor.
- **Failure scenario:** the "replace, don't duplicate" mechanism is never given a concrete algorithm in the plan (no awk/sed sketch, unlike Phase 3's explicit "temp-file rewrite, not `sed -i`" guidance) — it's asserted as a requirement without a described implementation, for a scenario (credential rotation on a personal box) that will happen rarely and under direct human supervision anyway.
- **Suggested fix:** Cut the auto-replace requirement; have the script `die` with a clear message if `delegation:` already exists ("already configured — edit `config.yaml` by hand to change the profile, or remove the block first"), avoiding a home-grown YAML-block splicer for a single-operator, rarely-re-run maintenance script.

## Finding 5: Phase 4's `--force` "overwrite" semantics for `ccs api create` are asserted as VERIFIED but no cited verification trail actually confirms that behavior

- **Severity:** Medium
- **Location:** Phase 4, "Key Insights" ("VERIFIED syntax (`ccs api create --help`): ... `--force` bypasses validation/overwrite")
- **Flaw:** Searching every prior verification record in this repo's plan history (`plans/260703-1738-fix-urgent-hermes-delegation-issues/research/live-host-verification-findings.md`, its red-team reports, and the design doc) for `--force` turns up exactly one hit — describing `deploy-systemd-units.sh`'s unrelated stale-canonical guard flag, not `ccs api create`'s. No `ccs api --help` transcript anywhere in this repo's plan history documents `--force`'s actual behavior on re-running `api create` against an existing profile name.
- **Failure scenario:** Phase 4's idempotency requirement ("`--force` overwrites cleanly" — Success Criteria) rests on an unverified assumption. If `ccs api create <name> --force` in fact errors ("profile exists, use a different command") rather than overwriting, step 4's "Idempotency check" fails at execution time, and the plan's stated idempotency guarantee for this script doesn't hold.
- **Suggested fix:** Before finalizing the script, run `ccs api create ccs-hermes ... --force` twice in a row on a real host (or `ccs api --help`'s actual text) and record the verified behavior — the same rigor Phase 4 already applies to the base `ccs api create` syntax.

## Contract Verifier Results

Enumerated actual consumers via `grep -rn` (excluding this plan's own files and other plan-history noise):

- **`delegation.ccs_profile` (value `ccs-hermes`):** 2 functional consumers — `templates/config/production.yaml:193` (source value) and `skills/dev/coding-agent-delegate/SKILL.md:48,85,87` (documentation describing how the value is consumed by the external Hermes gateway). No code in this repo reads the field at runtime (confirmed by prior plan's own finding: `plans/260703-1041-.../reports/from-code-reviewer-to-planner-red-team-assumption-destroyer-plan-review-report.md:54` — "zero consumers... external Hermes gateway"). Phase 6 only needs to keep `production.yaml`'s value in sync with what Phase 4/5 actually creates — it does (hardcodes `ccs-hermes`, matching `:193`, per Phase 4's own DRY note). No missed caller.
- **`ANTHROPIC_API_KEY`:** 8 functional file locations — `scripts/vps-bootstrap-oci.sh:180-181`, `scripts/vps-bootstrap.sh:164-165` (both scaffold the same line), `templates/config/production.yaml:26`, `templates/config/security-hardened.yaml:51`, `templates/config/cost-optimized.yaml:26`, `templates/config/telegram-bot.yaml:20`, `templates/config/minimum.yaml:18` (all reference `${ANTHROPIC_API_KEY}` for `api_key:`), plus doc mentions (`README.md:389`, `docs/quickstart.md`, `part1-setup.md`). Phase 3 only touches the OCI-scaffolded `.env` line and correctly doesn't touch any of the 5 config templates (it writes an env var value, not a template edit) — no missed caller.
- **Skill symlink pattern (`ln -sfn ... skills/*/*/`):** 2 consumers — `scripts/vps-bootstrap.sh:144-149` and `scripts/vps-bootstrap-oci.sh:160-165` (functionally identical blocks, one per bootstrap variant). This plan's Phase 1 inserts new sections 6c/6d immediately *before* this block (confirmed: section 6b ends `:155`, section 7 with the symlink loop starts `:158`) and does not modify it — correctly out of scope, no missed caller. Note: `vps-bootstrap.sh`'s equivalent block is never touched per decision 2 — consistent with the plan's stated scope, not a gap.
- **`production.yaml`'s live-config counterpart:** confirmed the actual live `/home/hermes/.hermes/config.yaml` was seeded from `cost-optimized.yaml` (`scripts/vps-bootstrap-oci.sh:172`), which has **no** `delegation:` key at all (`grep -n "^[a-z_]*:" templates/config/cost-optimized.yaml` — 7 top-level keys, no `delegation`). Phase 6 correctly treats "block absent" as the expected baseline case, consistent with the prior plan's own live verification (`grep -c "^delegation:" ~/.hermes/config.yaml` → 0). No contradiction found.

## Unresolved Questions

None — all findings are backed by direct grep/read evidence cited above.
