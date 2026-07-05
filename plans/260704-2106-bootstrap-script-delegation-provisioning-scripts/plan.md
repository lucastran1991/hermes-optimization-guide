---
title: "Automate Hermes Delegation Provisioning: Bootstrap Additions + Numbered Scripts"
description: ""
status: in-progress
priority: P2
branch: "main"
tags: []
blockedBy: []
blocks: []
created: "2026-07-04T21:08:22.052Z"
createdBy: "ck:plan"
source: skill
---

# Automate Hermes Delegation Provisioning: Bootstrap Additions + Numbered Scripts

## Overview

Automate the Hermes-agent delegation provisioning that today's session did BY HAND on the live OCI host (`gh auth`, ClaudeKit + skills venv, `claude` credential, `ccs api create`, merging the `delegation:` block into the live config). Turn the repeatable parts into scripts so re-provisioning this host — or standing up a fresh one — doesn't require redoing every manual step from memory.

Two work products:
1. **`scripts/vps-bootstrap-oci.sh` additions** (Phase 1) — two new UNCONDITIONAL sections (6c ClaudeKit + `ck init`; 6d skills `install.sh -y`), auto-run, no flags — matching the existing unconditional pattern for the other 4 coding-agent CLIs in section 6b. `scripts/vps-bootstrap.sh` (generic non-OCI) is OUT of scope.
2. **New `scripts/provision-hermes-delegation/` directory** (Phases 2–6) — small, numbered, single-job, independently re-runnable, flag/env-driven scripts. Mirrors this repo's precedent of splitting `scripts/deploy-systemd-units.sh` out of the monolithic bootstrap: bootstrap-time concerns stay in bootstrap; independently-repeatable maintenance actions (rotating a bot account later, re-auth, etc.) get their own scripts.

**Design constraints (confirmed via AskUserQuestion, not up for renegotiation):**
- Flag/env gated, NEVER interactive prompts — every script stays safe under `curl | sudo bash` / non-interactive use.
- Each script does ONE job, re-runnable in isolation.
- Phase 5 (`3-ccs-reuse-bridge.sh`) is INTERNAL-FORK-ONLY — never upstreamed to `OnlyTerp/hermes-optimization-guide`; carries a loud in-script header warning.

Full rationale: `plans/reports/from-brainstorm-to-planner-260704-2053-bootstrap-script-delegation-provisioning-design.md`.

This is PLAN-WRITING scope only for the scripts — the actual script files + the README/CHANGELOG edits get written when this plan is EXECUTED, not before.

## Execution Status (2026-07-05)

All 6 phases' file deliverables are authored and code-reviewed. Code review (mandatory `code-reviewer` subagent pass) found 1 critical shell-command-injection bug in `2-ccs-profile.sh` (`--preset`/`--api-key` were string-concatenated into a `bash -c` source instead of passed via env-var indirection — fixed, verified closed with a live PoC) plus 5 minor findings (a stale doc claim in `skills/dev/coding-agent-delegate/SKILL.md` re: ClaudeKit bootstrap coverage, a similar stale claim in this session's CHANGELOG.md draft re: which bootstrap variant changed, a missing `chmod 600` on credentials copied by `3-ccs-reuse-bridge.sh`, a missing charset gate on `--ccs-profile` in `4-merge-delegation-config.sh`, and a wording fix mischaracterizing `0-gh-auth.sh`'s auth mechanism) — all fixed in the same session.

**Live-host actions are intentionally NOT performed by this cook session** (deploying `deploy-systemd-units.sh`, restarting `hermes.service`, running any of the 5 numbered scripts with real credentials against the hermes host): these remain human/operator-run steps per this plan's own scope boundary (Phase 1's "Deploy" step, Phase 6's "does NOT restart the service" note) — no phase can reach a fully-verified `completed` state without them. Each phase file below is marked `in-progress`, not `completed`, for this reason. See per-phase "Execution Status" notes for the artifact-level vs runtime-level breakdown of each phase's Success Criteria.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Bootstrap ClaudeKit And Skills Setup](./phase-01-bootstrap-claudekit-and-skills-setup.md) | In progress — files authored + reviewed; live deploy/restart pending |
| 2 | [GH Auth Script](./phase-02-gh-auth-script.md) | In progress — script authored + reviewed; live run pending |
| 3 | [Claude Auth Script](./phase-03-claude-auth-script.md) | In progress — script authored + reviewed; live run pending |
| 4 | [CCS Profile Script](./phase-04-ccs-profile-script.md) | In progress — script authored + reviewed (injection fix applied); live run pending |
| 5 | [CCS Reuse Bridge Script](./phase-05-ccs-reuse-bridge-script.md) | In progress — script authored + reviewed; live run pending |
| 6 | [Merge Delegation Config And Docs](./phase-06-merge-delegation-config-and-docs.md) | In progress — script + docs authored + reviewed; live run pending |

## Dependencies

**Related plan (informational, NOT a hard blocker):** `plans/260703-1738-fix-urgent-hermes-delegation-issues/` (still `status: pending`) documents the manual, live-host provisioning this plan automates. Its phase-03 (claude-auth) and phase-05 (ccs-profile) hold the established Security/Risk analysis for those exact topics — Phases 3 and 4 here cross-reference them rather than re-deriving. This is a same-scope reference, not `blockedBy`.

**File ownership — all 6 phase deliverables are disjoint (no concurrent-write conflict):**
- Phase 1 → `scripts/vps-bootstrap-oci.sh` (new sections 6c/6d) + `templates/systemd/hermes.service` (Step 0 PATH fix — red-team F1). Both disjoint from every other phase.
- Phase 2 → `scripts/provision-hermes-delegation/0-gh-auth.sh` (new).
- Phase 3 → `scripts/provision-hermes-delegation/1-claude-auth.sh` (new).
- Phase 4 → `scripts/provision-hermes-delegation/2-ccs-profile.sh` (new).
- Phase 5 → `scripts/provision-hermes-delegation/3-ccs-reuse-bridge.sh` (new).
- Phase 6 → `scripts/provision-hermes-delegation/4-merge-delegation-config.sh` (new) + `README.md` + `CHANGELOG.md`.

No phase `blockedBy` another for AUTHORING (all files disjoint, all independently authorable). But at execution/verification time, **Phase 1 Step 0 (the hermes.service PATH fix, red-team F1) is a hard prerequisite for every other phase's smoke test** — until it lands, every `sudo -u hermes -i` smoke test gives a false positive (the login shell masks the exit-127 PATH bug the real sandbox hits). Ordered first for this reason.

**Real-world run order for a from-scratch host:**
`1` (bootstrap + Step 0 PATH fix, FIRST — deploy the unit via `deploy-systemd-units.sh`) → `0-gh-auth` → `1-claude-auth` (or accept-risk equivalent) → `2-ccs-profile` OR `3-ccs-reuse-bridge` (pick one) → `4-merge-delegation-config` → manual real `/coding-agent-delegate` test.

The final `/coding-agent-delegate` end-to-end test is `[HUMAN]`-only and OUT of this plan's scope — no script can substitute it (same human-gate boundary as the related plan's Phase 6). Phase 6's `4-merge-delegation-config.sh` functionally needs a `ccs_profile` name that only exists after Phase 4 OR Phase 5 has run against a host, so it is normally used LAST — noted in its Overview.

**<!-- Corrected 2026-07-04 evening: command-name fix -->** The bot command is `/coding-agent-delegate`, not `/delegate_code` — Hermes derives the slash-command from the skill's frontmatter `name:` field (`agent/skill_commands.py:400,513` in `hermes-agent` source), never from prose. `/delegate_code` never existed under any resolution path; `skills/dev/coding-agent-delegate/SKILL.md`'s own docs previously said otherwise and were corrected the same session (verified live: `resolve_skill_command_key('delegate_code')` → `None`, `resolve_skill_command_key('coding-agent-delegate')` → `/coding-agent-delegate`). See `[[project_hermes-telegram-bot-skill-command-checklist]]` memory and `plans/reports/ck-debug-260704-2133-hermes-coding-agent-delegate-slash-command-not-in-menu-report.md` for the full evidence chain. This also confirms a SEPARATE prerequisite this plan doesn't cover: the `coding-agent-delegate` skill must actually be symlinked into `~hermes/.hermes/skills/` and the service restarted (skill-command registry is cached in-process, not just re-read from config) before the completion-gate test can succeed — tracked by the related `plans/260703-1738-fix-urgent-hermes-delegation-issues/` plan, not duplicated here.

## Red Team Review

### Session — 2026-07-04
**Findings:** 16 adjudicated — 15 accepted, 1 rejected. (4 hostile reviewers → 26 raw → deduped to 15 accepted + 1 rejected reviewer point.)
**Severity breakdown (accepted):** 7 Critical, 6 High, 2 Medium.
**Evidence:** raw reports in `reports/from-code-reviewer-to-planner-red-team-{security-adversary,failure-mode-analyst,assumption-destroyer,scope-complexity-critic}-plan-review-report.md`; adjudication `reports/from-planner-to-user-red-team-adjudication-260704-2106.md`.

| # | Finding | Severity | Disposition | Applied To |
|---|---------|----------|-------------|------------|
| 1 | `hermes.service` PATH gap — real sandbox lacks `~/.local/bin`, every delegated CLI call fails exit 127; `sudo -u hermes -i` smoke tests mask it | Critical | Accepted | Phase 1 Step 0 (new, ordered FIRST) + `templates/systemd/hermes.service` `Environment=PATH=` |
| 2 | `cp -a` copies entire ken instance (transcripts/PII/projects), not just credentials | Critical | Accepted | Phase 5 — copy only `.credentials.json` + `.claude.json` |
| 3 | `--instance=<name>` unsanitized → root-privileged path traversal | Critical | Accepted | Phase 5 — `^[a-zA-Z0-9_-]+$` allowlist gate before path build |
| 4 | `gh` CLI never installed by bootstrap — Phase 2 fails on a fresh host | Critical | Accepted | Phase 2 — idempotent keyring+apt install (NodeSource pattern) |
| 5 | Run order guarantees empty-skills bug every fresh run; no automated fix, vague pointer | Critical | Accepted | Phase 1 — warn gives EXACT recovery sequence (`0-gh-auth.sh` + literal `ck init` re-run) |
| 6 | Phase 6 YAML gate broken 2 ways: PyYAML not installed on host; `safe_load` can't catch duplicate top-level key | Critical | Accepted | Phase 6 — guard-install `python3-yaml` (F6a) + post-merge `grep -c '^delegation:' == 1` assert (F6b) |
| 7 | Phase 6 needs local `production.yaml` but no `GUIDE_DIR`/stale-clone guard — contradicts curl\|bash constraint | Critical | Accepted | Phase 6 — `GUIDE_DIR` default + `git fetch`/`rev-list` guard (mirror `deploy-systemd-units.sh`) |
| 8 | `--force` on `ccs api create` claimed "VERIFIED" with no trail; contradicts sibling plan's `--api-key --yes` | High | Accepted | Phase 4 — drop `--force`; idempotency via verified `ccs api remove` + create |
| 9 | Bridge copies `instances/<name>/` only, not root `~/.ccs/config.yaml` — profile may not resolve by name | High | Accepted | Phase 5 — merge root-config instance entry (F9), `[UNVERIFIED]` shape flagged for pre-cook check |
| 10 | New 6c idempotency guard omits the `PATH` export its cited mirror (6b) uses | High | Accepted | Phase 1 — `export PATH="$HOME/.local/bin:$PATH"` in the 6c `bash -c` block |
| 11 | ClaudeKit under `~/.claude`, outside `hermes.service` `ReadWritePaths` → `EROFS` at runtime | High | Accepted | Phase 1 — Risk row; NOT widening `ReadWritePaths`; flag `CLAUDE_CONFIG_DIR` redirection as future follow-up |
| 12 | Unverified `sudo -u hermes -i <binary>` form; only `bash -c '<cmd>'` proven working this project | High | Accepted | Phases 2, 4, 5 — all invocations use `sudo -u hermes -i bash -c '<cmd>'` |
| 13 | `delegation:` block copy-boundary mechanism unspecified; `acp:` follows it in source | High | Accepted | Phase 6 — explicit awk top-level-key terminator (exclusive) |
| 14 | Phase 3 credential gate is a bare non-empty grep, unlike 4/5's smoke test | Medium | Accepted | Phase 3 — `sk-ant-` prefix gate + non-fatal `claude -p` functional smoke |
| 15 | Wrapper scripts leak own `--token=`/`--api-key=` argv via `ps`/history — live-credential blast radius | Medium | Accepted | Phases 2–5 — canonical F15 Security note in Phase 2, cross-referenced from 3/4/5 |
| R | `0-gh-auth.sh` "solves an already-solved problem" (today's host got a manual `cp` workaround) | — | **Rejected** | No change — the `cp` workaround only worked because ubuntu's `~/.claude` was already populated; a genuinely fresh host has nothing to copy, so gh-auth automation retains real value for the plan's stated future-host purpose |

### Whole-Plan Consistency Sweep
- **Files reread:** plan.md, phase-01 … phase-06 (all 7).
- **Decision deltas checked:** 15 accepted findings across 6 phases + 1 systemd unit.
- **Reconciled stale references (3 cross-file/structural):**
  1. `plan.md` file-ownership — Phase 1 now also owns `templates/systemd/hermes.service` (was "only file: vps-bootstrap-oci.sh").
  2. `plan.md` run-order — Phase 1 re-labelled from "standalone" to "FIRST / hard verification prerequisite" (Step 0 blocks all downstream smoke tests).
  3. `phase-03` manual OAuth alternative — bare `sudo -u hermes -i claude auth login` → `bash -c` form, for F12 consistency.
  - Intra-phase reconciliations (Phase 4 `--force` removed from 6 locations: Key Insights, Requirements, Architecture, Impl step, Success Criteria, Risk row) were updated in lockstep — no dangling `--force` reliance remains.
- **Unresolved contradictions:** 0. Two `[UNVERIFIED]` items remain in Phase 5 (F9 CCS profile-resolution mechanism; exact credential filename) — flagged as pre-cook live-verification tasks, not contradictions.

### Session 2 — 2026-07-04 (evening) — Live-Debug-Driven Correction

**Trigger:** a same-day live debugging session on the actual Hermes OCI host (unrelated `/ck-debug` investigation into the Telegram bot returning "Unknown command /delegate_code") discovered this plan's completion-gate test cited a command name that never existed. `/ck:plan update ... --tdd --validate --red-team --auto --parallel` requested to fold the correction in.

**Direct correction applied (high-confidence, live-verified before editing, not a red-team finding):** `/delegate_code` → `/coding-agent-delegate` in plan.md (2 refs) and phase-06 (5 refs) — Hermes derives slash-commands from the skill's frontmatter `name:` field (`agent/skill_commands.py:400,513`), never from prose; `/delegate_code` never resolved under any code path (live-verified: `resolve_skill_command_key('delegate_code')` → `None`). Evidence: `[[project_hermes-telegram-bot-skill-command-checklist]]` memory, `plans/reports/ck-debug-260704-2133-hermes-coding-agent-delegate-slash-command-not-in-menu-report.md`.

**Scoped red-team (2 parallel reviewers, delta-only — the plan's full 4-reviewer red-team already ran in Session 1 and wasn't re-litigated):**

| # | Finding | Disposition | Applied To |
|---|---------|-------------|------------|
| A | Completeness/correctness of the `/delegate_code` → `/coding-agent-delegate` sweep, symlink+restart dependency scoping, phase-01-vs-phase-06 restart-discipline contradiction check | **Rejected (edit already correct)** — reviewer independently verified `skill_commands.py:400,513` citations, confirmed the symlink+restart dependency is already owned by the related `fix-urgent-hermes-delegation-issues` plan (not a new untracked blocker), and confirmed the two restarts (Phase 1's PATH/RWPaths fix vs Phase 6's config/cache reload) are temporally distinct, not a double-bounce | No further edit needed |
| B | Whether `delegation.routing` (the `match:`/`agent:` table Phase 6 merges into live config) is actually code-enforced or, like `repo=`/`escalate=`/`harness=`, purely LLM-interpreted prose | **Confirmed, new finding** — verified live: `hermes_cli/config.py:2051-2074`'s `delegation` defaults schema recognizes only `model, provider, base_url, api_key, api_mode, inherit_mcp_toolsets, max_iterations, child_timeout_seconds, reasoning_effort` — no `routing`/`default`/`ccs_profile` keys anywhere in code (that schema backs the unrelated native `delegate_task()` sub-agent tool, which happens to share the `delegation:` top-level key name). Precedent: `tests/hermes_cli/test_config_drift.py:11-32` documents a prior real incident of dead `delegation.*` config being removed as "never read." | Phase 6 Key Insights — added scope-clarification note (not a text correction, since no existing plan text overstated this; the note prevents a future misreading) |

**Whole-Plan Consistency Sweep (Session 2):**
- **Files reread:** plan.md, phase-06 (the 2 touched files); phase-01 through phase-05 grepped for `delegate_code`/`routing` residue — zero relevant hits (phase-01's one "routing" hit is CCS traffic routing, an unrelated sense of the word).
- **Decision deltas checked:** 1 direct correction (command name, 7 refs total) + 1 scope-clarification addition (routing table, non-functional).
- **Reconciled stale references:** all 7 `/delegate_code` occurrences (2 in plan.md, 5 in phase-06); none remained outside historical `reports/` red-team artifacts (correctly left untouched, matching this plan's own precedent for not editing dated review reports).
- **Unresolved contradictions:** 0.

## Validation Log

### Session 1 — 2026-07-04

**Trigger:** `/ck:plan create --tdd --validate --auto --parallel` — user explicitly requested `--validate`.
**Verification pass:** Skipped per `references/verification-roles.md` guard — `## Red Team Review` already has verification evidence. Limited to resolving the 2 remaining `[UNVERIFIED]` tags in Phase 5 via live host inspection (not an interview question — pure fact-gathering):
- **F9 resolved (VERIFIED):** `ccs <name> -p` resolution needs a root `~/.ccs/config.yaml` entry, not pure disk-scan. Confirmed by reading hermes's live `~/.ccs/config.yaml` directly — it has a top-level `accounts:` block with `lucas`/`ken`/`luan` entries, exact shape `{created, last_used, context_mode: isolated}` (artifact of the earlier full-config-copy bridge). Phase 5 updated to require merging this entry, not treat it as optional.
- **Credential filename resolved (VERIFIED):** `ls -la /home/hermes/.ccs/instances/ken/` confirms both `.credentials.json` (471B) and `.claude.json` (42240B) exist — matches what Phase 5's Implementation Steps already assumed; no change needed there.

**Questions asked:** 4

#### Questions & Answers

1. **[Risk]** Finding 11 (ClaudeKit outside `ReadWritePaths`, EROFS risk at real delegation runtime) is currently deferred as a future follow-up per red-team disposition. Keep deferred, or fix now in this plan?
   - Options: Defer as red-team proposed (Recommended) | Fix now by widening `ReadWritePaths` in Phase 1
   - **Answer:** Fix now by widening `ReadWritePaths` in Phase 1
   - **Rationale:** User's explicit call, against the red-team/planner default recommendation (which favored not widening RWPaths per the repo's general established posture). Accepted because this is a freshly-confirmed, freshly-installed-by-this-very-phase directory (unlike the still-genuinely-open `~/.npm` EROFS gap elsewhere) — narrower and better-understood than a blanket RWPaths widening. **Action item:** Phase 1 Step 0 now also adds `/home/hermes/.claude` to `ReadWritePaths=`, with an explicit note this is a deliberate, scoped exception, not a precedent for widening RWPaths elsewhere without the same confirmation.

2. **[Risk]** Phase 1 Step 0 requires restarting `hermes.service` — same restart mechanism already used twice today (IMDS + seccomp fixes) with an established in-flight-check-and-announce discipline. Should Phase 1 restate this discipline explicitly, or assume it's already known?
   - Options: Add explicit reminder to Phase 1 (Recommended) | Don't restate, assume known
   - **Answer:** Add explicit reminder to Phase 1
   - **Rationale:** Matches the established pattern for this exact file (`templates/systemd/hermes.service`), used twice today already. **Action item:** Phase 1 Step 0 now includes an explicit pre-deploy check (`journalctl` in-flight check + announce) before running `deploy-systemd-units.sh`.

3. **[Scope]** Phase 6's `CHANGELOG.md` entry for the new `scripts/provision-hermes-delegation/` directory — should it mention Phase 5 (`3-ccs-reuse-bridge.sh`) exists, even framed as internal-only?
   - Options: Omit entirely from CHANGELOG (Recommended) | Mention briefly with internal-only framing
   - **Answer:** Omit entirely from CHANGELOG
   - **Rationale:** The repo's remote is public-reachable on GitHub even though it's a personal fork — any CHANGELOG mention, however framed, creates a discoverable public trail. **Action item:** Phase 6 now explicitly lists which 4 scripts the CHANGELOG entry may describe (`0-gh-auth.sh`, `1-claude-auth.sh`, `2-ccs-profile.sh`, `4-merge-delegation-config.sh`) and states zero mention of the reuse-bridge; Phase 5's own Risk Assessment updated to match (full omission, not just "avoid public-guidance framing").

4. **[Scope]** Any user-facing framing of Phase 4 (dedicated CCS profile) vs Phase 5 (reuse-bridge) — present as co-equal alternatives, or Phase 5 explicitly as last-resort/fallback?
   - Options: Phase 5 as explicit last-resort (Recommended) | Present as co-equal alternatives
   - **Answer:** Phase 5 as explicit last-resort
   - **Rationale:** Matches the risk framing already established in Phase 5's own Overview ("Phase 4 is strongly preferred; Phase 5 is the stopgap") — extends that framing to any other user-facing surface (script `--help`/usage text) so it's never presented as a neutral choice. **Action item:** Phase 6 now states this framing requirement explicitly for any user-facing text beyond the plan file itself.

#### Confirmed Decisions
- EROFS fix (F11): **fixed now** via `ReadWritePaths` widening in Phase 1 — final, overrides red-team's deferred default.
- Restart discipline: **explicit in Phase 1** — final.
- CHANGELOG scope: **full omission of the reuse-bridge** — final, stricter than red-team's original "just don't frame as public guidance."
- Phase 4 vs 5 framing: **Phase 5 is last-resort everywhere it's surfaced** — final.

#### Action Items
- [x] Phase 1: `ReadWritePaths` widened with `/home/hermes/.claude`, framed as a deliberate scoped exception.
- [x] Phase 1: explicit in-flight-check + announce step added to Step 0.
- [x] Phase 6 + Phase 5: CHANGELOG/README must fully omit the reuse-bridge script, not just soften its framing.
- [x] Phase 6: Phase 4-preferred / Phase 5-last-resort framing requirement stated explicitly.

#### Impact on Phases
- Phase 1: Risk Assessment (F11 row), Implementation Steps (Step 0), Related Code Files, Success Criteria all updated.
- Phase 5: Risk Assessment (upstream-risk row) tightened to full omission.
- Phase 6: Related Code Files (docs bullets) and Success Criteria updated with the omission + framing requirements.

### Whole-Plan Consistency Sweep (Validation Session 1)
- **Files reread:** plan.md, phase-01, phase-05, phase-06 (the 3 files touched this session); phase-02/03/04 unaffected by these 4 decisions, not re-edited.
- **Decision deltas checked:** 4 (EROFS fix-now, restart discipline, CHANGELOG omission, Phase 4/5 framing) + 2 resolved `[UNVERIFIED]` tags (F9 shape, credential filename).
- **Reconciled stale references:** phase-01's F11 risk row (defer → fix-now, 3 locations: Risk Assessment, Related Code Files, Success Criteria); phase-05's upstream-risk mitigation (soften-framing → full-omission); phase-06's docs bullets + Success Criteria (added omission + framing requirements).
- **Unresolved contradictions:** 0.

### Session 2 — 2026-07-04 (evening)

**Trigger:** `/ck:plan update ... --tdd --validate --red-team --auto --parallel` — see Red Team Review Session 2 above for the triggering context and findings.

**Interview:** Skipped, same guard as Session 1 — no unspecified assumption, missing acceptance criterion, or scope/risk trade-off requiring user judgment was introduced by this update. Both changes (command-name correction, routing-table scope clarification) are facts independently verified against the live host and the real `hermes-agent` source before writing, not design decisions. `AskUserQuestion` was not invoked because there was nothing to ask — matches this plan's own precedent (Session 1) for skipping the interview when the verification pass already resolves everything in play.

**Questions asked:** 0.
