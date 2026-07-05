---
phase: 6
title: "Integration Verification And Docs"
status: pending
effort: "1h5m"
---

# Phase 6: Integration Verification And Docs

**Priority:** P1 · **Status:** pending · **Effort:** ~1h5m · **Blocked by:** Phases 1, 2, 3, 5 (Phase 1's `/opt` reconcile — for the skill symlink source; crash-fix + auth + CCS smoke-test all green) · **Ownership:** repo docs + one out-of-repo memory file + host-side wiring (skill symlink, live-config merge)

## Context Links

- Debug report layer 4b (sandboxed delegation writes untested): `plans/reports/ck-debug-260703-1725-hermes-seccomp-claude-sigsys-stale-unit-report.md`.
- Stale sentence to fix: `skills/dev/coding-agent-delegate/SKILL.md:48`.
- Memory file (already exists, tracks CLI status): `/home/ubuntu/.ccs/instances/ken/projects/-home-ubuntu-workspace-hermes-optimization-guide/memory/project_oci_hermes_coding_agent_cli_status.md`.
- Changelog format reference: `CHANGELOG.md` (dated `## YYYY-MM-DD — Title` → `### Added`/`### Changed`).

## Overview

First land two host-side wiring steps that the earlier phases don't cover but that `harness: ccs` genuinely needs (both discovered via red-team, both verified live): (1) the `coding-agent-delegate` skill is NOT symlinked into the live hermes skill catalog, and (2) the live `/home/hermes/.hermes/config.yaml` has NO `delegation:` block at all. Without both, the real bot task cannot invoke `/delegate_code` or route through CCS no matter how well Phases 2–5 went. Then prove the real, sandboxed service path works (not just the plain-shell proxies from Phases 2/3/5), and reconcile the docs those phases made stale. **The authoritative test is a real `/delegate_code` task through the running bot — `[HUMAN]`-only, with NO agent fallback** (a plain-shell re-run does not exercise the sandboxed path and would silently downgrade the gate).

## Key Insights

- The per-phase checks (2/3/5) run from plain `sudo -u hermes` shells — **not** the systemd-sandboxed `hermes gateway run` process. A plain-shell pass does not prove the sandboxed service path works (org memory `feedback_verify_full_pipeline_not_first_layer`: after fixing one layer, test the next). The true gate is a real bot delegation.
- **The `coding-agent-delegate` skill is NOT in the live catalog (verified: `grep -rl coding-agent-delegate ~hermes/.hermes/skills/` → exit 1).** The other three `skills/dev/*` skills ARE symlinked from `/opt` (bootstrap loop, `vps-bootstrap-oci.sh:158-160`), but `/opt`'s `skills/dev/` lacks a `coding-agent-delegate` folder until Phase 1's reconcile lands it. Existing symlink pattern: `~/.hermes/skills/pr-review -> /opt/hermes-optimization-guide/skills/dev/pr-review/`. Must be symlinked (from reconciled `/opt`) before the real-task gate can invoke `/delegate_code`.
- **The live running config has NO `delegation:` block (verified: `sudo -u hermes grep -c "^delegation:" ~/.hermes/config.yaml` → 0).** The service reads `HERMES_CONFIG=/home/hermes/.hermes/config.yaml` (unit `Environment=`, line 27), NOT the repo's `templates/config/production.yaml`. The `delegation:` block (routing table + `ccs_profile: ccs-hermes`) at `production.yaml:168-193` must be merged into the LIVE file, or `harness: ccs` stays unreachable in production even after every other phase succeeds.
- **No non-interactive admin trigger exists for the real task.** README describes Telegram / browser admin panel / Kanban lanes (Part 12) — all human-interactive; grep found no documented CLI/API to send a task headlessly. So the real-task gate is genuinely `[HUMAN]`-only (Finding 9), not a matter of preference.
- `SKILL.md:48`'s "**ClaudeKit itself … is a separate prerequisite this guide does not install**" becomes misleading once Phase 4 provisions it — reframe into documented provisioning steps (mechanism, no phase numbers — per `~/.claude/rules/review-audit-self-decision.md` rule 5). Must cite **`claudekit-cli`** (not `claudekit`) and be honest that it is **provisioned manually per-host** — unlike its four sibling CLIs, it is NOT in `vps-bootstrap*.sh` (verified: `grep -n "claudekit\|ck init" scripts/vps-bootstrap*.sh` → no match).
- The memory file already tracks CLI status — **append, don't duplicate**.
- The **CHANGELOG documents guide-artifact changes** (the new deploy script, the SKILL.md reframe), **not host-operational state** (installing ccs on our box is not a guide change). Host state → the memory file.
- `part18-coding-agents.md:87,91` phrase the ClaudeKit dependency conditionally ("if `~/.claude/` does not exist") — it stays generically true for a fresh reader, so it is **not** categorically stale like `SKILL.md:48`. Flag for tone review only, not a required edit (and it is outside this phase's ownership).

## Requirements

`coding-agent-delegate` skill symlinked into the live catalog; `delegation:` block present in the live `config.yaml`; end-to-end delegation verified through the real bot (`[HUMAN]`); `SKILL.md` Prerequisites accurate; memory file updated; a CHANGELOG entry for the repo-artifact changes.

## Architecture

Wire the live host (symlink the skill from reconciled `/opt`; merge the `delegation:` block into `/home/hermes/.hermes/config.yaml`) → verify (real bot task, sandboxed path, `[HUMAN]`) → reconcile docs (`SKILL.md`, memory, `CHANGELOG.md`).

## Related Code Files

- **Modify:** `skills/dev/coding-agent-delegate/SKILL.md` (Prerequisites, ~line 48).
- **Modify:** `CHANGELOG.md` (new dated entry).
- **Modify (out of repo, not committed):** `…/memory/project_oci_hermes_coding_agent_cli_status.md` (append).
- **Host-side (not repo files):** create symlink `/home/hermes/.hermes/skills/coding-agent-delegate -> /opt/hermes-optimization-guide/skills/dev/coding-agent-delegate/`; merge the `delegation:` block into the live `/home/hermes/.hermes/config.yaml`.
- **Do NOT edit** `part18-coding-agents.md` — outside ownership; flagged as a follow-up.

## Implementation Steps

1. `[AGENT]` **Symlink the delegate skill into the live catalog** (needs Phase 1's `/opt` reconcile so the source exists): `sudo -u hermes ln -sfn /opt/hermes-optimization-guide/skills/dev/coding-agent-delegate/ /home/hermes/.hermes/skills/coding-agent-delegate` (mirrors the bootstrap loop pattern). Verify: `sudo -u hermes ls -la ~/.hermes/skills/coding-agent-delegate` resolves to the `/opt` target.
2. `[AGENT]` **Merge the `delegation:` block into the LIVE config the service reads** (`HERMES_CONFIG=/home/hermes/.hermes/config.yaml`, NOT the repo template). Back up first: `sudo -u hermes cp ~/.hermes/config.yaml ~/.hermes/config.yaml.bak`. Append/merge the `delegation:` block (routing table + `ccs_profile: ccs-hermes`) from `/opt/hermes-optimization-guide/templates/config/production.yaml:168-193` (post-reconcile) into the live file; validate YAML (`sudo -u hermes bash -c 'python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" ~/.hermes/config.yaml'` or equivalent). Verify: `sudo -u hermes grep -A2 '^delegation:' ~/.hermes/config.yaml`. **The service must reload config (a restart) to route via `harness: ccs`** — fold this restart into the `[HUMAN]` gate below (same downtime/in-flight considerations as Phase 2), do not bounce the service twice.
3. `[HUMAN]` **The true completion gate — no agent fallback.** Trigger one real `/delegate_code` task via the bot (Telegram / browser admin panel — the only mechanisms that exist; no non-interactive admin trigger was found). This is the ONLY step that exercises the sandboxed service path end-to-end. **An autonomous `/ck:cook --parallel` run MUST block/flag this for a human — it may NOT silently substitute the Phase 2/3/5 plain-shell proxies (they never exercise `ProtectHome`/`ReadWritePaths` and would downgrade the gate).** Concrete success signal: the bot's reply arrives without an error, AND `journalctl -u hermes` shows the delegated task completing with **no** `SIGSYS`/`Bad system call`, **no** `EROFS`, and **no** auth error.
4. `[AGENT]` Rewrite `SKILL.md:48`'s stale sentence. Replace "ClaudeKit itself … this guide does not install — `harness: ccs` without it produces identical (zero-harness) behavior to `harness: bare`" with the provisioning mechanism (no phase refs): ClaudeKit (`~/.claude/`) is provisioned for the service user via `npm install -g claudekit-cli` + `ck init --global --kit engineer`; once present, both `harness: bare` and `harness: ccs` load the full CK harness on this host (harness is gated by `~/.claude/` presence, not ccs-vs-bare). **State plainly that ClaudeKit is provisioned MANUALLY per-host — it is NOT in `vps-bootstrap*.sh` like the four sibling CLIs** (adding it to bootstrap is a flagged follow-up). Keep the surrounding wizard/smoke-test lines intact.
5. `[AGENT]` Append to the memory file: ccs `@8.7.0` (record resolved integrity hash from Phase 4) + `claudekit-cli` `<installed version>` provisioned for hermes; `~/.claude/` present; `coding-agent-delegate` skill symlinked; `delegation:` block merged into live config; profile `ccs-hermes` smoke-tested; P0 seccomp unit deployed. Don't duplicate existing lines.
6. `[AGENT]` Add a `CHANGELOG.md` entry (`## 2026-07-03 — …`) covering the **repo-artifact** changes only: the new `scripts/deploy-systemd-units.sh` (unit-drift prevention) + the `SKILL.md` Prerequisites reframe (ClaudeKit — via `claudekit-cli` — now documented/provisioned, no longer "out of scope"). Do NOT record host installs, the skill symlink, or the live-config merge as guide changes (those are host state → memory file).

## Todo List

- [ ] `coding-agent-delegate` skill symlinked into live catalog; symlink resolves to `/opt`.
- [ ] `delegation:` block merged into live `~/.hermes/config.yaml` (backed up first; YAML valid; `grep -A2 '^delegation:'` confirms).
- [ ] Real bot `/delegate_code` verified by a **human** (`[HUMAN]`-only gate — NO agent proxy fallback).
- [ ] `SKILL.md:48` reframed (mechanism only, no phase numbers; cites `claudekit-cli`; "manual per-host").
- [ ] Memory file appended (no duplication; includes `ccs` integrity hash + `claudekit-cli` version).
- [ ] `CHANGELOG.md` entry added (repo artifacts only).

## Success Criteria

Skill symlink resolves + `delegation:` block present in the live config; a real delegated task completes via the bot (no SIGSYS/EROFS/auth error in `journalctl -u hermes`); `SKILL.md` no longer claims ClaudeKit is uninstalled; memory + changelog current.

## Risk Assessment

| Risk | L×I | Mitigation |
|------|-----|------------|
| **Skill not symlinked → `/delegate_code` can't be invoked** | (was live) | Step 1 symlinks it from reconciled `/opt`; verified to resolve before the gate. |
| **Live config lacks `delegation:` block → `harness: ccs` unreachable in prod** | (was live) | Step 2 merges the block into the live `config.yaml` (backup + YAML-validate); `grep` confirms; restart reloads it. |
| Autonomous run silently downgrades the gate to plain-shell proxies | M×H | Step 3 is `[HUMAN]`-only with NO agent fallback; `/ck:cook --parallel` must block/flag it, not substitute proxies. |
| **`~/.npm` EROFS (live, already reproducing) sinks the real task for an unrelated reason** | M×M | Known pre-existing gap: `/home/hermes/.npm` is not in `ReadWritePaths` and `ProtectHome=read-only` blocks writes there. **Do NOT widen `ReadWritePaths`** (avoid extra attack surface for a secondary concern). **Scope the real gate task to avoid `npm install`/`npm ci`** so a failure there isn't misattributed to this plan's fixes. |
| OAuth token exfiltratable by a same-UID delegated sub-session (accepted) | M×H | Same accepted risk as Phase 3 (documented, not mitigated this pass); the real task may exercise a sub-session with `Bash` that can read `~/.claude*`. `CLAUDE_CONFIG_DIR` isolation deferred as a follow-up. |
| Sandboxed delegation writes fail under `ProtectHome=read-only` (debug report layer 4b) — **the RW-path "must be live" concern belongs here, not Phase 5** (Finding 18) | M×H | `ReadWritePaths=/home/hermes/.ccs` (Phase 2's deploy) must be live for the *sandboxed* consumer's CCS state; if the real task fails on other state writes, redirect via `CLAUDE_CONFIG_DIR`/`XDG_STATE_HOME` under `.hermes/` (existing pattern, `hermes.service:31`) rather than widening `ReadWritePaths`. Flagged, not pre-solved. |
| CHANGELOG accuracy depends on Phase 1 having landed | L×L | Phase 1 is now a listed blocker of Phase 6, so it lands first; scope the entry to what has landed. |
| `SKILL.md` reframe references phase numbers | L×L | Rule 5 — mechanism/commands only. |
| CHANGELOG describes host state as a guide change | M×L | Scope strictly to repo artifacts (deploy script + SKILL.md reframe); skill symlink + live-config merge are host state → memory file. |
| `part18` drifts vs the new `SKILL.md` | M×M | `part18:87,91` remain conditionally accurate; flag as a follow-up + open question (should its top-level tone also change?), out of this phase's ownership. |

## Security Considerations

Verifying real delegation may exercise write/exec tools in a sub-session — keep the tool allowlist minimal (SKILL.md security note). **A sub-session with `Bash` can read the hermes OAuth token (`~/.claude*`) and exfiltrate it — accepted risk from Phase 3, restated here** (same-UID, `ProtectHome=read-only` = readable). No new secrets are introduced by this phase. Editing the live `config.yaml` touches production routing — back it up and YAML-validate before the reload. The memory file lives under `/home/ubuntu/.ccs/…` (outside the repo tree) — it is **not** committed, so host-specific detail (integrity hashes, profile name) is fine there; keep the public `CHANGELOG.md` free of seat identity, keys, or host paths.

## Rollback

Doc-only edits: `git checkout -- skills/dev/coding-agent-delegate/SKILL.md CHANGELOG.md`; the memory-file append is removable. Host-side: `sudo -u hermes rm /home/hermes/.hermes/skills/coding-agent-delegate` (removes the symlink); `sudo -u hermes cp ~/.hermes/config.yaml.bak ~/.hermes/config.yaml` (restores the pre-merge live config) then restart to reload. The verification step itself has no state to roll back.

## Next Steps

Final phase — completes the plan. Follow-ups (out of scope, tracked as open questions): (a) add `claudekit-cli` + `ck init` to `vps-bootstrap*.sh` section 6b for repeatable provisioning (see Phase 4); (b) review `part18-coding-agents.md:87,91` tone now that ClaudeKit is documented as provisionable; (c) `CLAUDE_CONFIG_DIR` isolation for the OAuth token (Phase 3 accepted-risk follow-up).
