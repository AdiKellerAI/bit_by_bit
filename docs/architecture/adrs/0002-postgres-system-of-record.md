# ADR-0002: PostgreSQL is the system of record; Redis is never authoritative

## Status
Accepted

## Context
The architecture needs both a durable store (users, knowledge base, interaction logs, prompt
versions, budget policy, evaluation cases) and a fast ephemeral store (idempotency keys, rate
limit counters, semantic cache lookups, session state). PREPARATION-CHECKLIST.md Phase 6
states this explicitly as an "important principle," and PROJECT-SPEC.md §22 (Backup &
Recovery) draws the same line: PostgreSQL gets daily backups and tested restores; Redis is
treated as disposable.

## Decision
PostgreSQL (+ pgvector for embeddings) is the sole system of record. Redis is used only for:
- idempotency (webhook dedup, ARCHITECTURE-FLOWS.md §1 `IDEM <--> REDIS`)
- rate limiting (`RATE <--> REDIS`)
- semantic cache lookups, backed by a PostgreSQL-stored source of truth (`CACHE <--> REDIS`
  and `CACHE <--> PG` both appear in the same diagram — Redis fronts, Postgres backs)
- temporary/session state

No table or value that must survive a Redis flush, restart, or eviction may live in Redis
only. If a piece of state matters after Redis is gone, it is written to PostgreSQL first or
alongside.

## Consequences
- Redis can be wiped, resized, or restarted at any time in local dev without data loss beyond
  cache warmth and rate-limit windows resetting.
- Every Redis-backed feature (idempotency, rate limit, semantic cache) needs a
  PostgreSQL-durable fallback path or an acceptable "fail open/closed" behavior if Redis is
  briefly unavailable (see docs/architecture/threat-model.md, dependency failure section).
- This is why Phase 1 infrastructure includes PostgreSQL+pgvector and Redis as two clearly
  distinct services with different volume/backup treatment, rather than one shared datastore.
