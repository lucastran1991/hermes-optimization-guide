---
phase: 1
title: "Deploy-Drift Prevention Tooling"
status: completed
effort: "1h20m"
---

# Phase 1: Deploy-Drift Prevention Tooling

**Priority:** P2 · **Status:** pending · **Effort:** ~1h20m · **Blocked by:** none (parallel group A) · **Ownership:** repo-only authoring (`[AGENT]`) + a `[HUMAN]` reconcile of the canonical `/opt` clone

## Context Links

- Root-cause report: `plans/reports/ck-debug-260703-1725-hermes-seccomp-claude-sigsys-stale-unit-report.md` (its Unresolved Questions call for repo-side deploy automation to prevent repeat drift).
- Host verification: `plans/260703-1738-fix-urgent-hermes-delegation-issues/research/live-host-verification-findings.md` §1, §2.
- House style + current unit-install pattern: `scripts/vps-bootstrap-oci.sh:44-50` (helpers), `:194-198` (install/enable).

## Overview

The P0 fix (Phase 2) sat undeployed for a full day because there is **no repo-side tooling that syncs `templates/systemd/*.service` to `/etc/systemd/system/`**. Someone has to remember to `install` + `daemon-reload` + `restart` by hand. `vps-bootstrap-oci.sh:194-198` installs units only during a full bootstrap run — unconditionally, and it `enable`s but never `restart`s (correct at bootstrap, useless for "I just edited a template, push it").

Add `scripts/deploy-systemd-units.sh`: for each canonical `templates/systemd/*.service`, diff against its live counterpart; install only changed/absent units; `daemon-reload` once if anything changed; restart **only** units that both changed **and** are currently active; print a summary. Idempotent, re-runnable, self-elevating (`sudo` per privileged command) so a human can run `bash scripts/deploy-systemd-units.sh`. Plus a README note pointing operators at it after editing any unit template. This is the process fix for the exact gap that caused the Phase 2 incident.

**Canonical source-of-truth clone (structural fix, verified live).** There are TWO clones on this host: the bootstrap-canonical `/opt/hermes-optimization-guide` (`GUIDE_DIR` in `scripts/vps-bootstrap-oci.sh:105` and `scripts/vps-bootstrap.sh:89` — the clone whose `templates/systemd/*.service` bootstrap installs and whose `skills/*` are symlinked into `~hermes/.hermes/skills/`), and the developer workspace clone this plan is authored from (`/home/ubuntu/workspace/hermes-optimization-guide`). They have diverged: `/opt` HEAD = `e6a26fe` (2026-07-01) and its `templates/systemd/hermes.service` has **zero** `sched_setscheduler` (the fix this plan deploys). A naive diff-then-install script pointed at the wrong clone would see the *fixed live* unit (post-Phase-2) differ from `/opt`'s *stale* template and silently reinstall the pre-fix unit — reintroducing the SIGSYS crash via the very tool meant to prevent recurrence. Fix: (a) the script reads its templates from `GUIDE_DIR="${GUIDE_DIR:-/opt/hermes-optimization-guide}"` (the canonical clone — so it always knows which source to trust, regardless of where the script file is invoked from), and warns/refuses if `/opt`'s `main` is behind `origin/main` (stale canonical); (b) a `[HUMAN]` reconcile step brings `/opt` current before first use. Both fix commits are confirmed present in `origin/main` (verified: `c9631fc`, `72cc2fd` are ancestors of `origin/main`), so `git -C /opt … pull --ff-only` is safe and sufficient — no local-only commit is needed. `/opt` and the workspace clone share the same remote (verified: both `git@github.com:lucastran1991/hermes-optimization-guide.git`). This reconcile also lands `skills/dev/coding-agent-delegate` into `/opt`, unblocking Phase 6's skill symlink.

**Honest scoping (what actually prevents recurrence).** The script improves the *correctness and safety* of a redeploy once someone remembers to run it (diff-before-copy, restart-gating, stale-canonical guard). The actual behavior-change that prevents the incident recurring is the **README note** telling operators to run it after editing a unit template — a human-facing reminder, not enforcement. Per the confirmed Phase 1 scope decision, both the script and the note ship (no reduction to note-only). No new enforcement machinery (CI gate, `PathChanged=` watcher) is added — out of scope; noted as a possible future follow-up in Next Steps.

**Creating the script and README note is entirely `[AGENT]` work** (repo files, no privilege). Reconciling `/opt` (root-owned, verified `755 root:root`) and *running* the script against `/etc` are `[HUMAN]` (root file write / root-owned clone, password-gated).

## Key Insights

- No deploy automation exists today (debug report Unresolved Qs; findings §1). Bootstrap installs units at provision time only.
- **Two clones, one canonical (verified live).** `/opt/hermes-optimization-guide` (root-owned `755`, bootstrap `GUIDE_DIR`) is the on-host source-of-truth bootstrap actually installs from and symlinks skills from; the workspace clone is developer/transient. `/opt` is 2 days stale (`e6a26fe`, no `sched_setscheduler`). The script MUST read templates from the canonical clone, not `$PWD`/`$BASH_SOURCE`, or it can redeploy a stale pre-fix unit (Finding 4).
- **Reconcile is `[HUMAN]`.** `/opt` is root-owned → `git -C /opt … pull --ff-only` needs root (password-gated, outside the `sudo -u hermes` NOPASSWD grant). Safe as a fast-forward: both fix commits (`c9631fc`, `72cc2fd`) are already ancestors of `origin/main`, and both clones share the same remote.
- Agent sudo scope (findings §2): NOPASSWD for `sudo -u hermes …`, `systemctl {start,stop,restart,status} hermes*`, `daemon-reload`, `journalctl -u hermes*`. A generic root write to `/etc` is **password-gated** → the script's `install` step prompts for a password → running it is `[HUMAN]`. (`daemon-reload` and `restart hermes*` are within NOPASSWD, but the `install` gates the whole run.) Note `systemctl show` and `journalctl -k` are NOT in this grant (relevant to Phase 2's verification, not this phase).
- `/etc/systemd/system/*.service` are mode 0644, world-readable → diffing needs no privilege.
- House style (findings-cited `vps-bootstrap-oci.sh`): `#!/usr/bin/env bash`, `set -euo pipefail`, colored `log()`/`warn()`/`die()` prefixes. Mirror them for consistency.
- `shellcheck` is **not** installed on this host (verified) → the hard syntax gate is `bash -n`; run `shellcheck` only if later available.

## Requirements

**Functional:** (1) resolve the canonical clone `GUIDE_DIR="${GUIDE_DIR:-/opt/hermes-optimization-guide}"` and warn/refuse if its `main` is behind `origin/main` (stale-canonical guard); (2) compare each `"$GUIDE_DIR"/templates/systemd/*.service` to `/etc/systemd/system/<name>`; (3) install (0644 root:root) only differing/absent units; (4) `daemon-reload` iff ≥1 unit changed; (5) restart only changed units that are currently active; (6) print a summary (changed / restarted / unchanged-skipped / deployed-but-inactive).
**Non-functional:** idempotent, re-runnable, deploys from the canonical clone (never `$PWD`/`$BASH_SOURCE`), self-elevating via `sudo`, `bash -n`-clean.

## Architecture

Data in: **canonical** `"$GUIDE_DIR"/templates/systemd/*.service` (`GUIDE_DIR` defaults to `/opt/hermes-optimization-guide`). Transform: `diff -q` vs live. Data out: updated `/etc/systemd/system/*.service` + systemd runtime state.

Flow: `GUIDE_DIR="${GUIDE_DIR:-/opt/hermes-optimization-guide}"` → **stale-canonical guard:** `git -C "$GUIDE_DIR" fetch --quiet` then, if `git -C "$GUIDE_DIR" rev-list --count main..origin/main` > 0, `warn` loudly + refuse without `--force` (the canonical clone is behind the remote that carries the fixes — deploying from it would regress) → `shopt -s nullglob` over `"$GUIDE_DIR"/templates/systemd/*.service` → per unit: if live absent or `! diff -q` → `sudo install -m 0644 -o root -g root` and record as changed → after loop, if any changed: `sudo systemctl daemon-reload`, then per changed unit `systemctl is-active --quiet <name>` ? `sudo systemctl restart <name>` : record deployed-inactive → print summary. Sourcing from `GUIDE_DIR` (not the script's own location) means even a developer running the workspace copy deploys the *canonical* templates — the mechanism that makes "which source to trust" explicit (Finding 4a).

## Related Code Files

- **Create:** `scripts/deploy-systemd-units.sh` (chmod +x).
- **Modify:** `README.md` — add a Repo Map row (after the `vps-bootstrap.sh` row, ~line 69) and one **prominent** sentence near the systemd-units line (~line 67) or the bootstrap description (~line 53). The note must name the canonical clone explicitly: *the on-host source-of-truth is `/opt/hermes-optimization-guide` (the bootstrap `GUIDE_DIR`); after editing any `templates/systemd/*.service`, reconcile that clone (`git -C /opt/hermes-optimization-guide pull --ff-only`) then run `scripts/deploy-systemd-units.sh` (needs `sudo`) to deploy it.* This note — not the script — is what actually prevents recurrence, so keep it un-buried.
- **Read for style only:** `scripts/vps-bootstrap-oci.sh:44-50,194-198`; `GUIDE_DIR` convention at `:105`.
- **Do NOT edit** `CHANGELOG.md` here — it is Phase 6's (avoids a parallel-cook write conflict).
- **Host reconcile (not a repo file):** `/opt/hermes-optimization-guide` — `[HUMAN]` `git pull --ff-only` (root-owned).

## Implementation Steps

1. `[AGENT]` Read `scripts/vps-bootstrap-oci.sh:44-50` (helpers + `set -euo pipefail`), `:105` (`GUIDE_DIR`), and `:194-198` (install pattern) for house style.
2. `[AGENT]` Create `scripts/deploy-systemd-units.sh`:
   - shebang, `set -euo pipefail`, same `log`/`warn`/`die` palette.
   - `GUIDE_DIR="${GUIDE_DIR:-/opt/hermes-optimization-guide}"` (canonical clone; mirrors bootstrap); `TPL_DIR="$GUIDE_DIR/templates/systemd"`. Do NOT derive the source from `$BASH_SOURCE`/`$PWD` — the script must deploy the canonical templates no matter where its file lives.
   - **Stale-canonical guard:** `git -C "$GUIDE_DIR" fetch --quiet origin 2>/dev/null || true`; `behind=$(git -C "$GUIDE_DIR" rev-list --count main..origin/main 2>/dev/null || echo 0)`; if `[ "$behind" -gt 0 ]` and not `--force`: `die` with a loud message ("canonical clone $GUIDE_DIR is $behind commits behind origin/main — reconcile with 'git -C $GUIDE_DIR pull --ff-only' before deploying, or pass --force"). This is the guard against redeploying a stale/pre-fix template.
   - `shopt -s nullglob`; iterate `"$TPL_DIR"/*.service`; `name="$(basename "$tpl")"`; `live="/etc/systemd/system/$name"`.
   - if `[ ! -f "$live" ] || ! diff -q "$tpl" "$live" >/dev/null`: `sudo install -m 0644 -o root -g root "$tpl" "$live"`; append `name` to a `changed` array; else append to `unchanged`.
   - after loop: if `((${#changed[@]}))` → `sudo systemctl daemon-reload`; per `name` in `changed`: `if systemctl is-active --quiet "$name"; then sudo systemctl restart "$name"` (record restarted) `else` record deployed-inactive.
   - print a summary block (counts + names for each category).
   - `chmod +x scripts/deploy-systemd-units.sh`.
3. `[AGENT]` Add the README Repo Map row + one **prominent** deploy sentence naming the canonical `/opt` clone (see Related Code Files).
4. `[HUMAN]` **Reconcile the canonical clone** (unblocks the script's safe use AND Phase 6's skill symlink): confirm `git -C /opt/hermes-optimization-guide remote -v` matches `origin` and `git -C /opt/hermes-optimization-guide status` shows no local commits, then `sudo git -C /opt/hermes-optimization-guide pull --ff-only`. Safe fast-forward — both fix commits are already in `origin/main`. Verify post-condition: `grep -c sched_setscheduler /opt/hermes-optimization-guide/templates/systemd/hermes.service` = 1 AND `ls -d /opt/hermes-optimization-guide/skills/dev/coding-agent-delegate` resolves.
5. `[HUMAN]` (later, not part of authoring) Run `bash scripts/deploy-systemd-units.sh` from the reconciled canonical clone — prompts for the sudo password on the `/etc` write. This is the same operation Phase 2 performs by hand; the script generalizes it for every future template edit. (The new script itself becomes usable from `/opt` once it merges to `origin` and `/opt` next pulls; Phase 2's P0 deploy does not depend on it.)

## Todo List

- [x] `scripts/deploy-systemd-units.sh` created, executable, `bash -n`-clean. (code-reviewed, 2 low-priority polish items applied: restart-scope wording, rev-list-failure warn)
- [x] Templates sourced from `GUIDE_DIR` (canonical `/opt` clone), never `$BASH_SOURCE`/`$PWD`.
- [x] Stale-canonical guard: refuses (without `--force`) when `/opt`'s `main` is behind `origin/main`. (verified in sandbox by code-reviewer)
- [x] Diff-before-copy: unchanged units skipped (no needless restart).
- [x] Restart gated on changed AND `is-active`.
- [x] Brand-new/inactive units deployed + `daemon-reload`, NOT auto-started/enabled.
- [x] Clear summary printed.
- [x] README row + **prominent** deploy sentence (names the canonical `/opt` clone).
- [x] `[HUMAN]` `/opt` reconciled. **Note:** SSH `pull --ff-only` failed with `Permission denied (publickey)` — root cause: sudo's `env_reset` resets `HOME` to `/root`, so SSH can't find ubuntu's `~/.ssh/id_ed25519_github` (referenced via ubuntu's `~/.ssh/config`). Resolved via HTTPS one-off pull instead (repo is public, no auth needed): `sudo git -C /opt/hermes-optimization-guide pull --ff-only https://github.com/lucastran1991/hermes-optimization-guide.git main`. Post-condition verified: HEAD=`5b60fd4`, `grep -c sched_setscheduler` = 2, `skills/dev/coding-agent-delegate` present, working tree clean. Minor cosmetic artifact: `refs/remotes/origin/main` tracking ref is stale (pulled via raw URL, not the `origin` remote) — `git status` shows a misleading "ahead by N" that doesn't reflect reality; harmless (doesn't affect the script's stale-canonical guard, which only blocks on being *behind*), optionally fixable with `sudo env HOME=/home/ubuntu git -C /opt/hermes-optimization-guide fetch origin main`.

## Success Criteria

- `bash -n scripts/deploy-systemd-units.sh` exits 0 (and `shellcheck` clean if available later).
- Idempotence: on an already-synced host, a re-run reports "0 changed, nothing to do".
- Stale-canonical guard fires: with `/opt` deliberately behind `origin/main`, the script refuses to deploy without `--force` (proves it can't silently redeploy a pre-fix unit).
- Non-disruptive: after Phase 2 has deployed `hermes.service`, running the script (from the reconciled canonical clone) reports it **unchanged** and does not restart it — proves it won't bounce a healthy service.
- `/opt` reconciled: `grep -c sched_setscheduler /opt/.../templates/systemd/hermes.service` = 1 and `skills/dev/coding-agent-delegate` present.
- README shows the new script and the post-edit deploy instruction naming the canonical clone.

## Risk Assessment

| Risk | L×I | Mitigation |
|------|-----|------------|
| **Stale canonical `/opt` clone silently redeploys the pre-fix unit → reintroduces SIGSYS** | M×H | Script sources templates from `GUIDE_DIR` (canonical) + refuses when `/opt` is behind `origin/main` (stale-canonical guard); `[HUMAN]` reconcile step brings `/opt` current first; README note names the canonical clone so operators edit/deploy the right one. |
| Restarts an intentionally-stopped unit | M×M | Restart only if `systemctl is-active --quiet`. |
| Auto-starts a brand-new unit unexpectedly | L×M | Deploy file + `daemon-reload` only; never `enable`/`start` a new inactive unit — leave that to bootstrap/human. |
| Partial failure mid-loop → mixed state | L×H | `set -euo pipefail` aborts on first error; install precedes restart, so a failed restart still leaves the correct file on disk (re-run or manual `systemctl restart` recovers); print summary-so-far + a `journalctl -u <unit>` pointer. |
| Reconcile `pull --ff-only` fails (local commits / divergence in `/opt`) | L×M | Guard/step confirms `remote -v` matches and `status` is clean first; `--ff-only` refuses rather than forcing a merge — human resolves. Both fix commits already in `origin/main`, so no local commit needed. |
| A future non-`hermes*` unit template needs a restart outside agent NOPASSWD scope | L×L | Only two `hermes*` templates today; documented — the `sudo systemctl restart` self-elevates, so a human running the script still works. |
| **Stale-canonical guard's `git fetch` always fails on this host (live-confirmed), degrading to "warn and proceed with current HEAD" every run** | M×L | Confirmed live 2026-07-03: `git -C /opt fetch origin` fails both as the invoking user (non-root, no write access to `/opt/.git`) AND when the whole script is run via `sudo bash ...` (root has no SSH key at `/root/.ssh` — same `HOME`-reset issue as the manual `/opt` reconcile). The guard therefore can only ever warn, never actually block on staleness, unless someone runs it with `HOME=/home/ubuntu` explicitly preserved. Non-blocking (script still deploys correctly using current HEAD, verified 0-changed on a synced host) — flagged as a follow-up, not fixed this pass. |

## Security Considerations

- Writes to `/etc` are root-owned and password-gated; the script self-elevates per privileged command (`sudo install` / `sudo systemctl …`) rather than requiring the whole script to run as root.
- Deploys only repo-tracked unit files. Supply-chain caveat (pre-existing, out of scope): a compromised `main` could ship a malicious unit that this script would then install — same trust boundary as `vps-bootstrap*.sh`; noted in prior security scans, not introduced here.
- No secrets touched.

## Rollback

Additive only. Revert = `git checkout -- scripts/deploy-systemd-units.sh README.md` (or delete the new file). Merely *creating* the script changes no host state. The `/opt` reconcile is a forward-only fast-forward that aligns the canonical clone with the remote it already tracks — there is nothing to roll back (reverting it would re-introduce the staleness this phase exists to remove). A bad *run* of the script is covered by Phase 2's rollback (back up the live unit before overwriting).

## Next Steps

Gives Phase 2 (and every future `templates/systemd/*` edit) a repeatable, canonical-clone-safe deploy path. **The `/opt` reconcile step also unblocks Phase 6's `coding-agent-delegate` skill symlink** (which sources from `/opt/skills/dev/`), so this phase is no longer fully independent — Phase 6 lists Phase 1 as a blocker. Related gap to flag: Phase 4 installs `claudekit-cli` manually but `vps-bootstrap*.sh` has no `claudekit`/`ck init` line (it does have the `ccs` line at `:148-149`) — the same "manual change not captured in repeatable tooling" class this phase fixes for units; see Phase 4 Next Steps. Deferred follow-up (out of scope per the confirmed scope decision): enforce the deploy via a CI check or a host `PathChanged=` watcher so it can't be forgotten — not built now.
