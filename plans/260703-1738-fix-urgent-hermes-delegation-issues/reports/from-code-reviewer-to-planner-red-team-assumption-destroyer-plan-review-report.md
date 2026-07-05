# Red-Team Plan Review: Fix Urgent Hermes Delegation Issues

Reviewer role: Assumption Destroyer + Scope Auditor. All findings live-verified against the actual host (`lucas-oracle-instance`) or public registry/docs, read-only, no mutating plan steps executed.

## Scope Auditor Classification (assigned verification role)

**Isolation of `~/.ccs` (and `~/.claude`) between `hermes` and `ubuntu`: PASS, filesystem-enforced, not just conventional.**

Evidence:
- `stat -c "%a %U:%G" /home/ubuntu` → `750 ubuntu:ubuntu`. `id` as hermes → `uid=1002(hermes) gid=1002(hermes) groups=1002(hermes),100(users)` — hermes is in neither `ubuntu`'s primary nor any group granting access to `/home/ubuntu`.
- Live negative test: `sudo -u hermes ls -la /home/ubuntu` → `Permission denied`. `sudo -u hermes cat /home/ubuntu/.ccs/config.yaml` → `Permission denied`. This is an actual enforced denial, not an assumption.
- `/home/hermes` itself is `750 hermes:hermes`; hermes's future `~/.ccs`/`~/.claude` do not exist yet (confirmed `ABSENT`), so nothing has leaked pre-emptively.
- `$HOME` resolution is safe across every invocation style the plan uses (`sudo -u hermes bash -c`, `-H`, `-i`, `bash -lc` all correctly resolved `HOME=/home/hermes` — no risk of an `npm install --prefix "$HOME/.local"` accidentally landing in ubuntu's home via HOME-inheritance).
- `ck init --help`'s `-g/--global` is described as "platform-specific user configuration directory" (not a shared/system path); the one working reference (`ubuntu`'s own `/home/ubuntu/.claude`) is exactly `$HOME/.claude`, consistent with per-user scoping, not a shared location. No system-wide `claudekit`/`.claude` path found under `/etc`, `/usr/local`, `/usr/share`.

**Caveat (see Finding 7):** the plan under-describes what actually lives under `~/.ccs` — it is not just "credentials/session/queue" or "plugins"; it is a much larger auto-executing surface (`hooks/`, `mcp/`, `cliproxy/`, `instances/`, plus a nested `.claude/{skills,commands}` tree). This does not break the cross-user isolation classification above (still PASS), but it means Phase 4/5's "Security Considerations" understate the blast radius they're accepting *inside* hermes's own home.

No leak path found for the hermes↔ubuntu boundary specifically. The plan's more serious problems are correctness bugs (below), not identity-boundary leaks.

---

## Finding 1: Phase 4 installs the wrong npm package for "ClaudeKit" — `ck init` will never run

- **Severity:** Critical
- **Location:** Phase 4, sections "Overview" and "Implementation Steps" (steps 1–3); propagates into Phase 6 "Implementation Steps" step 2 (SKILL.md reframe) and `research/live-host-verification-findings.md` §5.
- **Flaw:** The plan installs `npm install -g --prefix "$HOME/.local" claudekit`, then immediately runs `ck init --global`. `claudekit` (unqualified, on the public npm registry) and the `ck` CLI actually used throughout this repo/session are **two different packages by two different authors**, not versions of the same tool.
- **Failure scenario:** Phase 4 step 2 installs `claudekit@0.9.5` (bins: `claudekit`, `claudekit-hooks` — no `ck` binary at all). Step 3's `ck init --global --kit engineer --yes --install-skills --skip-setup` fails with "command not found" because nothing in step 1/2 ever put a `ck` binary anywhere. `~/.claude/skills` is never populated. Phase 4's own Success Criteria ("`~/.claude/skills` count > 0") fails. `harness: ccs` remains a permanent no-op exactly as it is today (`SKILL.md:48`) — defeating the entire stated purpose of this plan's EXPANSION scope. Phase 6 step 2 then bakes the same wrong install command into `SKILL.md`'s Prerequisites as permanent documentation.
- **Evidence:**
  ```
  $ npm view claudekit
  claudekit@0.9.5 | MIT | ... 
  https://github.com/carlrannaberg/claudekit#readme
  bin: claudekit, claudekit-hooks

  $ readlink -f "$(command -v ck)"     # ubuntu's own already-working ck
  /home/ubuntu/.local/share/fnm/node-versions/v24.15.0/installation/lib/.../claudekit-cli/bin/ck.js
  $ grep name/version that package's package.json
  "name": "claudekit-cli", "version": "4.5.0" (registry latest: 4.5.1)
  https://github.com/mrgoonie/claudekit-cli   bin: ck
  ```
  Two distinct packages, distinct repos, distinct maintainers, distinct bin names. `research/live-host-verification-findings.md §5` ran `npm view claudekit version` (resolves `0.9.5`) but never cross-checked it against the `ck` binary already installed and working for `ubuntu` on the very same host — a one-command check (`command -v ck`) that would have caught this immediately.
- **Suggested fix:** Change Phase 4 step 2 to `npm install -g --prefix "$HOME/.local" claudekit-cli` (verified present on the registry: `claudekit-cli@4.5.1`). Re-verify `ck --help`'s actual flag set against `claudekit-cli`'s current CLI (not `claudekit`'s) before trusting `--kit engineer --yes --install-skills --skip-setup` all still apply.

## Finding 2: Phase 4's own verification command is syntactically broken — always fails regardless of install success

- **Severity:** Critical
- **Location:** Phase 4, "Implementation Steps" step 4, and "Success Criteria".
- **Flaw:** `sudo -u hermes command -v ccs` — `command` is a **shell builtin**, not a standalone executable. `sudo` execs a real binary via `secure_path`; there is no `command` binary on this host (or most Linux hosts) outside a shell.
- **Failure scenario:** Run verbatim, this always fails with a lookup error, independent of whether `ccs` was installed correctly in steps 1–2. An agent or human treating this as the completion gate gets a false negative every single time.
- **Evidence:**
  ```
  $ sudo -u hermes command -v ccs
  sudo: command: command not found
  $ echo $?
  1
  ```
  Confirmed live; `/usr/local/bin` and `/usr/local/sbin` (checked) are empty, so no wrapper rescues this.
- **Suggested fix:** `sudo -u hermes bash -c 'command -v ccs'` (wrap in a shell so the builtin resolves), and even then PATH must be set explicitly inside that `bash -c` (see Finding 3) — plain `bash -c 'command -v ccs'` without an exported PATH will also fail, since `.local/bin` isn't on the non-login shell's PATH by default.

## Finding 3: Phase 2's P0 acceptance test is broken today — "command not found," not a seccomp signal, live-verified

- **Severity:** Critical
- **Location:** Phase 2, "Implementation Steps" step 3, and "Todo List" ("`claude`/`opencode --version` succeed; no new SIGSYS after restart").
- **Flaw:** `sudo -u hermes claude --version` / `sudo -u hermes opencode --version` (no `bash -c`, no login shell, no explicit PATH) resolve via sudoers' `secure_path` only. `secure_path` on this host is `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin` — it does **not** include `/home/hermes/.local/bin`, where `claude`/`opencode` actually live. There is no symlink for these binaries anywhere on `secure_path`.
- **Failure scenario:** A human runs Phase 2's exact verification command post-deploy expecting to confirm the SIGSYS fix. Instead they get `sudo: claude: command not found` (exit 127-class) — a completely different failure signature than the SIGSYS/core-dump the fix targets. This is indistinguishable, on its face, from "the fix didn't take" and risks a wrong rollback decision, or at minimum burns troubleshooting time on the wrong layer. Confirmed this is not hypothetical: the debug report's own audit evidence and the currently-running bot's journal (`journalctl -u hermes`, see Finding 5) both show `claude`/`opencode` ARE reachable in *other* invocation contexts (systemd's `EnvironmentFile=` PATH, or a login shell that sources `.bashrc`) — so the gap is specifically in this literal command form, not in the CLIs' actual installation.
- **Evidence:**
  ```
  $ sudo -u hermes claude --version
  sudo: claude: command not found
  $ sudo -u hermes opencode --version
  sudo: opencode: command not found
  $ sudo -u hermes env | grep ^PATH
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
  $ sudo -u hermes bash -c 'echo PATH=$PATH'      # same result, bash -c doesn't source .bashrc
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
  $ sudo -u hermes -i bash -c 'echo PATH=$PATH'   # only -i (login sim) picks up .bashrc's PATH export
  PATH=/home/hermes/.local/bin:/usr/local/sbin:...
  ```
  `/home/hermes/.bashrc:119-120` has `export PATH="$HOME/.local/bin:$PATH"` — this is why a *login* shell works. Plain `sudo -u hermes <cmd>` never sources it.
- **Suggested fix:** Use `sudo -u hermes -i claude --version` (or `sudo -u hermes bash -lc 'claude --version'`) in every Phase 2/4 verification step, consistently — not a bare `sudo -u hermes <cmd>`. Apply the same fix to Finding 2's `ccs` check.

## Finding 4: Phase 3's "device-code style" OAuth claim is unverified and likely wrong for this CLI version

- **Severity:** High
- **Location:** Phase 3, "Overview" and "Key Insights" ("prints a URL + code completable from any device... works over SSH-only access, no browser on the host").
- **Flaw:** The installed `claude` (`2.1.199`) `auth login --help` shows only `--claudeai / --console / --email / --sso` — no mention of a device-code mechanism. Public documentation and multiple live upstream issues describe Claude Code's actual OAuth mechanism as a **loopback local-HTTP-server callback** (starts a server on a random local port, opens a browser to `console.anthropic.com`) — the same class of flow that is well-documented to break over pure SSH without port-forwarding or a local browser.
- **Failure scenario:** Whoever runs Phase 3 step 1 (`claude auth login` from a plain `sudo -u hermes` shell over SSH, no browser, no X11) may hit the exact failure mode reported upstream: browser fails to open (headless), and/or the local callback port is unreachable from wherever the human opens the printed URL. Some CLI versions have a manual fallback ("press c to copy the URL... paste code into the terminal"), which is closer to what the plan describes — but that is a *fallback UX detail*, not the primary "device-code style" mechanism the plan confidently asserts, and it is not guaranteed present/working in `2.1.199` (untested here; the plan cites no test of `claude auth login` itself, only `--help` text of `claude` generally).
- **Evidence:**
  ```
  $ sudo -u hermes -i bash -c 'claude auth login --help'
  Options:
    --claudeai       Use Claude subscription (default)
    --console        Use Anthropic Console (API usage billing) instead of Claude subscription
    --email <email>  Pre-populate email address on the login page
    --sso            Force SSO login flow
  (no device-code / URL+code language anywhere)

  $ sudo -u hermes -i bash -c 'claude --help' | grep -i auth
  setup-token   Set up a long-lived authentication token   # <- exists, never mentioned by the plan
  ```
  Web search corroboration: Claude Code Docs + live GitHub issues `anthropics/claude-code#20793` ("OAuth login fails in devcontainers — callback port not forwarded") and `#9376` ("OAuth callback server hangs after authorization — setup-token and /login both fail") describe exactly this failure class in remote/SSH/headless sessions.
- **Suggested fix:** Do not assert the mechanism confidently. Have the human test `claude auth login` first and be ready to fall back to `claude setup-token` (already present in `--help`, never mentioned in the plan) or `ANTHROPIC_API_KEY`, per Anthropic's own documented headless guidance, if the interactive login stalls.

## Finding 5: Phase 6's completion gate will likely hit a separate, already-observed EROFS failure unrelated to this plan's fixes

- **Severity:** High
- **Location:** Phase 6, "Implementation Steps" step 1 ("trigger one real `/delegate_code` task"); not addressed by any of the 6 phases; `templates/systemd/hermes.service:45` (`ReadWritePaths=/home/hermes/.hermes /home/hermes/.ccs /tmp`).
- **Flaw:** The currently-running bot has already, in production, hit `npm error code EROFS ... path /home/hermes/.npm/_cacache/...` — `/home/hermes/.npm` (npm's default cache directory under `$HOME`) is not in `ReadWritePaths` and is blocked by `ProtectHome=read-only`. This is a live, observed failure, not speculation.
- **Failure scenario:** Phase 6's real end-to-end test is the plan's stated "true completion gate." If the delegated task involves any `npm install`/`npm ci` (plausible for many real coding tasks — dependency audits, adding a package, running an install as part of a build/test step), it will fail with the same EROFS error already seen in the journal, independent of whether the SIGSYS/auth/ccs fixes in Phases 2/3/5 all work correctly. Nothing in the plan's Risk Assessment or the debug report's "layer 4b" note anticipates this specific, already-manifested symptom — only the generic, untested category "sandboxed delegation writes... unverified." A test failure here could be misattributed to a regression in this plan's changes rather than a pre-existing, orthogonal gap.
- **Evidence:**
  ```
  $ sudo systemctl status hermes.service --no-pager -l
  Jul 03 09:48:43 ... hermes[3276211]: WARNING agent.tool_executor: Tool terminal returned error (1.18s):
    {"output": "npm error code EROFS\nnpm error syscall open\nnpm error path /home/hermes/.npm/_cacache/tmp/cf0bc129\nnpm error errno EROFS ..."}
  ```
  `templates/systemd/hermes.service:45`: `ReadWritePaths=/home/hermes/.hermes /home/hermes/.ccs /tmp` — no `/home/hermes/.npm`.
- **Suggested fix:** Either add `/home/hermes/.npm` (or redirect via `npm config set cache` to somewhere already writable, e.g. under `.hermes/`) to the hardening, or explicitly scope Phase 6's real-task test to avoid any package-manager operation and document that limitation so a future npm-touching delegation doesn't get misdiagnosed.

## Finding 6: `[AGENT]`/`[HUMAN]` tagging throughout the plan is derived from a session-specific sudoers grant, not a verified-reproducible one

- **Severity:** Medium
- **Location:** Plan-wide — `plan.md` "Overview" ("Every host mutation is tagged... under NOPASSWD `sudo -u hermes`"); every phase's "Ownership" line; `research/live-host-verification-findings.md` §2.
- **Flaw:** Every `[AGENT]`-safe classification in this plan rests on one `sudo -n -l` snapshot explicitly scoped to the `ubuntu` account on this host, and its provenance is not discoverable in the repo.
- **Failure scenario:** If `/ck:cook` (or a human) executes this plan under a different account, a rotated/narrower sudoers grant, or a future session where this NOPASSWD rule has been tightened, every `[AGENT]`-tagged step (Phases 1's restart logic, Phase 2's verification, Phase 4's entire install sequence, Phase 5's smoke test) could silently prompt for a password instead of running non-interactively — which hangs or fails a non-interactive agent run without a documented detection/escalation step. The plan never instructs "re-run `sudo -n -l` and confirm it matches before trusting `[AGENT]` tags."
- **Evidence:**
  ```
  $ sudo -n -l
  Matching Defaults entries for ubuntu on lucas-oracle-instance:
      env_reset, mail_badpass, secure_path=..., use_pty
  User ubuntu may run the following commands on lucas-oracle-instance:
      (hermes) NOPASSWD: ALL
      (root) NOPASSWD: /bin/systemctl start hermes*, ... daemon-reload, journalctl -u hermes*
  ```
  Grepped the repo for `NOPASSWD`/`sudoers` provisioning — the only hits are prior planning/journal docs *describing* this grant after the fact (`docs/journals/260703-hermes-bun-sched-setscheduler-systemd-filter-bugfix.md:40`, the debug report), never a script that creates it (no hit in `scripts/vps-bootstrap*.sh`). `sudo -n cat /etc/sudoers.d/*` itself requires a password — the grant's origin/durability cannot even be inspected read-only.
- **Suggested fix:** Add an explicit pre-flight step: "run `sudo -n -l` and confirm the NOPASSWD grants below are present before executing any `[AGENT]`-tagged step; if absent, treat all steps as `[HUMAN]`."

## Finding 7: `~/.ccs`'s accepted risk surface is understated — it's not just "credentials" or "plugins"

- **Severity:** Medium
- **Location:** Phase 4 "Security Considerations" ("~/.ccs/ (plugins)"); Phase 5 "Overview"/"Context Links"; `templates/systemd/hermes.service:42-44` comment ("holds per-profile CCS state (credentials, session history, job queue)").
- **Flaw:** The only real reference install on this host (`/home/ubuntu/.ccs`, the same product, same version family) shows a much larger footprint than "credentials/session/queue" or "plugins": `hooks/`, `mcp/`, `cliproxy/`, `instances/`, `completions/`, `logs/`, `shared/`, plus a nested `.claude/{skills,commands}` tree that gets symlinked into the user-level `~/.claude/` (`~/.claude/skills/ccs-delegation -> ~/.ccs/.claude/skills/ccs-delegation`, `~/.claude/commands/ccs -> ~/.ccs/.claude/commands/ccs`).
- **Failure scenario:** Not a cross-user leak (isolation still holds — see Scope Auditor section) — but Phase 4/5's security review scopes the "accepted risk" too narrowly. `hooks/` and `mcp/` are auto-executing surfaces (hooks fire on events; MCP servers are long-running processes) that the plan doesn't mention when it says "two new auto-executed code surfaces... `~/.ccs/` (plugins)." If `ccs api create`/first-run on hermes replicates this same footprint, hermes's `~/.ccs` becomes a considerably richer execution surface than "an API key file," which changes the actual blast radius of the widened `ReadWritePaths=/home/hermes/.ccs` grant beyond what's documented.
- **Evidence:**
  ```
  $ ls -la /home/ubuntu/.ccs
  cache/ .claude/ cliproxy/ completions/ config.yaml hooks/ instances/ logs/ mcp/ prompts/ shared/
  $ ls -la /home/ubuntu/.ccs/.claude
  commands/ skills/
  $ npm view @kaitranntt/ccs@8.7.0
  "Claude Code Switch - Instant profile switching..." bin: ccs, ccsd, ccsx, ccsxp, ccs-codex, ccs-droid
  ```
- **Suggested fix:** Update the Security Considerations language from "plugins" to explicitly enumerate `hooks/` and `mcp/` as auto-executing, and confirm (post-Phase-5) exactly what gets created under hermes's `~/.ccs` before calling the risk "accepted" — don't infer scope from the product's marketing description alone.

## Finding 8: No recovery path if the operator starts Phase 5's wizard without a ready credential

- **Severity:** Medium
- **Location:** Phase 5, "Implementation Steps" step 1; "Risk Assessment" (only lists "Preset mismatches the credential's provider," not "no credential yet").
- **Flaw:** Phase 5's own "Security Considerations" flags as an open question "which `--preset`/provider credential will the operator dedicate to the bot?" — i.e., the plan is written knowing this may not be decided/available yet, but step 1 has the operator invoke the interactive `ccs api create ccs-hermes --preset <p>` wizard directly, with no guidance for what to do if they start it and don't have the key in hand.
- **Failure scenario:** Operator runs the wizard, gets to the key prompt, doesn't have a fresh hermes-dedicated key ready (e.g., needs to provision one from a provider console first), and aborts (Ctrl-C or blank entry). The plan doesn't say whether `ccs api create` leaves a named-but-incomplete `ccs-hermes` profile entry behind, or is atomic. On retry, this could hit a "profile already exists" error, or silently produce a broken profile that then fails Phase 5's own smoke test for an unrelated reason (partial state, not a genuine credential/config problem) — muddying diagnosis.
- **Evidence:** Phase 5 "Security Considerations": `**Open question:** which --preset/provider credential will the operator dedicate to the bot?` — explicitly unresolved at plan-authoring time, yet step 1 is written as if the operator will have it ready. No `ccs api remove`/cleanup command is mentioned anywhere in Phase 5 or its Rollback section for a *partial* creation (Rollback only covers a *fully created* profile).
- **Suggested fix:** Add a pre-step: confirm the credential is in hand *before* invoking the wizard; document the exact cleanup command for a partial/aborted `ccs api create` (check `ccs api --help` for a `remove`/`delete` subcommand) so a false-start doesn't block retries.

---

**Status:** DONE
**Summary:** 8 findings — 3 Critical (wrong npm package for ClaudeKit blocks the plan's core goal; Phase 4's `command -v` verification is syntactically broken; Phase 2's P0 acceptance test fails with "command not found" today, live-verified, unrelated to the seccomp fix it's meant to confirm), 2 High (Phase 3's "device-code" OAuth claim contradicted by live `--help` output and public docs; Phase 6's completion gate will likely collide with an already-observed, unaddressed `~/.npm` EROFS failure), 3 Medium (session-specific sudo-scope portability; understated `~/.ccs` risk surface; no recovery path for a mid-wizard credential gap in Phase 5). Scope Auditor classification: hermes↔ubuntu `.ccs`/`.claude` isolation is **PASS**, filesystem-enforced and live-verified (permission-denied tests), with the caveat that `.ccs`'s own contents are broader than documented (Finding 7).
