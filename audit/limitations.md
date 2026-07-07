# Audit Limitations

Capabilities that couldn't be verified in an audit run, and why. Append one row per run; don't delete old rows unless the underlying blocker is fixed.

| Date | Capability | Status | Reason | Impact | Confidence |
|---|---|---|---|---|---|
| 2026-07-07 | postgres.inspect | Unavailable | Runtime enforces `no_new_privs`, sudo blocked by kernel regardless of sudoers | Cannot verify `pg_stat_activity`, `pg_locks`, `pg_database_size` | Unknown |
