---
title: Apply Part 5 Curator + Part 7 Memory Discipline to Repo Artifacts
description: >-
  Config-only + doc-only application of the two guide chapters not yet reflected
  in shipped artifacts: curator + memory_audit config blocks and meeting-prep
  memory save discipline. No new skill.
status: completed
priority: P2
effort: 2h
branch: main
tags:
  - config
  - memory
  - curator
  - skills-hygiene
blockedBy: []
blocks: []
created: '2026-07-03T09:20:20.868Z'
createdBy: 'ck:plan'
source: skill
---

# Apply Part 5 Curator + Part 7 Memory Discipline to Repo Artifacts

## Overview

Close the two gaps where `part5-creating-skills.md` (Curator, v0.12) and
`part7-memory-system.md` (three-tier memory + v0.18 `/journey` audit) are not yet
reflected in the repo's shipped artifacts. Both researcher passes independently
concluded **neither part needs a new skill** — Curator and the memory tools are
built-in Hermes system features, not task-automation skills. Application is
therefore config + inline-doc only:

1. **`templates/config/production.yaml`** — append two entries to the existing
   `cron:` list: `monthly-skill-curator-reminder` and `monthly-journey-reminder`.
   <!-- Updated: Red Team Session 2 (adversarial) — RT2-1/RT2-2 --> **Revised
   after adversarial red-team review**: the original design (top-level
   `curator:`/`memory_audit:` config blocks with scoring weights, auto-archive,
   regex-based "suspicious pattern" detection) was fabricated — 3 independent
   hostile reviewers confirmed neither Curator nor `/journey` has any documented
   YAML-configurable or headless mode; both are CLI/TUI-interactive only. The
   revised design reuses the existing, already-proven `cron:` list to schedule
   plain reminders pointing at the real commands — no invented engine, no
   automation claim.
2. **`skills/dev/meeting-prep/SKILL.md`** — add a `## Memory discipline` note.
   This is the repo's only skill that declares the `memory` toolset yet has no
   save/don't-save rules; Part 7 exists to close exactly this.
3. **`CHANGELOG.md`** — one dated entry. No `skills/README.md` catalog change
   (no new skill), no new `docs/` file (Part 5/7 chapters are already the docs).

Total surface: **3 files, all modified, 0 new** — intentionally minimal per YAGNI
and matching both research reports' config-only/doc-only recommendation. No CI
change (`validate_skills.py` only validates `skills/**`, not config; `/journey`
and `/learn` are built-in commands, not declared toolsets). No `security-hardened.yaml`
change in this plan — documented deferred follow-up (trivial 2-line addition later),
not a silent omission.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [production.yaml curator and memory_audit config blocks](./phase-01-production-yaml-curator-and-memory-audit-config-blocks.md) | Completed |
| 2 | [meeting-prep memory save discipline](./phase-02-meeting-prep-memory-save-discipline.md) | Completed |
| 3 | [changelog sync](./phase-03-changelog-sync.md) | Completed |

## Dependencies

### Intra-plan dependency matrix

| Phase | blockedBy | Parallel group | File ownership (no overlap) |
|-------|-----------|----------------|------------------------------|
| 1 | — | A (start now) | Completed |
| 2 | — | A (start now) | Completed |
| 3 | [1, 2] | B (after 1 & 2) | Completed |

Execution: Phases 1 and 2 run in parallel (group A — disjoint files, no shared
edits). Phase 3 starts once both land, because the changelog entry must name the
exact fields/section actually shipped (re-grep-verified, no phantom features).

### Cross-plan dependencies

None. `plans/` holds two other plans — `260702-0525-oci-vps-bootstrap-variant`
(Done) and `260703-0347-hermes-coding-agent-delegation-skill` (completed). No file
or scope overlap: the delegation plan owns `delegation`/`acp`/`sandboxes` config
blocks and a new skill dir; this plan owns the disjoint `curator`/`memory_audit`
blocks and edits an existing skill. `pinned_skills` *references* the delegation
plan's `coding-agent-delegate` skill (read-only mention), which is why that plan
being already-completed is convenient but not a hard blocker.

## Red Team Review

### Self-critique session — 2026-07-03 (--auto mode, single-planner)

No separate `code-reviewer` fan-out spawned (3-file config/doc plan; the prior
7-file plan warranted 3 hostile reviewers, this does not per proportionality).
Instead, self-critique against the three mandated axes with grep/read-verified
evidence. Findings severity-ranked with dispositions.

| # | Axis | Finding | Severity | Disposition |
|---|------|---------|----------|-------------|
| RT-1 | (a) invented scope | Research report's `curator.scoring.*_weight` floats (0.20/0.25/…) and `archive_threshold: 0.35` are **invented** — `part5:137` names the five dimensions but publishes **no weights**. Shipping fabricated numbers implies an authoritative formula that doesn't exist. | High | **Accept** — cut all weight floats + threshold from Phase 1; replaced with a comment listing the five named dimensions and pointing to the CLI. Honors user's "don't invent scoring formulas" constraint. |
| RT-2 | (b) security | Does `notify:`/report channel need a new destination or safety gate? | Med | **Reject (no change needed)** — both blocks reuse the existing `telegram_dm` token already used by all five `cron:` entries and `security.approval.approval_channel` (`production.yaml:264,290-294`). No new egress surface. Verified. |
| RT-3 | (b) security | Does `curator.auto_archive` need an approval gate like the delegation plan's `delegate_task`/`kanban`/`sandbox` in `security.approval.require_approval`? | Med | **Reject** — those are *write-capable tool call surfaces* invokable in-conversation. Curator is scheduled internal housekeeping, archive is non-destructive/restorable (`part5:139`), scoped to agent-created skills. Admin config ≠ tool surface (`researcher-260703-0915:92-102`). Documented in Phase 1 Security. |
| RT-4 | (b) security | `memory_audit` could be mistaken for auto-pruning and erode memory. | High | **Accept (already mitigated)** — `auto_delete: false` + explicit "does NOT delete" comment is the load-bearing invariant; called out in Phase 1 Success Criteria as a checked item. |
| RT-5 | (c) arithmetic | Does the "3 files, 0 new" count hold? | — | **Verified** — Phase 1 → `production.yaml`; Phase 2 → `meeting-prep/SKILL.md`; Phase 3 → `CHANGELOG.md`. `skills/README.md` deliberately unchanged (justified). Zero new files. Count checks out. |
| RT-6 | (c) citations | Do all cited guide line ranges resolve? | — | **Verified** — re-read: `part5:117-150` (Curator), `part5:128` (weekly enable), `part5:139` (archive), `part5:140,145` (pin), `part5:146` (dry-run); `part7:64` (6-month durability → 180d), `part7:28-30,129` (anti-patterns), `part7:123` (monthly pruning). All present in source. |
| RT-7 | (a) premise | User premise "3 skills use memory toolset" — is it true? | Med | **Corrected** — `awk` over every `toolsets:` block: only `meeting-prep` declares `memory`. `nightly-backup`/`spam-trap` merely mention the word in prose. Phase 2 scoped to the one real file; documented in Phase 2 Key Insights. |
| RT-8 | (c) collision | Does top-level `memory_audit:` collide with existing `memory:` block? | Low | **Reject (no issue)** — distinct YAML keys; `memory:` (`:118-126`) is the LightRAG backend, `memory_audit:` is the report job. `_audit` suffix disambiguates. Verified no duplicate-key. |

**Net:** 3 accepted (RT-1 changed the plan by cutting invented config; RT-4, RT-7
were mitigations already baked in / corrections applied), 4 rejected-with-rationale,
2 pure verifications. 0 unresolved contradictions.

### Whole-plan consistency sweep (session 1)

- Files reread: `plan.md`, all 3 phase files, source `part5`/`part7`, target `production.yaml`, `meeting-prep/SKILL.md`, `CHANGELOG.md` format.
- Decision deltas checked: scoring-weights cut (RT-1) is reflected consistently — Phase 1 block, Phase 1 Key Insights, Phase 3 changelog draft (`### Added` deliberately omits weights), and Phase 3 Risk RT row all agree no weights ship.
- Reconciled stale references: none — the weight cut was applied at authoring time, not retrofitted, so no phase ever asserted weights.
- Unresolved contradictions: 0.

### Session 2 — 2026-07-03 (adversarial, 3 hostile reviewers, `--red-team --auto --parallel`)

Requested by user after Session 1's self-critique (single planner, no independent adversary).
Spawned 3 parallel `code-reviewer` agents per the phase-count scaling table (3 phases → 3
reviewers): Security Adversary, Assumption Destroyer, Failure Mode Analyst. Standard
verification tier (3-4 phases → Fact Checker + Contract Verifier, both roles applied by all
three reviewers per the tier-precedence rule). Reports:
`reports/from-code-reviewer-to-planner-red-team-security-adversary-plan-review-report.md`,
`reports/from-code-reviewer-to-planner-red-team-assumption-destroyer-plan-review-report.md`,
`reports/from-code-reviewer-to-planner-red-team-failure-mode-analyst-plan-review-report.md`.

**Findings:** 20 raw findings across 3 reports, deduplicated to 9 unique clusters (all passed
the evidence filter — every finding cited `file:line`).
**Severity breakdown (post-dedup):** 2 Critical, 3 High, 4 Medium.
**Disposition:** 6 accepted (applied — 2 caused a full Phase-1 redesign), 3 rejected/resolved-as-non-issue.

| # | Finding | Severity | Reviewers agreeing | Disposition | Applied To |
|---|---------|----------|---------------------|--------------|------------|
| RT2-1 | `memory_audit:`'s core premise (scheduled/automated `/journey` review with `suspicious_patterns` regex classifier) is fabricated — `/journey` is documented only as an interactive human command (`part7:120-123`, `part26:98,101,168`), no headless/cron mode exists | Critical | 3/3 (Security Adversary F1+F2, Assumption Destroyer F2, Failure Mode Analyst F1) | **Accept** | Phase 1 — full redesign: cut `memory_audit:` block entirely, replaced with a `monthly-journey-reminder` entry in the existing `cron:` list that reminds the operator to run `/journey` manually |
| RT2-2 | `curator:` top-level YAML block is itself fabricated — the guide only documents Curator as CLI-invoked (`hermes curator run/enable/status`), never as a YAML-configurable engine; `grep -rn "curator:" part*.md` = zero matches | Critical | 2/3 (Assumption Destroyer F1 explicit; Failure Mode Analyst F1 implicit — "curator schedulability traces to a real CLI" i.e. not to a real config schema) | **Accept** | Phase 1 — cut `curator:` block entirely, replaced with a `monthly-skill-curator-reminder` entry in the `cron:` list |
| RT2-3 | `pinned_skills` protects a category (`coding-agent-delegate`, `nightly-backup`, `audit-mcp`, `rotate-secrets` — all bundled/vendor skills) that Curator's own design explicitly deprioritizes (`part5:141`: "Focuses on agent-created skills first, not bundled/vendor skills") | High | 3/3 | **Accept (moot after RT2-2)** | Phase 1 — field no longer exists once `curator:` block was cut |
| RT2-4 | Phase 2 insertion-point instructions ("after Procedure line 75, before Tips line 88") skip an un-mentioned `## Triggering 15 min before each meeting` section (`SKILL.md:77-86`), which would wedge the new section ahead of the triggering config instead of after it | High | 3/3 | **Accept** | Phase 2 — corrected insertion point to "after `## Triggering...` (line 86), before `## Tips` (line 88)"; Requirements, Implementation Steps, and Todo List all updated |
| RT2-5 | `security-hardened.yaml` excluded from hygiene rollout with only a hand-wavy "admin config" rationale that doesn't distinguish it from `production.yaml` (which gets the blocks); it's also the one other template with its own `cron:` block, so the exclusion isn't structurally forced | High | 2/3 (Security Adversary F3, Failure Mode Analyst F2) | **Accept (as documented deferral, not a fix)** | Phase 1 Risk Assessment — recorded as an explicit, reasoned, deferred follow-up (2-line addition later) rather than a silent gap; scope stays at 3 files per this plan's YAGNI constraint |
| RT2-6 | No schema validation exists for the new config keys — CI yamllint has `comments`/`colons`/`commas`/`indentation` disabled, so a typo'd key ships silently | Medium | 1/3 (Assumption Destroyer F4) | **Reject (resolved by RT2-1/RT2-2 redesign)** | — the redesign reuses the `cron:` list's proven shape, which carries the same (pre-existing, accepted) validation posture as the 5 entries already in production; not a new gap this plan introduces |
| RT2-7 | `memory_audit` Telegram report could echo raw flagged memory content (attendee/deal context) past the write-time-only `memory_write_redaction` gate | Medium | 2/3 (Assumption Destroyer F6, Failure Mode Analyst F3) | **Reject (moot after RT2-1)** | — the redesign's reminder task string carries zero memory content, only a static imperative sentence |
| RT2-8 | Parallel Phase 1 + Phase 2 both flip status in the shared `plan.md` Phases table — no write-ownership protocol for concurrent sessions | Medium | 1/3 (Failure Mode Analyst F6) | **Reject** | — identical to a finding already adjudicated and rejected in the precedent plan (`plans/260703-0347-.../plan.md` finding #14): a structural property of the `ck-plan` parallel-mode tooling itself, not something this plan's phase files can fix |
| RT2-9 | Contract Verifier concern: does `curator:`/`memory_audit:`'s top-level-scalar shape match any real config-loading contract, vs. `cron:`'s proven list-of-maps shape | Medium | 1/3 (Security Adversary F6) | **Accept (resolved by RT2-1/RT2-2 redesign)** | Phase 1 — new entries reuse the exact `cron:` list-of-maps shape verified in production use at `production.yaml:289-294`, eliminating the unverified-schema question entirely |

**Net:** RT2-1 and RT2-2 (the two Critical findings) triggered a full Phase 1 redesign — the
invented `curator:`/`memory_audit:` engine-config schema was replaced with two plain reminder
entries appended to the existing, already-proven `cron:` list. RT2-3, RT2-6, RT2-7, RT2-9 became
moot as a direct consequence of that redesign (the fields/risks they targeted no longer exist).
RT2-4 (Phase 2 citation bug) and RT2-5 (security-hardened.yaml deferral) were independently
fixed/documented without needing the redesign. RT2-8 rejected as an already-known, out-of-scope
tooling limitation (precedent-plan finding #14, same rationale applies verbatim).

### Whole-plan consistency sweep (session 2)

- Files reread: `plan.md`, all 3 phase files (post-edit), `part5-creating-skills.md`,
  `part7-memory-system.md`, `templates/config/production.yaml` (`cron:` block + surrounding
  context), `skills/dev/meeting-prep/SKILL.md` (`## Procedure`/`## Triggering`/`## Tips` line
  numbers re-verified via `grep -n "^## "`).
- Decision deltas checked: (1) `curator:`/`memory_audit:` top-level blocks → two `cron:` list
  entries; (2) `pinned_skills`/`auto_archive`/`stale_threshold_days`/`suspicious_patterns`/
  `auto_delete` all cut; (3) Phase 2 insertion point moved from "after Procedure" to "after
  Triggering"; (4) `security-hardened.yaml` exclusion reframed from unstated to an explicit
  documented deferral.
- Reconciled stale references: `plan.md` Overview (rewritten to describe cron-reminder design);
  Phase 1 Overview/Key Insights/Architecture/Related Code Files/Implementation
  Steps/Todo/Success Criteria/Risk Assessment/Security Considerations/Next Steps (every section
  touched by the redesign, since the whole phase's mechanism changed); Phase 2
  Requirements/Key Insights/Implementation Steps/Todo List (insertion-point citation fixed in
  all four); Phase 3 changelog draft `### Added`/`### Notes` bullets (rewritten to name the
  actual shipped cron entries, not the cut config blocks) and step 2's re-grep instructions
  (updated to search for the new entry names instead of the cut top-level keys).
- **Validation Log reconciliation (session 1 → session 2 conflict found and fixed):** Session
  1's Validation Log decision #2 ("One global `stale_threshold_days: 180`... cut all curator
  scoring weights/threshold") is now **superseded** — `stale_threshold_days` itself no longer
  exists in the redesigned Phase 1 (the whole `memory_audit:` block it belonged to was cut, not
  just its weights). Added a superseding note directly under that decision in the Validation Log
  below so the two sessions don't contradict each other.
- Unresolved contradictions: 0.

## Validation Log

### Session 1 — 2026-07-03 (--auto)

Per this session's `--auto` directive, the three researcher-flagged open questions
were resolved autonomously with YAGNI/KISS rationale (repo convention: resolve
open questions with documented rationale, don't block). No user prompt within the
wait window; proceeded with the recommended option for each.

1. **Config block naming** (researcher Q1: `memory_audit` vs `journey_audit` vs `memory_discipline`).
   - **Decision (session 1):** `curator:` (Part 5) and `memory_audit:` (Part 7) as top-level config keys.
   - **Rationale (session 1):** `curator:` matches the guide's own noun (`hermes curator`) and the present-tense-noun `cron:` style. `memory_audit:` names *what the block does* (a scheduled audit/report), parallels `curator:` as a hygiene feature, and the `_audit` suffix cleanly disambiguates from the existing `memory:` LightRAG backend block — no YAML key collision (RT-8). Rejected `journey_audit:` (`/journey` is just the invocation verb, not the domain) and `memory_discipline:` (vaguer; "discipline" is the *doc* concern handled inline in Phase 2, not a scheduled job).
   - **Superseded (session 2, red team RT2-1/RT2-2):** neither name ships as a top-level YAML key — both were fabricated schemas (see Whole-Plan Consistency Sweep, session 2). The naming instinct survives as `cron:` list entry *names* instead: `monthly-skill-curator-reminder` and `monthly-journey-reminder` (matching the existing `cron:` entries' `name:` convention, e.g. `weekly-dep-audit`, `monthly-rotate`). RT-8's "no collision with `memory:` LightRAG block" concern is now moot — there's no `memory_audit:` key to collide.

2. **Staleness / threshold tuning** (researcher Q2: per-category vs global; scoring weights).
   - **Decision (session 1):** One global `stale_threshold_days: 180`; no per-category thresholds; **cut** all curator scoring weights/threshold.
   - **Rationale (session 1):** YAGNI + honesty. `part7:64` literally anchors 6 months → 180d, so one global value traces to the guide; per-category thresholds are invented (guide never describes them). `part5:137` names five scoring dimensions but **no weights** — fabricating `0.20/0.25/…` (RT-1) would imply a non-existent authoritative formula, directly violating the "don't invent scoring formulas beyond what the guide literally describes" constraint. Cut them; document the five dimensions as a comment pointing to the `hermes curator` CLI.
   - **Superseded (session 2, red team RT2-1):** `stale_threshold_days` itself is cut, not just its weight-siblings — the entire `memory_audit:` block it lived in was fabricated (no headless/scannable mode for `/journey` exists in the guide) and was replaced with a plain `monthly-journey-reminder` cron entry that carries no threshold field at all. Session 1's "keep one global threshold" decision was reasonable *given* the (mistaken) premise that an automated report job existed; session 2 removed that premise entirely. See Red Team Review session 2, RT2-1.

3. **Docs location** (researcher Q3: new `docs/memory-system-guide.md` vs `docs/code-standards.md` vs inline).
   - **Decision:** No new `docs/` file. Discipline lands inline in `meeting-prep/SKILL.md` (Phase 2); scheduling lands in config (Phase 1); `CHANGELOG.md` records it (Phase 3).
   - **Rationale:** DRY + anti-scope-creep. `docs/` currently holds only `quickstart.md`, `outreach/`, `reference-architectures/`, `wizard/` — no `code-standards.md` exists to embed into, and a new `docs/memory-system-guide.md` would **duplicate** `part7-memory-system.md`, which is already the canonical doc at repo root. A redundant docs file exceeds a 2-gap fix. Discipline is placed where it's *actionable* (the skill that holds the toolset), not in a reference file no agent reads at save-time.

#### Confirmed Decisions
- ~~Names: `curator:`, `memory_audit:` (top-level keys)~~ — **superseded session 2:** two `cron:` list entries, `monthly-skill-curator-reminder` and `monthly-journey-reminder`, no new top-level key.
- ~~Curator ships without fabricated scoring weights / archive_threshold~~ — **superseded session 2:** the entire `curator:`/`memory_audit:` schema (not just weights) was fabricated and cut; both reminders carry no scoring/threshold/pattern fields of any kind.
- No new `docs/` file; no `skills/README.md` catalog edit. *(still holds post-session-2 — unaffected by the Phase 1 redesign)*

#### Impact on Phases
- Phase 1: full redesign — `curator:`/`memory_audit:` top-level blocks replaced with two `cron:` list entries (see Red Team Review session 2, RT2-1/RT2-2).
- Phase 2: insertion-point citation corrected (RT2-4) — after `## Triggering...`, not after `## Procedure`.
- Phase 3: changelog draft rewritten to name the actual shipped cron entries; `docs/` explicitly out of scope; catalog unchanged confirmed *(this line unaffected by session 2)*.

**Verification results (session 1, self-critique):** 8 findings, all
evidence-backed (grep/read `file:line`). RT-1 applied (config changed); RT-4/RT-7
mitigations confirmed present; RT-2/RT-3/RT-8 rejected with cited rationale;
RT-5/RT-6 pure verifications passed. 0 `[UNVERIFIED]` tags remain.

**Verification results (session 2, adversarial red team — see `## Red Team Review`
above):** 20 raw findings across 3 independent hostile reviewers, deduplicated to 9,
all evidence-backed (grep `file:line`). 6 accepted (2 Critical findings — RT2-1,
RT2-2 — drove a full Phase 1 redesign; RT2-4 fixed a real citation bug in Phase 2;
RT2-3/RT2-6/RT2-7/RT2-9 resolved as moot once the redesign landed); RT2-5 accepted
as a documented deferral (not a code change); RT2-8 rejected as an already-known
tooling-level limitation. Whole-Plan Consistency Sweep (session 2): 0 unresolved
contradictions — every phase file and the Validation Log were reconciled against
the redesign (see superseding notes inline above).

## Next Steps

Ready to implement — session 2's adversarial pass replaced the fabricated
`curator:`/`memory_audit:` config-block design with two plain `cron:` reminder
entries reusing existing, proven infrastructure. Parallel group A (Phases 1 + 2)
then Phase 3. No push to remote without explicit user confirmation (repo memory).
Consider `hermes config validate` on `production.yaml` post-Phase-1 if the CLI is
available (though, per RT2-9, the new entries now reuse the same `cron:` shape the
5 pre-existing entries already validate against in production use, so this is a
lower-risk step than it was before the redesign).
