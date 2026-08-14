---
name: local-dev-stack
description: Use when starting, debugging, or modifying the local Docker environment for this repo (Postgres, Redis, n8n, Caddy) — docker-compose.yml, scripts/dev-up.sh, scripts/dev-status.sh, or anything Colima-related.
---

# Local dev stack

Full rationale: `docs/architecture/adrs/0005-local-docker-runtime.md`.

## Runtime

- **Colima, not Docker Desktop.** `colima start` (not `open -a Docker`). If `docker` commands
  fail with a connection error, check `colima status` first.
- Docker Compose plugin is wired via `~/.docker/config.json`'s `cliPluginsExtraDirs`, not the
  Docker Desktop plugin path — `docker compose` (space, not hyphen) is the v2 plugin.

## Topology (`docker-compose.yml`)

| Service | Published to host | Notes |
|---|---|---|
| postgres | `POSTGRES_PORT` (default 5432) | pgvector prebuilt image, healthcheck `pg_isready` |
| redis | 6379 | healthcheck `redis-cli ping` |
| n8n | **not published** | only reachable via reverse-proxy, by design (see ARCHITECTURE-FLOWS.md §11) |
| reverse-proxy (Caddy) | 5678 | proxies to `n8n:5678` on the internal compose network |

n8n's own workflow/credential metadata uses its embedded SQLite — a separate concern from the
`postgres` service, which is the *application's* system of record (ADR-0002). Don't conflate
the two when debugging.

## Scripts

- `./scripts/dev-up.sh` — starts Colima if needed, `docker compose up -d`, polls for health.
- `./scripts/dev-status.sh` — point-in-time check matching PREPARATION-CHECKLIST.md §5.3
  (Docker/Postgres/Redis/n8n/Git). Deliberately excludes "LLM API works" and "Telegram bot
  responds" — those belong to later phases, not infra.

## Common issues

- `docker compose exec postgres psql ...` needs `-U $POSTGRES_USER -d $POSTGRES_DB` (or the
  literal values from `.env`, e.g. `agent`/`agent` in this environment) — don't guess a
  default username.
- If Postgres SSL errors appear from an external client/tool (e.g. dbmate), the local
  `DATABASE_URL` needs `?sslmode=disable` appended — the container doesn't have SSL enabled
  for local dev.
- Changing `docker/postgres/init/*.sql` has **no effect** on an existing volume — that
  directory only runs on first container creation against an empty volume. Schema changes
  after that go through migrations (see the `db-migration` skill), not the init script.
- Building or debugging an actual n8n workflow (webhook URLs, node JSON, credentials,
  activation)? See the `n8n-workflow-authoring` skill instead — this skill is docker/compose
  topology only.
