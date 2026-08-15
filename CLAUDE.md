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

Tracked against **PROJECT-SPEC.md §24's own phase list** (Phase 0-9), not an informal
session-by-session numbering - earlier versions of this file used a different "Phase N" count
that didn't line up with the spec (e.g. what used to read "Phase 6" here was Generation work
the spec itself files under Phase 4 "Agent Core"). Always use the spec's phase names.

**Done:** Phase 0-3 (architecture docs, local infra, database schema, messaging pipe - see
`n8n/workflows/telegram-echo-bot.json`, `services/messaging-adapters/telegram/`). **Phase 4
"Agent Core" is now complete**: language detection, security classification (PUBLIC-only
stub), sensitive-data detection (`security/`, `shared/`), RAG (`knowledge/`, 10 real seeded
sources), budget guard, three-tier generation, rate limit, semantic cache, and a real intent
router - see "Phase 4 Agent Core design notes" below for all of these. `interaction_logs`
writes begin at Phase 4 generally; `retrieved_kb_ids`/`intent` from the RAG/generation work;
`routed_model`/tokens/`cost_usd`/`cache_hit`/`cached_input_tokens` all populated now.

**Not yet started:** Phase 5 "Prompt System" (only a Base persona prompt exists in
`database/seed/system-prompt.sql`; Router/Evaluator/Digest/Security/Sensitive-Data-Detection
prompts, versioned in `system_prompts`, don't exist yet). Phase 6 "LDD" (telemetry, feedback,
evaluator, golden-question evaluation, human approval, rollback - the project's actual
self-improving core; `interaction_logs.feedback_score`/`needs_review` sit unused). Phase 7
"Weekly Community Automation" (digest/knowledge-gap report/cost report/admin alerts). Hosting
migration (not a numbered spec phase, but an explicit hard prerequisite before Phase 8 Pilot)
is deliberately still deferred, not forgotten - staying local. Phase 8 Pilot and Phase 9
Expansion correctly not started, since they depend on everything above.

A candidate next step (not yet planned): Telegram inline-keyboard buttons for tap-to-select
clarifying answers - needs its own plan (model must emit structured suggested replies, plus new
webhook handling for `callback_query` events, which the current workflow doesn't handle).
**Update this section whenever a phase completes** - don't let it go stale.

### Phase 4 Agent Core design notes

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
- **Rate limit: 10 messages / 60s per user, Redis `incr`+`expire`, fails open.** Second node in
  the pipeline (right after idempotency), before the security gate even runs, per
  threat-model.md §3.1. Fails open (not closed) on Redis errors - availability over strict
  enforcement for a low-volume internal tool, matching the one prior fail-open precedent
  (`Load Conversation History`).
- **Semantic cache: pgvector-backed, cosine distance < 0.15, 24h freshness, $0 on hit.** New
  `semantic_cache` table (same hnsw pattern as `knowledge_base`). Sits between the security gate
  and the intent router/RAG, reusing the embedding `Embed Query` already computes. Only ever
  caches real generations (Tier 1/2), never KB-match/blocked/error responses, and only when the
  conversation has no prior turns and the message isn't time-sensitive (`Check Cache Eligible`
  node operationalizes PROJECT-SPEC.md §9's cache-hit criteria). `interaction_logs.cache_hit`/
  `cached_input_tokens` are populated now.
- **Intent router: a real `gpt-5.4-nano` classification call, not a post-hoc label.** `Classify
  Intent` + `Parse Intent` run after a cache miss, before RAG. Its `complexity` field drives
  Tier 1 vs Tier 2 (replacing the old regex/length heuristic entirely); its classified `intent`
  (question/greeting/feedback/off_topic/clarification) is appended to every logged intent (e.g.
  `generated_tier1_greeting`). Its `needs_kb` field is logged but deliberately does NOT gate the
  KB-match short-circuit - tried that, it made a real, reliable match unpredictably flaky since
  the classifier's guess is less trustworthy than `Pick Best Match`'s own distance threshold.
- **Cross-node reference safety is load-bearing in this workflow, verify it after any graph
  change.** A Postgres/Code node's output replaces `$json` entirely, and `$('Node Name')` throws
  if that node isn't a genuine ancestor of the current item's actual execution path (not just
  present somewhere in the file) - this has caused two real bugs in this workflow already (see
  git history: `Search Knowledge Base`'s bare `$json.data[0].embedding` broke when its direct
  predecessor changed; several leaf nodes needed `retrieved_kb_ids`/`prompt_version_id`/
  `cache_hit`/`cached_input_tokens` added to their common return shape so the final log insert
  never references a node that didn't run on every path). Before deploying any workflow change,
  run a script that (a) builds the connections graph, (b) computes true ancestors per node via
  BFS on the reversed graph, and (c) confirms every `$('Name')` reference found in that node's
  own parameters is in its ancestor set - this catches the class of bug live testing might not
  (a broken reference only throws for the specific branch it's on).
- **Style rule, enforced both in the bot's persona and in this codebase itself:** never use an
  em-dash (`—`); use a regular hyphen, comma, period, or shorter sentences.
- **Hebrew replies get an invisible RTL mark prepended in code, not left to prompt compliance.**
  Telegram picks a paragraph's direction from its first strong-direction character, so a Hebrew
  reply that opens with an English term (e.g. "Claude Code") renders misaligned. Verified live
  that asking the model to open with a Hebrew word isn't reliable even with an explicit example
  in the prompt - `Prepare Telegram Send` now prepends U+200F (RLM) to any Hebrew response
  deterministically, regardless of what the model actually generates. The prompt rule stays too
  (still nudges more natural phrasing) but is not the mechanism the fix depends on.
- **The public Telegram webhook depends on an external tunnel this repo doesn't manage or
  start** (`cloudflared tunnel --url http://localhost:5678`, run manually, logs to
  `/private/tmp/cloudflared.log`). `verify-all.sh`/`n8n/tests/run.sh` only ever hit
  `localhost:5678` directly, so a dead tunnel is invisible to them by design - "all checks
  passed" only ever claims the workflow logic is correct, not that Telegram can currently reach
  it. `./scripts/dev-status.sh` now checks the public `WEBHOOK_URL` for exactly this (added
  2026-08-15 after a stuck quick-tunnel silently stopped routing for hours). Quick tunnels get
  a new random hostname on every restart - after restarting one, update `.env`'s `WEBHOOK_URL`
  and re-register it with Telegram's `setWebhook` (needs the bot token from `.env`, so this is
  a step for the user, not something to automate blindly with a token neither you nor an
  agent should read).

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
