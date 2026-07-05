---
title: "Red-team adjudication — Automate Hermes Delegation Provisioning plan"
date: 2026-07-04
type: red-team-adjudication
plan: plans/260704-2106-bootstrap-script-delegation-provisioning-scripts/plan.md
---

# Red Team Adjudication

4 reviewers (Security Adversary, Failure Mode Analyst, Assumption Destroyer, Scope & Complexity Critic), 26 raw findings → deduplicated to 15 after merging overlaps (3 dup pairs merged, 2 finding-clusters combined). All 15 pass the evidence filter (file:line or empirical confirmation each).

**Headline finding (A3):** this plan's own premise may be moot — a same-day debug report already root-caused that `hermes.service` is missing `hermes`'s `~/.local/bin` on its systemd `PATH`, so real delegated `ccs`/`claude` calls fail `command not found` regardless of every credential this plan provisions. Every phase's smoke test uses `sudo -u hermes -i` (an unsandboxed login shell) which **masks** this exact bug. Proposed: **Accept**, add a Phase 0 (or fold into Phase 1) that fixes/verifies the PATH gap first, since nothing else in this plan matters until it's closed.

## Critical (7) — all proposed Accept

| # | Finding | Phase | Rationale for Accept |
|---|---|---|---|
| 1 | `hermes.service` PATH gap not addressed; smoke tests mask it | New/Phase 1 | Already root-caused same day (`ck-debug-260704-1355...report.md`); this plan is pointless without it |
| 2 | `cp -a` copies entire ken instance (transcripts, projects/, session-env/), not just credentials | Phase 5 | Real privacy/data-exposure overreach vs. what the plan describes doing |
| 3 | `--instance=<name>` unsanitized, path traversal, root-privileged | Phase 5 | Concrete injection primitive, cheap to fix (charset allowlist) |
| 4 | `gh` CLI never installed in `vps-bootstrap-oci.sh` | Phase 2 | Phase 2 fails immediately on a genuinely fresh host — the exact case this plan claims to serve |
| 5 | Run order guarantees empty-skills bug fires every fresh-host run, no automated fix-after | Phase 1 | Confirmed by 2 independent reviewers (Failure Mode + Scope Critic) |
| 6 | Phase 6 YAML-validate gate broken 2 ways: PyYAML not installed anywhere outside CI, AND `safe_load` silently accepts duplicate top-level keys even if it were | Phase 6 | Confirmed by 2 independent reviewers with different root causes for the same broken gate |
| 7 | Phase 6 needs local `production.yaml` but no `GUIDE_DIR` resolution/stale-clone guard, contradicts own curl\|bash constraint | Phase 6 | Real gap vs. the `deploy-systemd-units.sh` pattern it claims to mirror |

## High (6) — all proposed Accept

| # | Finding | Phase |
|---|---|---|
| 8 | `--force` on `ccs api create` claimed "VERIFIED" with no actual trail; contradicts sibling plan's documented form | Phase 4 |
| 9 | Bridge script copies `instances/<name>/` only, not the root `~/.ccs/config.yaml` alongside it — profile may not resolve | Phase 5 |
| 10 | New idempotency guard omits the `PATH` export its own cited mirror (section 6b) uses | Phase 1 |
| 11 | ClaudeKit installed outside `hermes.service`'s `ReadWritePaths` under `ProtectHome=read-only` — real writes may `EROFS` | Phase 1 |
| 12 | Unverified `sudo -u hermes -i <binary> <args>` form used; only `bash -c '<cmd>'` proven working this project (bitten twice today already) | Phases 2,4,5 |
| 13 | `delegation:` block grafted onto a config actually shaped like `cost-optimized.yaml` (8 fewer top-level keys); copy-boundary mechanism unspecified | Phase 6 |

## Medium (2 kept, rest capped) — proposed Accept

| # | Finding | Phase |
|---|---|---|
| 14 | Phase 3's credential gate is a bare non-empty-string check, unlike 4/5's mandatory smoke test | Phase 3 |
| 15 | Credential-bearing scripts leak their own argv (`--token=`/`--api-key=`) via `ps`/history for the whole runtime — bigger blast radius than the existing accepted curl\|bash risk, undocumented | Phases 2-5 |

**Dropped at the 15-cap (logged, not silently discarded — all Medium, cheap hygiene items):**
- Phase 6 doesn't structurally distinguish a bridge-sourced profile from a dedicated one
- Phase 5 ignores CCS's own `.locks/` concurrency file (low real-world odds, single-operator host)
- No `--ccs-profile=` input validation, no `EUID==0` guard, Phase 6's replace-logic called "speculative generality" — 3 small hygiene nits bundled

**One reviewer point I'm proposing Reject:** Scope Critic argued `0-gh-auth.sh` "solves an already-solved problem" (today's host got a manual `cp` workaround). Reject — that workaround only worked because ubuntu's own `~/.claude` was already populated; a genuinely fresh host has nothing to copy, so gh-auth automation still has real value for the plan's stated future-host purpose.

## Your call

