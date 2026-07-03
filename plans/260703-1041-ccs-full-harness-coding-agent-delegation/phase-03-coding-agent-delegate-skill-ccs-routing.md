---
phase: 3
title: "Coding-Agent-Delegate Skill CCS Routing"
status: completed
priority: P1
effort: "2.5h"
dependencies: [1, 2]
---

# Phase 3: Coding-Agent-Delegate Skill CCS Routing

## Context Links

- Brainstorm: `plans/reports/brainstorm-260703-1034-ccs-full-harness-delegation-skill-report.md`
- Target file, current state: `skills/dev/coding-agent-delegate/SKILL.md` — frontmatter
  `:1-26`, Prerequisites `:32-39`, Tier-1 procedure `:41-70`, escalation table
  `:91-97`, example invocations `:153-159`, See-also `:161-165`
- Phase 1 (blocking): confirms `ccs` install step + `ReadWritePaths` for Prereqs.
- Phase 2 (blocking): confirms `delegation.ccs_profile` config field name.
- Verified live this session (`ccs --help`/`ccs api --help`/`claude --help`,
  v8.7.0): `ccs <profile> -p "<prompt>" [claude-args...]` forwards unrecognized args
  straight to the underlying `claude` binary (usage line: `ccs <profile>
  [claude-args...]`); `claude --bare` (not used by default here) is what strips
  CLAUDE.md/hooks. **Correction (red-team, Critical):** this does NOT mean full
  harness "always loads" — it loads only if `~/.claude/` exists on the host in the
  first place, which nothing in this repo provisions for the `hermes` user (Phase
  1 Key Insights). CCS-routing and bare invocation are equivalent on that axis.

## Overview

Priority: P1. Status: Pending. Parallel group B — starts after Phase 1 + 2 land
(needs their confirmed naming, not their files).

Add a CCS-routed invocation path to Tier 1's `claude-code` branch as an explicit
**opt-in** (`harness: ccs`), keeping bare `claude -p` as the **default**
(`harness: bare`) — this default was flipped from the plan's original draft by
red-team findings (see below): CCS-routing does not itself guarantee harness or
safe unattended operation, so it must not be the silent default. Add a `harness`
parameter and a `parallel` parameter. Correct several things the guide/skill never
stated, and one thing the plan itself got wrong initially:
(a) print mode is already non-interactive — no new "auto" flag needed on the
inner call; (b) **harness is gated by whether `~/.claude/` (ClaudeKit) exists on
the host and whether `--bare` is passed — NOT by CCS routing.** `ccs <profile> -p`
and bare `claude -p` load identical harness on any given host. CCS-routing's real,
narrower value is delegating under a controlled identity/profile (separate
API key, separate quota, separate audit trail from a human's own CCS session) —
*if* the operator has also independently provisioned ClaudeKit onto the delegating
host, which this plan does not automate (see Phase 1 Key Insights); (c) the original
"unlimited concurrency" claim for one CCS profile is unverified and should be
softened — `@kaitranntt/ccs`'s own dependency tree includes `proper-lockfile`
(file-locking), suggesting some serialization may occur; verify actual throughput
on your deployment before relying on it, and the `--parallel` example's isolated
branches must be git **worktrees**, not just branch names, since concurrent CCS
invocations share one working tree otherwise.

## Key Insights

- **[Red-team, Critical, accepted — corrects the plan's original framing]
  CCS-routing does not grant harness by itself.** Any `claude` invocation (bare or
  `ccs`-wrapped) loads global `~/.claude/CLAUDE.md` + `~/.claude/rules/*` + skills
  catalog + hooks **if and only if `~/.claude/` exists on that host** and `--bare`
  isn't passed (verified flag: `--bare` = "skip hooks, LSP, plugin sync,
  attribution, auto-memory, and CLAUDE.md auto-discovery"). Phase 1 confirms
  nothing in this repo provisions `~/.claude/` for the `hermes` service user — so
  on an unmodified deployment, bare `claude -p` and `ccs <profile> -p` get
  **identical (zero) harness**. This phase's docs must say so plainly, not imply
  `harness: ccs` alone "gives you" the harness.
- **[Red-team, Critical, accepted — no rollout safety net, live-tested] Default
  flipped from `ccs` to `bare`.** Live-tested this session:
  `ccs nonexistent-profile-xyz -p "hi" --output-format json` exits 1
  (`Profile 'nonexistent-profile-xyz' not found`, E104) with **no automatic
  fallback**. A fresh deploy that follows Phase 1/2 exactly but skips the separate
  manual profile-provisioning step would have every Tier-1 `claude-code`
  delegation hard-fail if `harness: ccs` were the default. `bare` is the safe
  default; `ccs` is an explicit opt-in an operator flips only after completing
  Phase 1's smoke-test gate (step 10).
- **[Red-team, Critical, accepted — empirically tested, UNRESOLVED] API-profile
  state-directory behavior does not match the plan's original assumption.**
  Live-tested this session: creating a real API profile
  (`ccs api create --preset anthropic --api-key <dummy> --target claude --yes
  zz-test`) never created `~/.ccs/instances/zz-test/` — only a
  `~/.ccs/zz-test.settings.json` + a `config.yaml` entry. The invocation's own JSON
  output showed `memory_paths` pointing at the **default account profile's**
  instance dir (`~/.ccs/instances/lucas/...`), not one scoped to the invoked API
  profile. **On a headless `hermes` deployment with zero pre-existing account
  profiles** (the whole reason this plan recommends API profiles), this fallback
  behavior is untested and could error, silently write elsewhere, or hit
  `ProtectHome=read-only` outside the granted `ReadWritePaths`. This is flagged as
  an **unresolved question requiring live verification against a real target
  deployment** (see `plan.md`) — this phase's docs must say the exact
  `ReadWritePaths` scope and profile behavior needs re-confirming on the operator's
  actual `hermes` box, not presented as settled.
- **No new "auto/non-interactive" flag needed on the inner call.** `-p` mode is
  already non-interactive (part18-coding-agents.md:60: "no PTY, no approval prompts
  to manage"). `--dangerously-skip-permissions` exists in the real CLI but is
  security-hostile and out of scope — the skill's existing `--allowedTools` scoping
  (already documented, unchanged) is the correct control here.
- **[Red-team, High, accepted — softened] Concurrency ceiling for one CCS API
  profile is unverified, not "unlimited."** `@kaitranntt/ccs`'s published
  dependency list includes `proper-lockfile` (`npm view @kaitranntt/ccs
  dependencies`), a file-locking library — suggesting CCS may serialize some
  operations per profile rather than allow truly unbounded concurrency. No
  successful live concurrency test was completed (auth failed before reaching real
  load, using a placeholder key). Document the `--parallel` example as "verify
  actual concurrent throughput on your deployment" rather than asserting "no
  session-slot ceiling."
- **[Red-team, High, accepted] Same-repo parallel fan-out needs git worktrees, not
  just branch naming.** The skill's existing Git Hygiene section
  (`part18-coding-agents.md:210-225`) only documents `isolate_branches`/
  `branch_prefix` — branch *naming*, not separate checkout directories. The
  existing "different agent types" parallel example sidesteps this because each
  agent targets a disjoint area; this phase's new same-agent/same-repo example is
  the first case that actually needs filesystem-level isolation. Concurrent `ccs
  <profile> -p` processes sharing one working tree will race on the same files
  even with different target branches recorded in commit messages — each
  concurrent subtask needs its own `git worktree add`.

## Requirements

- Functional: Tier 1 `claude-code` branch supports CCS-routed invocation as an
  explicit opt-in (`harness: ccs`); **default stays `harness: bare`** (red-team
  reversal — see Key Insights); `parallel` worked example added with a `parallel`
  frontmatter parameter and worktree-per-subtask isolation; Prerequisites section
  documents `ccs` as a 5th required CLI + the one-time `ccs api create` step + an
  explicit statement that ClaudeKit provisioning on the host is a separate,
  out-of-scope prerequisite for harness to actually apply.
- Non-functional: `validate_skills.py` continues to pass unchanged (no new
  `toolsets` entry — this is an invocation-detail change, not a new capability);
  existing tiers 2/3, security note, and Git Hygiene section stay untouched
  (CCS only changes tier 1's `claude-code` sub-branch).

## Architecture

No runtime architecture change — same `delegate_task` toolset, same 3-tier
escalation model. Only the constructed shell command for tier-1 `claude-code`
changes:

```
Default (harness: bare, unchanged from today):
        claude -p "<task>" --allowedTools "..." --max-turns 20 --output-format json
Opt-in (harness: ccs, after completing Phase 1's smoke-test gate):
        ccs "<ccs_profile>" -p "<task>" --allowedTools "..." --max-turns 20 --output-format json
```
`<ccs_profile>` is illustrative — it stands for whatever value
`templates/config/production.yaml`'s `delegation.ccs_profile` (Phase 2) currently
holds; the Hermes gateway's own routing logic substitutes the real value at
dispatch time. This skill file documents the pattern in prose/pseudocode, it does
not implement string interpolation itself (this repo has no runtime — see A6 note
in Phase 2). `codex`/`gemini-cli`/`opencode` branches are untouched — `harness` is
a no-op for them (CCS is a Claude-specific wrapper).

## Related Code Files

**Modify:**
- `skills/dev/coding-agent-delegate/SKILL.md` — frontmatter (`harness` and
  `parallel` parameters), Prerequisites, Tier-1 procedure, example invocations.

**Create:** none. **Delete:** none.

## Implementation Steps (TDD)

### 1. Tests Before (baseline / regression protection)

1. Run `python .github/scripts/validate_skills.py` — confirm exit 0, all skills
   `ok` (baseline; this phase must not regress it — no new toolset needed).
2. Run `python .github/scripts/test_validate_skills.py -v` — confirm `Ran 4 tests`,
   all pass (baseline from the sibling plan's Phase 1 — this phase touches
   frontmatter but adds no new toolset, so this suite's assertions must still hold
   unchanged).

### 2. Implement

3. Frontmatter (`SKILL.md:13-25`): add under `parameters:`:
   ```yaml
     harness:
       type: string
       enum: [bare, ccs]
       default: bare
       description: "bare = plain `claude` (default — works with zero extra setup). ccs = route claude-code through `ccs <profile>` for a scoped delegation identity; only grants CK harness if ClaudeKit is separately provisioned on this host (see Prerequisites). Opt in only after Phase 1's smoke-test gate passes. No-op for codex/gemini-cli/opencode."
     parallel:
       type: integer
       description: "Number of subtasks to fan out concurrently within one delegate_code call. Each subtask runs in its own git worktree (see Git Hygiene). Optional — omit for a single-subtask delegation."
   ```
4. Prerequisites (`SKILL.md:32-39`): add `ccs` to the list of CLIs the routing table
   shells out to (alongside `claude`/`codex`/`gemini`/`opencode`), explicitly
   scoped to when `harness: ccs` is used; add a bullet documenting the one-time
   provisioning step (cross-reference Phase 2's `production.yaml` comment,
   preferring the interactive wizard `ccs api create` over the `--api-key`
   command-line form) and cross-reference Phase 1's systemd
   `ReadWritePaths=/home/hermes/.ccs` requirement AND its step-10 smoke-test gate.
   State plainly: **ClaudeKit itself (the `~/.claude/` bundle) is a separate
   prerequisite this guide does not install** — `harness: ccs` without it produces
   identical behavior to `harness: bare`.
5. Tier-1 procedure (`SKILL.md:45-70`): keep the existing bare-`claude` examples as
   the **default** (`harness: bare`, no change to today's behavior). After them, add
   an opt-in `harness: ccs` variant:
   ```bash
   ccs "<ccs_profile>" -p "..." --allowedTools "Read,Edit,Bash" --max-turns 20 --output-format json
   ```
   (`<ccs_profile>` = whatever `delegation.ccs_profile` currently holds — see
   Architecture note on interpolation.) Add a short paragraph (from Key Insights)
   clarifying: (a) print mode is already non-interactive, no separate flag needed;
   (b) harness depends on `~/.claude/` existing on the host, NOT on choosing `ccs`
   over `bare` — say this before the worked example, not after, so a reader doesn't
   walk away assuming `ccs` alone solves it.
6. Escalation tiers table (`SKILL.md:91-97`) and worked example (`SKILL.md:153-159`):
   add one `parallel` example — 3 concurrent `ccs ccs-hermes -p` calls, one
   subtask each, each in its own **git worktree** (new prose needed — the existing
   Git Hygiene section only covers branch naming, not worktrees):
   ```
   /delegate_code "add tests for src/payments/, split into 3 subtasks" repo=myorg/app harness=ccs parallel=3
     → 3x, each in its own worktree (git worktree add ../subtask-N devin/claude-code-<ts>-subtask-N):
        ccs ccs-hermes -p "<subtask N>" --allowedTools "Read,Edit,Bash" --max-turns 20 --output-format json
   ```
   Add a one-line note: one CCS profile can serve concurrent calls, but the actual
   throughput ceiling is unverified (see Key Insights, `proper-lockfile` dependency)
   — test on your deployment before assuming N is unbounded.

### 3. Tests After (confirm green)

7. Re-run `python .github/scripts/validate_skills.py` — still exit 0.
8. Re-run `python .github/scripts/test_validate_skills.py -v` — still `Ran 4 tests`,
   all pass (frontmatter changes are additive to `parameters`, not `toolsets`, so
   `ALLOWED_TOOLSETS` assertions are unaffected).
9. Manual check: `harness` parameter documented with exactly `[ccs, bare]` enum;
   grep confirms tiers 2/3 sections and the Git Hygiene section are byte-identical
   to before this phase (`git diff` shows no changes outside Prerequisites/Tier-1/
   escalation-table/example-invocation regions).

### 4. Regression Gate

10. `python .github/scripts/validate_skills.py` and
    `python .github/scripts/test_validate_skills.py -v` both exit 0 — this is the
    same gate CI runs (`ci.yml` `skill-frontmatter` job), verifiable locally without
    a push.

## Success Criteria

- [x] `harness` parameter added to frontmatter with `[bare, ccs]` enum, **`bare`
      default** (red-team reversal).
- [x] `parallel` parameter added to frontmatter (integer, optional).
- [x] Tier-1 `claude-code` branch's default worked example is unchanged bare
      `claude -p ...`; `ccs "<ccs_profile>" -p ...` documented as the explicit
      `harness: ccs` opt-in, with the profile-value interpolation described as
      illustrative, not literal executable syntax.
- [x] Prerequisites section lists `ccs` as required only when `harness: ccs` is
      used, the one-time `ccs api create` provisioning step (wizard preferred over
      `--api-key`), the systemd `ReadWritePaths` note, AND an explicit statement
      that ClaudeKit provisioning on the host is separate and out of this guide's
      scope.
- [x] A `parallel` worked example (3 concurrent CCS calls, each in its own **git
      worktree**, one profile) added to the escalation table or
      example-invocations section, with a throughput-unverified caveat.
- [x] `python .github/scripts/validate_skills.py` exits 0 (no regression).
- [x] `python .github/scripts/test_validate_skills.py -v` shows `Ran 4 tests`, all pass.
- [x] Tiers 2/3 and security note unchanged; Git Hygiene section gains new
      worktree prose (this is an intentional addition, not drift — `git diff`
      scoped to Prerequisites/Tier-1/escalation-table/examples/Git-Hygiene-worktree-addition only).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Reader assumes `harness: ccs` alone grants full CK harness without separately provisioning ClaudeKit | Med | High | Key Insights + Prerequisites state this plainly, before the worked example, not as a footnote |
| `harness: ccs` shipped as default would hard-fail every delegation on a box without a provisioned profile (was the plan's original design) | Was Med/High before this red-team pass | — | **Fixed**: default flipped to `bare`; `ccs` is opt-in after Phase 1's smoke-test gate |
| `parallel` example implies unlimited concurrency | Med | Low | Softened wording + `proper-lockfile` dependency note; recommend verifying on real deployment |
| Concurrent CCS invocations against one shared working tree race on file writes despite different target branches | Was unaddressed (red-team High) | High | New worktree-per-subtask requirement added to the example and Git Hygiene section |
| Frontmatter `parameters.harness`/`parameters.parallel` breaks `validate_skills.py` | Low | Med | `REQUIRED_KEYS`/`ALLOWED_TOOLSETS` don't constrain `parameters` shape (confirmed by reading `.github/scripts/validate_skills.py:16-29`) — step 7/8 re-run the real gate to confirm |
| Phase 3 starts before Phase 1/2 finalize naming, drifts from their actual field/CLI names | Low | Med | `dependencies: [1, 2]` — this phase's steps 4/5 cite Phase 1/2's exact strings; re-read both phase files' final state before implementing if they changed after this plan was written |
| API-profile state-directory fallback behavior (Key Insights, live-tested) differs on a real headless target vs. this dev session | Unresolved | Med | Documented as an explicit unresolved question (`plan.md`) requiring the operator to re-verify on their actual deployment, not assumed solved by this phase's docs |

## Security Considerations

No new write/exec surface beyond what Phase 1 already flags as an accepted,
unresolved risk (`~/.ccs` shared hook/plugin write access) — CCS-routed calls
carry the same `--allowedTools` scoping and the same
`security.approval.require_approval` gate (`delegate_task` dispatch) as
bare-`claude` calls (confirmed unchanged, Phase 2); that gate covers whether a
delegation dispatches, not what it can reach once approved. The `parallel`
example's concurrent sessions each need an isolated **worktree** (new
requirement, not previously covered by Git Hygiene's branch-only guidance) —
without it, concurrent writes to a shared tree are a real data-loss risk, not a
git-safety nicety.

## Next Steps

Unblocks Phase 4 (docs/catalog must describe the shipped `harness` parameter and
CCS example accurately, not a hypothetical one).
