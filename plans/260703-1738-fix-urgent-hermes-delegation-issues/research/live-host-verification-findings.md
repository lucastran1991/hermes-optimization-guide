# Live-Host Verification Findings — hermes user provisioning (lucas-oracle-instance)

Method: direct verification via `sudo -u hermes`/`sudo -n -l`/`npm view`/`--help` on the actual target host, not web research or scout agents — higher-confidence than external docs for host-specific facts (npm prefix writability, sudo scope, package resolution from this network).

## 1. Root cause + fix (full detail: `plans/reports/ck-debug-260703-1725-hermes-seccomp-claude-sigsys-stale-unit-report.md`)
Live `/etc/systemd/system/hermes.service` predates commit `c9631fc` (seccomp re-allow for `sched_setscheduler`) and `72cc2fd` (`ReadWritePaths+=/home/hermes/.ccs`). Both fixes exist in `templates/systemd/hermes.service`, neither deployed. One `install`+`daemon-reload`+`restart` fixes both.

## 2. Sudo scope (this session / ubuntu user)
`sudo -n -l`: NOPASSWD for `(hermes) ALL` (full run-as-hermes) + `systemctl {start,stop,restart,status} hermes*`, `daemon-reload`, `journalctl -u hermes*`. **No generic root file-write** — deploying to `/etc/systemd/system/` needs a human to run one `sudo install` command interactively (password required). Everything else below is agent-executable via `sudo -u hermes`.

## 3. claude CLI auth — two independent mechanisms
- `ANTHROPIC_API_KEY` env var: direct API billing, fully headless, no login step. Confirmed via `claude --help`: "strictly ANTHROPIC_API_KEY or apiKeyHelper... OAuth and keychain never read" (for isolated-settings invocations).
- `claude auth login`: OAuth against a Claude subscription seat, interactive (prints URL+code, works over SSH-only access, no local browser needed). `claude auth status` only reports on THIS mechanism — a "Not logged in" status does not imply API-key-based calls would fail; they're orthogonal.
- User selected **interactive OAuth login** for hermes (ties bot delegation usage to a real Claude subscription seat — flag whose account in Security Considerations).
- Neither `claude auth login` nor `--version`/`-p` invocation needs the systemd sandbox — safe to run from a plain `sudo -u hermes` shell (only `hermes gateway run`, the actual service process, is sandboxed). No ordering dependency between the P0 unit-deploy and the auth step.

## 4. ccs binary — installable now, currently absent
`command -v ccs` as hermes → not found. `/home/hermes/.ccs/` does not exist. But:
- `scripts/vps-bootstrap-oci.sh` (since commit `9fafe6e`) already has: `npm install -g --prefix "$HOME/.local" @kaitranntt/ccs@8.7.0` (idempotent, guarded by `command -v ccs ||`) — never successfully executed on this host (binary absent despite the other 3 CLIs from the same script section existing). Likely: host's CLI setup predates this line, or ran once and the `|| echo "[warn]..."` swallowed a failure silently.
- `npm view @kaitranntt/ccs@8.7.0 version` from this host → resolves fine (`8.7.0`, exit 0). Registry reachable, version exists — no reason the existing bootstrap line shouldn't work if re-run.
- hermes's system npm default prefix (`/usr`) is **not writable** by hermes (confirmed EACCES) — this is exactly why the existing script uses `--prefix "$HOME/.local"`. Any new install command for hermes MUST use the same `--prefix "$HOME/.local"` pattern.
- **Action: one-time remediation command, agent-executable** (`sudo -u hermes` NOPASSWD): `sudo -u hermes bash -c 'npm install -g --prefix "$HOME/.local" @kaitranntt/ccs@8.7.0'`.

## 5. ClaudeKit — installable now, currently absent
`/home/hermes/.claude/skills/` does not exist (confirmed absent — this is the fact behind the `/ask` answer that `harness: ccs` is currently a no-op per `skills/dev/coding-agent-delegate/SKILL.md`'s own Prerequisites note).
- `npm view claudekit version` from this host → resolves (`0.9.5`).
- `ck init --help` confirms a **fully non-interactive** install path: `-y/--yes` (sensible defaults) + `--skip-setup` (skip interactive provider-key wizard) + `--install-skills` (non-interactive skill deps) + `-g/--global` (installs to the user-level `~/.claude/` dir, not a project-local one — this is what we want, since delegated calls target arbitrary `repo=` paths, not one fixed project).
- **Action, agent-executable:**
  ```bash
  sudo -u hermes bash -c 'npm install -g --prefix "$HOME/.local" claudekit'
  sudo -u hermes bash -c 'export PATH=$HOME/.local/bin:$PATH; ck init --global --kit engineer --yes --install-skills --skip-setup'
  ```

## 6. ccs api create — provider presets + credential-hygiene constraint
`ccs api --help` (checked via ubuntu's own already-installed `ccs`, read-only, config never touched) confirms:
- `--preset {glm|km|anthropic|...}` (`km` = Kimi) matches the "glm/kimi/custom" language already in `templates/config/production.yaml`'s delegation comment and skill docs.
- A non-interactive form EXISTS (`ccs api create <name> --preset <p> --api-key <key> --yes`) but `coding-agent-delegate/SKILL.md` explicitly prefers the **interactive** wizard "over the `--api-key` command-line form, which leaves the key in shell history/process args" — respect that documented preference; do not silently "optimize" it away. Plan keeps this step human-interactive.
- `ccs auth`/`ccs persist`/`ccs sync` exist but are NOT needed for the delegate skill's documented usage (`ccs "<profile>" -p "..."` called directly per-invocation) — out of scope, YAGNI.

## 7. CRITICAL — hermes needs a SEPARATE CCS identity, never ubuntu's
`/home/ubuntu/.ccs/config.yaml` (mode 600, owned by ubuntu) is the **same CCS product** (`ccs` CLI) that this very session's "ken" instance runs under (`/home/ubuntu/.ccs/instances/ken/...`) — confirmed by directory layout (`instances/`, `config.yaml`, `cliproxy/`), not a naming collision with a different tool. **Not read** (contains real credentials, irrelevant to hermes's separate identity, consistent with plan `260703-1041`'s "separate API key, quota, audit trail" requirement). Hermes's `ccs api create` run must supply a **fresh, hermes-dedicated** credential — never copy/export/import ubuntu's profile.

## 8. Prior plans (completed, not blocking — referenced for lineage only)
- `plans/260703-0347-hermes-coding-agent-delegation-skill/` — added the delegate skill itself.
- `plans/260703-1041-ccs-full-harness-coding-agent-delegation/` — added opt-in `harness: ccs` param, explicitly documented ClaudeKit install as **out-of-scope** at the time. This plan (user-selected EXPANSION scope, this session's `/ask` + `/ck:plan` exchange) explicitly re-opens that decision — not a silent reversal, tracked here + in plan.md Context.

## Unresolved (carried to plan's open questions)
- Who/what deployed the stale Jul-2 unit — no forensic value pursued (low ROI vs. just fixing recurrence via Phase 1's drift-prevention script).
- Which `ccs api create --preset` the user will actually pick (glm/km/other) depends on which provider credential they choose to dedicate to the bot — deferred to phase execution time, doesn't block plan-writing.
