# Hermes Agent Knowledge Verification — nfi / kitchen / blueprint

Audit scope: `.hermes.md` (Hermes Agent's persistent project-knowledge file, analogous to CLAUDE.md) in each of the 3 projects, checked against actual codebase state. 3 parallel read-only agents, one per project.

## kitchen — CLEAN (8/8 match)

No drift. Go 1.26.4 (go.mod:3), SQLite via modernc.org/sqlite v1.36.1 (pure-Go, confirmed), React 19.1.0, TS 5.7 + Vite 6, kitchen-ask-mcp stdio server confirmed at `backend/cmd/kitchen-ask-mcp/main.go`, Vietnamese-chat/English-code convention confirmed in CLAUDE.md:2,5. Minor note: WS lib is `github.com/coder/websocket`, not gorilla — `.hermes.md` doesn't name a lib so not drift, just fyi.

## nfi — 2 drift items found

1. **PM2 claim stale at runtime.** `.hermes.md` says "managed by PM2" — config (`ecosystem.config.cjs`) is valid and defines `nfi-backend`/`nfi-frontend`, but live `pm2 list` (verified independently) shows neither process running; only `nfi-tunnel`, `cloudcli`, `kitchen-backend` are online. Config-correct, runtime-false.
2. **"Full build/run/convention details live in AGENTS.md" is wrong.** AGENTS.md (3325 bytes) is actually Codex doc-authoring meta-rules + Vietnamese-reply instruction — no build/run/convention content. That content is actually in README.md.

Everything else matched: Go 1.26.4, port 8282 (nfi.local.yaml:2 + config parity test), pgx/v5 Postgres, Groq chat client (`backend/internal/chat/groq_client.go`), React 18.3.1.

## blueprint — 3 items needing softer phrasing (no hard drift)

1. **Python 3.11 pin unverified** — no `.python-version`/`requires-python` anywhere; `backend/README.md:42` even says "Python 3.10+". FastAPI 0.115.5, SQLAlchemy 2.0.36, Alembic 1.14.0, fastapi-users 14.0.0 all confirmed in requirements.txt.
2. **"Migrated from TQL/Java" reads fully past-tense — only half true.** Migration plan (`plans/260630-1529-fastapi-backend-migration/plan.md`) is status=completed/100%, and backend is pure Python now. But frontend data-fetching layer is still mid-migration per `plans/260701-0306-frontend-http-infra/plan.md:20` (legacy screens still on WS/YAML/TQL). Separately: `backend/README.md` itself is stale — still fully describes the old Java engine as current; worth a docs-sync pass independent of `.hermes.md`.
3. **"13 node types"** — docs-consistent (PDR, README, docs/README all say 13) but `codebase-summary.md:5` hedges "11–13", and no single enum in code has exactly 13 (closest, `DMI_NODE_TYPES`, has 4 — different concept). Likely fine as a rounded doc figure, not a hard drift.

Confirmed matches: PostgreSQL dbu/dba split via asyncpg (`app/core/config.py:14-16`), React 18.3.1 + TS strict (`frontend/bp/tsconfig.app.json:29` — note actual app path is `frontend/bp/`, not `frontend/` root), Tailwind v4.1.14, Ant Design v6.3.7, react-three-fiber v8.18, Zustand v5.

## Recommended fixes to `.hermes.md`

- **nfi**: change "managed by PM2" → "managed by PM2 (see ecosystem.config.cjs; check `pm2 list` for current status)"; change AGENTS.md pointer to README.md for build/run details.
- **blueprint**: soften "migrated from TQL/Java engine" to note backend migration is done, frontend HTTP-client migration still in progress; drop or hedge the specific "Python 3.11" version since it's unpinned.
- **kitchen**: no changes needed.

## Unresolved questions

- nfi: is `nfi-backend`/`nfi-frontend` being down under PM2 an expected paused state or an actual outage worth flagging separately?
- blueprint: should `backend/README.md`'s stale TQL/Java description get its own docs-sync task (out of scope here)?
- blueprint: is "13 node types" meant as an exact count or a rounded figure — docs themselves disagree (11–13 vs 13)?
- Want me to apply the recommended `.hermes.md` edits above, or just leave this as a findings report?
