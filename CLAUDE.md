# CLAUDE.md

Project-level context, auto-loaded every session. Keep this short — it's for facts that
matter on nearly every task, not a copy of the full docs. Full spec:
[`docs/project_setup/PROJECT-SPEC.md`](docs/project_setup/PROJECT-SPEC.md) is the source of
truth; this file is a summary/pointer, not a replacement.

## What this is

A self-improving 1:1 AI assistant (Telegram for the MVP) for an internal AI/dev community,
plus a separate human-run WhatsApp Community (unrelated infra, not built here). Defense-sector
context — see PROJECT-SPEC.md §4 for the full security model.

## Status

Phase 0-5 done and committed to `main`: architecture docs, local infra, database schema
(Phase 0-2); a live Telegram echo bot with idempotency (Phase 3 —
`n8n/workflows/telegram-echo-bot.json`, `services/messaging-adapters/telegram/`); a security
gate — sensitive-data detection (real), classification (PUBLIC-only stub), language detection
— running before any echo/generation (Phase 4 — `security/`, `shared/`); a real knowledge
base + RAG retrieval, template-only responses, no generation yet (Phase 5 — `knowledge/`, 10
real seeded sources). `interaction_logs` writes begin at Phase 4; `retrieved_kb_ids`/`intent`
at Phase 5. Next: Generation (see "Generation phase requirements" below) — budget guard,
model registry, first real LLM calls. Staying local (no hosting migration) until after this.
**Update this line whenever a phase completes** — don't let it go stale.

### Generation phase requirements (given 2026-08-14, before that phase starts)

- **Three model tiers, not one model for everything.** Route by query complexity — simple
  questions get a cheap/fast model, harder ones escalate. Matches PROJECT-SPEC.md §5's
  Tier 0/1/2 design; the user explicitly reinforced this mid-Phase-5, so treat it as a hard
  requirement for the Model Selection/Intent Router design, not optional.
- **Token-frugal by design and a good user experience are both explicit goals** — not in
  tension by default, but if a cost-saving choice would visibly degrade response quality,
  surface that trade-off rather than silently picking cheap.
- **Query understanding must tolerate typos/unusual characters and use conversational
  context**, not just literal/vector matching (added 2026-08-14). This is fundamentally an
  LLM-level capability — Phase 5's pure embedding search is only mildly typo-tolerant and has
  zero multi-turn memory. Both requirements land in Generation, not as separate bolt-ons:
  routing the raw query through an LLM (even Tier 1) naturally absorbs typos/odd characters;
  conversational context needs an explicit design decision on how much history to carry and
  where it lives (Redis short-term per ADR-0002, backed by `interaction_logs`/`session_id`
  for anything durable).

## How we work (established this session — follow it, don't re-derive it)

- **Small approved phases only.** Plan → implement → verify → approve → continue. Never turn
  an architecture doc into a large codebase in one step (PREPARATION-CHECKLIST.md's Final
  Rule). Use plan mode for anything beyond a trivial fix.
- **Git: one branch per phase or bugfix.** Commit completed, approved work to `main`, then
  branch for the next unit of work. Merge back to `main` only after the user approves.
- **Run `./scripts/verify-all.sh` before every merge to `main`.** It must pass. It
  auto-discovers every `<component>/tests/run.sh` — new phases add a `tests/run.sh` for
  whatever they build, not leave verification as a one-off manual step (see
  `.claude/skills/phase-workflow/SKILL.md`).
- **Don't invent open decisions.** Budget numbers, golden eval set contents, sensitive-data
  detection patterns, model pricing — these are the user's job to bring, not something to
  guess. Flag them as open instead.
- **Never read `.env` or `docs/links_and_details.md`** (real secrets/credentials, both
  gitignored — keep them that way). If new env vars are needed, append blindly via shell
  redirection without reading existing content, or ask the user to fill them in.

## Load-bearing architecture decisions (don't propose around these without saying why)

- Messaging is behind an adapter interface; Telegram is the only active adapter; WhatsApp
  Cloud API is scaffolded-but-inactive (ADR-0001).
- PostgreSQL is the system of record; Redis is cache/session/rate-limit/idempotency only,
  never authoritative (ADR-0002).
- Sensitive-data detection is a distinct, always-on pre-LLM control, separate from data
  classification, excluded from LDD (ADR-0003).
- LDD changes always require human approval before activation (ADR-0004).
- Community is Hebrew-primary; the Agent mirrors the user's language and keeps the listed
  technical terms in English (PROJECT-SPEC.md §14). Any copy/prompts/errors drafted here
  should default to Hebrew.
- Local Docker runtime is Colima, not Docker Desktop (ADR-0005).

Full rationale for each: `docs/architecture/adrs/`.

## Local dev quickstart

```sh
colima start   # if not already running
cp .env.example .env   # first time only, then fill in real values
./scripts/dev-up.sh    # starts Postgres+pgvector, Redis, n8n, Caddy
./scripts/dev-status.sh
dbmate status           # migration state
```
