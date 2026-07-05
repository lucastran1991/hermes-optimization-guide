---
title: "Live-host verification of plans/260703-1738-fix-urgent-hermes-delegation-issues phase statuses"
date: 2026-07-04
type: verification
plan: plans/260703-1738-fix-urgent-hermes-delegation-issues/plan.md
---

# Phase status vs live host reality (lucas-oracle-instance)

Verified each phase's claimed status against live commands (not re-reading the plan's own claims as truth). Findings below only — no plan-content questioned unless evidence contradicts it.

## Phase-by-phase

| Phase | Plan says | Live evidence | Verdict |
|---|---|---|---|
| 1 Deploy-drift tooling | Completed | `scripts/deploy-systemd-units.sh` used successfully this session (diff-detected, restarted only changed unit, skipped unchanged). `/opt` was stale before this session (missing IMDS fix), reconciled today via HTTPS fetch (SSH key on root not set up — worked around). | **Accurate, still holds.** |
| 2 Deploy P0 systemd fix | Completed | `hermes.service` running, no SIGSYS, restarted cleanly for today's IMDS fix too. | **Accurate.** |
| 3 Claude auth for hermes | Pending — `[HUMAN]` login needed | `claude auth status` for hermes → `loggedIn: true, subscriptionType: team`. `md5sum` of `/home/hermes/.claude/.credentials.json` vs `/home/ubuntu/.claude/.credentials.json` → **identical** — this is a raw file copy of ubuntu's own personal account, not a `claude auth login` by a dedicated seat. | **Stale status text AND non-compliant.** Technically "logged in" now (status line should not still say Pending), but violates Validation Session 1 Q4's confirmed decision ("dedicated bot-specific seat, not personal account", plan.md:167-170). Done via an out-of-plan bridge (see `[[hermes-temporarily-shares-ubuntu-personal-claude-credential]]` memory), not via this phase's documented procedure. |
| 4 Install CCS + ClaudeKit | In progress — installed, `ck doctor` 3 accepted gh-auth FAILs | `ccs` v8.7.0 installed for hermes. `ck` v4.5.1 installed but `ck --version` reports "No ClaudeKit installation found" — `ck init --global` never run, so Phase 4's own Requirements line 34 (`~/.claude/skills` non-empty AND `ck doctor` healthy) is **not met**. | **"In progress" undersells the gap** — `ccs` binary present, but ClaudeKit itself (the harness) isn't initialized at all, so `harness: ccs` is still a no-op per `SKILL.md:48`'s own documented caveat. |
| 5 Provision CCS profile | Pending — `[HUMAN]` wizard needed | `ccs api list` → "No API profiles configured". No `ccs-hermes` profile exists via the documented `ccs api create` flow. | **Accurate as literally stated.** BUT: a *different*, undocumented bridge exists — `/home/hermes/.ccs/instances/ken/` (a raw copy of ubuntu's own CCS "ken" instance, confirmed working via `ccs ken -p "echo ok"` → HTTP 429 quota, not an auth failure). This is a distinct CCS mechanism (account "instances", not "API profiles") and directly violates this phase's own Insights: *"CRITICAL (findings §7): never copy, export, or import [ubuntu's `.ccs`]... hermes needs a fresh, dedicated credential."* Phase 5 is genuinely not done — the bridge doesn't satisfy it, doesn't show up in `ccs api list`, and isn't what Phase 6 should treat as "done". |
| 6 Integration verify + docs | Blocked on 1,2,3,5 | `coding-agent-delegate` skill **not** symlinked into `/home/hermes/.hermes/skills/` (Finding 5 fix not applied). Live `~/.hermes/config.yaml` has no `delegation:` block (`ccs --version` confirms "Delegation: Not configured", matches known Finding 7). | **Accurate — still correctly blocked.** Even setting aside 3/5's non-compliance, 6's own prerequisites (skill symlink, config merge) are separately not done. |

## Bottom line

Phase 1/2 solid. Phase 4 has a bigger gap than "in progress" suggests (ClaudeKit never initialized). Phase 3 and Phase 5 are each satisfied today only by a **temporary, explicitly-accepted-as-stopgap credential bridge** (ubuntu's personal Claude + CCS "ken" copied to hermes, 2026-07-04) that **directly contradicts** both phases' own confirmed security requirements (dedicated seat; never reuse ubuntu's CCS identity). Today's separate IMDS egress fix (`IPAddressDeny=169.254.169.254/32` in `hermes.service`, commit `60a2683`) is unrelated to this plan's 6 phases — a new, out-of-band hardening, not a plan deliverable.

## Unresolved questions

- Phase 3 status line ("Pending — [HUMAN] login needed") is now factually stale — update to reflect "functionally unblocked via non-compliant bridge, not via documented procedure" instead of leaving as Pending? Not changed here — plan-authored status text, want confirmation before editing.
- Same question for Phase 5 — worth an explicit note in the phase file that the "ken" bridge is NOT this phase's completion, so a future session doesn't mistake it for done?
- Do you want Phase 3/5 done properly now (real dedicated bot Claude account + real `ccs api create` profile), which would let Phase 6 actually proceed? Or keep the bridge and defer Phase 6 indefinitely?
