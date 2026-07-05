# Red Team Review: Bootstrap Script Delegation Provisioning Plan (Security Adversary)

Reviewed: plan.md + phase-01..06 + design doc `plans/reports/from-brainstorm-to-planner-260704-2053-bootstrap-script-delegation-provisioning-design.md`.

## Finding 1: `3-ccs-reuse-bridge.sh` copies far more than "credentials" — full conversation history + project data

- **Severity:** Critical
- **Location:** Phase 5, section "Architecture" / "Key Insights"
- **Flaw:** The plan frames this script as copying "an existing personal CCS instance's credentials" (Overview) and its Risk Assessment only discusses "shared quota + impersonation." The actual operation is `cp -a "$SRC" /home/hermes/.ccs/instances/` on the WHOLE instance directory tree, not a credential file.
- **Failure scenario:** Live instance dir `/home/ubuntu/.ccs/instances/ken/` contains `.credentials.json` AND `history.jsonl` (69KB, real conversation transcripts), `.claude.json` (41KB session config), `projects/`, `plans-registries/`, `session-env/` (45 session dirs), `file-history/`. `cp -a` recursively copies all of it into hermes's home, then `chown -R hermes:hermes`. This is a wholesale export of a real person's conversation history/PII/prior-session secrets (anything ever pasted into a chat) into a service account's home directory — a materially larger blast radius than "credential reuse," and it's never named as a risk, gated, or scoped down (e.g. copying only `.credentials.json`/`.claude.json`).
- **Evidence:** `ls -la /home/ubuntu/.ccs/instances/ken/` shows `history.jsonl` (69168 bytes), `.credentials.json`, `.claude.json`, `projects/`, `session-env/`, `plans-registries/`. Plan text (phase-05-ccs-reuse-bridge-script.md:44): `cp -a "$SRC" /home/hermes/.ccs/instances/`. Risk Assessment table only lists "Personal identity impersonation + shared quota" and "Copied creds outlive their welcome" — no line item for history/PII exposure.
- **Suggested fix:** Scope the copy to the minimum files CCS actually needs to route through the profile (credential + minimal profile config), not the entire instance tree; or explicitly risk-accept and document the full-tree exposure in Security Considerations.

## Finding 2: `--instance=<name>` is spliced unsanitized into a filesystem path — path traversal with root privilege

- **Severity:** Critical
- **Location:** Phase 5, section "Architecture" / Implementation Steps step 2
- **Flaw:** `SRC=/home/ubuntu/.ccs/instances/$INSTANCE` — `$INSTANCE` is taken directly from `--instance=<name>` with no validation (no charset allowlist, no rejection of `/` or `..`). The script must run as root (needed to read another user's `0700` home dir and later `chown`), so a malformed/malicious value turns this into a root-privileged arbitrary-directory copy + re-own primitive.
- **Failure scenario:** `--instance=../../../etc` resolves `SRC` to `/etc`; `cp -a /etc /home/hermes/.ccs/instances/` followed by `chown -R hermes:hermes` copies and re-owns arbitrary system directories into hermes's home. Even without malice, a typo (extra `/` or a name containing `..`) silently copies the wrong tree with no fixed anchor check.
- **Evidence:** phase-05-ccs-reuse-bridge-script.md:67: "`SRC=/home/ubuntu/.ccs/instances/$INSTANCE; [ -d "$SRC" ] || die "no such instance: $SRC"`" — only existence is checked, not shape.
- **Suggested fix:** Validate `$INSTANCE` against a strict allowlist (e.g. `[[ "$INSTANCE" =~ ^[A-Za-z0-9_-]+$ ]] || die`) before building `$SRC`.

## Finding 3: Phase 2's Risk Assessment gives false assurance about token leakage

- **Severity:** High
- **Location:** Phase 2, section "Risk Assessment"
- **Flaw:** The mitigation for "Token leaks via `ps`/shell history" is "Pass via STDIN (`--with-token`) not an arg to `gh`" — true for the internal `gh` invocation, but irrelevant to the actual leak point: the SCRIPT's own `--token=<PAT>` argument. `bash 0-gh-auth.sh --token=ghp_xxx` places the PAT in that process's argv, visible via `ps aux`/`/proc/<pid>/cmdline` for the script's whole runtime, and in shell history if invoked interactively/via a `curl | sudo bash -s -- --token=...` one-liner.
- **Failure scenario:** Any other local user (or a monitoring agent, or a compromised sibling process) running `ps aux` during the ~1s the script executes captures the live PAT. Contrast with Phases 3/4, which explicitly acknowledge this exact trade-off ("Key passed as a flag lands in the CALLER's history — document...", "This is the accepted, explicitly-acknowledged trade-off") — Phase 2 uniquely omits the acknowledgment and instead implies the risk is handled.
- **Evidence:** phase-02-gh-auth-script.md:74: `| Token leaks via ps/shell history | M×M | Pass via STDIN (--with-token) not an arg to gh; prefer $GH_TOKEN env for the fully-headless path. |` — no mention that the wrapper's own `--token=` arg is the actual leak surface.
- **Suggested fix:** Either drop `--token=` entirely (require `$GH_TOKEN` only) or add the same explicit acknowledgment Phases 3/4 carry, and recommend `GH_TOKEN=$(cat tokenfile) bash 0-gh-auth.sh` / env-file sourcing over inline flags.

## Finding 4: Credential-bearing scripts inherit the repo's existing unpinned-curl|bash trust model, raising blast radius

- **Severity:** High
- **Location:** Plan-wide (decision 1, `plan.md:26`); Phases 2 and 4 specifically
- **Flaw:** Design decision 1 requires every script stay "`curl | sudo bash`-safe" (no interactive prompts). `vps-bootstrap-oci.sh` itself already documents an accepted-risk precedent for this pattern for CLI installers ("fetched via curl|bash with no published checksum to pin against... accepted risk: runs as unprivileged hermes"). The new scripts reuse this exact unauthenticated-fetch model, but now the payload flowing through it is a live GitHub PAT (`--token=`) or a provider API key (`--api-key=`), not just an installer binary.
- **Failure scenario:** If the fetch channel is compromised (DNS/TLS MITM, or a malicious commit landed in the unpinned repo before the operator's `git pull`), the substituted script can exfiltrate the PAT/API key the operator is about to hand it — a strictly higher-value target than "run malicious installer as unprivileged hermes" (Phase 2/4's own accepted-risk baseline). This asymmetry isn't called out anywhere in the plan's Security Considerations.
- **Evidence:** `scripts/vps-bootstrap-oci.sh:133-136` (comment): "claude.ai/opencode.ai installers are fetched via curl|bash with no published checksum to pin against... Accepted risk: runs as unprivileged `hermes`". Phase 2/4 Security Considerations sections don't reference or extend this existing accepted-risk note for the new credential-bearing scripts.
- **Suggested fix:** Recommend operators pull the numbered scripts from a pinned commit/tag (not `curl | bash` of `main`) specifically when a `--token=`/`--api-key=` flag is involved, or note this asymmetry explicitly as an accepted risk.

## Finding 5: `4-merge-delegation-config.sh` splices `--ccs-profile=<name>` into YAML with no validation

- **Severity:** Medium
- **Location:** Phase 6, section "Architecture" / "Key Insights"
- **Flaw:** `--ccs-profile=<name>` is merged straight into the `ccs_profile:` line of the live `delegation:` block via unspecified text substitution, with no charset/format validation shown anywhere in the plan.
- **Failure scenario:** A value containing a colon, embedded newline (via `$'a\nb'`), or leading `#`/quote can corrupt the block boundary the "detect + replace" logic relies on (the real block, verified at `templates/config/production.yaml:168-193`, is a multi-key nested structure with interleaved comments — not a single flat key=value line). The plan's own YAML-validate-then-rollback gate (`.bak` restore) only catches gross syntax breaks, not a value that's syntactically valid YAML but wrong (e.g. injecting a sibling key under `delegation:` because the substitution swallowed indentation).
- **Evidence:** `templates/config/production.yaml:168-193` shows `delegation:` as a nested block (`default`, `routing:` list, `ccs_profile`) with 6 lines of interspersed comments before `ccs_profile:` — the plan's Implementation Steps (step 2, "Merge the `delegation:` block... replace an existing block if present") don't specify a parser, only "textual" merge language.
- **Suggested fix:** Validate `--ccs-profile` against `^[A-Za-z0-9_-]+$` before use; do the merge/replace with a real YAML library (e.g. `python3 -c 'import yaml...'`) rather than line-based text substitution, given the block's nested shape is already confirmed non-trivial.

## Finding 6: TOCTOU risk copying a live/active user's CCS instance directory

- **Severity:** Medium
- **Location:** Phase 5, "Architecture" data flow
- **Flaw:** `/home/ubuntu/.ccs/instances/` has its own `.locks/` subdirectory, evidence CCS implements its own concurrency control around instance state. `cp -a` has no awareness of these locks and can copy a directory mid-write (session-env, history.jsonl) if the source user has an active session at copy time.
- **Failure scenario:** Operator runs `3-ccs-reuse-bridge.sh --instance=ken` while `ken`'s own CCS session is live (mtimes on `history.jsonl`/`session-env` in the actual instance show activity same-day as this review) — the copy can land in a torn/inconsistent state that then passes or fails the smoke test non-deterministically, or corrupts data the operator didn't intend to duplicate.
- **Evidence:** `ls -la /home/ubuntu/.ccs/instances/.locks/` exists (empty at review time, confirming the mechanism); `ls -la /home/ubuntu/.ccs/instances/ken/` shows `history.jsonl` mtime "Jul 4 21:13" and `session-env`/`.claude.json` similarly fresh.
- **Suggested fix:** Add a pre-copy check/warn for an active lock in `.locks/<name>` (or advise running only when the source user's session is confirmed idle) before `cp -a`.

## Finding 7: No explicit privilege precondition in any of the 5 scripts

- **Severity:** Medium
- **Location:** Phases 2, 3, 4, 5 (all Implementation Steps sections)
- **Flaw:** None of the 5 scripts' documented implementation steps include an `[ "$(id -u)" = 0 ]`-style guard, despite every one of them requiring root or passwordless-sudo-to-hermes (`sudo -u hermes -i ...`, `chown hermes:hermes`, and Phase 5's cross-user directory read at `/home/ubuntu/.ccs/instances/`).
- **Failure scenario:** Invoked by an operator without sufficient sudo rights, the first privileged command fails with a raw `sudo: a password is required` or `Permission denied` rather than the scripts' own `die()` with a clear message — inconsistent with every other `die`-on-precondition-failure pattern the plan otherwise follows (missing token, missing `.env`, missing source dir all get named `die`s).
- **Evidence:** phase-02/03/04/05's Implementation Steps enumerate `die` for missing flags/files but never for missing privilege; `scripts/deploy-systemd-units.sh` (the style being mirrored) also has no explicit EUID check, so this gap is inherited from the pattern being copied, not net-new — but it compounds here because these scripts handle live secrets, where a half-run script (e.g. token piped to `gh auth login` before a later `chown` fails) is a worse partial-state than a systemd unit sync failing halfway.
- **Suggested fix:** Add `[ "$(id -u)" = 0 ] || die "run as root (sudo)"` near the top of each of the 5 scripts.

---

## Fact Checker Verification (15 sampled claims, full 6-phase tier)

1. `scripts/vps-bootstrap-oci.sh:123-155` = section 6b coding-agent CLI block — **VERIFIED** (banner at 124, block closes 155; off-by-one on start line only, immaterial).
2. Section 6c/6d insertion point "between section 6b (:155) and section 7 (:157)" (phase-01) — **VERIFIED** (`scripts/vps-bootstrap-oci.sh:155` closing `'`, banner for section 7 starts `:157`, `# 7.` comment at `:158`).
3. `.env` scaffold at `scripts/vps-bootstrap-oci.sh:178-194` (phase-03) — **VERIFIED** (block actually 177-194; `ANTHROPIC_API_KEY=` at line 181, mode 600 chmod at 192).
4. `templates/config/production.yaml` `delegation.ccs_profile: ccs-hermes` (phase-04) — **VERIFIED** at `templates/config/production.yaml:193`; `delegation:` block starts `:168`.
5. `README.md:72` Repo Map row for `deploy-systemd-units.sh` (phase-06) — **VERIFIED** exact line/content match.
6. `CHANGELOG.md:5` existing `## 2026-07-04 — Unit-Drift Prevention Script + ClaudeKit Prerequisite Reframe` entry (phase-06) — **VERIFIED**.
7. `gh auth login --with-token` reads PAT from STDIN (phase-02) — **VERIFIED** via `gh auth login --help`: "use `--with-token` to pass in a personal access token... on standard input."
8. Minimum gh token scopes `repo`, `read:org`, `gist` (phase-02) — **VERIFIED** via `gh auth login --help`: "minimum required scopes for the token are: `repo`, `read:org`, and `gist`."
9. `scripts/deploy-systemd-units.sh` style — `set -euo pipefail`, `log()/warn()/die()`, `--force` arg loop (phases 2-6 "style to mirror") — **VERIFIED** at `scripts/deploy-systemd-units.sh:21-36`.
10. `ccs api create <name> --preset <id> --api-key <key> --target <cli> --yes/--force` syntax (phase-04) — **VERIFIED** via `ccs help api`; presets list includes `anthropic`, `glm`, `km`, `deepseek`, `qwen`, `openrouter` as claimed.
11. `ccs api remove <name>` rollback command (phase-04) — **VERIFIED** in `ccs help api` output.
12. `/home/ubuntu/.ccs/instances/ken/` exists as the reuse-bridge source (phase-05) — **VERIFIED**, and contains far more than credentials (see Finding 1).
13. Related plan phase files `phase-03-claude-auth-for-hermes.md` and `phase-05-provision-ccs-profile.md` exist under `plans/260703-1738-fix-urgent-hermes-delegation-issues/` (cross-referenced, not re-derived, by phases 3/4/5) — **VERIFIED** via directory listing.
14. `templates/systemd/hermes.service` `ProtectHome=read-only` + `ReadWritePaths=/home/hermes/.hermes /home/hermes/.ccs /tmp` (relevant to phase-03's "smaller blast radius" cross-reference) — **VERIFIED** at lines 41/45; `/home/hermes/.claude` is NOT in `ReadWritePaths`, but `/home/hermes/.ccs` IS — meaning credentials landed by Phases 4/5 under `~hermes/.ccs/` are within the same read/write surface a delegated same-UID sub-session can reach, same class of exposure the existing memory (`hermes-oauth-credential-exposed-to-delegated-subsessions`) already flags for `.claude`.
15. `skills/dev/coding-agent-delegate/SKILL.md` documents the `--allowedTools "Read,Edit,Bash"` delegated sub-session allowlist — **VERIFIED** (lines ~76-77) — supports Findings 1/6: whatever Phase 5 copies into `/home/hermes/.ccs/instances/<name>/` is readable by any same-UID delegated Bash-capable sub-session, same threat model already accepted-risked for OAuth creds, now extended to a full personal conversation history.

## Unresolved Questions

- None — all findings are grep/read-verified against current repo + live host state, not assumed from plan text.
