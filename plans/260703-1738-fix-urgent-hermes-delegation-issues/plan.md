---
title: "Fix Urgent Hermes Delegation Issues: Stale Unit, Auth, CCS/ClaudeKit Provisioning"
description: "Deploy the undeployed P0 seccomp fix crashing Hermes bot delegation, add unit-drift-prevention tooling, and provision claude auth + CCS/ClaudeKit so harness: ccs delegation works end-to-end."
status: in-progress
priority: P1
effort: "4h25m"
branch: "main"
tags: [infra, security, delegation, ccs, bugfix]
blockedBy: []
blocks: []
created: "2026-07-03T17:54:31.904Z"
createdBy: "ck:plan"
source: skill
---

# Fix Urgent Hermes Delegation Issues: Stale Unit, Auth, CCS/ClaudeKit Provisioning

## Overview

Fixes an actively-broken production Hermes bot and completes the delegation stack it depends on.

Root cause (full analysis: `plans/reports/ck-debug-260703-1725-hermes-seccomp-claude-sigsys-stale-unit-report.md`): the deployed `/etc/systemd/system/hermes.service` predates commit `c9631fc`, which re-allows `sched_setscheduler` in the seccomp filter. Every delegated `claude`/`opencode` invocation dies with SIGSYS ("Bad system call") — even `--version`. The fix already exists at `templates/systemd/hermes.service:82`; it was authored but never deployed. One `install`+`daemon-reload`+`restart` clears the crash.

Lineage: `plans/260703-0347-hermes-coding-agent-delegation-skill/` added the `coding-agent-delegate` skill; `plans/260703-1041-ccs-full-harness-coding-agent-delegation/` added the opt-in `harness: ccs` parameter and — at that time, by explicit decision — scoped ClaudeKit installation OUT (documented as an external, unmet prerequisite; see that plan's Unresolved Question 2). **This plan re-opens that decision by the user's explicit choice this session — EXPANSION scope selected over the HOLD / REDUCTION alternatives that were also offered.** It provisions CCS + ClaudeKit on the hermes host so `harness: ccs` delivers real harness instead of the current no-op (`skills/dev/coding-agent-delegate/SKILL.md:48`). Deliberate scope expansion, not silent drift.

Six phases: deploy the P0 fix (2), add tooling so unit-drift can't silently recur (1), authenticate `claude` for the hermes user (3), install + init CCS/ClaudeKit (4), provision the CCS delegation profile (5), verify end-to-end + reconcile the now-stale docs (6). Every host mutation is tagged `[HUMAN]` (needs root / OAuth / a real key — password-gated) or `[AGENT]` (safe under NOPASSWD `sudo -u hermes`). **`/ck:cook --parallel` MUST NOT attempt `[HUMAN]` steps.**

**Red-team pass applied (2026-07-03).** A four-reviewer red-team review was adjudicated and applied (see `## Red Team Review`). Three additions surfaced by it — reconciling the stale canonical `/opt` clone (Finding 4, Phase 1), symlinking the `coding-agent-delegate` skill into the live catalog (Finding 5, Phase 6), and merging the `delegation:` block into the live `config.yaml` (Finding 7, Phase 6) — are **necessary conditions for EXPANSION to deliver what it promised (a working `harness: ccs` in production), not optional scope creep**; they were discovered via red-team, not part of the original scope-challenge estimate, hence the effort increase (`3h25m` → `4h25m`).

**Three open trade-off questions (OAuth credential risk acceptance, Phase 1 script-vs-note scope, EXPANSION-vs-REDUCTION re-confirm) were asked via AskUserQuestion during red-team adjudication and got no response — proceeded on the recommended default for each (documented below); flag to the user for override before `/ck:cook`.** Defaults taken: (1) OAuth exfil risk is documented as ACCEPTED, not redesigned with `CLAUDE_CONFIG_DIR` isolation (Phase 3/6); (2) Phase 1 keeps BOTH the deploy-drift script AND the README note (no reduction to note-only); (3) scope stays EXPANSION with the three necessary additions above (no retreat to REDUCTION).

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Deploy-Drift Prevention Tooling](./phase-01-deploy-drift-prevention-tooling.md) | **Completed** — script live-validated (0 changed on synced host, idempotent, non-disruptive) |
| 2 | [Deploy P0 Systemd Fix](./phase-02-deploy-p0-systemd-fix.md) | **Completed** — verified: unit live, no SIGSYS since restart, claude/opencode --version both exit 0 |
| 3 | [Claude Auth For Hermes](./phase-03-claude-auth-for-hermes.md) | **Completed (2026-07-06)** — verified via real delegated `claude -p` success (Success Criteria's alternate clause), not a direct `claude auth status` check; see phase file |
| 4 | [Install CCS And ClaudeKit](./phase-04-install-ccs-and-claudekit.md) | In progress — installed, `ck doctor` has 3 accepted gh-auth FAILs |
| 5 | [Provision CCS Profile](./phase-05-provision-ccs-profile.md) | **Completed (2026-07-06)** — `production.yaml:193` confirmed `ccs-hermes`; smoke-test superseded by a real successful task run; see phase file |
| 6 | [Integration Verification And Docs](./phase-06-integration-verification-and-docs.md) | Pending — unblocked (1,2,3,5 all done) but its own Success Criteria (skill symlink, live `delegation:` block, `SKILL.md` reframe, memory/changelog sync) has no evidence any of it happened yet |

## Dependency Graph

Phases 1–4 have no interdependency (one fully-parallel group). Phase 5 needs the `ccs` binary from Phase 4. Phase 6 is the end-to-end gate and needs the crash-fix (2), auth (3), CCS smoke-test (5) — **and now Phase 1's `/opt` reconcile** (Finding 4), because Phase 6's `coding-agent-delegate` skill symlink (Finding 5) sources from the reconciled canonical `/opt` clone.

| Phase | blockedBy | Parallel group |
|-------|-----------|----------------|
| 1 Deploy-drift tooling + `/opt` reconcile | — | A (start now) |
| 2 Deploy P0 fix | — | A (start now) |
| 3 Claude auth | — | A (start now) |
| 4 Install CCS+ClaudeKit | — | A (start now) |
| 5 Provision CCS profile | 4 | B (after 4) |
| 6 Integration verify + docs | 1, 2, 3, 5 | C (after B) |

```
        ┌── 1 ─────────────────────┐
start ──┼── 2 ──┐                   │
        ├── 3 ──┼───────────────────┼─► 6  (needs 1,2,3,5)
        └── 4 ──┴── 5 ──────────────┘
```

Note: the new Phase 1 → Phase 6 edge does NOT collapse group A — Phases 1,2,3,4 still all start together; only Phase 6 (terminal) gains Phase 1 as a blocker. Phase 2 (P0) remains fully independent and should run ASAP.

## File Ownership Matrix

Only Phases 1 and 6 write repo files, and they are disjoint — safe for `/ck:cook --parallel`.

| Phase | Repo files owned | Host-only ops |
|-------|------------------|---------------|
| 1 | `scripts/deploy-systemd-units.sh` (new); `README.md` (Repo Map row + prominent deploy sentence naming the canonical `/opt` clone) | `[HUMAN]` reconcile canonical clone `/opt/hermes-optimization-guide` (`git pull --ff-only`) |
| 2 | none | `/etc/systemd/system/hermes.service` deploy + `daemon-reload` + `restart` (+ `reset-failed` on rollback) |
| 3 | none | `claude auth login` as hermes (fallback: `setup-token` / `ANTHROPIC_API_KEY`) |
| 4 | none | npm installs (`@kaitranntt/ccs@8.7.0`, `claudekit-cli`) into `~hermes/.local`, `ck init --global`, `npm audit` |
| 5 | `templates/config/production.yaml:193` **only if** the chosen profile name ≠ the already-set `ccs-hermes` (default: keep `ccs-hermes`, no edit) | `ccs api create` + smoke-test as hermes |
| 6 | `skills/dev/coding-agent-delegate/SKILL.md` (Prerequisites); `CHANGELOG.md`; the ken auto-memory file `project_oci_hermes_coding_agent_cli_status.md` (outside the repo tree — not committed) | symlink `coding-agent-delegate` into `~hermes/.hermes/skills/`; merge `delegation:` block into live `/home/hermes/.hermes/config.yaml`; `[HUMAN]` trigger a real `/delegate_code` task |

Disjointness: Phase 1 `{deploy-systemd-units.sh, README.md}` ∩ Phase 6 `{SKILL.md, CHANGELOG.md, memory}` = ∅. Phase 5's conditional `production.yaml` line overlaps neither. The new host-only ops don't touch repo files and target distinct host paths (Phase 1: `/opt` clone; Phase 6: `~hermes/.hermes/{skills,config.yaml}`) — no conflict.

**Verified correction to the brief's "Phases 2,3,4,5 write no repo files" claim:** `templates/config/production.yaml:193` is already `ccs_profile: ccs-hermes` (NOT unset). If Phase 5 keeps that name (recommended — matches `SKILL.md:183` and prior plan `260703-1041`), Phase 5 truly writes no repo file. Only a non-default rename writes that one line, owned solely by Phase 5.

## Execution Strategy

- **Pre-flight sudo-scope check (Finding 16).** Before trusting any `[AGENT]` tag in this plan, run `sudo -n -l` and confirm it matches the grants this plan assumes (`(hermes) NOPASSWD: ALL`; root NOPASSWD for `systemctl {start,stop,restart,status} hermes*`, `daemon-reload`, `journalctl -u hermes*`). If it doesn't match, treat every `[AGENT]` step as `[HUMAN]` instead. This grant is session-specific and not reproducible by repo inspection (`sudo -n cat /etc/sudoers.d/*` itself needs a password).
- **Phase 2 is P0 — a human should run it ASAP, independently of everything else.** The bot's delegation is broken right now; every `/delegate_code` SIGSYS-crashes until this deploys. Downtime is best-case ~2-5s but up to 90s worst case (no `TimeoutStopSec=` override → systemd default) if a restart lands mid-tool-call; check for in-flight activity and announce first.
- The rest of group A (1, 3, 4) is not urgency-blocking. An agent can land Phase 1's script authoring + Phase 4's installs autonomously in parallel while the human handles Phase 2, the `[HUMAN]` `/opt` reconcile (Phase 1), and the `[HUMAN]` steps of 3 and 5.
- Phase 5 after Phase 4. Phase 6 last — its real-bot delegation test is the true completion gate and is **`[HUMAN]`-only with no agent fallback** (Finding 9): plain-shell checks in 2/3/5 are proxies, not proof of the sandboxed service path, so `/ck:cook --parallel` must block/flag the gate for a human rather than substituting them.

## Dependencies

Cross-plan: **none blocking.** Prior plans `260703-0347` and `260703-1041` are both `completed`. This plan touches `templates/config/production.yaml` (Phase 5, conditional one line at :193) and `skills/dev/coding-agent-delegate/SKILL.md` (Phase 6) — files those plans also edited, but they are done, so no concurrent-write risk.

Host: the canonical on-host clone is **`/opt/hermes-optimization-guide`** (bootstrap `GUIDE_DIR`, `vps-bootstrap-oci.sh:105` / `vps-bootstrap.sh:89`); it was 2 days stale and is reconciled in Phase 1. Both fix commits (`c9631fc`, `72cc2fd`) are already in `origin/main`, and both clones share the same remote, so the reconcile is a safe fast-forward. Phases 5/6 also depend on a running `hermes gateway` and a provider credential the operator dedicates (open questions in those phases).

## Red Team Review

**Session:** 2026-07-03 · **Reviewers:** 4 (security-adversary, failure-mode-analyst, assumption-destroyer, scope-complexity-critic) · **Adjudication:** external (final; 4 most-consequential claims re-verified live by the adjudicator). This planner pass **applied** the adjudicated dispositions — it did not re-adjudicate.

**Findings:** 23 total — 6 Critical, 9 High, 8 Medium. **Dispositions:** 21 ACCEPT, 2 REJECT.
**Cap note:** the formal finding cap is 15; Mediums **16–21 are beyond cap, included for low cost / high value**; 22–23 (beyond cap) are rejected with rationale below.

| # | Finding | Severity | Disposition | Applied To |
|---|---------|----------|-------------|------------|
| 1 | Bare `sudo -u hermes <cli>` non-functional (`secure_path` lacks `.local/bin`) across P2/3/4 | Critical | ACCEPT | Phase 2 step 4, Phase 3 step 2/Reqs/Success, Phase 4 step 5/Success (all PATH-wrapped) |
| 2 | Wrong npm package (`claudekit` → `claudekit-cli` for the `ck` bin) | Critical | ACCEPT | Phase 4 Overview/Insights/step 2/rollback/Next; Phase 6 SKILL.md reframe + memory |
| 3 | Rollback omits `systemctl reset-failed` (StartLimitBurst=5 strands it) | Critical | ACCEPT | Phase 2 Rollback (first cmd) + Risk row |
| 4 | Stale canonical `/opt` clone can silently redeploy pre-fix unit | Critical | ACCEPT | Phase 1 (canonical designation, reconcile step, stale-guard, Risk); plan.md Dep Graph/Ownership/Dependencies |
| 5 | `coding-agent-delegate` skill not symlinked into live catalog | Critical | ACCEPT | Phase 6 step 1 + Insights/Risk; plan.md Dep Graph (P6 blockedBy 1) |
| 6 | OAuth token readable/exfiltratable by same-UID delegated sub-session | Critical | ACCEPT (documented risk, user default — not redesigned) | Phase 3 Security/Risk; Phase 6 Security/Risk; plan.md Overview default note |
| 7 | Live `config.yaml` has no `delegation:` block (service reads it, not the template) | High | ACCEPT | Phase 6 step 2 + Insights/Risk; Phase 5 step 3 note |
| 8 | `~/.npm` EROFS (live, reproducing) can sink the real-task gate | High | ACCEPT | Phase 6 Risk (do NOT widen RWPaths; scope task to avoid npm install) |
| 9 | Phase 6 gate has a mechanism-free fallback that downgrades it | High | ACCEPT | Phase 6 step 3 (`[HUMAN]`-only, no fallback); plan.md Execution Strategy |
| 10 | "device-code style" OAuth claim likely wrong for `2.1.199` | High | ACCEPT | Phase 3 Overview/Insights/step 1 (soften + `setup-token`/API-key fallback) |
| 11 | No in-flight check before restart; "~5s" downtime overstated (90s worst) | High | ACCEPT | Phase 2 Overview/step 1/Risk; plan.md Execution Strategy |
| 12 | Phase 1 script doesn't prevent the forgetting failure mode | High | ACCEPT (per user default: keep script + note) | Phase 1 Overview honesty + Next Steps |
| 13 | Full ClaudeKit harness auto-loads on every hermes `claude` call | High | ACCEPT (document, not narrow — user chose EXPANSION) | Phase 4 Security subsection + Risk row |
| 14 | `@kaitranntt/ccs` supply-chain trust unexamined | High | ACCEPT | Phase 4 step 4 (`npm audit` + record hash) + Risk; Phase 6 memory |
| 15 | EXPANSION doesn't deliver working `harness: ccs` without 4/5/7 | High | ACCEPT (fold into Overview) | plan.md Overview |
| 16 | Add pre-flight sudo-scope check | Medium (beyond cap) | ACCEPT | plan.md Execution Strategy |
| 17 | SKILL.md reframe must admit ClaudeKit is manual-per-host, not bootstrap | Medium (beyond cap) | ACCEPT | Phase 6 step 4 + Insights; Phase 4 Next Steps |
| 18 | Phase 5's Phase-2 `ReadWritePaths` dependency is a category error | Medium (beyond cap) | ACCEPT | Phase 5 Insights/Risk/Next; Phase 6 Risk (RW-path moved here) |
| 19 | `~/.ccs` risk surface understated ("plugins" → `hooks/`+`mcp/`) | Medium (beyond cap) | ACCEPT | Phase 4 Security; Phase 5 Security |
| 20 | Wizard UX unconfirmed; no credential-pre-check / cleanup path | Medium (beyond cap) | ACCEPT | Phase 5 Insights/step 1/Risk/Rollback (`ccs api remove`) |
| 21 | Phase 4 install-success check too weak (partial `--install-skills`) | Medium (beyond cap) | ACCEPT | Phase 4 Requirements/step 5/Todo/Success (`ck doctor` mandatory) |
| 22 | Add `--dry-run`/`--unit=` targeting flags to Phase 1 script | Medium (beyond cap) | **REJECT** | Rationale below (conflicts with confirmed Phase 1 KISS scope; no live conflict) |
| 23 | Add a "maintenance mode" for the live gateway as 3rd actor | Medium (beyond cap) | **REJECT** | Rationale below (new-feature scope; no new regression this plan introduces) |

**Rejection rationale (logged so not silently dropped):**
- **#22 REJECT:** Conflicts with the confirmed Phase 1 scope (keep it simple, don't gold-plate). Only 2 units exist today and the script's diff-based design already touches only changed units; the "unrelated mid-edit unit swept up" scenario has no live instance (`hermes-dashboard.service` verified in sync). The stale-canonical guard added for #4 already covers the real regression hazard. Defer `--dry-run`/`--unit=` until a real conflict occurs.
- **#23 REJECT:** The reviewer's own trace found no actual collision from the live gateway as a 3rd actor (the two-human race is benign — Phase 2 never touches `.ccs`). A maintenance-mode flag is new-feature scope disproportionate to the risk; the live gateway hitting "command not found"/SIGSYS mid-rollout is the SAME failure it hits today, not a new regression this plan introduces. **Recorded as an accepted, low-priority residual risk, not an action item.**

### Whole-Plan Consistency Sweep

- **Files reread/swept (post-edit):** `plan.md` + all six `phase-0[1-6]-*.md`, via targeted grep for every decision delta below.
- **Decision deltas checked:** (a) wrong npm package name `claudekit`→`claudekit-cli` outside the fix sites; (b) unwrapped `sudo -u hermes <cli>` (claude/opencode/ccs/ck/codex/gemini/command) across all 6 phases; (c) "~5s" downtime asserted as fact; (d) "device-code" OAuth claim; (e) Phase 6 `blockedBy` includes new Phase 1 edge; (f) `systemctl show`/`journalctl -k` no longer tagged `[AGENT]`/NOPASSWD; (g) "all NOPASSWD" overclaim; (h) "owner-only" OAuth framing; (i) removed "stretch" footnote; (j) stale commit SHA `9fafe6e`; (k) Phase 5's Phase-2 `ReadWritePaths` category error; (l) effort re-sum + Dependency Graph + File Ownership Matrix.
- **Reconciled stale references:** 1 — `phase-03` Context Link restated §3's "device-code / no browser" characterization; softened to defer to Finding 10. (All other grep hits were the corrections themselves or correctly-qualified `claudekit-cli`.)
- **Effort recomputed:** 80 (P1 1h20m) + 25 (P2) + 20 (P3) + 40 (P4) + 35 (P5) + 65 (P6 1h5m) = **265 min = 4h25m**, matching frontmatter (was `3h25m`).
- **Scope preserved:** `## Phases` table (CLI-owned) and every phase's `phase`/`title` frontmatter left untouched; the lone unqualified "ClaudeKit" hit is the product name in that CLI-owned table (title, not a package command).
- **Research/reports NOT edited (by design):** `research/live-host-verification-findings.md` §5 (`claudekit`) and §3 (device-code) are historical evidence artifacts the adjudication rests on; their now-superseded characterizations are corrected authoritatively in the phase files + this Red Team Review, not by rewriting the evidence trail.
- **Unresolved contradictions:** **0.**

## Validation Log

### Session 1 — 2026-07-03

**Trigger:** User ran `/ck:plan validate` after the red-team pass, specifically to get real confirmation on the 3 decisions that had been taken by default (unanswered AskUserQuestion) during red-team adjudication, plus 2 genuinely open execution-time questions.
**Verification pass:** Skipped per `references/verification-roles.md` guard — `## Red Team Review` already contains verification evidence (4 reviewers, live-host-verified). No `[UNVERIFIED]` tags found in any phase file.
**Questions asked:** 4

#### Questions & Answers

1. **[Risk]** OAuth token exfiltration risk (Finding 6) was accepted by default (no response) during red-team adjudication. Re-confirm?
   - Options: Confirm accept the risk (Recommended) | No, redesign with `CLAUDE_CONFIG_DIR` isolation first
   - **Answer:** Confirm accept the risk (Recommended)
   - **Rationale:** Matches the EXPANSION scope already chosen; a `CLAUDE_CONFIG_DIR` redesign is new engineering scope the user did not ask for. Phase 3/6 Security Considerations already document this as an accepted, not mitigated, risk — no phase change needed.

2. **[Scope]** EXPANSION's true cost is now visible (4h25m, 3 newly-required additions: `/opt` reconcile, skill symlink, live-config sync). Re-confirm doing all 6 phases vs retreating to REDUCTION (Phase 2 only)?
   - Options: Confirm EXPANSION, all 6 phases (Recommended) | Retreat to REDUCTION (Phase 2 only, defer the rest)
   - **Answer:** Confirm EXPANSION, all 6 phases (Recommended)
   - **Rationale:** User wants `harness: ccs` to actually work, not just the crash fixed. No phase change needed — this confirms the plan's existing shape.

3. **[Assumption]** Phase 5 needs a `ccs api create --preset` choice (glm/km/anthropic/...) tied to whichever provider credential the operator dedicates to the bot.
   - Options: GLM (Z.AI) | Kimi (Moonshot) | Not decided yet, defer to Phase 5 execution time
   - **Answer:** Not decided yet, defer to Phase 5 execution time
   - **Rationale:** Confirms Phase 5's existing "open question" framing is correct as-is — no premature commitment to a preset. No phase change.

4. **[Risk]** Phase 3's `claude auth login` needs a real Claude account — which one?
   - Options: Dedicated bot-specific seat, not personal (Recommended) | Operator's personal account
   - **Answer:** Dedicated bot-specific seat, not personal (Recommended)
   - **Rationale:** Directly narrows Phase 3's previously-open "whose seat?" question and reduces Finding 6's blast radius (a dedicated seat has less at stake than a personal one if the OAuth-exfil risk is ever exercised). **Action item — propagated to Phase 3** (see below).

#### Confirmed Decisions
- OAuth credential exfiltration risk: **accepted, documented, not redesigned** (final — matches red-team default).
- Scope: **EXPANSION, all 6 phases** (final — matches red-team default).
- Phase 5 `ccs` preset/provider: **deferred to execution time** (no plan change).
- Phase 3 OAuth seat: **dedicated bot-specific account, not the operator's personal account** (new guidance, propagated).

#### Action Items
- [x] Phase 3: replace the open "whose seat?" question with explicit guidance to use a dedicated, bot-specific Claude account.

#### Impact on Phases
- Phase 3: Todo List / Security Considerations / Open Questions updated to state the seat decision as confirmed guidance rather than an open question.

### Whole-Plan Consistency Sweep (Validation Session 1)

- Re-read `plan.md` and all six `phase-0[1-6]-*.md` after propagating the Phase 3 change.
- Checked for stale "open question: whose seat" phrasing elsewhere (none found outside Phase 3).
- No other phase references seat ownership, so no further propagation needed.
- **Unresolved contradictions: 0.**

## Status Update (2026-07-06)

This plan's phase files were committed once (`8bc32b4`, 2026-07-03) and never updated despite two later, independent pieces of live evidence. Reconciled now:

- **Phase 3 (Claude Auth) → completed.** `plans/reports/scout-260705-1421-hermes-oci-live-host-best-practice-drift-audit-report.md` (2026-07-05) reported claude auth functional live; today (2026-07-06) a real delegated `ccs ccs-hermes -p '/ck:brainstorm...'` run (model `claude-opus-4-8`, exit 0) directly satisfies this phase's own Success Criteria alternate clause. See `plans/260705-1752-ccs-delegation-timeout-progress-tracking-fix/phase-03-live-host-verification.md` Addendum for the raw evidence.
- **Phase 5 (Provision CCS Profile) → completed.** Same live-test run invoked the `ccs-hermes` profile successfully end-to-end (stronger than the documented `echo ok` smoke test); `production.yaml:193` independently confirmed still `ccs-hermes`.
- **Phase 4 unchanged (in-progress)** — `ck doctor`'s 3 gh-auth FAILs are accepted-degraded, not "healthy" per the literal Success Criteria; no new evidence closes this gap.
- **Phase 6 unchanged (pending)** — dependency-wise unblocked now that 3 and 5 are done, but its Success Criteria (skill symlink into live catalog, `delegation:` block in live `config.yaml`, `SKILL.md` reframe, memory/changelog sync) has no evidence any of that work happened. This is the one phase still genuinely open in this plan.
- Top-level `status` frontmatter: `pending` → `in-progress` (4/6 phases done, 1 in-progress, 1 pending).
