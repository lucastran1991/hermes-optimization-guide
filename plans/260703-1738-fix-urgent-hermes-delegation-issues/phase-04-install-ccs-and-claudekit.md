---
phase: 4
title: "Install CCS And ClaudeKit"
status: in-progress
effort: "40m"
---

# Phase 4: Install CCS And ClaudeKit

**Priority:** P2 · **Status:** pending · **Effort:** ~40m · **Blocked by:** none (parallel group A) · **Ownership:** host-only, no repo writes · **Fully `[AGENT]`-autonomous.**

## Context Links

- Host verification: `research/live-host-verification-findings.md` §4 (ccs installable, currently absent), §5 (ClaudeKit installable, non-interactive `ck init` path), §8 (lineage).
- Skill this unblocks: `skills/dev/coding-agent-delegate/SKILL.md:48,83` (harness gated on `~/.claude/` presence).
- Prior decision being re-opened: `plans/260703-1041-ccs-full-harness-coding-agent-delegation/plan.md` (ClaudeKit scoped OUT at the time; Unresolved Q2).

## Overview

**This phase reverses plan `260703-1041`'s explicit "ClaudeKit install is out of scope" decision — by this session's explicit user EXPANSION choice (EXPANSION selected over HOLD/REDUCTION), not silent drift.** It installs `@kaitranntt/ccs@8.7.0` (the bootstrap line exists but never succeeded on this host — the binary is absent) and **`claudekit-cli`** (the package that provides the `ck` binary), then runs `ck init --global` so `~/.claude/` exists for the hermes user. Every step is fully non-interactive → agent-autonomous under NOPASSWD `sudo -u hermes`.

**Package-name correction (verified live).** The `ck` CLI this plan drives comes from **`claudekit-cli`** (`mrgoonie`; `npm view claudekit-cli version bin` → `4.5.1`, bin `ck`) — NOT the unqualified `claudekit` package (`carlrannaberg`; bins `claudekit`/`claudekit-hooks`, **no `ck`**). `readlink -f "$(command -v ck)"` on ubuntu's own working copy resolves to the `claudekit-cli` package. Installing `claudekit` would leave `ck init` failing with "command not found" and `harness: ccs` a permanent no-op. The `ck init --global --kit engineer --yes --install-skills --skip-setup` flags were checked against the real `claudekit-cli` `ck` binary this session, so they stay correct.

## Key Insights

- `ccs` is absent despite `vps-bootstrap-oci.sh:148-149` carrying the install line — guarded by `command -v ccs ||` and a trailing `|| echo "[warn]…"` that silently swallowed whatever failed. Registry reachable, `@kaitranntt/ccs@8.7.0` resolves cleanly from this network (findings §4). No script edit needed; the line just never ran to completion.
- hermes's default npm prefix (`/usr`) is **not writable** by hermes (EACCES) → every install MUST use `--prefix "$HOME/.local"` (findings §4), same as bootstrap.
- **The `ck` binary comes from `claudekit-cli`, not `claudekit`** (two different packages/authors — see Overview). Install `claudekit-cli`.
- ClaudeKit's skills catalog absent (`~/.claude/skills` missing) — that is exactly why `harness: ccs` is currently a no-op (`SKILL.md:48`). `ck init` has a fully non-interactive path: `-g/--global --yes --install-skills --skip-setup` (findings §5). `--global` targets user-level `~/.claude/` — correct, since delegated calls target arbitrary `repo=` paths, not one fixed project.
- Harness loads from `~/.claude/` presence, independent of ccs-vs-bare (`SKILL.md:83`) → once installed, even `harness: bare` hermes `claude` calls get the full CK rules/skills catalog **+ hooks**. This is a first-class capability/attack-surface change on the exact plain-`claude` path that caused this incident — treated in Security Considerations below (not a "stretch" footnote), documented in Phase 6.

## Requirements

`ccs` resolves on the hermes PATH; `~/.claude/skills` is non-empty **and `ck doctor` reports healthy** (mandatory — a bare non-empty count can pass on a partial `--install-skills` failure).

## Architecture

`[AGENT]` `sudo -u hermes` npm installs into `$HOME/.local` → `ck init --global` scaffolds `~/.claude/` (CLAUDE.md, rules, skills catalog, hooks) → verify presence.

## Related Code Files

None modified in the repo. Host-only. (Remediates the *intent* of `vps-bootstrap-oci.sh:148-149`; does not edit the script — the line is already correct.)

## Implementation Steps

All `[AGENT]` (NOPASSWD `sudo -u hermes`):

1. `[AGENT]` `sudo -u hermes bash -c 'npm install -g --prefix "$HOME/.local" @kaitranntt/ccs@8.7.0'`
2. `[AGENT]` `sudo -u hermes bash -c 'npm install -g --prefix "$HOME/.local" claudekit-cli'` (**`claudekit-cli`**, the package that provides `ck` — NOT `claudekit`).
3. `[AGENT]` `sudo -u hermes bash -c 'export PATH=$HOME/.local/bin:$PATH; ck init --global --kit engineer --yes --install-skills --skip-setup'`
4. `[AGENT]` **Supply-chain due-diligence** (Finding 14, non-blocking): `sudo -u hermes bash -c 'npm audit --prefix "$HOME/.local" 2>&1 | tail -20'` and record the resolved version + integrity hash of `@kaitranntt/ccs` (`sudo -u hermes bash -c 'npm ls -g --prefix "$HOME/.local" @kaitranntt/ccs --json 2>/dev/null | grep -E "version|resolved|integrity"'`, or read it from `$HOME/.local/lib/node_modules/@kaitranntt/ccs/package.json` + the lockfile) — carry these into Phase 6's memory note for future drift/tamper detection. No CI/OIDC provenance exists for this package, so this is best-effort, not a gate.
5. `[AGENT]` Verify: `sudo -u hermes bash -c 'export PATH="$HOME/.local/bin:$PATH"; command -v ccs'` resolves (the **PATH-wrapped bash** form — `sudo -u hermes command -v ccs` is doubly broken: `command` is a shell builtin, and `secure_path` lacks `~/.local/bin`); `sudo -u hermes bash -c 'ls ~/.claude/skills | wc -l'` > 0; **and mandatory** `sudo -u hermes bash -c 'export PATH="$HOME/.local/bin:$PATH"; ck doctor'` reports healthy (catches a partial `--install-skills` failure the count check would miss).

## Todo List

- [x] `ccs@8.7.0` installed into `~hermes/.local`. Integrity: `sha512-M/cRVa7tF+hGh8C20tpWNwgL0qzKCh2ciaY0xim5ryoJqUvIZars1JfvtseVtGyw0cGOogkbrUbIV+T65llxGg==`.
- [x] `claudekit-cli@4.5.1` installed into `~hermes/.local` (provides `ck`). Integrity: `sha512-0NlPLPSVoOMqYkcb7KgYmWGzBzA3IbQmwyCULahYytQ2b8ekLvg3aW1ICdyyGcOpgCoFDzCUsSJiVUss7OjWdA==`.
- [x] `ck init --global` completed.
- [x] `~/.claude/skills` non-empty (96 skills) + `~/.claude/agents` non-empty (14 agents). **DEVIATION from plan:** `ck init --install-skills` alone left the catalog empty because it fetches via `gh` and hermes has no GitHub CLI auth (new blocker found live, not anticipated in the plan). User's explicit choice (not gh-auth, not a shared token): copy the skill+agent collections from ubuntu's own `~/.claude/{skills,agents}` into hermes's `~/.claude/{skills,agents}` (staged via a world-readable tmp dir, copied as hermes so ownership is correct — no root/password needed, no credential shared).
- [~] **`ck doctor`: 25 PASS / 8 WARN / 3 FAIL** (after `ck doctor --fix` auto-remediated the skill-listing-budget issue). The 3 remaining FAILs are ALL `gh`-auth-only (GitHub Token / Repository Access / GitHub Reachability) — accepted per user's explicit choice to skip `gh auth login` for hermes. Not "fully healthy" per the plan's literal gate, but the functional requirement (non-empty skills catalog) is met via the copy approach.
- [x] `npm audit` **could not run** — npm does not support `audit` against global (`-g`) installs (`ENOLOCK`/`ESHRINKWRAPGLOBAL`, confirmed live, no lockfile mechanism exists for global prefixes). Substituted: recorded registry-published integrity hashes via `npm view <pkg>@<version> dist.integrity` (above) as the supply-chain due-diligence record instead.

## Success Criteria

`sudo -u hermes bash -c 'export PATH="$HOME/.local/bin:$PATH"; command -v ccs'` resolves; `~/.claude/skills` count > 0; `ck doctor` reports healthy.

## Risk Assessment

| Risk | L×I | Mitigation |
|------|-----|------------|
| Wrong package installed (`claudekit` ≠ `claudekit-cli`) → `ck` missing | (was live) | Install `claudekit-cli`; step 5 verifies `ck doctor` runs (proves the `ck` binary exists). |
| npm registry flake / version yanked | L×M | findings §4 confirmed reachable + version exists; retry. `ccs` pinned `@8.7.0`. |
| `claudekit-cli` unpinned (`@latest`) drifts | M×L | Matches the bootstrap pattern for the other CLIs; record the installed version in Phase 6's memory note so drift is traceable. |
| **`@kaitranntt/ccs` supply-chain (single maintainer, 1029 versions, no CI/OIDC provenance, bundles `bcrypt`/`express`/`ws`/`open`)** | L×H | `npm audit` + record resolved version/integrity hash (step 4) into Phase 6 memory for drift/tamper detection. No CI/OIDC alternative exists for this package → cannot block on it; documented, not eliminated. Runs under the same UID that holds the CCS credential (Phase 5) and can read the OAuth token (Phase 3 exfil risk). |
| **Full ClaudeKit harness auto-loads on EVERY hermes `claude` call (hooks + skills catalog), incl. the plain non-CCS path that caused this incident** | M×M | Accepted per EXPANSION choice; documented in Security Considerations below rather than narrowed (user chose full ClaudeKit — no `--exclude`/`--only` scoping added). |
| `ck init` prompts despite flags | L×M | findings §5 verified `--yes --skip-setup --install-skills` is non-interactive; if it still blocks it fails fast (agent surfaces, does not hang). |
| Install to wrong prefix → EACCES | L×H | Always `--prefix "$HOME/.local"`; never the system prefix. |
| Partial `--install-skills` (network drop) passes the count check | M×M | `ck doctor` is now a mandatory success gate (step 5) — count > 0 alone is insufficient. |

## Security Considerations

Installs run as the unprivileged hermes user (not root) — blast radius is the hermes home. `ck init --skip-setup` deliberately skips the provider-key wizard, so no key material is written here (that is Phase 5).

**Full ClaudeKit harness now auto-loads on every hermes `claude` invocation (first-class risk, not a stretch note).** Per `SKILL.md:83`, once `~/.claude/` exists, the full harness — `CLAUDE.md` + rules + the **entire skills catalog + hooks** — loads for *any* `claude` call by the hermes user, **independent of `harness: bare` vs `ccs`**. That includes the exact plain, non-CCS invocation path that caused THIS incident (a bot-initiated `claude --version`), and it is the `default: claude-code` Tier-1 agent path taken on every un-routed delegated task. Consequence: a compromised/rogue delegated task no longer runs inside a bare `claude` binary constrained to whatever `--allowedTools` the delegate skill passed — it runs inside a full harness that can fire ClaudeKit hooks (which shell out to Node/Python under `~/.claude/hooks/`) and reference any skill in the catalog. **Accepted per the user's EXPANSION choice (full ClaudeKit) — documented plainly, NOT narrowed** (no `--exclude`/`--only` catalog-scoping added, since that would quietly reduce what the user asked for). Follow-up option (not built): triage which hooks/skills should auto-load in a bot-delegation context.

**`~/.ccs/` and `~/.claude/` are richer auto-executing surfaces than "plugins."** The reference install (`/home/ubuntu/.ccs`) shows `hooks/`, `mcp/`, `cliproxy/`, `instances/` — i.e. event-fired hooks and long-running MCP servers, not just an API-key file. The widened `ReadWritePaths=/home/hermes/.ccs` (Phase 2) covers exactly this surface. Accepted per the EXPANSION choice (the `.ccs` widening was a pre-accepted risk in plan `260703-1041`), now named accurately (`hooks/` + `mcp/`, not "plugins").

## Rollback

`sudo -u hermes bash -c 'npm rm -g --prefix "$HOME/.local" @kaitranntt/ccs claudekit-cli'` and `sudo -u hermes bash -c 'rm -rf ~/.claude ~/.ccs'`. No repo or root state is touched.

## Next Steps

Unblocks Phase 5 (needs the `ccs` binary + a writable `~/.ccs`). ClaudeKit's presence makes `SKILL.md:48`'s "this guide does not install" stale — reframed in Phase 6. **Drift follow-up (open question):** these installs are manual and one-host; `vps-bootstrap*.sh` has an `ccs` line (`:148-149`) but **no `claudekit-cli`/`ck init` line**, so a fresh VPS bootstrap would still lack ClaudeKit. Consider adding `claudekit-cli` + `ck init` to bootstrap section 6b for repeatable provisioning — deliberately NOT done here (would make this phase write a repo file, breaking its host-only ownership); flagged for a follow-up. Phase 6's SKILL.md reframe must therefore describe ClaudeKit as "provisioned manually per-host," not bootstrap-covered like its four sibling CLIs.
