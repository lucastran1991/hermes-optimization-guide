# Red-Team Security Review: Hermes Coding-Agent Delegation Skill Plan

Reviewer role: Security Adversary + Fact Checker.
Scope: `plan.md`, `phase-01..04-*.md` in `plans/260703-0347-hermes-coding-agent-delegation-skill/`.

---

## Finding 1: `sandboxes` block pushes `~/.hermes` (incl. live secrets) to third-party remote infra, contradicting the guide's own stated invariant

- **Severity:** Critical
- **Location:** Phase 2, section "Implementation Steps" step 4 ("Add `sandboxes` block from `part21-remote-sandboxes.md:54-74`")
- **Flaw:** The verbatim block the plan tells the author to copy contains `sync: { push: ~/.hermes, pull_on_teardown: true, pull_paths: [.hermes, projects] }`. This uploads the entire `~/.hermes` directory to a remote sandbox backend (SSH/Modal/Daytona/Vercel/Fly/E2B — several of them third-party cloud vendors) on every sandbox start, and pulls files back on teardown by SHA-256 diff.
- **Failure scenario:** `~/.hermes/.env` (chmod 600, holds `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.) lives directly inside `~/.hermes`. The `ignore:` list in the same source block (`part21-remote-sandboxes.md:69-73`) only excludes `.git`, `node_modules`, `__pycache__`, `*.log` — **not `.env`**. Following the plan literally ships a production config template whose `sandboxes.dev-box.sync.push: ~/.hermes` uploads live provider API keys to a third-party cloud sandbox on every `/sandbox start`. This directly contradicts `part19-security-playbook.md:196` — *"The agent **cannot read `~/.hermes/.env`** (keys stay on the host)"* — one of the guide's own explicit security invariants. Worse, `pull_on_teardown: true` + `pull_paths: [.hermes, ...]` means a compromised or malicious sandbox backend can write back into local `~/.hermes` (including `.env`, `security.approval` config, MCP server definitions) on teardown — a config-poisoning / supply-chain path back into the trusted host.
- **Evidence:** `part21-remote-sandboxes.md:63-73` (sync block + ignore list, no `.env` exclusion); `part19-security-playbook.md:159,196` (`.env` chmod 600, "agent cannot read ~/.hermes/.env — keys stay on the host"); Phase 2 `phase-02-config-template-wiring.md:56` ("Add `sandboxes` block... Keep `${VAR}`/non-secret paths (`identity_file: ~/.ssh/...` is a path, not a secret)") — the plan reasons only about the SSH identity file, never about the `push: ~/.hermes` / `pull_paths: [.hermes]` lines in the same block.
- **Suggested fix:** Before committing the `sandboxes` block, add an explicit `ignore: [.env, .env.*, "*.pem", "*_ed25519"]` entry (or scope `sync.push` to a subdir that excludes secrets) and add a security-note line in both Phase 2 and the new skill file calling out that operators must exclude `.env`/key material from sync paths. Do not copy the block verbatim without this addition.

---

## Finding 2: New high-risk toolsets (`delegate_task`/`kanban`/`sandbox`) are never wired into the repo's existing approval-gate control

- **Severity:** High
- **Location:** Phase 2, "Related Code Files" (no `security.approval` edit); Phase 3, "Security Considerations"
- **Flaw:** `templates/config/production.yaml:170-188` already has a `security.approval.require_approval` list gating specific tool classes (`github`, `terminal`, `email`, `twilio`, `any_mcp`). The repo's own existing `skills/security/audit-approval-bypass/SKILL.md:34` rule states: *"Flag if `toolsets:` includes `terminal` or `bash` AND the skill accepts any user-supplied argument."* The new skill's `toolsets` include `delegate_task`, `kanban`, `sandbox` and it accepts user-supplied `task`/`repo` params (`phase-03-coding-agent-delegation-skill.md:58-66`), which is exactly the shape `audit-approval-bypass` is designed to flag — yet none of `delegate_task`/`kanban`/`sandbox` appear in `require_approval`.
- **Failure scenario:** The new skill ships with no `require_approval` entry, so any Telegram/Discord/Slack-triggered `/delegate_code` invocation (per the skill's own `when_to_use`) executes Bash-capable delegation without the approval gate the rest of the config uses for equivalent risk (`terminal: [exec]`). Running the repo's own `audit-approval-bypass` skill against this new skill immediately post-merge would flag it — the plan ships a known-flaggable config gap in the same PR that adds a security-conscious skill.
- **Evidence:** `templates/config/production.yaml:183-188` (require_approval list, no delegate_task/kanban/sandbox entries); `skills/security/audit-approval-bypass/SKILL.md:34` (the flagging rule); Phase 3 Security Considerations (`phase-03-coding-agent-delegation-skill.md:131-133`) never mentions `security.approval` at all.
- **Suggested fix:** Phase 2 should add `{ tool: delegate_task, actions: [exec] }` and `{ tool: sandbox, actions: [start, stop] }` (or equivalent) to `require_approval`, and Phase 3's security note should instruct operators to add the new skill's tools there.

---

## Finding 3: Tier-1 example command grants full Bash by default, contradicting the security note's own "least privilege" instruction

- **Severity:** High
- **Location:** Phase 3, "Implementation Steps" step 2 (Procedure item 2, "Tier 1 — print mode")
- **Flaw:** The plan instructs quoting `part18-coding-agents.md:72-77` verbatim as the tier-1 example: `claude -p "..." --allowedTools "Read,Edit,Bash" --max-turns 20 --output-format json`. This is presented as the **default** invocation for the lowest, most-automatic escalation tier. Meanwhile the plan's own security blockquote (step 2, same phase) says: *"scope the tool allowlist to the minimum per tier."*
- **Failure scenario:** A skill author or operator copies the tier-1 example verbatim (as instructed) and now the *default* delegation path for arbitrary user-supplied `task` text grants unrestricted `Bash` execution with no scoping guidance beyond a generic blockquote. Contrast with the sibling skill this plan is told to mirror, `skills/dev/pr-review/SKILL.md:49`, which explicitly disables write tools (`"--allowedTools", "Read", # No Edit, no Bash, no Write`) and uses a two-PAT read/write split (`skills/dev/pr-review/SKILL.md:72-78`). The new plan provides no equivalent concrete per-tier tool-scoping example — only a prose blockquote — so the one worked example in the file is the maximally-permissive one.
- **Evidence:** `part18-coding-agents.md:72-77`; `phase-03-coding-agent-delegation-skill.md:77` (security blockquote text) vs `:82` (verbatim Bash-enabled command); `skills/dev/pr-review/SKILL.md:43-52,72-78` (contrasting least-privilege pattern in the sibling skill this plan is told to structurally mirror).
- **Suggested fix:** Add a second, scoped-down example (e.g. `--allowedTools "Read,Edit"` for refactor/bugfix tasks, `Bash` only when the task classification requires running tests/builds) so the security note has a concrete enforcement mechanism, not just prose.

---

## Finding 4: `acp` block citation excludes the inbound-listener config — the only line in that section with a security comment

- **Severity:** Medium
- **Location:** Phase 2, "Implementation Steps" step 3 ("Add `acp` block from `part18-coding-agents.md:195-206`")
- **Flaw:** `part18-coding-agents.md:190-204` is one YAML block: `acp: { enabled: true, server: { listen: 127.0.0.1:41212  # Accept inbound ACP from editors }, clients: {claude-code, codex, gemini-cli} }`. The plan's citation range `195-206` starts at the `claude-code:` client entry (line 195) and **excludes lines 190-194** — the parent `acp:` key, `enabled: true`, and the `server: listen: 127.0.0.1:41212 # Accept inbound ACP from editors` lines. That excluded fragment is the only part of the whole block carrying an inline security-relevant comment, and the source doc mentions no authentication for that inbound listener anywhere.
- **Failure scenario:** Following the plan's line range literally does not even yield valid standalone YAML (client entries without their `acp:`/`clients:` parent keys). If the implementer reconstructs the parent keys from memory (as Phase 2's own architecture note implies: "acp → the client bindings tier 1 dispatches through"), they will most likely reconstruct only `clients:`, silently dropping `enabled`/`server.listen` — meaning the shipped template documents outbound-dispatch bindings but gives zero guidance on the unauthenticated localhost ACP server the same subsystem also exposes. Neither Phase 2 nor Phase 3 mentions the ACP inbound listener or its lack of auth anywhere.
- **Evidence:** `part18-coding-agents.md:190-204` (full block); `phase-02-config-template-wiring.md:55` (citation range `195-206`, description limited to "CLI client bindings").
- **Suggested fix:** Either cite the full `190-206` range and comment on the inbound listener/auth posture, or explicitly state in Phase 2 that the `server`/`enabled` sub-keys are intentionally omitted and why (e.g. "template ships dispatch-only; inbound ACP server left disabled by omission — do not add `enabled: true` without binding to loopback + a reverse-proxy auth layer").

---

## Finding 5: `kanban`/`sandbox` toolset names are new, undifferentiated capability labels invented for this plan with no other referent in the repo

- **Severity:** Medium
- **Location:** Phase 1, "Overview"; Phase 3, frontmatter (step 1)
- **Flaw:** `grep -rn "kanban\|sandbox" skills/` returns zero hits before this plan — no existing skill uses either as a toolset name. The guide only ever names granular tools (`kanban_show`, `kanban_create`, `kanban_complete`, ... — `part23-tenacity-stack.md:36`) or a slash command (`/sandbox start`/`/sandbox stop` — `part21-remote-sandboxes.md:79,81`), never a coarse `sandbox` toolset. The plan's own researcher report flagged this as an open question and the plan does not resolve it: *"`kanban`/`sandbox` toolsets aren't yet in `ALLOWED_TOOLSETS`... should the new skill's frontmatter include them anyway... or omit them from `toolsets:`"* (`research/researcher-skill-style-report.md:75`).
- **Failure scenario:** `toolsets:` is the field the repo's own trust-review tooling reads to assess a skill's blast radius (`skills/security/audit-approval-bypass/SKILL.md:27-34`, `skills/security/audit-mcp/SKILL.md`). Collapsing "can start/stop remote code-execution environments across SSH/Modal/Daytona/Vercel/Fly/E2B with bidirectional file sync" into the single opaque token `sandbox` (next to self-explanatory tokens like `github`, `email`) hides the actual capability from anyone doing a toolset-based trust review, unlike every other entry in `ALLOWED_TOOLSETS` which maps to one well-scoped external system.
- **Evidence:** `.github/scripts/validate_skills.py:16-29` (current `ALLOWED_TOOLSETS`, no kanban/sandbox); `research/researcher-skill-style-report.md:75` (open question, unresolved); `phase-03-coding-agent-delegation-skill.md:53-57` (frontmatter declares `kanban`, `sandbox` toolsets with no scoping).
- **Suggested fix:** Either split `sandbox` into narrower/labeled toolsets (or document per-backend scoping in the skill body under `## Escalation tiers`), or explicitly note in the skill's security blockquote that `sandbox` toolset = "can execute code on / sync files with any backend defined under `sandboxes:` in the operator's config."

---

## Finding 6: Phase 1's "no runtime surface" security claim overstates the assurance the CI validator actually provides

- **Severity:** Medium
- **Location:** Phase 1, "Security Considerations"
- **Flaw:** Phase 1 states: *"None — CI validation logic only; no secrets, no runtime surface. Widening `ALLOWED_TOOLSETS` is a whitelist expansion documented by the guide chapters (part21/part23)."* This frames the change as low-risk because it's "just CI," but doesn't note that `ALLOWED_TOOLSETS` is the *only* mechanism in this repo that gates what capability tokens a skill file may claim — there is no runtime enforcement here (no Hermes runtime in this repo) and, per Finding 2, no corresponding `require_approval` wiring either.
- **Failure scenario:** A future contributor reads "Security Considerations: None" on Phase 1 and treats the toolset-allowlist widening as risk-free precedent for adding further broad capability tokens (e.g. `exec`, `admin`) without matching approval-config updates, since the stated precedent explicitly says widening this list carries no security weight.
- **Evidence:** `phase-01-ci-toolset-validation.md:87-89`; contrast with the actual capability the new tokens unlock per Findings 1-3.
- **Suggested fix:** Rephrase to: "No change to CI logic's own security surface, but widening `ALLOWED_TOOLSETS` is a capability-allowlist decision — cross-check `security.approval.require_approval` (Phase 2) is updated in step."

---

## Finding 7: The repo's only existing automated guardrail (regex denylist) cannot see structured `kanban`/`sandbox`/`delegate_task` invocations

- **Severity:** Medium
- **Location:** Phase 2 & Phase 3 (no mention); underlying control at `templates/config/production.yaml:176-182`
- **Flaw:** `security.approval.denylist` is a list of regex patterns (`rm\s+-rf\s+/`, `curl\s+.+\|\s*(sh|bash)`, `169\.254\.169\.254`, `cat\s+~?/?\.?ssh/`, `aws\s+s3\s+sync...`, `ssh-keyscan`) matched against **terminal exec strings**. `/kanban create ...`, `/sandbox start <name>`, and `delegate_task(...)` are structured tool/slash-command invocations, not raw shell strings passed through `terminal`.
- **Failure scenario:** The denylist is the only automated backstop this config has against dangerous shell patterns (e.g. SSRF against the cloud metadata endpoint, curl-pipe-to-shell). None of it applies to the three new delegation surfaces this plan adds, so a malicious or malformed `task` string routed through tier 1/2/3 delegation bypasses the only pattern-based guardrail in the template — and neither Phase 2 nor Phase 3 proposes an equivalent check for the new surfaces.
- **Evidence:** `templates/config/production.yaml:176-182` (denylist, terminal-string-shaped patterns only); Phase 2/3 have no denylist-equivalent guidance for `delegate_task`/`kanban`/`sandbox`.
- **Suggested fix:** Note in the skill's security blockquote that denylist patterns don't cover delegated-agent-internal shell use, and that the *delegated* agent's own `--allowedTools`/approval posture is the only control — make that limitation explicit rather than implicit.

---

## Fact-Check Summary (sampled claims)

| Claim | Result |
|---|---|
| `ALLOWED_TOOLSETS` set at `.github/scripts/validate_skills.py:16-29`, missing kanban/sandbox | VERIFIED (`validate_skills.py:16-29`) |
| `validate()` rule logic at `:46-72` | VERIFIED (`validate_skills.py:46-72`) |
| CI `skill-frontmatter` job at `ci.yml:34-45` | VERIFIED (`.github/workflows/ci.yml:34-45`) |
| `yaml-lint` job runs `yamllint ... templates/ benchmarks/ skills/` | VERIFIED (`.github/workflows/ci.yml:24-32`) |
| `CONTRIBUTING.md:25` comment-every-field rule, `:27` no-secrets/`${VAR}` rule | VERIFIED (`CONTRIBUTING.md:25,27`) |
| `part18-coding-agents.md:108-123` delegation routing yaml | VERIFIED |
| `part18-coding-agents.md:195-206` acp clients | VERIFIED but citation range excludes `190-194` (see Finding 4) |
| `part18-coding-agents.md:130-133` `/kanban create` form | VERIFIED |
| `part23-tenacity-stack.md:36` kanban_* tool names | VERIFIED |
| `part23-tenacity-stack.md:87` completion-contract note | VERIFIED |
| `part21-remote-sandboxes.md:54-74` sandboxes SSH backend config | VERIFIED, but see Finding 1 for the security-relevant lines the plan doesn't reason about |
| `part21-remote-sandboxes.md:79,81` `/sandbox start`/`stop` | VERIFIED |
| `skills/dev/pr-review/SKILL.md` as structural sibling | VERIFIED, exists, and its least-privilege pattern contradicts Phase 3's tier-1 example (Finding 3) |
| `production.yaml:1-220` — no existing `delegation`/`acp`/`sandboxes` blocks | VERIFIED (file is 219 lines; no such top-level keys present) |
| `security.approval.require_approval` list exists and excludes new tools | VERIFIED, not cited anywhere in the plan (`production.yaml:183-188`) — **this is new evidence the plan missed, not just a stale note** |
| No existing skill uses `kanban`/`sandbox` toolset | VERIFIED via `grep -rn "kanban\|sandbox" skills/` (zero hits) |

## Unresolved Questions

- Should `sandboxes.sync.ignore` exclusions for secret files (`.env`, key material) be added to the guide chapter (`part21-remote-sandboxes.md`) itself, or only patched locally in the Phase 2 config template? The underlying gap exists in the guide source, not just this plan.
- Does the repo want a formal decision on whether `security.approval.require_approval` coverage is a hard CI-checkable requirement for any skill introducing new toolsets, or purely advisory? No such check exists today (`validate_skills.py` never reads `production.yaml`).
