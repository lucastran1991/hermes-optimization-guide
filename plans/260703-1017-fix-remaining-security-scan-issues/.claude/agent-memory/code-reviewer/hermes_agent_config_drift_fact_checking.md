---
name: hermes-agent-config-drift-fact-checking
description: Techniques for fact-checking claims that a hermes-optimization-guide template config key is "real" vs "fictional" against the hermes-agent source repo
metadata:
  type: project
---

Working on `hermes-optimization-guide` (docs/config-template repo for `hermes-agent`). Plans in this repo frequently claim a YAML config key is "verified real" or "confirmed fictional" against `/home/ubuntu/workspace/hermes-agent` source. These claims are worth independently re-checking rather than trusting citations, because:

1. **Citations drift.** A cited line range (e.g. `config.py:2408-2434`) can be stale or not actually cover the keys attributed to it — always re-`grep -n` the exact key name rather than trusting a line range.
2. **"Not flagged by research → out of scope" is not the same as "confirmed real."** Adjacent keys in the same block that the original scan didn't happen to name can be just as fictional. Always grep the adjacent keys too, not just the ones named in the finding.
3. **Annotated git tags need the `^{}` line.** `git ls-remote <repo> 'refs/tags/vX*'` on an annotated tag returns TWO lines: the tag object's own SHA, and (marked `^{}`) the commit it points to. For GitHub Actions SHA-pinning, you need the `^{}` (peeled) commit SHA — the plain tag-ref line is a tag *object* SHA, not a commit. Verify via `GET /repos/{owner}/{repo}/git/commits/{sha}` (200 = commit, 404 = not a commit, e.g. a tag object).
4. **Templates get rewritten out from under scan reports.** A security scan and a plan/research report can be written hours apart; a template file touched same-day (check `git log --oneline -- <file>`) may no longer match what the scan/research describes. Always re-read the actual current file content before trusting a plan's "Related Code Files" line citations — don't assume the file still has the block the plan says to edit.
5. **hermes-agent's real webhook adapter (`gateway/platforms/webhook.py`) already implements `rate_limit` (default 30/min) and `max_body_bytes` (default 1MB) under `platforms.webhook.extra.*`.** Guide-repo claims that "no rate limit/body cap exists" or that "Caddy is the only enforcement layer" for the webhook vhost are commonly wrong — check this file before accepting such claims.
6. **MCP per-server "sampling" config is a nested dict** (`sampling: {enabled, model, max_tokens_cap, timeout, max_rpm, allowed_models, max_tool_rounds, log_level}` per `tools/mcp_tool.py` docstring), not a flat `allow_sampling: true/false`. There is no real per-server tool-restriction/allowlist key (`tools_allowlist` is fictional) and no real `trust_label` under `platforms.*` (that string is only used, unrelated, in `hermes_cli/skills_hub.py`'s skill-marketplace display).
7. **`profiles: {name: {...}}` / `profile: <name>` as a top-level config.yaml key is entirely fictional** — hermes-agent's DEFAULT_CONFIG has no `"profiles"`/`"profile"` key. The only real "profile" concept is the unrelated directory-based multi-instance CLI feature (`hermes_cli/profiles.py`, `hermes -p <name>`, separate `~/.hermes/profiles/<name>/` home dirs) — do not conflate the two when a template claims a `profile: quarantine` selector switches in-conversation trust tiers.

See [[team-coordination-rules]] pattern: when a peer red-team report already exists in the reports dir before you write yours, read it first — cross-verifying its claims independently (fresh grep/curl, not copy-paste) is valuable convergent evidence, and gives you a citation trail if the planner asks which agent found what.
