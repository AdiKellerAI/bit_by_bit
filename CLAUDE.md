# CLAUDE.md

Project-level context, auto-loaded every session. Keep this short - it's for facts that
matter on nearly every task, not a copy of the full docs. Full spec:
[`docs/project_setup/PROJECT-SPEC.md`](docs/project_setup/PROJECT-SPEC.md) is the source of
truth; this file is a summary/pointer, not a replacement.

## What this is

A self-improving 1:1 AI assistant (Telegram for the MVP) for an internal AI/dev community,
plus a separate human-run WhatsApp Community (unrelated infra, not built here). Defense-sector
context - see PROJECT-SPEC.md §4 for the full security model.

## Status

Phase 0-6 done: architecture docs, local infra, database schema (Phase 0-2); a live Telegram
echo bot with idempotency (Phase 3 - `n8n/workflows/telegram-echo-bot.json`,
`services/messaging-adapters/telegram/`); a security gate - sensitive-data detection (real),
classification (PUBLIC-only stub), language detection - running before any echo/generation
(Phase 4 - `security/`, `shared/`); a real knowledge base + RAG retrieval (Phase 5 -
`knowledge/`, 10 real seeded sources); real LLM generation with three-tier model routing,
budget guard, and Redis-backed conversational memory (Phase 6 - see "Generation phase design"
below). `interaction_logs` writes begin at Phase 4; `retrieved_kb_ids`/`intent` at Phase 5;
`routed_model`/tokens/`cost_usd` at Phase 6. Next: not yet planned - a candidate follow-up is
Telegram inline-keyboard buttons for tap-to-select clarifying answers (needs its own plan: model
must emit structured suggested replies, plus new webhook handling for `callback_query` events,
which the current workflow doesn't handle). Staying local (no hosting migration) until after
Generation stabilizes. **Update this line whenever a phase completes** - don't let it go stale.

### Generation phase design (Phase 6, done)

- **Three model tiers, not one model for everything.** Implemented in
  `n8n/workflows/telegram-echo-bot.json`'s "Route Model Tier" node: Tier 0 (template, KB match
  or budget hard-stop) → Tier 1 (`gpt-5.4-nano`) → Tier 2 (`claude-sonnet-5`, escalates on
  complexity signals). Matches PROJECT-SPEC.md §5's Tier 0/1/2 design.
- **Token-frugal by design and a good user experience are both explicit goals.** The system
  prompt (`database/seed/system-prompt.sql`) now explicitly enforces brevity (chat-length
  replies, not articles) and short, numbered/yes-no clarifying questions instead of open-ended
  ones - added after live Telegram testing showed the model defaulting to long, prose-heavy
  answers.
- **Query understanding tolerates typos/unusual characters and uses conversational context.**
  Routing the raw query through an LLM (Tier 1+) absorbs typos/odd characters; conversational
  context is carried in Redis per `conv:<platform_user_id>`, capped at the last 3 exchanges,
  TTL 1800s (ADR-0002: Redis is cache/session only, `interaction_logs` remains the durable
  record).
- **Known model-API quirks, worth remembering if these models change:** `gpt-5.4-nano` rejects
  `max_tokens`, needs `max_completion_tokens`. `claude-sonnet-5` returns extended-thinking
  content blocks by default (`content[0].type === 'thinking'`); the real answer is the first
  block with `type === 'text'`, not a fixed index - see "Validate Tier 2 Output" node.
- **Style rule, enforced both in the bot's persona and in this codebase itself:** never use an
  em-dash (`—`); use a regular hyphen, comma, period, or shorter sentences.

## How we work (established this session - follow it, don't re-derive it)

- **Small approved phases only.** Plan → implement → verify → approve → continue. Never turn
  an architecture doc into a large codebase in one step (PREPARATION-CHECKLIST.md's Final
  Rule). Use plan mode for anything beyond a trivial fix.
- **Git: one branch per phase or bugfix.** Commit completed, approved work to `main`, then
  branch for the next unit of work. Merge back to `main` only after the user approves.
- **Run `./scripts/verify-all.sh` before every merge to `main`.** It must pass. It
  auto-discovers every `<component>/tests/run.sh` - new phases add a `tests/run.sh` for
  whatever they build, not leave verification as a one-off manual step (see
  `.claude/skills/phase-workflow/SKILL.md`).
- **Don't invent open decisions.** Budget numbers, golden eval set contents, sensitive-data
  detection patterns, model pricing - these are the user's job to bring, not something to
  guess. Flag them as open instead.
- **Never read `.env` or `docs/links_and_details.md`** (real secrets/credentials, both
  gitignored - keep them that way). If new env vars are needed, append blindly via shell
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
