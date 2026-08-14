---
name: db-migration
description: Use when adding, modifying, or reviewing a database migration in this repo - new tables, columns, indexes, or constraints under database/migrations/. Covers dbmate conventions and the verification steps established in Phase 2.
---

# Database migrations (dbmate)

Source of truth for what fields belong on which table: PROJECT-SPEC.md §7 and
ARCHITECTURE-FLOWS.md §3 (ERD) - always check there before adding/changing a column, don't
invent fields. `docs/architecture/threat-model.md` §5 resolves the one known field-list
mismatch (data-classification categories) in favor of PROJECT-SPEC.md.

## Tooling

- Migration tool is **dbmate** (`brew install dbmate` if missing), not node-pg-migrate or raw
  scripts - see `docs/architecture/adrs/0005-local-docker-runtime.md`'s sibling reasoning
  (Phase 2 plan) for why.
- Config lives in `.env` (`DBMATE_MIGRATIONS_DIR=database/migrations`,
  `DBMATE_SCHEMA_FILE=database/schema.sql`) and mirrored in `.env.example`.
- `dbmate` reads `DATABASE_URL` from `.env` automatically; the local Postgres container
  publishes port 5432 to the host so no compose changes are needed to run it.
- `pg_dump` must be on `PATH` for `dbmate dump` to regenerate `database/schema.sql` - it's
  installed keg-only via `brew install libpq`; export
  `PATH="/opt/homebrew/opt/libpq/bin:$PATH"` if `dbmate dump` silently does nothing.

## Conventions

- One focused migration per table/change: `database/migrations/<timestamp>_<verb>_<name>.sql`.
- Every migration has both `-- migrate:up` and `-- migrate:down` - no forward-only migrations.
- UUID primary keys use `DEFAULT gen_random_uuid()` (built into Postgres 16, no pgcrypto
  extension needed).
- `platform` columns are `TEXT CHECK (platform IN ('telegram', 'whatsapp'))`, not an ENUM type
  - cheaper to extend later.
- Status/lifecycle columns without a spec-defined vocabulary stay plain `TEXT` (no CHECK) until
  the vocabulary is actually pinned down elsewhere - don't guess allowed values.
- Config/reference tables (`model_registry`, `budget_policy`, `evaluation_cases`) get schema
  only, never seed rows with invented numbers - pricing, budgets, and golden-eval content are
  the user's decisions.
- `sensitive_data_events` must never gain a foreign key or join path into `interaction_logs`
  or any LDD/Loop 3 table - that's a hard architectural boundary (ADR-0003), not an oversight.

## Verification (do all of these before considering a migration done)

1. `dbmate up` applies clean.
2. `docker compose exec postgres psql -U agent -d agent -c '\dt'` shows the new table.
3. Spot-check any new constraint actually rejects bad data (insert a violating row, confirm it
   errors, then clean it up).
4. `dbmate down` then `dbmate up` round-trips without error (down migrations are real, not
   stubs).
5. `dbmate dump` to refresh `database/schema.sql` if `pg_dump` is available.
