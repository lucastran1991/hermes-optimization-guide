# Scout Report: Hermes OCI Live-Host Drift & Best-Practice Audit

Scope: live Hermes install on this OCI host (provisioned by `scripts/vps-bootstrap-oci.sh`), verified directly via Bash on the host itself (not just repo reading), cross-checked vs repo templates, official guide docs, and prior fix history. 4 parallel agents + direct checks.

## Root Cause (single highest-leverage finding)

**`/opt/hermes-optimization-guide` is stale and effectively un-fixable by the current user.**
- `/opt` HEAD = `60a2683`, 14 commits behind `origin/main` / workspace repo (`ac78889`).
- `/opt` is `root:root 755` — `ubuntu` cannot `git fetch`/`pull` there (`Permission denied` on `.git/FETCH_HEAD`).
- `scripts/deploy-systemd-units.sh` has a staleness guard (`git fetch` + compare) but swallows the fetch failure (`2>/dev/null` + soft `warn`, no `die`) and proceeds — so running it *right now* would falsely report "0 changed, nothing to do" instead of fixing or failing loudly.
- Because systemd `EnvironmentFile=`/unit source and all 14 skill symlinks resolve against `/opt`, **every fix merged to `origin/main` since `60a2683` is invisible on the live host** until someone with root re-pulls `/opt` and reruns the deploy script.

Two concrete consequences of this one root cause:

1. **`/etc/systemd/system/hermes.service` missing `Environment=PATH=...` and `/home/hermes/.claude` in `ReadWritePaths=`** (fix landed in commit `28431a3`, never reached `/opt`→`/etc`). Currently masked — `~/.hermes/.env`'s own `PATH=` line (loaded via `EnvironmentFile=`) happens to cover the gap today, but that's the exact fragile fallback the unit-level fix's own commit message warns against (only works for freshly-scaffolded `.env` files). One `.env` rewrite away from `command not found` (exit 127) on every delegated `ccs`/`claude`/`ck`/`opencode` call. `/home/hermes/.claude` missing from `ReadWritePaths=` also risks `EROFS` under `ProtectHome=` for any write there.
2. **`coding-agent-delegate` skill's `SKILL.md` (symlinked from `/opt`) still tells users `/delegate_code`** instead of the corrected `/coding-agent-delegate` (fix in commit `0250db4`, this morning, never reached `/opt`). This directly contradicts an existing debug report (`ck-debug-260704-2133`) that claimed "docs corrected, `/opt` synced" — that claim is **false today**.

**Recommended fix (needs root):**
```bash
sudo git -C /opt/hermes-optimization-guide pull --ff-only
sudo bash scripts/deploy-systemd-units.sh   # or wherever it's meant to be invoked from
```
Also worth hardening: make `deploy-systemd-units.sh`'s fetch-failure path `die`, not `warn`+continue — this exact drift class has now bitten this project 2-3 times per the journals (see docs/journals/260704-live-imds-fix-...).

## Other Confirmed Drift / Bugs

- **Broken cross-user symlink:** `~hermes/.claude/skills/ccs-delegation → /home/ubuntu/.ccs/.claude/skills/ccs-delegation`, owned by `ubuntu`, unreadable by `hermes` (permission denied). hermes has its own valid copy at `/home/hermes/.ccs/.claude/skills/ccs-delegation/` — the symlink should point there. Net effect: hermes's Claude Code **cannot load the `ccs-delegation` skill at all right now**. Likely a `ccs`/`ck` install step that resolved `$HOME` against the wrong user.
- **Flagged in logs:** at 12:19 the hermes agent's terminal tool attempted `su hermes` and `su ubuntu` (both failed, no tty/password) — an agent-initiated attempt to switch into other local accounts, including the host's own login user. Unresolved whether this is a routine self-diagnostic (checking claude auth for both accounts) or anomalous/injected behavior — needs tracing to the triggering skill/task.
- **`ANTHROPIC_API_KEY` empty in `~/.hermes/.env`**, while `config.yaml` routes `coding_complex`/high-complexity tasks to `anthropic/claude-sonnet-5`. Primary model provider is `nous`, so this may be intentional, but as-is that routing rule would fail over or error if triggered — needs confirmation.

## Best-Practice Compliance Gaps (vs this guide's own docs)

1. **Config never upgraded from the bootstrap stub.** Live `config.yaml` = `cost-optimized.yaml` scaffold + onboarding-added keys, never swapped to `production.yaml`/`security-hardened.yaml` despite this being a persistent, multi-service box with real Telegram tokens and real secrets — contradicts the README's own "I'm running this in production" path.
2. **Zero observability.** No Langfuse/OTEL/Helicone anywhere in `.env` or config, despite `hermes.service` being a live production install. No trace surface if something loops, burns budget, or gets prompt-injected via Telegram — only raw journald.
3. **Untrusted-input + broad execute allowlist + no terminal isolation.** `approvals.destructive_slash_confirm: false` disables the documented default protection for `/clear /new /reset /undo`; `command_allowlist: [execute_code]` is a standing always-approve on code execution; `terminal.backend` is unset (defaults to local, no docker/ssh isolation) — this combination, on a box that ingests untrusted Telegram input, is exactly what part19-security-playbook.md calls "operating outside Hermes' supported security model."
4. `tirith` (secrets-redaction binary) referenced by config comments but **not installed** — one documented defensive layer silently absent (low severity, `redact_secrets` default `true` still covers the base case).

## Confirmed PASS / Correctly-Designed (no action needed)

- `hermes-dashboard.service` byte-identical to repo template — in sync.
- `delegation:` config block correctly merged via `scripts/provision-hermes-delegation/4-merge-delegation-config.sh`, matches `production.yaml` verbatim, backup timestamps line up.
- Caddy and UFW correctly absent (by OCI-variant design); no stray cron/timers.
- `fail2ban` is *not* dead weight here — `sshd` genuinely listens on `0.0.0.0:22`/`[::]:22` (not Tailscale-only), so it's real defense-in-depth pending OCI NSG config (not independently verifiable from inside the host).
- `unattended-upgrades` functioning via `apt-daily.timer`/`apt-daily-upgrade.timer` (no literal `unattended-upgrades.timer` unit — that's expected on Ubuntu).
- Seccomp `sched_setscheduler` SIGSYS fix is deployed and holding (0 SIGSYS hits in journal).
- All 14 expected skill symlinks present, matching repo, no dangling links (`-xtype l` clean) other than the cross-user `ccs-delegation` case above.
- ClaudeKit is now fully initialized globally (`ck doctor` → PASS, 14 agents/86 skills) — this contradicts an older report (`live-host-verification-260704-2009`) that called it an open gap; it's since been fixed.
- A real, working `ccs-hermes` CCS profile now exists (created today, functional `ccs ccs-hermes --version` responds) — also contradicts the same older report calling it pending.
- `2-ccs-profile.sh`'s shell-injection fix (env-var indirection for `--preset`/`--api-key`) is correctly landed in the repo and correctly *not* yet deployed live (human-gated, as designed). The one remaining raw-concatenated var (`PROFILE_NAME`) is a hardcoded constant, not user input — not exploitable.
- `.gitignore`, GHA action SHA pinning, and known curl\|bash installer risk (accepted, unfixed by design) all match what the security-scan remediation report claims — no discrepancy.

## Unresolved Questions

1. Who/what triggered the `su hermes`/`su ubuntu` attempts in the agent's own terminal tool at 12:19 — routine or anomalous? Needs tracing to the specific task/skill.
2. Is `ANTHROPIC_API_KEY` empty intentional (nous is primary) or a leftover gap that breaks the `coding_complex` routing rule?
3. Should `/opt/hermes-optimization-guide` ownership/reconciliation be automated (e.g., a periodic `sudo git pull` timer, or fixing `deploy-systemd-units.sh` to hard-fail instead of silently warning on fetch failure) given this is now a recurring drift class?
4. OCI Security List / NSG rules could not be verified from inside the host — the "fail2ban is real defense-in-depth" conclusion assumes NSGs are scoped as the bootstrap script's header claims.
5. Was `ccs-hermes` provisioned via the documented wizard or some other path — not traced, outside this audit's read-only scope.
