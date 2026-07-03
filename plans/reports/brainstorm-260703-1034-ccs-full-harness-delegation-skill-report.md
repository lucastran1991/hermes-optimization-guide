# Brainstorm: CCS Full-Harness Delegation for Hermes Coding-Agent Skill

## Problem Statement

Hermes' shipped `skills/dev/coding-agent-delegate/SKILL.md` (Tier 1) shells out to bare
`claude -p "..." --allowedTools "Read,Edit,Bash" --max-turns 20 --output-format json`.
This is a vanilla Claude Code invocation — no ClaudeKit (CK) rules, no skills catalog, no
hooks, no agent-memory. It behaves nothing like the harness a human dev gets.

Reference project `kitchen/` (Go+React AI Studio) shows the intended pattern: its own
CLAUDE.md says "All code work → delegate to Claude Code: `cd here && ccs lucas`" — i.e.
route through a **CCS account profile**, not bare `claude`. That gives the delegated
session the full harness: global `~/.claude/CLAUDE.md`, `~/.claude/rules/*.md`
(primary-workflow, development-rules, orchestration-protocol, skill routing, etc.),
ClaudeKit skills catalog, hooks (Plan Context / Naming injection), superpowers skills,
agent-memory — the exact stack this very session is running under.

Ask: analyze the CCS+CK mechanism and enhance the Hermes delegation skill (or add a new
one) to use it, with `--auto`/`--parallel` behavior.

## Verified Facts (scout)

- CCS v8.7.0 has two orthogonal profile kinds (`ccs --help`, `ccs list`):
  - **Account profiles** (`lucas`/`ken`/`luan`) — isolated Claude OAuth identity + state
    at `~/.ccs/instances/<name>/`. These carry the full CK harness because they point at
    shared `~/.claude`.
  - **CLIProxy profiles** (`claude`/`gemini`/`codex`/... ) — swaps model/provider only,
    unrelated to harness.
  - `ccs <account-profile> -p "<prompt>" [claude-args...]` is a documented headless mode
    (confirmed in the CLI's dispatcher: special-cased when `-p`/`--prompt` is present and
    target is `claude`).
- `kitchen/docs/claudekit-kg/entities/ccs-profiles.yaml` explicitly notes account profiles
  (`ken/luan/lucas/vuong`) are "NOT routable delegation targets — pinned by the caller at
  dispatch time as identity/quota context" — i.e. they're an identity dimension, not a
  cost-routing dimension. Cost-routing already exists via cliproxy ids (`mm`, `gemini`, etc.)
  and is out of scope here.
- `skills/dev/coding-agent-delegate/SKILL.md` (this repo, already shipped, plan
  `plans/260703-0347-hermes-coding-agent-delegation-skill/`) is the "current claude-code
  skill" the user means — its Tier 1 `claude -p` example never references CCS.
- `part18-coding-agents.md` already documents "Parallel Delegation" but only across
  **different agent types** (claude-code + codex + gemini-cli each once) — never multiple
  CCS account instances for the same agent type.
- `.github/scripts/validate_skills.py` `ALLOWED_TOOLSETS` has no `ccs` entry and doesn't
  need one — this is an invocation-detail change inside the existing `delegate_task`
  toolset, not a new capability category.

## Discovery Attempt

Asked 4 clarifying questions (skill scope, `--parallel` meaning, `--auto` meaning, which
CCS profile to use) via AskUserQuestion — no response within the wait window. Proceeding
on recommended/most-consistent defaults below, flagged explicitly so they're easy to
correct. Per repo convention (see `plans/260703-0347.../plan.md` validation log), an
unanswered question under an autonomous/best-judgment directive resolves to the
recommended option, documented as an assumption rather than silently baked in.

**Assumptions made (need confirmation):**
1. **Enhance existing skill**, don't fork a new one — `coding-agent-delegate` stays the
   one Tier-1/2/3 skill; CCS routing is an added option inside Tier 1, not a parallel
   skill file. Reason: the existing skill is already generic across claude/codex/
   gemini/opencode; CCS only applies to the `claude-code` branch, so it's a localized
   change, not a new concern needing its own file (DRY / YAGNI).
2. **`--parallel` = both meanings, additively**: existing multi-agent-type fan-out
   (already documented) stays as-is; new capability added is multi-**instance** fan-out
   — split one task across `lucas`/`ken`/`luan` concurrently to dodge single-account rate
   limits. They compose (e.g. 3 subtasks × pick an agent type × pick a CCS instance per
   claude-code branch) but the new design surface is only the instance dimension.
3. **`--auto` = full autonomy at both layers**: skip Hermes' own `delegation.approval:
   prompt` gate AND force the inner Claude Code session non-interactive (no blocking
   AskUserQuestion — always take the recommended option), matching `/ck:cook --auto`'s
   existing meaning elsewhere in this ecosystem.
4. **CCS profile = config-driven default + per-call override**: add
   `delegation.ccs_profile: lucas` to `~/.hermes/config.yaml` (default identity Hermes
   delegates as), overridable per invocation for the parallel-instance case.

## Approaches Evaluated

### A. Enhance `coding-agent-delegate` in place (recommended)
Add a `harness` param (`ccs` | `bare`, default `ccs` when `agent: claude-code`) to Tier 1.
When `ccs`, invocation becomes:
```bash
ccs "${delegation.ccs_profile:-lucas}" -p "<task>" \
    --allowedTools "Read,Edit,Bash" --max-turns 20 --output-format json
```
Rather than bare `claude -p`. `--parallel` with multiple instances = run N of the above
concurrently with different profile ids, each on its own git branch/worktree (existing
"Git Hygiene" section already mandates per-delegation branches — reuse verbatim).

**Pros:** one skill file, no new concept for skill authors to learn, reuses the existing
routing table/tiers/security-note/git-hygiene sections untouched. **Cons:** couples a
Claude-specific mechanism into a multi-agent-generic skill (mitigated: the `harness` param
is only consulted when `agent == claude-code`, everything else is a no-op for
codex/gemini/opencode).

### B. New dedicated skill (e.g. `ccs-harness-delegate`)
Separate skill purely for "delegate to Claude Code via CCS with full harness", leaving
`coding-agent-delegate` untouched.

**Pros:** zero risk of regressing the just-shipped generic skill; cleaner separation of
concerns if CCS-specific config grows (browser/docker/proxy CCS features are a large
surface per `ccs --help`). **Cons:** two skills now both able to reach `claude-code`,
duplicated routing/tier/git-hygiene boilerplate, violates DRY for marginal benefit — the
CCS-vs-bare choice is a one-line invocation swap, not a different escalation model.

**Recommendation: A.** The difference between CCS-mode and bare-mode is exactly one
invocation string; forking a whole skill for that inflates surface area for no
functional gain, and the existing skill's tiers/security/git-hygiene sections apply
identically either way.

## Prerequisites Gap (new, not previously documented)

Today's `scripts/vps-bootstrap.sh` (per the skill's own Prerequisites section) installs
`claude`/`codex`/`gemini`/`opencode` CLIs onto the Hermes service PATH — **not `ccs`**.
For approach A to work in production, the bootstrap script needs a 5th CLI install step
for `@kaitranntt/ccs` (or whatever npm package + version this env's CCS is), plus the same
`ProtectHome=read-only` / `ReadWritePaths` caveat already called out for `~/.claude`,
extended to `~/.ccs/instances/<profile>/` (where CCS keeps per-account state) — otherwise
the CCS-routed branch fails identically to the `claude: command not found` failure mode
already documented, just one layer up (`ccs: command not found`).

## Implementation Considerations / Risks

- **Identity/quota exposure**: delegating as a named human account profile (`lucas`) means
  Hermes-triggered work consumes that person's OAuth quota and appears in their CCS
  instance history — needs an explicit decision (a dedicated `hermes` account profile via
  `ccs auth create hermes` is cleaner than borrowing a real user's identity, but wasn't
  confirmed — see assumption 4 above).
- **Harness drift**: "full harness" is whatever `~/.claude/` currently contains for that
  profile — if a human edits rules/skills mid-flight, delegated sessions silently pick up
  the change. Acceptable (same as human sessions) but worth a one-line doc note so it's
  not mistaken for a bug.
- **`--auto` forcing no-block AskUserQuestion inside the delegated session** needs the
  inner session to actually respect a flag/env for that — needs verification against
  current Claude Code CLI flags before writing the phase spec (not yet checked in this
  brainstorm pass).
- **Parallel multi-instance**: 3 concurrent `ccs <profile> -p` calls = 3 concurrent Claude
  Code sandboxed sessions each mutating the same repo unless the existing
  `delegation.git.isolate_branches: true` + worktree pattern is enforced per instance —
  already documented, just needs to be explicitly wired to the instance dimension too.

## Success Metrics / Validation

- `ccs <profile> -p "..."` invocation added to Tier 1 with a worked example, gated behind
  `harness: ccs` (default when agent is claude-code) vs `harness: bare` (opt-out).
- Bootstrap script prerequisite gap documented/fixed (5th CLI + `ReadWritePaths` note).
- CI's `validate_skills.py` continues to pass unchanged (no new toolset needed).
- A worked "3 parallel CCS instances, one subtask each, isolated branches" example mirrors
  the existing part18 "Parallel Delegation" recipe format.

## Next Steps

- Confirm the 4 flagged assumptions (skill scope, `--parallel`/`--auto` semantics, CCS
  profile ownership) — recommend a short follow-up AskUserQuestion pass once the user is
  back, before handing to `/ck:plan`.
- Once confirmed: `/ck:plan` (default mode — this is a moderate enhancement to an
  existing, already-tested skill, not a from-scratch build or a refactor of critical
  logic, so `--tdd` isn't obviously warranted, but worth asking too).

## Unresolved Questions

1. Skill scope: enhance `coding-agent-delegate` in place (assumed) vs new dedicated skill?
2. `--parallel`: multi-instance fan-out (assumed, new) vs multi-agent-type (existing) vs both?
3. `--auto`: Hermes-side approval skip only, inner-Claude-Code non-interactive only, or both (assumed)?
4. Which CCS account profile does Hermes delegate as — reuse an existing human profile
   (`lucas`), or provision a dedicated `hermes` CCS account? Config-default + per-call
   override assumed, but the *identity* choice itself is unconfirmed.
5. Does `--auto` actually map to an existing Claude Code CLI flag for "never block on
   AskUserQuestion, take recommended" — not yet verified against current CLI docs.
