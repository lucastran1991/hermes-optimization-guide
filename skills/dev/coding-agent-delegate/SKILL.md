---
name: coding-agent-delegate
description: Delegate a coding task to a CLI agent, escalating to a Kanban lane or remote sandbox
when_to_use:
  - User invokes /delegate_code <task>
  - A Kanban card is assigned to a coding-agent lane
  - A task needs isolated or remote execution (heavy compute / untrusted deps)
toolsets:
  - delegate_task
  - kanban
  - sandbox
  - file
parameters:
  task:
    type: string
    description: "What to build/fix, in one line"
    required: true
  repo:
    type: string
    description: "Target repo/worktree path or owner/repo"
    required: true
  escalate:
    type: string
    enum: [auto, print, kanban, sandbox]
    default: auto
  harness:
    type: string
    enum: [bare, ccs]
    default: bare
    description: "bare = plain `claude` (default — works with zero extra setup). ccs = route claude-code through `ccs <profile>` for a scoped delegation identity; only grants CK harness if ClaudeKit is separately provisioned on this host (see Prerequisites). Opt in only after Phase 1's smoke-test gate passes. No-op for codex/gemini-cli/opencode."
  parallel:
    type: integer
    description: "Number of subtasks to fan out concurrently within one delegate_code call. Each subtask runs in its own git worktree (see Git Hygiene). Optional — omit for a single-subtask delegation."
---

# coding-agent-delegate — Tiered Coding-Agent Delegation

> **Security note:** Delegated sub-sessions may get write/exec tools (`Edit`, `Bash`, `Write`). Scope the tool allowlist to the minimum required per tier. Isolate each delegation on its own branch/worktree. Never pass writable production credentials into a sub-session.

## Prerequisites

The routing table below shells out to external CLIs: `claude` (claude-code), `codex`, `gemini` (gemini-cli), `opencode`. Each one must be installed **for the user that runs the Hermes gateway** and resolvable from the **service PATH** — not just from an interactive shell:

- systemd does not read shell profiles. A CLI installed under a different login user's home (e.g. an fnm/nvm-managed npm prefix) is unreachable from the service and fails at delegation time with `claude: command not found` (exit 127).
- `scripts/vps-bootstrap.sh` and `scripts/vps-bootstrap-oci.sh` (section 6b) install all four CLIs into `~hermes/.local/bin`, and their generated `~/.hermes/.env` prepends that dir to the service PATH via the unit's `EnvironmentFile=`.
- Quick check that the service (not your shell) can see them: `sudo -u hermes env PATH=/home/hermes/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin claude --version` (repeat per CLI).
- Caveat: the hardened `templates/systemd/hermes.service` sets `ProtectHome=read-only` with `ReadWritePaths=/home/hermes/.hermes` only — a delegated CLI that writes state under `$HOME` (e.g. `~/.claude`, `~/.codex`) may need its state dir redirected into `~/.hermes/` (same pattern as the unit's `XDG_STATE_HOME` workaround) or an extra `ReadWritePaths=` entry.
- **`ccs` — required only when `harness: ccs` is used.** `scripts/vps-bootstrap.sh` / `-oci.sh` install `ccs@8.7.0` alongside the other four CLIs. Before flipping any delegation to `harness: ccs`, complete the one-time profile-provisioning step: run the interactive wizard `ccs api create` (preferred over the `--api-key` command-line form, which leaves the key in shell history/process args) to create the profile named in `templates/config/production.yaml`'s `delegation.ccs_profile` field (see that file's provisioning comment). `templates/systemd/hermes.service`'s `ReadWritePaths=/home/hermes/.ccs` (Phase 1) must already be in place for the profile's state to persist. Confirm the profile actually works with Phase 1's manual smoke-test gate — `ccs "<ccs_profile>" -p "echo ok" --output-format json` must exit 0 with valid JSON — **before** enabling `harness: ccs` anywhere; there is no automatic fallback to `bare` on failure. **ClaudeKit itself (the `~/.claude/` bundle) is a separate prerequisite this guide does not install** — `harness: ccs` without it produces identical (zero-harness) behavior to `harness: bare`.

## Procedure

1. **Parse the task** — read `task`, `repo`, `escalate`; classify intent (refactor / bugfix / explore / dependency_audit).

2. **Tier 1 — print mode (default)** — pick an agent via the `delegation.routing` cost table:
   ```yaml
   delegation:
     default: claude-code
     routing:
       - match: { type: refactor, files_changed_gte: 5 }
         agent: claude-code
       - match: { type: bugfix, single_file: true }
         agent: codex
       - match: { type: explore, repo_tokens_gte: 200000 }
         agent: gemini-cli
       - match: { type: dependency_audit }
         agent: gemini-cli
       - match: { budget: low }
         agent: opencode
         model: moonshot/kimi-k2.6
   ```
   Invoke print-mode CLI. For edit-only tasks that don't need shell access, scope the allowlist down — no Bash:
   ```bash
   claude -p "..." --allowedTools "Read,Edit" --max-turns 20 --output-format json
   ```
   Reserve the full `Read,Edit,Bash` allowlist for tasks that explicitly need to run commands (tests, builds):
   ```bash
   claude -p "..." --allowedTools "Read,Edit,Bash" --max-turns 20 --output-format json
   ```
   `/delegate_task` selects the ACP client per routing rules and streams progress back over a single WebSocket.

   These two examples use the **default `harness: bare`** — no change to today's behavior.

   Before switching to `harness: ccs`, note: (a) print mode (`-p`) is already non-interactive — no separate "auto"/unattended flag is needed on the inner call; (b) harness (whether `~/.claude/CLAUDE.md` + rules + skills catalog + hooks load) depends on `~/.claude/` existing on **the host**, not on choosing `ccs` over `bare` — both wrap the same `claude` binary and get identical harness on a given machine. Don't walk away assuming `harness: ccs` alone solves it; see Prerequisites. With that understood, the opt-in `harness: ccs` variant routes the same call through a scoped delegation identity/profile (separate API key, quota, and audit trail from a human's own CCS session), only after Phase 1's smoke-test gate has passed:
   ```bash
   ccs "<ccs_profile>" -p "..." --allowedTools "Read,Edit,Bash" --max-turns 20 --output-format json
   ```
   `<ccs_profile>` stands for whatever `delegation.ccs_profile` (`templates/config/production.yaml`) currently holds — this is illustrative, not literal executable syntax; the Hermes gateway substitutes the real value at dispatch time.

3. **Detect escalation signals** — long-running / needs human review / multi-handoff → tier 2; needs isolation / heavy compute / untrusted deps → tier 3.

4. **Tier 2 — Kanban lane** — create a durable card:
   ```text
   /kanban create "Fix flaky checkout tests and open a PR" \
     --assignee codex-worker \
     --workspace worktree
   ```
   Workers use `kanban_*` (`kanban_show`, `kanban_list`, `kanban_complete`, `kanban_block`, `kanban_heartbeat`, `kanban_comment`, `kanban_create`, `kanban_link`, `kanban_unblock`). Attach a `/goal` completion contract so the card only closes when conditions are demonstrated, not merely claimed.

5. **Tier 3 — remote sandbox**:
   ```
   /sandbox start dev-box
   /claude-code refactor src/auth/ to use JWT rotation
   /sandbox stop dev-box                # Syncs changes back, then stops
   ```

6. **Git hygiene** — isolate one branch/worktree per delegation (per part18's "Git Hygiene When Agents Share a Workspace" section) so parallel agents never clobber each other. When fanning out `parallel` subtasks against the **same repo with the same agent** (e.g. multiple `ccs <profile> -p` calls), branch naming alone is not enough — concurrent processes sharing one working tree race on file writes even if each targets a different branch in its commit message. Give each subtask its own `git worktree add ../subtask-N <branch-N>` checkout, and run the delegation inside that worktree's directory.

## Escalation tiers

| Signal | Tier | Mechanism |
|--------|------|-----------|
| Default; single-shot task with a clear routing match | 1 — print mode | `delegate_task` + `delegation.routing` cost table, print-mode CLI |
| Long-running / needs human review / multi-handoff | 2 — Kanban lane | `/kanban create` durable card + `kanban_*` toolset + `/goal` completion contract |
| Needs isolation / heavy compute / untrusted deps | 3 — remote sandbox | `/sandbox start` / `/sandbox stop` against a `sandboxes:` backend |

Tier 1 routing table:
```yaml
delegation:
  default: claude-code
  routing:
    - match: { type: refactor, files_changed_gte: 5 }
      agent: claude-code
    - match: { type: bugfix, single_file: true }
      agent: codex
    - match: { type: explore, repo_tokens_gte: 200000 }
      agent: gemini-cli
    - match: { type: dependency_audit }
      agent: gemini-cli
    - match: { budget: low }
      agent: opencode
      model: moonshot/kimi-k2.6
```

Tier 2 card creation:
```text
/kanban create "Fix flaky checkout tests and open a PR" \
  --assignee codex-worker \
  --workspace worktree
```

Tier 3 sandbox config:
```yaml
# ~/.hermes/config.yaml
sandboxes:
  dev-box:
    backend: ssh
    host: dev.local
    user: hermes
    identity_file: ~/.ssh/hermes_ed25519
    workdir: /home/hermes/sandboxes
    control_master: auto              # Reuses connection for bulk sync
    control_persist: 600
    sync:
      push: ~/.hermes                 # Uploaded at sandbox create
      pull_on_teardown: true
      pull_paths:
        - .hermes
        - projects                    # Grabs any code changes made in-sandbox
      ignore:
        - .git
        - node_modules
        - __pycache__
        - "*.log"
        - .env                      # Excludes ~/.hermes/.env — without this, `push: ~/.hermes`
                                     # above would sync live provider API keys to the remote
                                     # sandbox host. See templates/config/production.yaml and
                                     # part19-security-playbook.md ("keys stay on the host").
```

## Example invocation

```
/delegate_code "fix flaky checkout tests" repo=myorg/app
/delegate_code "refactor src/auth to JWT rotation" repo=myorg/app escalate=kanban
/delegate_code "run full e2e suite" repo=myorg/app escalate=sandbox
```

`parallel` example — fan out subtasks concurrently within one `delegate_code` call, opted into `harness: ccs`, one worktree per subtask:

```
/delegate_code "add tests for src/payments/, split into 3 subtasks" repo=myorg/app harness=ccs parallel=3
  → 3x, each in its own worktree (git worktree add ../subtask-N devin/claude-code-<ts>-subtask-N):
     ccs ccs-hermes -p "<subtask N>" --allowedTools "Read,Edit,Bash" --max-turns 20 --output-format json
```

One CCS profile can serve concurrent calls, but the actual throughput ceiling is unverified (`@kaitranntt/ccs`'s `proper-lockfile` dependency suggests possible serialization) — test on your deployment before assuming `N` is unbounded.

## See also

- [Part 18: Coding Agents](../../../part18-coding-agents.md)
- [Part 23: Tenacity Stack](../../../part23-tenacity-stack.md)
- [Part 21: Remote Sandboxes](../../../part21-remote-sandboxes.md)
