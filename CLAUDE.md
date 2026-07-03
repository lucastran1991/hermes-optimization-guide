# Language Rules
- Assistant must always reply in Vietnamese
- Tone: friendly, concise, clear
- Keep responses as short as possible to save tokens — be direct, skip filler
- Artifacts (code, comments, docs, reports, commit messages) are English; only the chat reply is Vietnamese

# Execution Mode (authoritative)

This file is the authoritative guide for this repo; where global rules conflict, this file wins.

- Default to **lean-direct execution**: make the smallest correct change yourself, scoped to the request.
- Heavy ck-orchestration (planner → cook → test → code-reviewer → ship chain, multi-agent fan-out, mandatory docs sweeps) is **opt-in**, not the default. Engage it only when:
  - the user explicitly invokes a `/ck:` skill, OR
  - the task spans multiple subsystems or is large (>~1 day), OR
  - the user asks for parallel/subagent work.
- For bug fixes, small features, edits, and questions: skip the chain — implement, verify, done.
- Finalize once: in a cook→ship (or fix→ship) chain, don't write journal/docs in the implement step and again in ship — the final ship step writes journal + docs a single time.