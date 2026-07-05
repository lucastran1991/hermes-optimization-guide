---
name: hermes-host-sudo-secure-path-strips-local-bin
description: On lucas-oracle-instance, bare `sudo -u hermes <cli>` fails for every coding-agent CLI because sudo's secure_path overrides PATH and excludes ~/.local/bin.
metadata:
  type: project
---

On `lucas-oracle-instance`, `sudo -n -l` shows a `secure_path` Default (`/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin`) that applies to every `sudo` invocation, including `sudo -u hermes ...`. All coding-agent CLIs (`claude`, `opencode`, `codex`, `gemini`, `ccs`) install into `/home/hermes/.local/bin`, which is NOT in `secure_path`. A bare `sudo -u hermes claude --version` (no shell, no PATH export) always fails with `sudo: claude: command not found` — it looks like the binary is missing even when it's correctly installed. Verified 2026-07-03 by direct reproduction for `claude`, `opencode`, and `command -v ccs` (the last one fails doubly: `command` is a bash builtin, not an executable, so `sudo -u hermes command -v ccs` can never work regardless of PATH).

**Why:** sudo's `secure_path` is a security control (prevents PATH-hijacking of privileged commands) that has the side effect of breaking any plan/script that assumes `sudo -u <user> <cli>` inherits that user's normal login PATH. This bit the `260703-1738-fix-urgent-hermes-delegation-issues` plan across three phases (2, 3, 4) — every literal bare-form verification command in that plan was non-functional as written; see `plans/260703-1738-fix-urgent-hermes-delegation-issues/reports/from-code-reviewer-to-planner-red-team-security-adversary-plan-review-report.md` Finding 1.

**How to apply:** When reviewing (or writing) any plan/script that runs coding-agent CLIs as hermes via `sudo`, the ONLY working form is `sudo -u hermes bash -c 'export PATH="$HOME/.local/bin:$PATH"; <cmd>'`. Flag any bare `sudo -u hermes <cli-binary>` (without the `bash -c` + explicit PATH export wrapper) as broken-as-written, not just a style nit — verify by reproducing, don't assume.
