---
phase: 1
title: "Bootstrap CCS Prerequisites"
status: completed
priority: P2
effort: "1.5h"
dependencies: []
---

# Phase 1: Bootstrap CCS Prerequisites

## Context Links

- Brainstorm: `plans/reports/brainstorm-260703-1034-ccs-full-harness-delegation-skill-report.md` ("Prerequisites Gap" section)
- Existing CLI-install pattern: `scripts/vps-bootstrap.sh:103-127` ("6b. Coding-agent CLIs")
- systemd hardening: `templates/systemd/hermes.service` (`ProtectHome=read-only`, `ReadWritePaths=/home/hermes/.hermes /tmp`)
- Sibling precedent (bash -n test pattern): `plans/260703-0347-hermes-coding-agent-delegation-skill/phase-01-ci-toolset-validation.md`

## Overview

Priority: P2. Status: Pending. Parallel group A (no deps, runs alongside Phase 2).

`scripts/vps-bootstrap.sh`/`-oci.sh` install `claude`/`codex`/`gemini`/`opencode` for
the `hermes` service user but not `ccs` — so Phase 3's CCS-routed Tier-1 branch would
fail `ccs: command not found` (exit 127) in production, identical to the
`claude: command not found` failure mode the skill's own Prerequisites section
already documents for the 4 existing CLIs. Add `ccs` as a 5th CLI, and extend the
hardened systemd unit's `ReadWritePaths` to cover CCS's per-profile state directory
(currently blocked by `ProtectHome=read-only`).

## Key Insights

- Verified directly (`ccs --help`, `v8.7.0`, this session): `ccs` is a global npm
  package (`@kaitranntt/ccs` in this dev environment) providing the `ccs` binary —
  same install shape as `codex`/`gemini` (`npm install -g --prefix "$HOME/.local"
  ...`), not a curl-installer like `opencode`.
- `templates/systemd/hermes.service` today: `ProtectHome=read-only` +
  `ReadWritePaths=/home/hermes/.hermes /tmp` (verified by reading the file). CCS
  keeps per-profile state under `~/.ccs/` (session history, credentials,
  daemon socket, job queue — verified by listing a live `~/.ccs/instances/<profile>/`
  tree in this session: `.credentials.json`, `history.jsonl`, `daemon/`, `jobs/`,
  `sessions/`, etc.). Under the current unit, every write there would fail —
  `ccs <profile> -p` would error identically to a read-only filesystem, not just
  `command not found`. `ReadWritePaths` must add `/home/hermes/.ccs`.
- Do NOT add a new `XDG_STATE_HOME`-style redirect (the unit's existing comment
  explains that trick was used to avoid widening `ReadWritePaths` for one specific
  lock-dir case) — CCS's state directly under `~/.ccs` is what needs write access,
  a redirect doesn't apply here.
- **[Red-team, Critical, accepted] `~/.ccs` also holds shared, auto-executed code
  — `ReadWritePaths` as scoped here is broader than "per-profile state."** A live
  `~/.ccs` tree in this session also has `shared/hooks/`, `shared/plugins/`,
  `shared/skills/`, `shared/commands/`, `shared/agents/`, and top-level
  `hooks/*.cjs`/`mcp/*.cjs` — JS that CCS auto-loads on invocation, not scoped to
  one profile. Granting `/home/hermes/.ccs` write access (this phase's minimum
  viable fix, since CCS's own instance/shared layout isn't sub-path-documented)
  means a compromised Tier-1 task (`--allowedTools "Read,Edit,Bash"`, task text
  from an external chat platform) could write to shared hook/plugin code that
  runs on the NEXT invocation — a persistence path beyond one delegated session.
  **Mitigation shipped here:** grant `/home/hermes/.ccs` as the practical minimum
  (CCS's internal path layout isn't guaranteed stable enough to hand-carve a
  narrower allowlist from outside its source), but this is accepted as a known,
  documented risk, not a solved one — see Security Considerations below and
  `plan.md`'s Unresolved Questions.
- **[Red-team, Critical, accepted] `~/.claude` (the actual ClaudeKit harness —
  `CLAUDE.md`, `rules/*`, skills catalog, hooks) is never provisioned for the
  `hermes` service user by anything in this repo.** Verified: `grep -n
  "\.claude\b\|ClaudeKit" scripts/vps-bootstrap.sh scripts/vps-bootstrap-oci.sh
  templates/systemd/hermes.service` returns zero matches. `scripts/vps-bootstrap.sh:128-149`
  only symlinks *this guide's own* Hermes skills into `~/.hermes/skills/` — a
  completely different tree from ClaudeKit's `~/.claude/`. **This means CCS-routing
  by itself grants no harness at all on a fresh VPS.** `ccs <profile> -p` and bare
  `claude -p` both read the same `~/.claude/` on the same host (gated only by
  `claude`'s own `--bare` flag, which neither invocation passes) — CCS changes
  identity/quota, not harness. Getting an actual harness onto the `hermes` box
  requires separately installing ClaudeKit there — a distribution/install process
  this guide repo does not own or document, and is explicitly OUT OF SCOPE for
  this phase (see `plan.md` Overview + Unresolved Questions). This phase's `ccs`
  CLI install is a necessary but NOT sufficient step for "full harness" — say so
  plainly in the skill's docs (Phase 3) rather than implying `ccs`-routing alone
  delivers it.

## Requirements

- Functional: `ccs` binary installed and on the `hermes` service PATH in both
  bootstrap script variants; systemd unit grants write access to `~/.ccs`.
- Non-functional: match the existing `command -v <cli> >/dev/null 2>&1 || npm
  install ... || echo "[warn] ... install failed"` idempotent pattern already used
  for `codex`/`gemini` (no new install style introduced).

## Architecture

No runtime architecture — this is an install-script + systemd-unit change. Data
flow: bootstrap script installs `ccs` into `~/.local/bin` (already on the service
PATH per the file's own section 7 note) → systemd unit's `ReadWritePaths` widened →
`ccs <profile> -p "..."` (added in Phase 3) can read `~/.claude/` (untouched,
already readable) and write `~/.ccs/instances/<profile>/` (now permitted).

## Related Code Files

**Modify:**
- `scripts/vps-bootstrap.sh` (~line 103-127, section "6b. Coding-agent CLIs") — add
  `ccs` install line.
- `scripts/vps-bootstrap-oci.sh` — same section, mirrored.
- `templates/systemd/hermes.service` — extend `ReadWritePaths`.

**Create:** none. **Delete:** none.

## Implementation Steps (TDD)

### 1. Tests Before (baseline / regression protection)

1. Run `bash -n scripts/vps-bootstrap.sh && bash -n scripts/vps-bootstrap-oci.sh` —
   confirm both currently pass (baseline).
2. `grep -c 'command -v .* >/dev/null 2>&1 ||' scripts/vps-bootstrap.sh` — record
   current count (4, one per existing CLI) as the regression baseline; the count
   must be 5 after this phase, never fewer.

### 2. Implement

3. In `scripts/vps-bootstrap.sh`'s section 6b (after the `gemini` install line,
   `~line 126`), add:
   ```bash
   command -v ccs >/dev/null 2>&1 || \
     npm install -g --prefix "$HOME/.local" @kaitranntt/ccs@8.7.0 || echo "[warn] ccs install failed"
   ```
   **[Red-team, High, accepted]** Pin the version (`@8.7.0`, matching the version
   verified throughout this plan) rather than installing `@latest` — `@kaitranntt/ccs`
   is a single-maintainer personal-scope package (unlike the vendor-owned
   `@openai/codex`/`@google/gemini-cli`), and this dependency now sits in the trust
   chain for both credentials and auto-executed hook/plugin code (see Key Insights
   above) — an unpinned install on a hardened production service is a wider
   supply-chain exposure than the existing 3 npm-installed CLIs already accept.
   Bump the pin deliberately when upgrading, not automatically.
   Update the section's leading comment (`~line 12`, "Installs coding-agent CLIs
   (claude, opencode, codex, gemini) as hermes") to list `ccs` too, and update the
   trailing `warn` message (`~line 127`) if it enumerates CLI names.
4. Mirror the same line into `scripts/vps-bootstrap-oci.sh`'s equivalent section.
5. In `templates/systemd/hermes.service`, change:
   ```
   ReadWritePaths=/home/hermes/.hermes /tmp
   ```
   to:
   ```
   ReadWritePaths=/home/hermes/.hermes /home/hermes/.ccs /tmp
   ```
   Add a one-line comment above it (matching the file's existing comment style)
   noting `.ccs` holds per-profile CCS state (credentials, session history, job
   queue) needed by the coding-agent-delegate skill's CCS-routed Tier 1.

### 3. Tests After

6. Re-run `bash -n scripts/vps-bootstrap.sh && bash -n scripts/vps-bootstrap-oci.sh`
   — both still pass.
7. `grep -c 'command -v .* >/dev/null 2>&1 ||' scripts/vps-bootstrap.sh` — now 5, and
   confirm the 4 pre-existing lines (`claude`, `opencode`, `codex`, `gemini`) are
   byte-for-byte unchanged (`git diff` shows only additions, no modified lines in
   the pre-existing 4 entries).
8. `grep -n 'ReadWritePaths=' templates/systemd/hermes.service` — confirm it now
   lists `/home/hermes/.ccs`.

### 4. Regression Gate

9. `bash -n` on both scripts must exit 0. `git diff --stat` on
   `templates/systemd/hermes.service` must show only the `ReadWritePaths` line (and
   its new comment) changed — no other hardening directive touched.
10. **[Red-team, Critical, accepted — go/no-go gate]** This phase's install +
    `ReadWritePaths` steps are necessary but NOT sufficient. Before Phase 3's skill
    documents `harness: ccs` as usable in a given deployment, the operator must
    independently: (a) provision ClaudeKit (`~/.claude/CLAUDE.md` + `rules/*` +
    skills) onto the `hermes` box — out of this repo's scope, see Key Insights; (b)
    provision a CCS profile (Phase 2); (c) run a smoke test:
    `ccs "<ccs_profile>" -p "echo ok" --output-format json` and confirm exit 0 with
    valid JSON. This is a manual go/no-go check, not something this phase's scripts
    can verify automatically (no CI runner has a provisioned `hermes` box to test
    against) — document it as a required manual step, do not claim it's satisfied
    by this phase's own file changes.

## Success Criteria

- [x] `ccs` install line present in both `scripts/vps-bootstrap.sh` and
      `scripts/vps-bootstrap-oci.sh`, using the same idempotent
      `command -v || npm install ... || warn` pattern as `codex`/`gemini`, pinned
      to `@8.7.0` (not `@latest`).
- [x] `bash -n` passes on both scripts.
- [x] The 4 pre-existing CLI install lines are unchanged (verified via `git diff`).
- [x] `templates/systemd/hermes.service`'s `ReadWritePaths` includes
      `/home/hermes/.ccs`, with no other hardening directive altered.
- [x] Manual smoke-test step (`ccs "<profile>" -p "echo ok" --output-format json`
      exits 0) documented as a required go/no-go gate before enabling
      `harness: ccs` in a real deployment — not silently assumed to pass.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `@kaitranntt/ccs` package name/version drifts from what's actually installed in a given deploy | Med | Med | Pin `@8.7.0` (step 3); install failure warns, doesn't hard-fail bootstrap, same posture as the other 3 npm-installed CLIs |
| Widening `ReadWritePaths` to `/home/hermes/.ccs` grants write access to shared, auto-executed hook/plugin code, not just per-profile state (**was Low/Low, corrected to Med/High by red-team**) | Med | High | Documented explicitly as an accepted, unresolved risk (Key Insights above) — CCS's internal path layout isn't stable/documented enough from outside its source to hand-carve a narrower allowlist; flagged in `plan.md` Unresolved Questions for future tightening once CCS's own docs cover this |
| `opencode`'s curl-installer section (different install shape) accidentally edited instead of the npm-style CLIs | Low | Low | Step 3 explicitly targets "after the `gemini` install line" — `opencode`'s block stays untouched |
| Operator enables `harness: ccs` in production without completing the ClaudeKit-provisioning + profile + smoke-test prerequisites (step 10) | Med | High | Step 10 is an explicit go/no-go gate; Phase 3 defaults `harness` to `bare` (not `ccs`) precisely so this failure mode requires an active opt-in, not an accidental default |

## Security Considerations

`ReadWritePaths=/home/hermes/.ccs` grants the hardened service write access to a new
directory tree containing Claude credentials (`.credentials.json` per profile),
session history, AND shared auto-executed code (`~/.ccs/shared/hooks`, `plugins`,
`skills`, `commands`, `agents` — see Key Insights). This is a broader trust grant
than the existing `/home/hermes/.hermes` (secrets/config only, no auto-executed
code) — **accepted here as a known, documented risk**, not eliminated, because CCS
doesn't publish a stable per-profile-only subpath to scope `ReadWritePaths` to. A
compromised delegated task (attacker-influenced text reaching `--allowedTools
"Read,Edit,Bash"`) could in principle write to shared hook/plugin code that
executes on the next invocation — treat this the same way as any other write
access granted to a service that also runs untrusted task text, and revisit if CCS
later documents a narrower state path. No new `security.approval` wiring needed:
`templates/config/production.yaml`'s `delegation.approval.require_approval`
already gates `delegate_task` dispatch (Phase 2 confirms, doesn't add this) —
independent of which binary Tier 1 shells out to. That gate covers *whether a
delegation dispatches at all*, not what a dispatched session can reach once
approved — the `ReadWritePaths` risk above is a separate, unresolved layer.

## Next Steps

Unblocks Phase 3's naming of the CCS prerequisite/install step in the skill's own
Prerequisites section.
