---
title: "Design: split delegation-provisioning steps out of vps-bootstrap-oci.sh into numbered scripts"
date: 2026-07-04
type: brainstorm-summary
next: /ck:plan
---

# Problem

`scripts/vps-bootstrap-oci.sh` bootstraps a fresh OCI host but doesn't cover what today's session actually did by hand to get `harness: ccs` delegation working: `gh auth`, ClaudeKit install, skills' Python venv, `claude auth`, `ccs api create`, merging `delegation:` into the live config. Want the script(s) to reflect reality so re-provisioning (or a future fresh host) doesn't require redoing all of today's manual steps from memory.

# Decisions (via AskUserQuestion, this session)

1. **Interaction model:** flag/env-var gated, NOT interactive prompts — script(s) stay `curl | sudo bash`-safe.
2. **File scope:** only the OCI variant; `vps-bootstrap.sh` (generic VPS) untouched, no parity effort.
3. **Bridge option (reuse an existing personal CCS instance like "ken"):** ship it, but **internal-fork-only** — this fork (`lucastran1991/hermes-optimization-guide`) will not upstream it to `OnlyTerp/hermes-optimization-guide`. Loud warning comments, not silent.
4. **ClaudeKit + skills `install.sh`:** auto-run unconditionally in the bootstrap script itself (free, local, non-interactive, matches the existing pattern for the other 4 CLIs) — no flag needed.
5. **Code structure:** decompose into **separate numbered scripts**, one job each, independently re-runnable later (e.g. to rotate a bot account without touching bootstrap) — mirrors this repo's existing precedent of splitting `deploy-systemd-units.sh` out of the monolithic bootstrap for the same bootstrap-time-vs-maintenance-time reason.

# Design

## A. `vps-bootstrap-oci.sh` — two new unconditional sections (no flags)

- **New section 6c — ClaudeKit:** `npm install -g claudekit-cli` (as hermes) → `ck init --global --kit engineer --yes --install-skills --skip-setup`. Known gotcha (already lived through today): `--install-skills` silently produces an **empty** `~/.claude/skills` if hermes has no `gh auth` yet — exit code stays 0. Detect this (`[ -z "$(ls -A ~/.claude/skills 2>/dev/null)" ]`) and `warn` pointing at the new `0-gh-auth.sh` + a manual re-run of `ck init --global --install-skills`, instead of silently claiming success.
- **New section 6d — skills Python venv:** `~/.claude/skills/install.sh -y`, run from hermes's own home (`sudo -u hermes -i bash -c '...'` — must use `-i`, not bare `bash -c`, per today's confirmed CWD gotcha where a bare `bash -c` inherits the caller's cwd and `ck`/install.sh try to write into it).

## B. New directory `scripts/provision-hermes-delegation/` — numbered, independent, flag/env-driven

| Script | Purpose | Non-interactive mechanism |
|---|---|---|
| `0-gh-auth.sh` | `gh auth login` for hermes | `--token=<PAT>` or `$GH_TOKEN` → `gh auth login --with-token` |
| `1-claude-auth.sh` | Claude Code credential for hermes | `--api-key=<key>` → writes `ANTHROPIC_API_KEY` into hermes's `.env` (simplest fully-scriptable path; real OAuth `claude auth login`/dedicated seat stays a documented manual alternative, not scripted — it needs a browser) |
| `2-ccs-profile.sh` | Real, dedicated CCS API profile | `--preset=<glm\|km\|anthropic> --api-key=<key>` → `ccs api create ccs-hermes --preset ... --api-key ... --target claude --yes` (the plan's own documented non-interactive emergency form; accepted `ps`/history trade-off) |
| `3-ccs-reuse-bridge.sh` | **Internal-fork-only.** Copy an existing personal CCS instance's credential to hermes as a stopgap | `--instance=<name>` → copies `/home/ubuntu/.ccs/instances/<name>/` to `/home/hermes/.ccs/instances/<name>/`. Header comment block: NOT for the public guide, shared-quota/impersonation risk, matches `[[hermes-temporarily-shares-ubuntu-personal-claude-credential]]` |
| `4-merge-delegation-config.sh` | Wire the `delegation:` block into the live config | `--ccs-profile=<name>` (either `ccs-hermes` from script 2, or the bridge instance name from script 3) → backup `config.yaml.bak`, append block, YAML-validate, print a reminder that `hermes.service` needs a restart to reload (does **not** restart itself — same reasoning as today: fold into the real delegation test, don't double-bounce) |

Run order for a from-scratch host: `vps-bootstrap-oci.sh` → `0` → `1` (or accept-risk equivalent) → `2` or `3` → `4` → manual real `/delegate_code` test (still `[HUMAN]`-only, no script can substitute it).

# Alternatives considered, rejected

- **Everything in `vps-bootstrap-oci.sh`** — rejected per decision 5: couples one-time bootstrap with independently-repeatable maintenance actions (e.g. rotating a bot account later would mean re-running the whole bootstrap flag set).
- **One combined `provision-hermes-delegation.sh`** — rejected: less granular than what was asked; user wants per-step numbered scripts, runnable individually.
- **Interactive prompts** — rejected per decision 1: breaks the `curl | sudo bash` one-liner pattern this repo's install docs rely on.

# Open items for `/ck:plan`

- Exact flag names/parsing boilerplate per script (mirror `deploy-systemd-units.sh`'s existing `--force`-style arg loop).
- Whether `3-ccs-reuse-bridge.sh`'s warning belongs only in the script header, or also needs a one-time confirmation gate (e.g. require `--i-understand-the-risk` alongside `--instance=`) given it's destined to live in a repo, not just a throwaway local file.
- README/CHANGELOG update scope (new directory needs at least a one-line Repo Map mention; CHANGELOG entry should NOT claim this is upstream-public guidance per decision 3).

# Unresolved questions

None blocking — all 5 architecture decisions confirmed via AskUserQuestion this session.
