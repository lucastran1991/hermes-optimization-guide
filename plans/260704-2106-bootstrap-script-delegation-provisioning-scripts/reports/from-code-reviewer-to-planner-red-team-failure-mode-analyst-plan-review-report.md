---
title: "Red Team (Failure Mode Analyst): Bootstrap Script Delegation Provisioning Plan"
date: 2026-07-04
type: plan-review
role: failure-mode-analyst / flow-tracer
verdict: 7 findings — 2 Critical, 3 High, 2 Medium
---

# Scope

Reviewed plan.md + phases 1-6 of `plans/260704-2106-bootstrap-script-delegation-provisioning-scripts/`, the design doc, and the two related manual-plan phases (`260703-1738-.../phase-03-claude-auth-for-hermes.md`, `phase-05-provision-ccs-profile.md`). Grep-verified every claim below against the live repo, not plan prose.

---

## Finding 1: `gh` CLI is never installed anywhere the plan can reach

- **Severity:** Critical
- **Location:** Phase 2, section "GH Auth Script" (and transitively Phase 1's remediation path, Phase 6's success chain)
- **Flaw:** `0-gh-auth.sh` authenticates `gh` for hermes (`gh auth login --with-token`) but the plan never installs the `gh` binary. `scripts/vps-bootstrap-oci.sh`'s apt package list (`curl ca-certificates gnupg jq git python3-venv python3-pip age rclone fail2ban unattended-upgrades debian-keyring debian-archive-keyring apt-transport-https`, `vps-bootstrap-oci.sh:58-60`) has no `gh`/`gh-cli`/`github-cli` entry, and section 6b's per-hermes CLI installer block (`vps-bootstrap-oci.sh:124-155`) only installs `claude`, `opencode`, `codex`, `gemini`, `ccs` — not `gh`.
- **Failure scenario:** On a genuinely fresh host (the exact scenario the plan's Overview says it's automating — "standing up a fresh one"), running `0-gh-auth.sh` hits `gh: command not found` immediately. Since Phase 1's own empty-skills remediation instructs the operator to "re-run `0-gh-auth.sh`" (phase-01 §Risk Assessment), and Phase 6's success depends transitively on gh working for skill installs, this is not an edge case — it's the default first-run outcome on any host that isn't the one operator's hand-configured box from today.
- **Evidence:** `grep -n "gh \|github-cli" scripts/vps-bootstrap-oci.sh` → only a false-positive match ("through your existing cloudflared tunnel", line 250); apt list at `vps-bootstrap-oci.sh:58-60` confirmed gh-free.
- **Suggested fix:** Add `gh` to Phase 1's apt package list (Ubuntu's `gh` is available via the official apt repo, not the default archive — needs a keyring+repo add step, same pattern as `debian-keyring`) or install it in `0-gh-auth.sh` itself as a precondition, guarded/idempotent (`command -v gh || …`).

## Finding 2: The mandated run order guarantees the exact "empty skills" failure it warns about, with no automated fix

- **Severity:** Critical
- **Location:** Phase 1, section "Key Insights" / Phase 2, section "Next Steps"; plan.md "Real-world run order for a from-scratch host"
- **Flaw:** plan.md's own documented run order is `1 (bootstrap) → 0-gh-auth → 1-claude-auth → …` (plan.md:59-62). Phase 1's Key Insight states `ck init --global … --install-skills` "silently produces an EMPTY `~/.claude/skills/` if hermes has no `gh auth` configured yet" (phase-01:26). Since bootstrap (which runs `ck init --install-skills`, section 6c) always executes *before* `0-gh-auth.sh` in the documented order, every from-scratch bootstrap run will hit the empty-skills condition — not a rare fault, the default outcome. The only remediation is a `warn` message pointing at "a manual re-run of `ck init --global --install-skills`" (phase-01:42, 56) — this manual re-run exists nowhere as an automated step in any of the 5 new scripts.
- **Failure scenario:** Operator runs the amended bootstrap on a fresh OCI host exactly as documented, sees the warn, runs `0-gh-auth.sh` per the pointer, and then has to remember/improvise the undocumented-in-script `ck init --global --install-skills` re-run by hand — precisely the "redoing manual steps from memory" problem this whole plan exists to eliminate (plan.md Overview, first sentence).
- **Evidence:** `phase-01-bootstrap-claudekit-and-skills-setup.md:26,42,56,81`; `plan.md:59-62`.
- **Suggested fix:** Either have `0-gh-auth.sh` end by re-invoking the ClaudeKit skills-install step itself (making Phase 2 responsible for completing what Phase 1 left incomplete), or reorder so 6c's `--install-skills` call is deferred/re-attempted at the end of the numbered-script chain rather than unconditionally in bootstrap.

## Finding 3: `--force` flag for `ccs api create` is an unverified claim contradicting the one actually-verified idempotency mechanism

- **Severity:** High
- **Location:** Phase 4, section "Key Insights" / "Architecture" / Implementation step 2
- **Flaw:** Phase 4 asserts `` `--force` bypasses validation/overwrite `` and labels the whole syntax block "VERIFIED syntax (`ccs api create --help`)" (phase-04:24). But this plan folder has no `research/` artifact and no live-host command transcript backing that verification — unlike the cross-referenced related plan, which DID capture a live `ccs api --help` check and documented only `ccs api create <name> --preset <p> --api-key <key> --yes` plus `ccs api remove <name>` for cleanup (`plans/260703-1738-.../research/live-host-verification-findings.md:34-37`, `phase-05-provision-ccs-profile.md:24-25` — no `--force` mentioned anywhere in either). Phase 4 builds its entire idempotency design (Implementation step 2, Success Criteria, Risk Assessment row "Re-run duplicates/corrupts profile") on a flag the project's own prior, actually-verified research never observed.
- **Failure scenario:** If `--force` doesn't exist or doesn't do what's claimed, `2-ccs-profile.sh --force` either errors out (`unknown flag`) or silently behaves like a plain re-create attempt that fails because the profile already exists — breaking the idempotency guarantee Phase 4's Success Criteria depends on, discovered only when someone actually re-runs the script.
- **Evidence:** `phase-04-ccs-profile-script.md:24,32,45,61,64,74,84` (six separate places assume `--force` works) vs. `plans/260703-1738-fix-urgent-hermes-delegation-issues/research/live-host-verification-findings.md:34-37` and `phase-05-provision-ccs-profile.md:24-25` (the only actually-verified form, no `--force`).
- **Suggested fix:** Re-verify `ccs api create --help` live before relying on `--force`; fall back to the already-verified `ccs api remove <name> ; ccs api create <name> …` sequence for idempotency if `--force` isn't confirmed.

## Finding 4: CCS reuse-bridge copies only `instances/<name>/`, never touches the root `~/.ccs/config.yaml` the plan's own evidence says exists

- **Severity:** High
- **Location:** Phase 5, section "Architecture" / "Implementation Steps"
- **Flaw:** Phase 5's data flow is `cp -a /home/ubuntu/.ccs/instances/NAME/ → /home/hermes/.ccs/instances/NAME/` then `chown -R` (phase-05:44-45, step 2 line 68) — it never reads, merges, or creates any `/home/hermes/.ccs/config.yaml`. But the plan's own cross-referenced research explicitly confirms `/home/ubuntu/.ccs/` has a root `config.yaml` sibling to `instances/` — "confirmed by directory layout (`instances/`, `config.yaml`, `cliproxy/`)" (`plans/260703-1738-.../research/live-host-verification-findings.md:41`). If `ccs` resolves/registers profile names via that root config (not purely by scanning `instances/<name>/` on disk), copying only the instance subtree leaves hermes's `ccs` unable to find the profile by name at all.
- **Failure scenario:** `3-ccs-reuse-bridge.sh --instance=ken --i-understand-the-risk` completes its copy + chown steps successfully, but the mandatory smoke test (`ccs ken -p "echo ok" --output-format json`) fails with a "profile not found"-class error — not a credential problem, a registration problem the script's design never accounts for, and its own `die` messaging ("check credential/preset") would misdirect debugging.
- **Evidence:** `phase-05-ccs-reuse-bridge-script.md:44-49,61,68` (copy-only design) vs. `plans/260703-1738-fix-urgent-hermes-delegation-issues/research/live-host-verification-findings.md:41` (root `config.yaml` confirmed to exist alongside `instances/`).
- **Suggested fix:** Before relying on this design, verify whether `ccs`'s profile resolution needs any entry from the root `config.yaml` merged/regenerated for hermes; if so, the script needs an additional merge step, not just a directory copy.

## Finding 5: Phase 6 grafts a `delegation:` block from a config with 8 more top-level sections onto a live config seeded from a template that has none of them, with no specified extraction boundary

- **Severity:** Medium
- **Location:** Phase 6, section "Architecture" / "Key Insights"
- **Flaw:** Phase 6 sources the `delegation:` block from `templates/config/production.yaml` (`delegation:` at line 168, next top-level key `acp:` at line 197 — confirmed via `grep -n '^[a-zA-Z_]*:' templates/config/production.yaml`). But the LIVE config it merges into is seeded, per `vps-bootstrap-oci.sh:170-175`, from `templates/config/cost-optimized.yaml`, which has ONLY `version, models, routing, context, platforms, memory, telemetry` — no `delegation`, `acp`, `mcp_servers`, `sandboxes`, `approvals`, `command_allowlist`, `security`, or `cron` (confirmed: `grep -n '^[a-zA-Z_]*:' templates/config/cost-optimized.yaml` returns none of those keys). The plan never specifies the mechanism (sed range? python/yq?) that extracts exactly the `delegation:` block's line range from `production.yaml` without also capturing neighboring top-level keys.
- **Failure scenario:** A boundary-detection bug in the (unspecified) extraction step over-captures past `delegation:`'s end and injects part of `acp:`/`mcp_servers:` into the live config. YAML-validation (`python3 -c 'import yaml; yaml.safe_load(...)'`) would NOT catch this — it's syntactically valid YAML, just wrong/duplicated content — so the script's stated safety gate ("YAML-validate; on failure restore `.bak` + `die`", phase-06:74) gives false confidence here.
- **Evidence:** `vps-bootstrap-oci.sh:170-175` (cost-optimized.yaml is the seed); `templates/config/cost-optimized.yaml` top-level keys vs `templates/config/production.yaml` top-level keys (grep above); `phase-06-merge-delegation-config-and-docs.md:29,52,73` (merge mechanism never named).
- **Suggested fix:** Name the exact extraction tool/algorithm in the phase file (e.g., a small python script using `ruamel.yaml`/`PyYAML` to load both files and set only the `delegation` key, re-dump) rather than leaving block-boundary detection to an unspecified bash text operation.

## Finding 6: Phase 4/5 invoke `sudo -u hermes -i <binary> <args>` directly — a form this exact project has never verified working, unlike its one confirmed-safe pattern

- **Severity:** Medium
- **Location:** Phase 4, Implementation step 2 (`sudo -u hermes -i ccs api create …`); Phase 2, Implementation step 2 (`sudo -u hermes -i gh auth login …`); Phase 5, step 2 (`sudo -u hermes -i ccs "$INSTANCE" …`)
- **Flaw:** This exact host was already found (via live reproduction, two red-team passes ago) to break on any bare `sudo -u hermes <cli>` invocation because sudo's `secure_path` excludes `~/.local/bin` (`plans/260703-1738-.../reports/from-code-reviewer-to-planner-red-team-assumption-destroyer-plan-review-report.md:64-79`). The only form that red team actually reproduced as working is `sudo -u hermes -i bash -c '<cmd>'` (login shell + explicit `bash -c` wrapper) — confirmed at line 76 of that report: "`sudo -u hermes -i bash -c 'echo PATH=$PATH'` # only -i (login sim) picks up .bashrc's PATH export". This new plan's Phase 2/4/5 instead pass the binary directly as sudo's command argument (`sudo -u hermes -i ccs api create …`, no `bash -c` wrapper) — a form never reproduced/tested in either plan.
- **Failure scenario:** If sudo's argument-passing to a login shell behaves differently than the `bash -c`-wrapped form for quoting/escaping (e.g. the `--api-key` value or STDIN-piped token), the script could fail in a way indistinguishable from a bad credential — repeating the exact debugging trap ("command not found" looking like "not logged in") this project was already burned by twice.
- **Evidence:** `phase-04-ccs-profile-script.md:61`; `phase-02-gh-auth-script.md:57-58`; `phase-05-ccs-reuse-bridge-script.md:69`; vs. the one verified-working form documented in `plans/260703-1738-fix-urgent-hermes-delegation-issues/reports/from-code-reviewer-to-planner-red-team-assumption-destroyer-plan-review-report.md:76,79`.
- **Suggested fix:** Standardize every new script on the one form this project has actually reproduced as working: `sudo -u hermes -i bash -c '<full command with args>'`, matching `vps-bootstrap-oci.sh`'s own section 6b convention (`bash -c '...'` block, `vps-bootstrap-oci.sh:132-154`).

## Finding 7: Phase 3's credential has no functional verification, unlike every other credential-provisioning phase

- **Severity:** Medium
- **Location:** Phase 3, section "Implementation Steps" step 3 / "Success Criteria"
- **Flaw:** Phase 2 verifies via `gh auth status`; Phase 4/5 both gate on a mandatory `ccs … -p "echo ok" --output-format json` smoke test that must exit 0 (phase-04:31,62; phase-05:32,69). Phase 3's only check is `grep -q "^ANTHROPIC_API_KEY=.\+" ~/.hermes/.env` (phase-03:55,64,69-70) — confirming a non-empty string was written, not that the key is valid, unrevoked, or actually usable by `claude`/the delegated `claude -p` path.
- **Failure scenario:** A typo'd, expired, or wrong-scope API key passes every one of Phase 3's Success Criteria (non-empty line, correct file mode) and the failure only surfaces at the very end, during the `[HUMAN]`-only `/delegate_code` end-to-end test that Phase 6 explicitly defers all real verification to (phase-06:109) — the least specific point in the whole pipeline to discover a Phase-3-introduced problem.
- **Evidence:** `phase-03-claude-auth-script.md:55,63,69-70` (grep-only gate) vs. `phase-04-ccs-profile-script.md:31,42,62` and `phase-05-ccs-reuse-bridge-script.md:32,46,69` (both mandate a real smoke test).
- **Suggested fix:** Add a lightweight functional check, e.g. `sudo -u hermes -i bash -c 'export PATH="$HOME/.local/bin:$PATH"; claude -p "echo ok" --output-format json'` (mirroring the PATH-wrapped form Phase 3's related plan already established at `phase-03-claude-auth-for-hermes.md:29,42`), gated non-fatal (`warn`, not `die`, since API-key pickup by `claude` may need more than `.env` alone) but at least surfaced before the human-only end-to-end test.

---

# Flow Tracer Verification Results

| Claim | Traced path | Result |
|---|---|---|
| "6c/6d slot in AFTER 6b (:155) and BEFORE 7 (:157)" (phase-01:28,49) | `vps-bootstrap-oci.sh` section markers: 6b block ends `:155`, section 7 starts `:157-158` | VERIFIED — line citation accurate |
| "Target file … scaffolded by `scripts/vps-bootstrap-oci.sh:178-194`" (phase-03:16) | `.env` heredoc at `vps-bootstrap-oci.sh:178-194` | VERIFIED |
| "`production.yaml` already `ccs_profile: ccs-hermes`" (phase-04:16,25) | `templates/config/production.yaml:193` | VERIFIED — `ccs_profile: ccs-hermes` present |
| "Live config the service reads: `/home/hermes/.hermes/config.yaml`" merge source is `production.yaml`'s `delegation:` block (phase-06:16,29) | `vps-bootstrap-oci.sh:170-175` seeds that live file from `templates/config/cost-optimized.yaml`, NOT `production.yaml` | FAILED as an implicit-schema-match assumption — see Finding 5. The file path claim itself is correct, but the plan's mental model (live config resembles production.yaml enough to safely graft a block in) does not hold; actual seed template has zero overlapping delegation-adjacent keys. |
| "README Repo Map row to mirror: `README.md:72`" (phase-06:17) | `README.md:72` | VERIFIED — `deploy-systemd-units.sh` row is exactly there |
| "CHANGELOG entry already exists: `CHANGELOG.md:5`" (phase-06:18) | `CHANGELOG.md:5` | VERIFIED — `## 2026-07-04 — Unit-Drift Prevention Script + ClaudeKit Prerequisite Reframe` |
| "`--force` bypasses validation/overwrite" for `ccs api create` (phase-04:24) | No `research/` artifact in this plan folder; cross-referenced related-plan research (`live-host-verification-findings.md:34-37`) documents only `--api-key --yes` + `ccs api remove` for cleanup, never `--force` | FAILED to verify — see Finding 3 |
| "`sudo -u hermes -i ccs …`/`gh …` direct-invocation works" (phase-02/04/05) | Only verified-working form in this project's history is `sudo -u hermes -i bash -c '<cmd>'` (`…assumption-destroyer-plan-review-report.md:76,79`) | UNCONFIRMED for the bare (non-`bash -c`) form — see Finding 6 |
| Phase 5 copy of `instances/<name>/` alone is sufficient for `ccs <name>` to resolve | Related-plan research confirms a root `config.yaml` exists alongside `instances/` at `/home/ubuntu/.ccs/` (`live-host-verification-findings.md:41`); Phase 5 never touches it | UNCONFIRMED / likely gap — see Finding 4 |
| `gh` binary availability for `0-gh-auth.sh` | `vps-bootstrap-oci.sh` apt list (`:58-60`) and CLI-install block (`:124-155`) | FAILED — `gh` not installed anywhere — see Finding 1 |

---

## Unresolved Questions

- Does `ccs api create` actually support `--force`? Needs a live `ccs api create --help` re-run before Phase 4 is cooked (Finding 3).
- Does `ccs`'s profile resolution read anything from `~/.ccs/config.yaml` beyond `instances/<name>/`? Needs a live inspection of a real `~/.ccs` tree structure/CLI source before Phase 5 is cooked (Finding 4).
- Is `gh` expected to be provisioned by some OUT-OF-PLAN mechanism (e.g. already present on this specific OCI image via cloud-init or a manual apt-get today) that the plan implicitly assumes but never states? If so, Phase 1/2 should say so explicitly rather than silently depending on it (Finding 1).
