# Red-Team Plan Review: Scope & Complexity Critic (+ Contract Verifier)

Plan: `plans/260703-1738-fix-urgent-hermes-delegation-issues/`. All findings verified live against the actual host (`lucas-oracle-instance`) and both git checkouts, read-only, no mutating commands run.

## Finding 1: Phase 1's new deploy script can silently UN-FIX the P0 bug it exists to prevent, because a second, stale, bootstrap-canonical clone exists and no phase checks it

- **Severity:** Critical
- **Location:** Phase 1, "Overview" / "Architecture" (`scripts/deploy-systemd-units.sh` design); Plan Overview (root-cause narrative)
- **Flaw:** Both bootstrap scripts hardcode `GUIDE_DIR=/opt/hermes-optimization-guide` as *the* on-host guide clone (`scripts/vps-bootstrap-oci.sh:105`, `scripts/vps-bootstrap.sh:89`), clone it fresh or `git pull --ff-only` it, symlink its skills into `~hermes/.hermes/skills/`, and `install` its `templates/systemd/*.service` files. This plan is authored and will be executed entirely from a *different* clone, `/home/ubuntu/workspace/hermes-optimization-guide`. Live-verified these are NOT the same checkout and have diverged badly:
  - `/opt/hermes-optimization-guide` HEAD = `e6a26fe` (2026-07-01, "Refresh guide for Hermes v0.17.0/v0.18.0").
  - `/home/ubuntu/workspace/hermes-optimization-guide` HEAD = `0cf76e7` (2026-07-03) — two days and the entire `c9631fc` seccomp fix, `72cc2fd` ReadWritePaths fix, and both delegation-feature plans (`260703-0347`, `260703-1041`) ahead.
  - `grep sched_setscheduler /opt/hermes-optimization-guide/templates/systemd/hermes.service` → **zero matches**. `/opt`'s own copy of the template never received the fix this whole plan exists to deploy.
  - No phase mentions `/opt/hermes-optimization-guide`, checks whether it's in sync, or updates it. No cron/systemd-timer runs `git pull` there either (checked: empty `crontab -l`, no `/opt` references in any installed unit).
- **Failure scenario:** Phase 2 deploys the fixed unit (from the workspace clone, using its correct absolute path) — the live host is now healthy. Weeks later, someone edits a unit template and, per Phase 1's own new README note, runs `scripts/deploy-systemd-units.sh` — but from `/opt/hermes-optimization-guide` (the *only* location bootstrap conventions, `GUIDE_DIR`, and the live skill symlinks treat as canonical — far more discoverable to an operator than one developer's personal workspace checkout). The script does exactly what it's designed to do: diff `/opt`'s stale template against the live (fixed) unit, see a difference, and — because it cannot tell "stale source" from "legitimate edit" — `install` the pre-fix template, `daemon-reload`, and (since the unit is active) `restart` it. This silently reintroduces the exact SIGSYS crash the plan was written to fix, via the tool built to prevent recurrence.
- **Evidence:**
  ```
  $ git -C /opt/hermes-optimization-guide log -1 --format='%H %ci %s'
  e6a26fef858f29c72b13a51a6a21a87455fbd45a 2026-07-01 19:02:15 -0400 Refresh guide for Hermes v0.17.0 'Reach' and v0.18.0 'Judgment' (#26)
  $ git -C /home/ubuntu/workspace/hermes-optimization-guide log -1 --format='%H %ci %s'
  0cf76e76fde7cd42ace751295898cf4bbe19b604 2026-07-03 17:37:16 +0000 docs: add debug report on stale hermes.service unit causing claude SIGSYS
  $ grep -n "sched_setscheduler" /opt/hermes-optimization-guide/templates/systemd/hermes.service
  (no output)
  $ grep -n "GUIDE_DIR=" scripts/vps-bootstrap-oci.sh scripts/vps-bootstrap.sh
  scripts/vps-bootstrap-oci.sh:105:GUIDE_DIR=/opt/hermes-optimization-guide
  scripts/vps-bootstrap.sh:89:GUIDE_DIR=/opt/hermes-optimization-guide
  ```
- **Suggested fix:** Before Phase 1 ships the script, add an explicit step (in Phase 1 or Phase 2) to `git -C /opt/hermes-optimization-guide pull --ff-only` (or otherwise reconcile the two clones) and document which clone is authoritative going forward. The script itself should refuse to run (or warn loudly) if `git status`/`git log` on its own `REPO_ROOT` shows it isn't the same commit as `/opt/hermes-optimization-guide`, or the README note should explicitly pin the one clone path operators must use.

## Finding 2: The `coding-agent-delegate` skill is not symlinked into the live hermes skill catalog — Phase 6's "true completion gate" cannot pass no matter how well Phases 2–5 go, and nothing in the plan surfaces this

- **Severity:** Critical
- **Location:** Phase 6, "Implementation Steps" step 1 ("Trigger one real `/delegate_code` task via the bot... This is the true completion gate"); Phase 4/5 Overview (premise that provisioning CCS+ClaudeKit "completes the delegation stack")
- **Flaw:** `sudo -u hermes ls ~/.hermes/skills/` lists 29 skills; `coding-agent-delegate` is not among them, and a recursive grep for `coding-agent-delegate|delegate_code` across the *entire* live skills tree returns zero hits. The other three `skills/dev/*` skills (`meeting-prep`, `pr-review`, `release-notes`) ARE correctly symlinked from `/opt/hermes-optimization-guide/skills/dev/...` — but `/opt`'s `skills/dev/` directory doesn't even contain a `coding-agent-delegate` folder (it postdates that clone's checkout, see Finding 1), so it was never a candidate for bootstrap's symlink loop. No phase (1, 4, 5, or 6) proposes symlinking this skill into the live host.
- **Failure scenario:** Phases 2–5 all complete perfectly — crash fixed, hermes logged in, ccs+ClaudeKit installed, profile smoke-tested. Phase 6 step 1 (the plan's own stated "true completion gate") asks a human to trigger a real `/delegate_code` task via Telegram/admin panel. The bot has no such skill loaded, so there is nothing to invoke — the task fails or is silently ignored by the bot's own routing, for a reason with zero connection to anything the previous 5 phases touched. The plan has no fallback for "the skill doesn't exist yet" (only a fallback for "triggering isn't practical," which re-runs plain-shell proxies from 2/3/5 — none of which exercise `/delegate_code` either).
- **Evidence:**
  ```
  $ sudo -u hermes ls ~/.hermes/skills/
  apple audit-approval-bypass audit-mcp autonomous-ai-agents computer-use cost-report
  creative daily-inbox-triage data-science dogfood email github hermes-weekly media
  meeting-prep mlops nightly-backup note-taking productivity pr-review release-notes
  research rotate-secrets smart-home social-media software-development spam-trap
  telegram-triage weekly-dep-audit yuanbao
  $ sudo -u hermes bash -c "grep -rl 'coding-agent-delegate\|delegate_code' ~/.hermes/skills/ 2>/dev/null"; echo "exit: $?"
  exit: 1
  $ ls /opt/hermes-optimization-guide/skills/dev/
  meeting-prep  pr-review  release-notes
  ```
- **Suggested fix:** Add an explicit step (Phase 4 or a new prerequisite in Phase 6) to symlink `skills/dev/coding-agent-delegate` into `/home/hermes/.hermes/skills/coding-agent-delegate` (mirroring the existing bootstrap pattern) — from whichever clone Finding 1's fix designates canonical — and verify it resolves before Phase 6 attempts its "true gate."

## Finding 3: Phase 2 and Phase 3's own literal verification commands fail with "command not found" — live-reproduced — risking a false-negative rollback of a working P0 fix

- **Severity:** Critical
- **Location:** Phase 2, "Implementation Steps" step 3 (`sudo -u hermes claude --version` / `sudo -u hermes opencode --version`); Phase 3, "Implementation Steps" step 2 (`sudo -u hermes claude auth status --text`)
- **Flaw:** `sudo`'s inherited/secure PATH for a bare `sudo -u hermes <cmd>` invocation does not include `/home/hermes/.local/bin`, where `claude`/`opencode` actually live. Phase 2 step 3 and Phase 3 step 2 both use this bare, unwrapped form. Phase 4 and Phase 5's commands, by contrast, correctly wrap every invocation as `sudo -u hermes bash -c 'export PATH=$HOME/.local/bin:$PATH; <cmd>'` — the plan is internally inconsistent about handling a constraint it clearly already knows about (SKILL.md itself documents this exact PATH gap for the systemd service).
- **Failure scenario:** Immediately after Phase 2's `[HUMAN]` restart, the `[AGENT]` verification step runs `sudo -u hermes claude --version` expecting "success, no core dump" — but gets `sudo: claude: command not found` (exit 1) regardless of whether the seccomp fix worked. An operator reading this during an active-incident restart could reasonably read "command not found" as "the fix didn't work / something's more broken now" and pull the `.bak` rollback (Phase 2's own documented rollback path) — reintroducing the outage that had just been fixed. Phase 3's identical-pattern auth-status check has the same problem: it can never distinguish "not logged in" from "PATH broken," making the Phase 3 Todo/Success Criteria item unverifiable as literally written.
- **Evidence:**
  ```
  $ sudo -u hermes claude --version
  sudo: claude: command not found            # rc=1
  $ sudo -u hermes opencode --version
  sudo: opencode: command not found           # rc=1
  $ sudo -u hermes bash -c 'export PATH=$HOME/.local/bin:$PATH; claude --version'
  2.1.199 (Claude Code)                       # rc=0 — same binary, works fine
  $ sudo -u hermes bash -c 'export PATH=$HOME/.local/bin:$PATH; opencode --version'
  1.17.13                                     # rc=0
  $ sudo -u hermes env | grep -i path
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin   # no ~/.local/bin
  ```
- **Suggested fix:** Rewrite Phase 2 step 3 and Phase 3 step 2 to use the same `sudo -u hermes bash -c 'export PATH=$HOME/.local/bin:$PATH; ...'` wrapper Phases 4/5 already use, so "command not found" and "still crashing"/"not logged in" can never be confused.

## Finding 4: Phase 5 only verifies the repo *template*; the live host's actual running config has no `delegation:` block at all — the real consumer is never checked

- **Severity:** High
- **Location:** Phase 5, "Requirements" / "Success Criteria" (`production.yaml:193 == profile name`); Plan File Ownership Matrix (row 5)
- **Flaw:** The service loads `HERMES_CONFIG=/home/hermes/.hermes/config.yaml` (confirmed via `systemctl cat hermes.service`), not `templates/config/production.yaml` — that repo file is a template an operator is meant to copy in. Live-verified the actual runtime config has **no `delegation:` key whatsoever** (17 top-level keys enumerated, `delegation` isn't one), and a case-insensitive grep for `ccs|delegat|harness|claude-code` across the whole file returns nothing. Phase 5's Requirements/Success Criteria ("A profile... exists; `production.yaml:193` equals that name; smoke-test exits 0") check only the repo template and the standalone `ccs` CLI — never the file the running gateway actually reads.
- **Failure scenario:** Phase 5 completes exactly as documented — profile created, smoke-test green, `production.yaml:193` matches. The live bot still has no `delegation.ccs_profile` (or `delegation.routing`) to route through, because nobody copied the updated `delegation:` block into `/home/hermes/.hermes/config.yaml`. `harness: ccs` remains just as unreachable in production as it was before Phase 5 ran — it now works from a bare shell test, but the service itself has no config path to it.
- **Evidence:**
  ```
  $ sudo -u hermes grep -nE '^[a-zA-Z_]+:' ~/.hermes/config.yaml
  1:model: 5:agent: 7:web: 10:browser: 13:display: 15:tts: 18:stt: 21:context:
  25:memory: 30:approvals: 32:command_allowlist: 34:onboarding: 37:_config_version: 32
  38:version: 1 39:models: 61:routing: 76:platforms: 80:telemetry: 85:image_gen: 87:session_reset:
  # no "delegation:" key
  $ sudo -u hermes grep -ni 'ccs\|delegat\|claude-code\|harness' ~/.hermes/config.yaml; echo "exit: $?"
  exit: 1
  ```
- **Suggested fix:** Add a Phase 5 (or Phase 6) step that diffs the live `/home/hermes/.hermes/config.yaml` against `templates/config/production.yaml`'s `delegation:` block and merges/updates the live file — the actual artifact the running process reads — not just the repo template and a standalone CLI smoke-test.

## Finding 5: Phase 1 is framed as "drift-prevention" but the design doesn't prevent the failure mode that caused the incident — it only makes a remembered re-run less error-prone

- **Severity:** High
- **Location:** Phase 1, "Overview" ("no repo-side tooling that syncs... Someone has to remember to install + daemon-reload + restart by hand"); "Requirements"/"Architecture" (diff/idempotency/self-elevation design)
- **Flaw:** The root cause of the incident, by the plan's own words, was a human forgetting to run a manual command after a template edit — a *remembering* failure, not a *capability gap*. The new ~50-line script (diff-before-copy, restart-only-if-active, self-elevating, summary printer) still requires a human to *remember to invoke it*; nothing enforces or triggers it automatically (no pre-commit/pre-push hook, no CI check comparing `templates/systemd/*` against a recorded live-deployed hash, no path-unit/cron on the host). A future editor who is unaware Phase 1 ever happened reproduces the exact same incident, script or no script. The one piece of Phase 1 that actually addresses "prevention" (a human-facing reminder) is the single README sentence — which could ship alone, today, with none of the diff/idempotency/restart-gating machinery.
- **Failure scenario:** Six months from now, a different contributor edits `templates/systemd/hermes.service` in a PR, doesn't read the README (or the guide has been forked/cloned and the note wasn't carried over), merges, and walks away. `scripts/deploy-systemd-units.sh` never runs. The live unit drifts exactly as it did this time — the incident recurs, and the "drift-prevention tooling" this phase shipped prevented nothing, because prevention requires forcing execution, not merely making execution nicer once someone remembers to opt in.
- **Evidence:** Phase 1 Overview: *"Add `scripts/deploy-systemd-units.sh`... Idempotent, re-runnable, self-elevating... so a human can run `bash scripts/deploy-systemd-units.sh`. Plus a README note pointing operators at it after editing any unit template."* — the "plus a README note" is doing 100% of the actual prevention work; the script does 0% (it improves correctness/idempotence of a run that must still be manually triggered).
- **Suggested fix:** Either (a) ship only the README note for this incident's actual root cause, and defer the script until there's a real trigger for it (a CI check, a systemd `PathChanged=` watcher, or a bootstrap re-run cadence), or (b) if the script ships, make invocation non-optional — e.g., a CI step that fails the PR if `templates/systemd/*.service` changed and a corresponding deploy-log entry didn't, forcing the reminder into a gate rather than a suggestion.

## Finding 6: EXPANSION phases (3–6, ~90% of the plan's effort) have zero dependency coupling to the urgent P0 fix, and their own foundational wiring (Findings 2 & 4) doesn't exist yet — the scope decision wasn't made with that cost visible

- **Severity:** High
- **Location:** Plan.md, "Dependency Graph" (Phase 2: `blockedBy: —`, nothing downstream blocks on it either); "Overview" (EXPANSION framing)
- **Flaw:** By the plan's own dependency table, Phase 2 (the P0 crash fix, 20 of the plan's 205 total minutes — effort header `3h25m`) is fully independent of Phases 1/3/4/5/6. Deploying it alone fully satisfies "fix urgent Hermes delegation issues" as stated in the plan title (delegated `claude`/`opencode` calls stop dying with SIGSYS). The remaining ~185 minutes (90% of the budgeted effort) — drift tooling, OAuth login, CCS+ClaudeKit install, profile provisioning, integration/docs — exist to complete a *different*, previously and deliberately descoped feature (`harness: ccs`, scoped OUT by plan `260703-1041`'s own Unresolved Q2). The plan states this is "by the user's explicit choice this session" (plan.md line 24), but there is no artifact in this plan folder (no `reports/`-stored transcript, no brainstorm doc) recording how the REDUCTION/HOLD/EXPANSION options were actually presented, and — more importantly — Findings 2 and 4 show the EXPANSION's own foundational wiring (the skill isn't symlinked, the live config has no `delegation:` block) isn't addressed by any of Phases 3–6 either. The "EXPANSION" therefore doesn't fully deliver working `harness: ccs` in production even on its own terms; it delivers binaries-on-disk-plus-an-auth-token, one layer short of the thing it was chosen to accomplish.
- **Failure scenario:** Stakeholder approves "EXPANSION" believing it "completes the delegation stack... so harness: ccs delivers real harness instead of the current no-op" (plan.md line 24). After ~3h of work and real production changes (new auth token tied to a real subscription seat, new auto-executed hook/plugin surfaces per Phase 4/5's own Security Considerations), `harness: ccs` is *still* a no-op in production, for reasons (missing skill symlink, missing config block) that were discoverable by the same live-host verification this plan already did for other facts, but weren't checked for these two.
- **Evidence:** `plan.md:43-50` dependency table; effort header `plan.md:6` (`effort: "3h25m"`) vs. Phase 2 header `phase-02-deploy-p0-systemd-fix.md:5` (`effort: "20m"`); Findings 2 and 4 above for the unaddressed wiring gaps.
- **Suggested fix:** Before committing the EXPANSION's remaining budget, add the two missing wiring steps (skill symlink, live-config delegation block) to Phase 4/5/6 so the scope actually delivers what it was chosen to deliver — or split Phase 2 into its own immediately-shippable unit (as the REDUCTION option would have) and re-confirm EXPANSION's remaining phases as a distinctly-tracked follow-up once the true end state is fully specified.

## Finding 7: Phase 4's ClaudeKit "stretch" note undersells an active, default-on change to the exact code path that caused this incident

- **Severity:** Medium
- **Location:** Phase 4, "Overview" / "Implementation Steps" ("Stretch (optional, clearly labeled...)"); Security Considerations
- **Flaw:** Once ClaudeKit is installed, *every* plain `claude` invocation by the hermes user — not only `ccs`-routed ones — auto-loads the full `--kit engineer` harness (`CLAUDE.md`, rules, hooks, skills catalog), per the phase's own citation of `SKILL.md:83` ("harness loads from `~/.claude/` presence, independent of ccs-vs-bare"). The phase calls this "a one-line note for Phase 6's docs update, not a separate action item." But the debug report's own trigger was a bot-initiated bare `claude --version` call outside any CCS/skill routing — i.e., the hermes user's plain `claude` invocations are already a live, exercised path, not a hypothetical. Phase 4's Security Considerations acknowledges "two new auto-executed code surfaces appear" only in the abstract (hooks/plugins as a class), without connecting it to this concrete consequence: the fix for an urgent crash is being bundled with a default-on expansion of auto-exec surface on the very invocation path that just caused a production incident.
- **Failure scenario:** A future hook or rule shipped in the `engineer` kit (or a compromised/misconfigured one) fires on some plain `claude` call the hermes bot makes for an unrelated reason (e.g. a user asking it to "check if claude works"), executing with the ambient authority of whatever the kit's hooks are scoped to — a materially larger blast radius than "no ClaudeKit" produced, introduced as a side effect of an urgent-bug plan rather than a reviewed, opt-in decision.
- **Evidence:** Phase 4: *"Harness loads from `~/.claude/` presence, independent of ccs-vs-bare (`SKILL.md:83`) → once installed, even `harness: bare` hermes `claude` calls get the CK rules/skills catalog (stretch note below; documented in Phase 6)."* Debug report Trigger: *"Hermes bot Telegram report ('claude --version core dumped, Bad system call')"* — a bare, non-CCS invocation.
- **Suggested fix:** Treat this as a first-class Security Consideration with its own risk row (likelihood/impact, mitigation), not a "stretch... one-line note" — at minimum, confirm what hooks ship with `--kit engineer` and whether any are auto-approved/auto-exec before enabling this for a production service account.

## Finding 8: Phase 6's SKILL.md reframe will describe a ClaudeKit "prerequisite" that, unlike every sibling prerequisite in the same section, has no repeatable install path — creating the same guide-vs-reality drift Phase 1 exists to eliminate

- **Severity:** Medium
- **Location:** Phase 6, "Implementation Steps" step 2 (SKILL.md:48 rewrite); Phase 4, "Next Steps" (explicit deferral)
- **Flaw:** `SKILL.md:48`'s Prerequisites section documents `claude`/`codex`/`gemini`/`opencode`/`ccs` as things `scripts/vps-bootstrap.sh` / `-oci.sh` install (verified: both scripts install all five). Phase 6 will rewrite the same paragraph to describe ClaudeKit provisioning ("`npm install -g claudekit` + `ck init --global --kit engineer`") as the mechanism — but confirmed via grep, **neither bootstrap script has a `claudekit` or `ck init` line**. Phase 4's own "Next Steps" explicitly flags this ("a fresh VPS bootstrap would still lack ClaudeKit... deliberately NOT done here"). So after Phase 6, the Prerequisites section will contain one prerequisite class (ClaudeKit) that silently differs in kind from all the others it sits next to: the rest are "already handled by the one-command bootstrap this guide advertises" (README.md:53), ClaudeKit is "a manual sequence a human must remember to run per-host, forever, until a deferred follow-up lands."
- **Failure scenario:** An operator follows this guide's advertised "one command to production" path (`README.md:50-53`) on a brand-new host, reads the reframed SKILL.md Prerequisites, and reasonably assumes ClaudeKit — described alongside four other bootstrap-covered CLIs — is likewise already handled. It is not; `harness: ccs` (once they also fix Findings 2/4 themselves) remains a silent no-op on their host with no error, exactly the failure mode `SKILL.md:48` already warns about today for a different reason.
- **Evidence:**
  ```
  $ grep -n "claudekit\|ck init" scripts/vps-bootstrap.sh scripts/vps-bootstrap-oci.sh; echo "exit: $?"
  exit: 1
  ```
  Phase 4 Next Steps: *"`vps-bootstrap*.sh` has an `ccs` line (`:148-149`) but no `claudekit` line, so a fresh VPS bootstrap would still lack ClaudeKit... deliberately NOT done here... flagged for a follow-up."*
- **Suggested fix:** Either fold the bootstrap-script `claudekit` line into this plan's scope (small, since Phase 4 already worked out the exact non-interactive command) so the SKILL.md rewrite in Phase 6 describes something actually true for new deployments, or have Phase 6's rewrite explicitly flag ClaudeKit as "manual, per-host, not yet in bootstrap" rather than presenting it in the same voice as the bootstrap-covered items around it.

**Status:** DONE
**Summary:** 8 findings (3 Critical, 3 High, 2 Medium). Critical: Phase 1's script can silently redeploy a stale pre-fix unit from the bootstrap-canonical `/opt` clone (2 days behind, missing the fix entirely) and reintroduce the SIGSYS crash; the `coding-agent-delegate` skill isn't symlinked into the live host at all, so Phase 6's stated completion gate is currently impossible; Phase 2/3's literal verification commands fail with "command not found" (live-reproduced) due to sudo's restricted PATH, risking a false-negative rollback of a working P0 fix. High: Phase 5 verifies only the repo template while the live running config has no `delegation:` block whatsoever; Phase 1's "drift-prevention" doesn't prevent the forgetting failure mode that caused the incident; the EXPANSION phases (90% of the plan's effort) are undelegated by the urgent fix and don't fully deliver working `harness: ccs` even on their own terms. Medium: Phase 4's ClaudeKit stretch under-scopes a real auto-exec blast-radius increase on the bot's already-exercised bare-`claude` path; Phase 6's SKILL.md reframe will describe a prerequisite with no repeatable install path, unlike its sibling bullets.
