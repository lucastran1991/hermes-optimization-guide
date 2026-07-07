# Audit Evidence Engine

Rule for any agent producing an audit: distinguish `verified`, `inferred`, and `unknown`. Never present unavailable evidence as a verified fact.

```
Evidence -> Confidence -> Conclusion
```

## Structure

- `evidence/` — raw command output, logs, screenshots. One file per check, named `{capability}-{date}.txt` (or `.png`).
- `findings/` — one finding per file, using `findings/TEMPLATE.md`. Each finding cites the evidence file(s) it's based on.
- `limitations.md` — capabilities that could not be checked this run, and why. Use `findings/TEMPLATE.md`'s confidence scale.

## Confidence scale

| Confidence | Meaning |
|---|---|
| High | Direct command output / log inspected |
| Medium | Inferred from adjacent evidence (e.g. process list implies a lock isn't held, but lock table itself wasn't read) |
| Low | Assumption only, no evidence gathered |
| Unknown | Capability unavailable — see `limitations.md`, do not assign a confidence to the underlying claim |

## Coverage report

Every audit run ends with a coverage block, one line per subsystem checked:

```yaml
coverage:
  system: verified
  network: verified
  postgres: partial
  docker: unavailable
  reason: no_new_privs
```

`partial` means some checks in that subsystem succeeded and others didn't — cross-reference `limitations.md` for which ones.

## Anti-pattern

Bad: "No locks found." (implies a check ran and returned empty)
Good: "Lock table unreadable (`pg_locks` blocked by `no_new_privs`) — cannot confirm absence of contention." (confidence: unknown)
