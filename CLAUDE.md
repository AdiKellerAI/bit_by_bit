# CLAUDE.md

Project-level context, auto-loaded every session. Keep this short - it's for facts that
matter on nearly every task, not a copy of the full docs. Full spec:
[`docs/project_setup/PROJECT-SPEC.md`](docs/project_setup/PROJECT-SPEC.md) is the source of
truth; this file is a summary/pointer, not a replacement.

## What this is

**Direction changed 2026-08-17 - read this before trusting PROJECT-SPEC.md's framing below.**
The product is now a **content agent for the community's WhatsApp Community**: it curates and
drafts weekly shared content (a featured article/podcast/video each Sunday, a summary of
community-shared links each Thursday), every draft admin-approved via Telegram before Adi
manually posts it to WhatsApp (the agent cannot post into that group itself - see the sub-phase
1 notes below for why), learning from Adi's corrections over time via the existing LDD pipeline,
retargeted. The original 1:1 Telegram Q&A/RAG assistant (everything below "Done" in the phase
table) is fully built and merged but **currently turned off** - community members are WhatsApp-
only now, not Telegram at all. **PROJECT-SPEC.md itself has NOT been updated for this pivot yet**
- it still documents the original 1:1-Q&A-first MVP definition (§17 MVP Validation, Phase 4-6's
framing, DoD list) as the source of truth. Treat PROJECT-SPEC.md as accurate for the *how* of
things already built (schema, ADRs, security model) but stale on *what the product's primary
purpose is* until it's explicitly revised - don't be surprised by the mismatch, and don't treat
silence in PROJECT-SPEC.md about WhatsApp content curation as this direction being unplanned.
Defense-sector context - see PROJECT-SPEC.md §4 for the full security model, still accurate.

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
**Phase 6 sub-phase 3 (admin commands) is now also complete**: `/pending`, `/prompts`,
`/approve`+`/confirm approve`, `/reject`, `/rollback`+`/confirm rollback` all live in
`telegram-echo-bot.json`, gated to `ADMIN_TELEGRAM_CHAT_ID` and exempt from the per-user rate
limit - see "Phase 6 LDD sub-phase 3 design notes" below. **Phase 6 "LDD" as a whole is now
functionally complete for v1** (§8's full loop - telemetry, feedback, nightly evaluation, golden
scoring, human-gated activation/rollback - all exist and were verified end to end); what remains
is refinement, not missing pieces: §11's three under-instrumented input signals (repeated
questions, security false positives, low-confidence RAG results - see sub-phase 2's notes) and
the "Security refusal" golden-eval category (blocked on real classification logic beyond the
PUBLIC-only stub). The golden evaluation set
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

### Phase 6 LDD sub-phase 3 design notes (Admin commands, §16)

- **Only the LDD-relevant subset of §16's admin command list is built.** `/status`, `/cost`,
  `/weekly`, `/gaps`, `/incidents` belong to Phase 7 (Weekly Community Automation) / general
  admin visibility, not Loop 3 - don't be surprised they're absent, that's intentional scope,
  not an oversight.
- **Admin identity gate runs before rate limiting, not after - moved there mid-implementation,
  not the original design.** Originally placed after `Over Rate Limit?`'s false branch (same
  spot as `Is Feedback Command?`), which meant a rapid admin session (e.g. testing
  `/approve`/`/confirm approve` back to back) could hit the same 10-messages/60s cap as ordinary
  users - confirmed live during this session's own testing. Adi chose to exempt admin commands
  entirely rather than accept that risk: `Is New?`'s true branch now goes straight to
  `Is Admin Command?`, which only falls through to `Check Rate Limit` on its false branch -
  admin commands never touch the rate-limit counter at all.
- **Chained IF nodes, not the Switch node, for the 7-way command routing** (`/pending`,
  `/prompts`, `/approve`, `/reject`, `/rollback`, `/confirm approve`, `/confirm rollback`).
  `n8n-nodes-base.switch`'s `rules.values` shape would have been cleaner for 7 branches but was
  unverified in this codebase; IF nodes had a fully proven-reliable exact schema by this point
  in the session. Deliberate verbosity-for-reliability trade-off on a feature that can activate
  a new Base Prompt for every subsequent conversation.
- **Two-step text confirmation, not inline buttons, for the two destructive actions.** `/approve
  <id>` and `/rollback` only ever show what *would* happen; the actual mutation requires a
  separate `/confirm approve <id>` / `/confirm rollback` message. Stateless by design - each
  command re-specifies/re-derives everything it needs (the id, or "most recently superseded base
  version") rather than trusting anything carried over from the prior message, so a stale or
  out-of-order confirm can't act on outdated assumptions. `/reject` has no confirmation step -
  §16 only requires confirmation for "prompt activation; rollback", not rejection, which is
  non-destructive.
- **A real "0 items silently stops a branch" bug, caught by manual testing, not code review.**
  `List Pending Proposals` originally used a bare `SELECT ... WHERE status = 'pending'`, which
  returns zero rows whenever nothing's pending - the exact silent-branch-stop failure mode this
  project has hit multiple times before (see Phase 4 notes). Fixed with the same
  `LEFT JOIN LATERAL ... ON true` dummy-row pattern used everywhere else "found or not" needs to
  reach a downstream node. Every other admin-command lookup was built with this guard from the
  start; this was the one plain `SELECT` that slipped through.
- **`UPDATE ... RETURNING` needs a `WITH` CTE, not `LEFT JOIN LATERAL`, for the same
  zero-rows-safety.** `LEFT JOIN LATERAL` can't wrap a data-modifying statement (INSERT/UPDATE/
  DELETE) - only `SELECT`. `Reject Proposal` uses `WITH updated AS (UPDATE ... RETURNING id)
  SELECT u.id FROM (SELECT 1) AS dummy LEFT JOIN updated u ON true LIMIT 1` instead - a new
  pattern for this codebase, valid standard Postgres (data-modifying CTEs), guarantees exactly
  one output row whether or not the UPDATE actually matched anything.
- **Activation is two sequential DB round-trips (deactivate, then insert), not one atomic
  transaction.** `idx_system_prompts_one_active_per_type` only allows one active `base` row at a
  time, so the old row must be deactivated before the new one can be inserted as active. There's
  a small window with zero active base prompts between the two calls - accepted as fine for a
  rare, admin-triggered, non-hot-path action, consistent with this codebase not using explicit
  multi-statement transactions anywhere else either.
- **Rollback reactivates history, it doesn't create a new version.** "Most recently superseded
  base version" (`is_active = false`, latest `created_at`) gets reactivated in place - no new
  `system_prompts` row, no new `version_tag`. Matches "never delete historical versions" and
  avoids an unbounded v1->v2->v3(=v1 again) version-tag mess from repeated rollbacks.
- **The automated test deliberately never drives the positive admin-gate path through the real
  webhook.** Doing so would require the real `ADMIN_TELEGRAM_CHAT_ID` to pass the identity check
  - meaning every `verify-all.sh` run would deliver real Telegram messages to Adi's phone,
  forever. `n8n/admin-commands/tests/run.sh` instead covers the command-parsing regex in
  isolation, the actual SQL state transitions directly against Postgres (with explicit save/
  restore of the real active Base Prompt), and the negative admin-gate case (wrong chat_id, safe
  via the real webhook since it never delivers). The full positive round-trip for every command
  and edge case was manually verified once, live, this session - that's the source of confidence
  the logic works; the automated suite is the regression guard underneath it, not a replay of it.

## WhatsApp Community Content Agent (new direction, replaces 1:1 Q&A as the primary product)

Decided across an extended conversation with Adi, 2026-08-17. Full sequence, sub-phases 1-2 done:

1. **Turn off the 1:1 Q&A bot** (done, see notes below)
2. **Thursday link-request -> Sunday featured-post draft/approval loop** (done, see notes below)
3. Community link relay -> Thursday summary, `knowledge_base` entries + Google Sheets sync for
   a public, searchable archive (not started)
4. LDD retargeted: Adi's corrections to drafts become the learning signal for future drafts,
   instead of Q&A feedback (not started) - `weekly_content_items` already captures both
   `draft_description_he` and `final_description_he`/`corrected` for exactly this, from
   sub-phase 2 onward, so there's nothing to backfill once sub-phase 4 starts.

**Why WhatsApp can't be posted into directly, confirmed against Meta's own docs (not assumed):**
the official WhatsApp Cloud API's Groups API can only create/manage groups the business itself
creates via the API, capped at 8 participants - it cannot join or post into a pre-existing,
human-created group (Adi's real community). The only compliant alternative (1:1 template-based
broadcast to opted-in individual phone numbers) changes the experience from a shared group post
into individual DMs, which isn't what's wanted here. Unofficial WhatsApp automation (session-
hijacking libraries etc.) would technically work but violates WhatsApp's Terms of Service and
risks the number being banned - explicitly ruled out, not a corner to cut under pressure.
**The resolution**: Adi is both the required approval gate (his own explicit requirement -
nothing posts without his review) and the only human with real access to the group, so he's also
the delivery mechanism - the agent drafts, Telegram is the review/approval surface (reusing the
existing `ADMIN_TELEGRAM_CHAT_ID` control surface), and Adi manually posts the approved content
into WhatsApp himself. This isn't a workaround, it's the actual architecture now.

**Group-visibility is zero, and that shapes what's buildable.** The agent cannot read anything
that happens inside the real WhatsApp group (messages, reactions, who joined) since it's not a
Cloud-API-controlled participant there. This killed two originally-requested features outright:
automatic new-member welcome messages (no join-event detection possible without ToS-violating
automation - dropped entirely, not attempted) and automatic survey-response collection (also
dropped - surveys would need a separate compliant mechanism like a web form, not attempted yet).
It's why the Thursday "community-shared-links" summary depends on Adi manually relaying links he
notices in the group via Telegram, by his own explicit choice, over the alternative of an
automated Google-Form-based collection mechanism that was offered and declined.

### Sub-phase 1 design notes (Turn off the 1:1 Q&A bot)

- **Disabled, not deleted - one connection cut, not a rewrite.** `Sensitive Data Flagged?`'s
  false branch (in `n8n/workflows/telegram-echo-bot.json`) now points at a 3-node dead-end
  (`Insert interaction_logs (qa disabled)` -> `Send Q&A Disabled Reply` -> `Respond Q&A
  Disabled`) instead of `Classification Is PUBLIC?`. Everything from there on - cache, RAG,
  budget guard, Tier 0/1/2 generation - is untouched in the file, just unreachable. Re-enabling
  later is one connection change, not a rebuild.
- **Sensitive-data detection still runs, unconditionally - this was the one thing that could
  NOT move.** ADR-0003's "distinct, always-on pre-LLM control" applies regardless of whether
  Q&A itself is enabled. The cut point is deliberately *after* `Detect Language, Classify,
  Detect Sensitive Data` and `Sensitive Data Flagged?`, not before - a message containing a
  real secret still gets blocked, redacted, and logged to `sensitive_data_events` exactly as
  before. Verified live, not assumed.
- **The nightly evaluator (`nightly-evaluator.json`) needed zero changes to go dormant.** It
  already only acts on `interaction_logs` rows with `feedback_score = 0 OR needs_review =
  true`. With Q&A off, no new rows meeting that condition are ever created, so `Any Flagged?`
  is false every night and it no-ops for free - graceful by construction, not something
  special-cased for this change. It'll come back to life for real once sub-phase 4 retargets
  what feeds `prompt_change_proposals`.
- **The ancestor-safety verification script needed a real fix, not just a rerun.** Orphaning an
  entire subgraph (26 nodes: cache/RAG/generation) made the existing BFS-based checker fire 26
  false positives - it correctly found their `$('Node')` references don't resolve via the
  ancestor graph, but that's expected and harmless for nodes with zero incoming connections
  that will never execute, not a bug. Fixed by first computing reachability from the workflow's
  actual trigger nodes (BFS forward from `Webhook`/`scheduleTrigger`/`manualTrigger` node
  types) and only checking `$('Node')` references inside nodes that are actually reachable.
  This distinction (reachable-but-wrong-reference vs. unreachable-so-references-don't-matter)
  is now a permanent part of what this check needs to do, not a one-off fix - any future
  workflow-graph change that orphans nodes should still show "N unreachable nodes with
  references, skipped" as expected output, not zero problems by coincidence.
- **`n8n/tests/run.sh` lost real coverage on purpose, not carelessly.** The RAG-match/no-match,
  Tier 1/Tier 2 routing, semantic-cache-hit, Security Prompt signal, and base-prompt-selection
  tests all asserted behavior on a path that's now intentionally unreachable - left in place
  they'd be permanently red for a reason that isn't a bug. Removed rather than skipped/commented
  out, with a note in the file that the underlying logic isn't gone, just dormant, and that
  coverage can be restored from git history if Q&A ever comes back. What's kept and still
  fully real: secret/webhook validation, idempotency, sensitive-data blocking (still live),
  rate limiting (runs before the disabled cut, unaffected), and the qa_disabled path itself.

### Sub-phase 2 design notes (Thursday link-request -> Sunday post approval)

- **New table, `weekly_content_items`, deliberately shaped for both this phase and phase 3.**
  `content_type` already distinguishes this phase's `featured_link` from phase 3's planned
  `community_summary` so the same table serves both without a schema change later - not
  speculative, since phase 3's shape was already agreed, just not yet built.
- **The only new workflow file is the Thursday prompt itself - everything else lives in the
  existing webhook.** `n8n/workflows/weekly-content-agent.json` is just Schedule Trigger (+
  Manual Trigger, same testability pattern as `nightly-evaluator.json`) -> compute next Sunday's
  date -> send the prompt. Receiving Adi's reply, fetching the link, drafting, and handling the
  approval reply all reuse `telegram-echo-bot.json`'s existing webhook and `Verify & Normalize`/
  `Is Admin Command?` infrastructure rather than standing up a second receiving endpoint.
- **Both new branches are exempt from the per-user rate limit, inserted right after `Is Admin
  Command?`'s false branch (before `Check Rate Limit`) - matching the precedent already set for
  LDD admin commands**, not a fresh decision. `Is Admin Command?`'s false branch now goes to
  `Is Link Submission?` first, whose own false branch goes to `Check Pending Draft`, whose
  "nothing pending" branch is what finally reaches `Check Rate Limit` - ordinary users still hit
  the same rate limit exactly as before, just one hop later in the graph.
- **The pending-draft lookup's security boundary is the SQL WHERE clause, not a separate
  identity-gate node - and getting this right mattered.** `Check Pending Draft` filters
  `submitted_by = $1` where `$1` is the *current sender's own* `platform_user_id`, not the
  `ADMIN_TELEGRAM_CHAT_ID` env var. An earlier version of this reasoning (caught during planning,
  before any code was written) would have filtered on the env var instead - which would have let
  *any* Telegram user "approve" the admin's pending draft by sending `/approve` while one was
  waiting, since the query wouldn't have checked who was actually asking. Because `submitted_by`
  can only ever be set to the real admin's id (only reachable via the already-admin-gated link-
  submission branch), scoping the lookup to "does *this* sender have a pending draft" is both
  correct and sufficient - verified live with a synthetic non-admin id against a real pending
  admin draft, confirmed it cannot be hijacked.
- **Fetching arbitrary URLs needs `responseFormat: 'text'` and a real `User-Agent`, confirmed by
  reading `HttpRequest/V3/Description.js` in-container** - the default `autodetect` format risks
  mis-parsing HTML as something else, and many sites reject requests with no browser-like
  `User-Agent` header. `neverError: true` so a blocked/failed fetch degrades gracefully (title/
  description come back `null`, the drafting prompt is instructed to say so honestly) rather
  than crashing the run.
- **The Hebrew-description LLM call is grounded, not free-form, and explicitly told not to
  invent content when extraction fails.** Uses `gpt-5.4-nano` (cheap tier - this is admin content
  drafting, not the "real reasoning" category that earned `claude-sonnet-5` in the nightly
  evaluator's tiering decision), fed only the extracted `<title>`/`og:title`/`og:description`/
  meta-description text, with an explicit fallback instruction to say it couldn't produce a
  preview rather than fabricate one - same no-fabrication discipline as the RAG "don't invent a
  KB citation" rule and the digest prompt's "don't invent data" rule elsewhere in this project.
- **The correction path takes Adi's text completely verbatim, no LLM involved.** Matches his own
  explicit instruction ("I'll just send the fixed phrasing... no back and forward messaging with
  the LLM") - `Mark Approved (corrected)` writes `$('Verify & Normalize').item.json.text`
  directly into `final_description_he`, nothing generated or rephrased.

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
