---
phase: 3
title: "Claude Auth For Hermes"
status: pending
effort: "20m"
---

# Phase 3: Claude Auth For Hermes

**Priority:** P1 · **Status:** pending · **Effort:** ~20m · **Blocked by:** none (parallel group A) · **Ownership:** host-only, no repo writes

## Context Links

- Root-cause report: `plans/reports/ck-debug-260703-1725-hermes-seccomp-claude-sigsys-stale-unit-report.md` ("Next failure layers → Auth (layer 2, still broken)").
- Host verification: `research/live-host-verification-findings.md` §3 (the two auth mechanisms; no sandbox). Note §3's "device-code / no browser" characterization is **softened** here — the mechanism is unconfirmed for `2.1.199` (see Key Insights / Finding 10).

## Overview

Even after Phase 2 stops the crash, `claude` for the hermes user is "Not logged in" (debug report, auth layer). The user chose **interactive OAuth login** over API-key auth — this ties bot delegation to a real Claude subscription seat. Login does not run inside the systemd sandbox (only `hermes gateway run` is sandboxed), so there is **no ordering dependency on Phase 2**. **The exact login UX is unconfirmed for this CLI version** (see Key Insights) — attempt OAuth first per the user's choice, and be ready with the documented fallbacks if it stalls over this SSH-only host.

## Key Insights

- Two orthogonal mechanisms (findings §3): `ANTHROPIC_API_KEY` env (headless, direct billing) vs `claude auth login` (OAuth seat). `claude auth status` reports only the OAuth one — a "Not logged in" status does not by itself mean API-key calls would fail. User picked OAuth.
- **Do NOT assert the login mechanism confidently.** `claude auth login --help` on this host (`2.1.199`) shows only `--claudeai/--console/--email/--sso` — no device-code language. Claude Code's documented OAuth flow is a local-loopback HTTP-callback (opens a browser to a random local port), which upstream issues report breaking over pure SSH without port-forwarding. Some versions offer a manual "copy URL / paste code" fallback, but it is not guaranteed present/working in `2.1.199` (untested). **Fallbacks if `claude auth login` stalls over this SSH-only host:** `claude setup-token` (a headless long-lived-token subcommand visible in `claude --help`, never assumed elsewhere in this plan) or `ANTHROPIC_API_KEY` (the orthogonal mechanism above). Keep OAuth as the primary attempt per the user's choice.
- Only `hermes gateway run` (the service) is sandboxed; a plain `sudo -u hermes` shell is not — so `ProtectHome=read-only` does not apply during login and the token persists normally (findings §3).

## Requirements

`sudo -u hermes bash -c 'export PATH="$HOME/.local/bin:$PATH"; claude auth status --text'` reports logged in. The seat's owning account is known and appropriate.

## Architecture

`[HUMAN]` `sudo -u hermes -i` → `claude auth login` (fall back to `claude setup-token` or `ANTHROPIC_API_KEY` if it stalls over SSH) → follow the flow's prompt (browser/loopback, or the copy-URL fallback if the version offers it) → OAuth token persisted under the hermes home → `[AGENT]` verify.

## Related Code Files

None. Host-only.

## Implementation Steps

1. `[HUMAN]` `sudo -u hermes -i` (or `sudo -u hermes bash -l`), then `claude auth login`; complete the flow. **Interactive — NOT agent-executable**: it authorizes a real subscription seat and requires a human to choose/confirm the account. **If it stalls** (headless/SSH-only host — no browser, loopback callback may be unreachable): fall back to `claude setup-token` (headless long-lived token) or set `ANTHROPIC_API_KEY` for the hermes user, per Anthropic's headless guidance. Note the fallback chosen, so Security Considerations reflects the actual credential type in play.
2. `[AGENT]` Verify: `sudo -u hermes bash -c 'export PATH="$HOME/.local/bin:$PATH"; claude auth status --text'` reports logged in (not "Not logged in"). The **PATH-wrapped** form is required — a bare `sudo -u hermes claude auth status` fails with `command not found` (sudo `secure_path` excludes `~/.local/bin`), which is indistinguishable from "not logged in".

## Todo List

<!-- Updated: Validation Session 1 - seat ownership confirmed, no longer an open question -->
- [ ] Dedicated bot-specific Claude account ready (NOT the operator's personal account — confirmed via validation interview) before login.
- [ ] `claude auth login` completed as hermes (or fallback `setup-token`/`ANTHROPIC_API_KEY` chosen + noted).
- [ ] `claude auth status --text` (PATH-wrapped) reports logged in.

## Success Criteria

`sudo -u hermes bash -c 'export PATH="$HOME/.local/bin:$PATH"; claude auth status --text'` = logged in (or, if a fallback was used, the delegated `claude -p` path authenticates successfully in Phase 6).

## Risk Assessment

| Risk | L×I | Mitigation |
|------|-----|------------|
| Login authorizes the WRONG account | M×H | Whoever runs step 1 authorizes *their* seat — the bot then consumes that account's usage/quota. **Confirmed (Validation Session 1): use a dedicated bot-specific account, not personal** — have it ready before running step 1; if the wrong account gets authorized, `claude auth logout` (or delete the credential) and re-login the correct seat. |
| **OAuth token readable + exfiltratable by any same-UID delegated sub-session (ACCEPTED risk)** | M×H | A delegated `claude -p` runs as the **same `hermes` UID** as the token owner; `ProtectHome=read-only` makes `~/.claude*` readable (not hidden), and it is never in `ReadWritePaths` (irrelevant to *reads*). A delegated task with `Bash` (per `SKILL.md:77`'s own `Read,Edit,Bash` example) could read + exfiltrate the token → account-level impersonation of whoever logged in, until manually revoked. **Accepted per user default (not redesigned this pass).** `CLAUDE_CONFIG_DIR`-based isolation (scope the credential dir away from sub-sessions) was considered and explicitly deferred as a follow-up option — see Security Considerations. |
| `claude auth login` stalls over SSH-only host | M×M | Mechanism unconfirmed for `2.1.199`; fall back to `claude setup-token` or `ANTHROPIC_API_KEY` (Key Insights). |
| Sandboxed delegation later can't read/refresh the token | L×M | Login runs from a plain shell so it persists fine now; if a *sandboxed* `claude -p` later fails on token *write/refresh* I/O (debug report layer 4b, untested), redirect config via `CLAUDE_CONFIG_DIR` under `.hermes/` rather than widening `ReadWritePaths` (debug report recommendation) — flagged for Phase 6. |
| OAuth session expiry over time | M×M | Tokens may need periodic re-login; note as an operational follow-up (no automated refresh in scope). |

## Security Considerations

<!-- Updated: Validation Session 1 - seat ownership confirmed -->
**Seat ownership (CONFIRMED via validation interview): use a dedicated, bot-specific Claude account — NOT the operator's personal account.** Bot delegation usage bills/attributes to whichever account logs in, and a dedicated seat bounds Finding 6's OAuth-exfil blast radius (less at stake than a personal account if the risk is ever exercised). OAuth is used deliberately instead of `--api-key`, so no key lands in shell history or `ps`.

**The stored token is NOT protected against the threat that matters here.** Prior wording ("stored under the hermes home, owner-only") addressed only a *different-user* threat model. The real exposure: a delegated coding sub-session runs as the **same `hermes` UID** as the token owner (it is forked from the same service account), so DAC "owner-only" bits give it zero protection — it can *read* whatever `claude auth login` persists under `/home/hermes/.claude*`. `ProtectHome=read-only` means readable, not hidden; adding/omitting `~/.claude` from `ReadWritePaths` governs *writes* only and is irrelevant to reads. Concretely, a rogue/compromised delegated task (prompt injection via Telegram, a poisoned target-repo dependency, a malicious task description) running with the `Read,Edit,Bash` allowlist that `SKILL.md:77` itself documents can `cat` the OAuth credential and exfiltrate it (nothing in the sandbox blocks outbound network for an independent `claude -p` subprocess) — yielding **account-level impersonation** of the human whose seat was authorized, until they notice and revoke. Choosing OAuth (a full account seat) over a scoped, independently-revocable API key amplifies this blast radius.

**This is a REAL, ACCEPTED risk — documented, not mitigated, per the user's default resolution (unconfirmed — see plan.md Overview / Red Team Review; flag for override before `/ck:cook`).** A mitigation was considered and explicitly deferred: redirect `claude`'s credential dir via `CLAUDE_CONFIG_DIR` to a path only the top-level orchestrator reads (sub-sessions never inherit it), or use a scoped API key instead of an account seat. Not designed or built now — recorded as a follow-up option, not a requirement.

**Open questions (1 resolved, 1 remains):** ~~whose subscription seat should own this login?~~ **RESOLVED (Validation Session 1): a dedicated bot-specific account, not the operator's personal one.** Still open: should `CLAUDE_CONFIG_DIR` isolation be built before enabling this in production (currently accepted-as-is per Validation Session 1 Q1)?

## Rollback

`claude auth logout` (or remove the credential file under the hermes home) reverts to unauthenticated. No other state touched.

## Next Steps

Required before Phase 6's end-to-end delegation test can succeed. Independent of Phases 1, 2, 4.
