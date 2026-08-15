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

**Phase 5 "Prompt System" is now complete**: Base (persona), Router, Evaluator, Digest, and
Security prompts all exist, versioned in `system_prompts` with a `prompt_type` discriminator
column (see "Phase 5 Prompt System design notes" below). Router and Security are wired into
live runtime use; Evaluator and Digest are stored/versioned only, with no consumer yet - they
feed Phase 6 and Phase 7 respectively. Sensitive-Data Detection deliberately stayed as
code-based rules (`security/sensitive-data-detection/patterns.ts`), not a `system_prompts`
row, per ADR-0003/ADR-0004's explicit exclusion from the automated prompt pipeline.

**Phase 6 "LDD" sub-phase 1 (§10 "Loop 2 - Telemetry & Feedback") is now complete**:
`interaction_logs` collects every field §10 lists (query, response, model, tokens, cost,
latency, cache hit, intent, language, RAG docs, feedback, security classification,
sensitive-data flag, prompt version, platform), and the required `feedback 1`/`feedback 0`
command path actually writes to `feedback_score`/`needs_review` - see "Phase 6 LDD sub-phase 1
design notes" below. **Phase 6 sub-phase 2 (Loop 3 "Meta-Learning" §11, evaluator + golden-eval
scoring half) is now also complete**: `n8n/workflows/nightly-evaluator.json` (Schedule Trigger,
nightly 03:00) selects flagged interactions, calls the Evaluator, synthesizes a full candidate
prompt, runs it against all 22 golden-eval cases, LLM-judges each answer, and stores a scored
row in `prompt_change_proposals` (auto-`rejected` below a 90% pass threshold or on any critical
sensitive-data-case failure, else `pending`) - see "Phase 6 LDD sub-phase 2 design notes" below.
**Not yet started:** admin commands (`/pending`, `/approve`, `/reject`, `/rollback`, `/prompts`)
that actually act on those `pending` rows - there was nothing real to act on before this
sub-phase existed, so this is explicitly next. The golden evaluation set
(`database/seed/golden-eval-cases.sql`, 22 cases across 15 of ARCHITECTURE-FLOWS.md §16's 16
categories) is seeded - category 11 "Security refusal" is still deliberately excluded, since
`security/classification/classify.ts` remains a PUBLIC-only stub with no real refusal logic to
test yet. The Evaluator Prompt is seeded and now has a real consumer. Phase 7 "Weekly Community
Automation" (digest/knowledge-gap report/cost report/admin
alerts; the Digest Prompt is seeded and waiting) not started. Hosting migration (not a numbered
spec phase, but an explicit hard prerequisite before Phase 8 Pilot) is deliberately still
deferred, not forgotten - staying local. **This gap is sharper now than before the nightly
evaluator existed**: a request/response Telegram bot only fails to respond while the laptop is
down; a Schedule Trigger workflow simply never fires nightly at all unless Colima +
`docker compose` happen to be up at 03:00 - flagged directly to Adi (2026-08-15), who chose to
keep building sub-phases locally and treat hosting as a separate, later decision rather than
solving it now. Phase 8 Pilot and Phase 9 Expansion correctly not started, since they depend on
everything above.

Two candidate next steps, neither planned yet: Telegram inline-keyboard buttons for
tap-to-select clarifying answers (model must emit structured suggested replies, plus new
webhook handling for `callback_query` events); and Adi's stated intent to make WhatsApp the
sole community-facing channel eventually, not Telegram, with a "should the bot even respond"
gate for group dynamics (weekly shared content, casual conversation) - see this session's
memory for the WhatsApp direction, not yet reflected in PROJECT-SPEC.md/this file.
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

### Phase 5 Prompt System design notes

- **`system_prompts.prompt_type` discriminates the five prompt kinds** (base/router/evaluator/
  digest/security), each independently active via a per-type partial unique index
  (`idx_system_prompts_one_active_per_type`) - this replaced the original global "only one
  prompt active at all" constraint. **Every query against `system_prompts` must filter on
  `prompt_type`, with no exceptions** - a real production bug happened here: `Get System
  Prompt` (fetches the Base persona) kept its pre-Phase-5 query, `WHERE is_active = true` with
  no `prompt_type` filter and no `ORDER BY`, so once five types were simultaneously active it
  non-deterministically returned whichever row Postgres picked first - in practice, the Router
  prompt - and real users got raw router-classification JSON echoed back as the "answer".
  Caught via live Telegram testing, not automated tests (no test asserted persona *identity*,
  only that a prompt existed). Fixed, and a regression test now asserts a real generation's
  `prompt_version_id` matches the active base-type row specifically.
- **A bad response can outlive the fix that prevents new ones, via the semantic cache.** The
  broken router-JSON response from the bug above got written to `semantic_cache` before the
  fix landed; retesting the same query kept returning the broken answer until that specific
  cache row was manually deleted, even though the underlying bug was already fixed. When
  debugging a response that looks stale/wrong after a fix, check `semantic_cache` for a
  poisoned row with the same `query_text` before assuming the fix didn't work.
- **Security Prompt is advisory only, on purpose.** It runs a real LLM call and logs a
  PUBLIC/INTERNAL/SENSITIVE/CLASSIFIED signal to `interaction_logs.security_signal` (deliberately
  a separate column from the authoritative `security_classification`), but does not gate
  anything - `security/classification/classify.ts`'s always-PUBLIC stub is unchanged. This was
  an explicit, conservative choice for a security-critical path in a defense-sector-adjacent
  project; don't wire this signal to gate behavior without a fresh explicit decision once real
  classification data has been reviewed.
- **Evaluator and Digest prompts have no consumer yet, on purpose.** They're stored and
  versioned (satisfying Phase 5's literal scope) but nothing invokes them - Phase 6 (LDD) builds
  the nightly evaluator loop, Phase 7 (Weekly Community Automation) builds the digest job. Don't
  be surprised these prompts exist with no code path that calls them; that's the intended state
  until those phases land.

### Phase 6 LDD sub-phase 1 design notes (Telemetry & Feedback, §10)

- **This sub-phase is data collection only, not the self-improving loop itself.** §10's
  telemetry list and the `feedback 1`/`feedback 0` command feed **Loop 3 "Meta-Learning" (§11)**
  - a nightly evaluator agent that reads this data and proposes prompt changes automatically -
  which is deliberately not built yet, blocked on Adi preparing the golden evaluation set
  (`evaluation_cases`' own migration comment: "prepared by you... not invented here"). Loop 3 is
  agent-driven end to end except the final activation step, which always requires human approval
  via `/approve`/`/reject`/`/rollback` (ADR-0004) - the evaluator can never activate its own
  change.
- **Feedback command runs before the rate limit's downstream pipeline, but still counts against
  the same rate limit.** `Is Feedback Command?` sits right after `Over Rate Limit?`'s false
  branch, before `Detect Language, Classify, Detect Sensitive Data` - a feedback command never
  triggers RAG/generation/cost, and is intentionally not logged as its own `interaction_logs`
  row (it mutates an existing row instead).
- **Reply-based correlation, with a same-user fallback.** `Find Target Interaction` prefers
  matching `platform_response_message_id` against the message the user replied to
  (`reply_to_message_id`, captured in `Verify & Normalize` off the raw Telegram update); if
  there's no reply target (or it doesn't match), it falls back to that user's single most recent
  `interaction_logs` row. Uses the same defensive `LEFT JOIN LATERAL` pattern as
  `Search Semantic Cache`/`Get Router Model` - guarantees exactly one output row even when
  nothing matches, so the downstream `Found Target Interaction?` IF node always has something to
  branch on.
- **Capturing the bot's own sent Telegram `message_id` needed an INSERT-then-UPDATE, not a
  single INSERT.** `Insert interaction_logs (final)` runs before `Send Telegram Message`, so the
  Telegram-assigned `message_id` isn't known until after the send. `Insert interaction_logs
  (final)` now has `RETURNING id`, threaded through `Prepare Telegram Send` as
  `interaction_log_id`, and a new `Update interaction_logs (message_id)` node (best-effort,
  `onError: continueRegularOutput`) runs after the send to fill in
  `platform_response_message_id`. A failure here should degrade feedback matching, not break
  message delivery, which already succeeded by that point.
- **`latency_ms` is computed in SQL, not a Code node.** `Verify & Normalize` now also returns
  `processing_started_at` (when our pipeline started, distinct from `received_at` which is when
  Telegram says the user sent the message); `Insert interaction_logs (final)`'s query computes
  `EXTRACT(EPOCH FROM (now() - $N::timestamptz)) * 1000` directly rather than subtracting in a
  separate node.
- **Only the required fallback command is built, not emoji reactions.** §10 explicitly gates
  emoji reactions as "implement only where supported"; the command path (`feedback 1`/
  `feedback 0`) is the one piece the spec actually mandates for MVP completeness. n8n's Telegram
  integration does support inline-keyboard `callback_query` handling for a tap-to-react UI later
  (confirmed available, unused today) - a larger, separate feature, not in scope here.

### Phase 6 LDD sub-phase 2 design notes (Evaluator + Golden Evaluation, §11)

- **A separate workflow file, not a branch inside `telegram-echo-bot.json`.**
  `n8n/workflows/nightly-evaluator.json` has its own Schedule Trigger (cron `0 3 * * *`) - a
  fundamentally different trigger type from the webhook bot, but the same running `n8n`
  container/docker-compose service. Also carries a parallel `n8n-nodes-base.manualTrigger` node
  feeding the same first real step, purely for testability (see the CLI note below) - production
  scheduling is unaffected by its presence.
- **Manually executing a Schedule-Trigger workflow needs two non-obvious fixes, both confirmed
  by reading n8n's own source in-container.** (1) `n8n execute --id=<id>` requires a node type
  from `STARTING_NODES` (`n8n-nodes-base.manualTrigger` or the langchain manual-chat variant) or
  an `executeWorkflowTrigger` node - a bare Schedule Trigger alone throws "Missing node to start
  execution", hence the parallel Manual Trigger node above. (2) Running `n8n execute` in the same
  container as the live main process conflicts on the Task Broker's default port 5679 - fixed
  with `-e N8N_RUNNERS_BROKER_PORT=5680` on the one-off `docker compose exec` call (confirmed via
  `@n8n/config`'s `runners.config.js`), not by stopping/restarting the main process.
- **Tiered model selection, not "always the expensive model" - a real cost correction made
  during planning, not an afterthought.** The Evaluator and Synthesize-Candidate-Prompt calls
  (real reasoning/writing work - diagnosing *why* something failed, writing new prompt text) use
  `claude-sonnet-5`; the 22 Golden Eval candidate-answer calls and the batched judge call use
  `gpt-5.4-nano` (same model most real production traffic already uses; judging pass/fail
  against a written `expected_behavior` doesn't need the priciest model). First real run's actual
  cost: $0.0398 - in line with the ~$0.03-0.05/run estimate, confirming the tiering works as
  intended rather than being a guess that happened to sound right.
- **The Evaluator's `proposed_prompt_change` is a change description, not a full prompt - a
  synthesis step bridges that gap.** The Evaluator Prompt's fixed JSON contract (seeded in Phase
  5, unchanged here) only ever returns a *description* of what to change ("the specific text
  change to the Base Prompt"). `prompt_change_proposals.proposed_prompt` needs the complete
  candidate text to actually run Golden Evaluation against, so a dedicated `Synthesize Candidate
  Prompt` call (current base prompt + the change description in, complete new prompt text out)
  produces it. Verified on a real run: the synthesized text is coherent, real Hebrew persona
  copy correctly starting from the actual active Base Prompt, not a fragment.
- **Judged in one batched call across all 22 cases, not 22 separate judge calls** - keeps total
  LLM calls per run at ~25 instead of ~45, and the judge system prompt is a plain string
  hardcoded in the node, not a `system_prompts` row (it's an internal scoring tool, not a
  user/community-facing persona, so it doesn't belong in the prompt-versioning system).
- **Auto-reject threshold: pass rate < 90%, OR any `sensitive_data` critical-severity case
  fails on its own regardless of overall score.** Confirmed with Adi - a secret-leak-handling
  regression should hard-block even if the other 21 cases look fine; a flat percentage alone
  would let that slip through if enough easy cases compensate.
- **Evaluation cost is tracked (`prompt_change_proposals.evaluation_cost_usd`, computed from
  real `model_registry` pricing, same pattern as `Get Model Pricing`/`Validate Tier 2 Output`)
  but deliberately does NOT gate on `budget_policy`.** That budget governs user-facing traffic;
  this is an internal admin process, confirmed as a distinct decision with Adi.
- **§11's input signal list is only partially instrumented, and this sub-phase does not fake
  the rest.** Of the five listed signals (👎, repeated questions, flagged responses, security
  false positives, low-confidence RAG results), only `feedback_score = 0` and `needs_review =
  true` are real, queryable columns today - `interaction_logs` has no repeat-question tracking,
  no human-confirmed-false-positive mechanism for `security_signal`, and no persisted RAG
  similarity/distance score (only `retrieved_kb_ids`, matched-or-not). `Select Flagged
  Interactions` uses only the two real signals; the other three remain a documented gap for a
  future refinement.
- **This sub-phase produces `pending`/`rejected` rows but nothing acts on `pending` ones yet.**
  `/approve`/`/reject`/`/rollback`/`/pending`/`/prompts` (§16) are explicitly the next piece,
  not built here - there was nothing real to approve before real scored proposals existed.

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
