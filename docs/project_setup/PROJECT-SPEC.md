# Project Specification — Self-Improving AI Agent for an Internal AI & Development Community
> Document status: Updated master specification (Telegram-first Agent channel)
> Purpose: Source of truth for Cursor / implementation
Language: English for architecture, prompts, code and documentation; Hebrew for the
community-facing UX where specified
Primary principle: Build a useful, secure MVP first, then evolve it through controlled
Loop-Driven Development (LDD).


---

## 0. Executive Decision

The original concept is strong, but several parts of the earlier plan must be corrected before
implementation.

**The concept is approved**

The project should provide:
- A human-run **WhatsApp Community** for employees.
- A separate **1:1 Agent**, reachable through its own messaging channel.
- A curated knowledge base covering AI basics, AI trends/AGI, development with
AI, Copilot, Claude, automation and relevant industry content.
- Weekly curated content prepared by the Agent and reviewed/published by a
human administrator.
- A self-improving Agent using LDD.
- Dynamic model routing and semantic caching to control cost.
- Human approval before changes to prompts, routing policies or other behavior
become active.
- Strong security boundaries suitable for a defense-sector environment, including
active monitoring of what users type — not just what the Agent says back.

**Channel correction (updated)**

The original plan assumed the Agent's 1:1 channel and the WhatsApp Cloud API were the same
decision. They are not, and this project treats them as two independent tracks:

1. **The WhatsApp Community is unaffected by any Agent-channel decision.** It is created
   directly through the WhatsApp app (Settings → Communities → New Community). It requires
   no Meta Developer Account, no business verification, and no API access of any kind.
2. **The Agent's 1:1 channel is implemented behind a messaging-adapter abstraction.**
   For the MVP, the concrete adapter is a **Telegram bot** (created via @BotFather — no SMS
   verification, no business account, available immediately).
3. A **WhatsApp Cloud API adapter** may be added later, once Meta Developer Account access is
   unblocked, as a second adapter alongside Telegram — not a replacement, unless later decided
   otherwise.
4. Nothing about the Agent's internal logic (security, RAG, caching, cost routing, LDD)
   depends on which adapter is active. Only the inbound-normalize / outbound-format nodes in
   n8n are channel-specific.
5. The community contains instructions telling members how to contact the Agent (currently:
   a Telegram link).
6. The Agent generates weekly content drafts.
7. A human administrator reviews and manually posts those drafts into the WhatsApp Community.

This separation is a hard architectural boundary, same as in the original plan — it now also
applies between "Agent channel" and "Community channel," which are allowed to be different
platforms entirely.


---

## 1. Vision

Create a living AI/technology learning community that helps employees:
- discover what is happening outside the organization;
- learn AI from beginner to advanced levels;
- discover podcasts, articles, tools and practical development techniques;
- share ideas and things they have built;
- identify opportunities for automation and innovation;
- discuss what they would like to see improved;
- gradually become more comfortable with modern AI terminology and workflows.

The primary cultural objective is:
> **Open people's minds before asking them to change how they work.**

The community should not feel like another corporate training program.
It should feel like:
- a technology radar;
- an idea exchange;
- a practical learning space;
- a place to discover what is happening outside;
- a safe place to ask beginner questions;
- a living demonstration of AI.


---

## 2. UX Model

### 2.1 Human Community (WhatsApp)

The human-run community contains, conceptually:

Announcements
Used for:
- weekly curated content;
- important technology news;
- selected podcasts;
- community announcements;
- challenges;
- polls.

Sandbox
Used for:
- discussion;
- questions;
- ideas;
- sharing projects;
- sharing experiments;
- requests for tools/features.

The Agent does not post directly into these groups in v1, regardless of which platform the
Agent itself runs on.

**Ownership and admin control.** WhatsApp Communities are not available in the WhatsApp
Business app (a real, current platform limitation) — only in the regular WhatsApp app. The
Community is therefore created and owned by a regular WhatsApp account belonging to a
trusted household member, with the project owner's own number added as a full admin of the
Community and every group inside it immediately after creation. This ensures day-to-day
control, moderation, and posting authority do not depend solely on the creator account.
Actual phone numbers are treated as credentials: stored in the personal secrets backup
(see PREPARATION-CHECKLIST.md), never written into project documents or committed to the
repository. This ownership arrangement is a personal-POC bridge, and — like the messaging
platform choice — should be revisited as part of the organizational review in §4.7 before
any wider rollout.

### 2.2 AI Agent (Telegram for MVP; WhatsApp adapter optional/future)

The Agent is a separate 1:1 contact — a Telegram bot for the MVP.

Users can ask, in either Hebrew or English, e.g.:
- ”יש פודקאסט טוב למתחילים ב-AI”?
- “What is RAG?”
- ”תמצא לי משהו על Copilot”
- ”מה חדש בעולם ה-Agents”?
- ”יש משהו טוב על AGI”?
- ”אני רוצה להבין איך AI יכול לעזור ב-testing”

The Agent responds in the language of the user. This behavior is identical regardless of
whether the underlying transport is Telegram or WhatsApp.


---

## 3. Product Principles

1. Adoption before sophistication.
2. Security before convenience.
3. Human approval before autonomous behavioral change.
4. Measure everything that matters.
5. Keep costs observable and bounded.
6. Use the cheapest model capable of completing a task.
7. Do not confuse "learning" with uncontrolled self-modification.
8. The Agent must be useful even if every advanced AI feature is disabled.
9. Public/external knowledge and internal corporate knowledge must be separate
trust domains.
10. The system must fail safely.
11. The messaging channel is an implementation detail, not an architectural
dependency — the system must not assume a single fixed platform.
12. What users type must be actively monitored for sensitive content, not just
what the Agent says back.


---

## 4. Security Model

This is a defense-sector context. The system must assume that external AI APIs — and the
messaging platform itself — are an untrusted data boundary unless explicitly approved by the
company.

### 4.1 MVP security boundary

During a personally funded proof of concept:
- use only public information;
- use synthetic test users;
- do not ingest internal company documents;
- do not ingest source code;
- do not ingest tickets;
- do not ingest internal architecture;
- do not ingest internal names or organizational information unless explicitly
approved;
- do not put classified, proprietary or sensitive information into the Agent.

The POC must not be presented as approved for production corporate data. This holds
identically whether the Agent runs on Telegram, WhatsApp, or both.

### 4.2 Sensitive-Data Monitoring (new)

Beyond the data-classification gate below, the system must actively **monitor what users
type**, independent of intent, and treat detection as an incident, not a soft signal:

Requirements:
- A dedicated detection step runs on every inbound message before it reaches RAG, cache, or
  any LLM call.
- It looks for: credential-shaped strings (API keys, tokens, passwords), personal
  identifiers, anything resembling a classification marking, internal ticket/case numbers,
  internal hostnames or IP ranges, source-code fragments, and other org-specific sensitive
  patterns to be defined with input from Elbit's security team.
- A positive match always: (a) blocks the message from proceeding to any LLM call,
  (b) responds to the user with a short, non-judgmental safe redirect, (c) writes a row to a
  dedicated `sensitive_data_events` audit table (separate from general telemetry), and
  (d) notifies the administrator — not just logs the event passively.
- Sensitive-data events are never used as training signal for Loop 3 — they are an audit/
  incident trail only, reviewed by a human.
- This detector is explicitly called out as a distinct component (not folded into the general
  "data classification" step) so it can be reviewed, tuned and audited on its own.
- Detection patterns must be treated as a living configuration, not a one-time hardcoded list
  — expected to be refined with the organization's security team over time.

Do not rely only on regex detection for this either — regex/heuristics are a first-pass
signal; treat unclear cases as flagged rather than silently passed.

### 4.3 Secrets

**Development / private POC**

A local `.env` file may be used for development.

Requirements:
- `.env` is never committed.
- `.env.example` contains placeholders only.
- secrets are never printed to logs;
- secrets are never placed in prompts;
- secrets are never stored in database tables;
- secrets are never included in workflow exports.

**Production**

Do not assume `.env` is the final enterprise secret-management solution.
The production design must support a secret manager approved by the organization, such as
an enterprise vault/secrets service.
n8n credentials should reference managed secrets rather than embedding values in workflows.

### 4.4 Data classification

Introduce an explicit data classification decision before every external LLM call:
```text
PUBLIC
INTERNAL
SENSITIVE
CLASSIFIED
```
MVP policy:
- PUBLIC -> may be processed by external LLMs, subject to passing sensitive-data detection.
- INTERNAL -> blocked unless explicitly approved by security architecture.
- SENSITIVE -> blocked.
- CLASSIFIED -> blocked.

Do not rely only on regex detection.
Regex/heuristics are a signal, not a security boundary.

### 4.5 Input security pipeline

Before an external LLM call:
```text
Inbound message (any platform)
|
v
Normalize
|
v
Security classification
|
+---- blocked ----> Safe refusal + security telemetry
|
v
Sensitive-data detection
|
+---- flagged ----> Safe redirect + audit event + admin alert
|
v
Prompt-injection screening
|
v
Scope validation
|
v
LLM
```

The system must never claim that regex scrubbing can guarantee removal of sensitive
information.

### 4.6 Prompt injection

Treat user input and retrieved knowledge as untrusted content.
The Agent must distinguish:
- system instructions;
- developer instructions;
- retrieved knowledge;
- user content.

Retrieved articles must never be allowed to override system policy.

### 4.7 Organizational approval (new)

Before rolling this out to any group of colleagues — regardless of which platform the Agent
runs on — the data-handling design in this section (classification, sensitive-data
monitoring, no ingestion of internal data, full audit trail) should be reviewed with Elbit's
security/IT function. The messaging platform choice (Telegram vs WhatsApp) is a secondary
question to raise in that same conversation, not a substitute for it.

### 4.8 Messaging automation method (new — considered and rejected alternative)

A WhatsApp Business **app** (the free consumer app, distinct from Cloud API) is already
available for this project's use. Two ways exist to turn that into an automated channel:

1. **Official — WhatsApp Cloud API**, gated behind Meta Developer Account verification
   (currently blocked). This is the only method used or planned in this project.
2. **Unofficial — WhatsApp Web automation libraries** (e.g. Baileys, whatsapp-web.js), which
   drive a real WhatsApp number by automating the WhatsApp Web protocol, without any Meta
   Developer Account or API approval.

Option 2 was explicitly considered and **rejected** for this project:
- it violates WhatsApp's Terms of Service and risks the number being banned;
- it is unsupported and can silently break on any WhatsApp protocol change;
- it requires holding a persistent authenticated session with a personal/business number
  inside project infrastructure — a trust and audit posture inconsistent with §4 of this
  document;
- "we found a workaround" is not a substitute for the organizational security review in
  §4.7.

The WhatsApp Business app number is therefore held in reserve for the official Cloud API
migration only. Until that migration happens, the Agent's 1:1 channel remains Telegram.


---

## 5. Technology Stack

Core
- Messaging adapter layer (Telegram Bot API active; WhatsApp Cloud API as a future adapter)
- n8n self-hosted
- PostgreSQL
- pgvector
- Redis
- Docker / Docker Compose
- TypeScript for deterministic logic and n8n Code nodes

AI

Use a configurable multi-provider model registry.

Example tiers:

**Tier 0 — No LLM**
Use for:
- cache hits;
- deterministic commands;
- simple validation;
- budget checks;
- routing rules when possible;
- sensitive-data pattern matching.

**Tier 1 — Cheap / Fast**
Use for:
- classification;
- simple Q&A;
- podcast lookup;
- formatting;
- onboarding;
- weekly digest drafting.

Examples may include Gemini Flash-class or GPT-mini-class models.

**Tier 2 — Advanced**
Use only when justified:
- difficult technical analysis;
- evaluator;
- prompt improvement proposal;
- complex synthesis.

The exact model names must be configurable. Do not hardcode obsolete model names into the
architecture.


---

## 6. Architecture

```text
┌───────────────────────────┐
│ Human WhatsApp Community │
│ Announcements + Sandbox │
│ Human controlled │
└─────────────┬─────────────┘
│
weekly draft
│
v
┌────────────┐
│ ADMIN │
│ human gate │
└─────┬──────┘
│ manual post
v
Community Group

User
|
v
Telegram (MVP) / WhatsApp (future)
|
v
Messaging Provider API
|
v
Reverse Proxy / HTTPS
|
v
n8n Webhook
|
+--> Idempotency / Redis
|
+--> Rate Limit / Redis
|
+--> Security Classification
|
+--> Sensitive-Data Detection --> flagged --> Admin Alert + Audit Log
|
+--> Semantic Cache
| |
| +--> HIT ----> Send response
|
+--> Intent Router
|
+--> Knowledge Retrieval
| |
| v
| PostgreSQL + pgvector
|
+--> Budget Guard
|
+--> Model Selection
|
+--> Generation
|
+--> Response Validation
|
+--> Send via Messaging Adapter
|
+--> Telemetry
|
v
PostgreSQL

Async:
Loop 3 --> Evaluator --> Candidate Prompt --> Golden Eval --> Human Approval
Loop 4 --> Weekly Analytics --> Budget/Knowledge Recommendations --> Human
```


---

## 7. Database Design

### 7.1 users

Fields:
- platform_user_id PK
- platform (telegram | whatsapp)
- display_name
- preferred_language
- interaction_count
- first_seen_at
- last_seen_at
- status
- created_at
- updated_at

### 7.2 knowledge_base

Fields:
- id
- category
- title
- url
- summary_he
- summary_en
- source_type
- trust_level
- embedding
- status
- created_at
- updated_at

Categories:
- basics
- agi
- ai_tools
- dev_tools
- automation
- testing
- architecture
- news
- podcasts
- other

The knowledge base is curated.
The Agent may propose new entries, but should not silently publish them.

### 7.3 system_prompts

Fields:
- id
- version_tag
- role_description
- prompt_text
- few_shot_examples
- is_active
- created_by
- created_at

Only one production prompt version can be active.
Never delete historical versions.

### 7.4 interaction_logs

Fields:
- id
- session_id
- platform_user_id
- platform
- user_query
- agent_response
- routed_model
- input_tokens
- output_tokens
- cached_input_tokens
- cost_usd
- feedback_score
- needs_review
- cache_hit
- intent
- security_classification
- sensitive_data_flagged
- sensitive_data_category
- prompt_version_id
- retrieved_kb_ids
- created_at

Knowledge and prompt references may be JSONB because one answer can use multiple KB
records.

### 7.5 webhook_events

Fields:
- platform_message_id PK
- platform
- received_at
- processed
- processing_status
- error_code
- created_at

Purpose: prevent duplicate processing across any connected platform.

### 7.6 message_templates

Fields:
- id
- template_name
- platform
- purpose
- language
- approval_status
- last_synced_at

Examples:
- onboarding
- admin_alert
- weekly_digest_nudge
- budget_alert
- sensitive_data_redirect

### 7.7 model_registry

Recommended addition.

Fields:
- id
- provider
- model_name
- tier
- input_price_per_1m_tokens
- output_price_per_1m_tokens
- cached_input_price_per_1m_tokens
- effective_from
- enabled
- max_context
- created_at

Never hardcode model prices in workflow code.
This makes cost calculation auditable and changeable without rewriting workflows.

### 7.8 budget_policy

Recommended addition.

Fields:
- monthly_budget_usd
- daily_budget_usd
- warning_threshold
- hard_stop_threshold
- cheap_model_policy
- updated_at

### 7.9 evaluation_cases

Recommended addition.

Fields:
- id
- category
- question
- expected_behavior
- expected_language
- severity
- active
- created_at

This is the golden-question set required to safely operate LDD. Must include sensitive-data
/ secret-leak attempt cases (see ARCHITECTURE-FLOWS.md §16).

### 7.10 prompt_change_proposals

Recommended addition.

Fields:
- id
- current_prompt_id
- proposed_prompt
- proposed_examples
- rationale
- source_interactions
- evaluation_score
- status
- approved_by
- created_at

This creates an explicit audit trail between learning and activation.

### 7.11 sensitive_data_events (new)

Fields:
- id
- platform_user_id
- category
- detector
- redacted_excerpt
- action_taken
- admin_notified
- created_at

A dedicated, append-only audit trail — separate from interaction_logs — for every time the
sensitive-data detector fires. Never used as LDD training signal.


---

## 8. LDD — Loop-Driven Development

LDD is the central architectural idea.

The Agent should not simply answer questions.
It should continuously create evidence about:
- what people ask;
- what content they need;
- which answers fail;
- which models are unnecessarily expensive;
- what topics are missing;
- how language preferences evolve;
- which prompts work better.

But learning must be controlled, and must never touch sensitive-data handling logic without
explicit human review — that logic is treated as a security control, not a tunable behavior.


---

## 9. Loop 1 — Execution Loop

Real-time path:
```text
Incoming message
|
Idempotency
|
Rate limit
|
Security classification
|
Sensitive-data detection
|
Semantic cache
|
Intent routing
|
RAG
|
Budget guard
|
Model selection
|
Generation
|
Output validation
|
Send via messaging adapter
|
Telemetry
```

**Cache**

Use semantic caching carefully.
A cache hit should require:
- sufficiently high similarity;
- same language;
- same intent;
- same knowledge freshness;
- no personalized context;
- no time-sensitive question.

Start conservatively.
Do not assume 0.93 is universally safe.
Make the threshold configurable and validate it using evaluation data.


---

## 10. Loop 2 — Telemetry & Feedback

Collect:
- query;
- response;
- model;
- token usage;
- actual cost;
- latency;
- cache hit;
- intent;
- language;
- RAG documents;
- feedback;
- security classification;
- sensitive-data flag;
- prompt version;
- platform.

Feedback sources:

**Explicit**
- 👍
- 👎
- optional command such as `feedback 1` / `feedback 0`

Do not assume every messaging platform exposes every reaction event identically. Implement
reactions only where supported (Telegram and WhatsApp differ here) and retain an explicit
fallback command-based path that works on both.

**Implicit**
Examples:
- repeated near-identical question;
- immediate correction;
- user asks ”לא הבנתי”;
- user asks for a better explanation.

Implicit signals should create a review signal, not automatically prove failure.


---

## 11. Loop 3 — Meta-Learning

Run nightly.

**Input**

Select:
- 👎 interactions;
- repeated questions;
- flagged responses;
- security false positives;
- low-confidence RAG results.

Explicitly excluded: sensitive_data_events. Those are security incidents, reviewed only by a
human administrator, never fed into prompt-improvement evaluation.

**Evaluator**

The evaluator receives sanitized interaction examples.
It must output structured JSON:
```json
{
"problem": "...",
"root_cause": "...",
"proposed_prompt_change": "...",
"new_examples": [],
"expected_benefit": "...",
"risk": "...",
"confidence": 0.0
}
```

**Important**

The evaluator must never activate its own changes.

**Flow:**
```text
**Evaluator**
|
Candidate
|
Golden Evaluation
|
+--> fail --> reject
|
+--> pass --> Human Approval
|
+------+------+
| |
approve reject
|
activate
```

This is the safe definition of "self-improving" for v1.


---

## 12. Loop 4 — Knowledge + Cost Optimization

Run weekly.

Produce:
- top topics;
- unanswered questions;
- missing knowledge;
- most useful content;
- cache-hit rate;
- model distribution;
- token consumption;
- monthly spend;
- projected monthly spend;
- negative feedback;
- security blocks;
- sensitive-data incident count (aggregate only, no content).

The Agent sends the administrator a digest.

The administrator can:
- add KB items;
- reject suggestions;
- approve content;
- adjust budget;
- review model routing;
- review sensitive-data incidents.


---

## 13. Dynamic Cost Control

Cost management must be a first-class feature.

**Cost hierarchy**
```text
1. Deterministic answer $0
2. Exact/semantic cache $0
3. Cheap model low
4. Advanced model higher
```

Budget states

**NORMAL**
All configured routing is allowed.

**WARNING**
Prefer Tier 1.
Avoid unnecessary Tier 2 calls.

**RESTRICTED**
Tier 2 disabled except for administrator-approved workflows.

**HARD STOP**
No paid generation.
Return a short safe message.

**Cost calculation**

Use actual provider usage whenever available.
Calculate:
```text
input_cost
+ cached_input_cost
+ output_cost
= actual_cost
```
Never use a guessed "average cost per message" for accounting.


---

## 14. Language Strategy

The community should primarily communicate in Hebrew.
This is an adoption decision.

The Agent:
- mirrors the user's language;
- uses Hebrew when the user writes Hebrew;
- uses English when the user writes English;
- keeps standard technical terms in English.

Example:
אפשר להשתמש ב-`RAG` כדי לתת ל-Agent גישה ל-Knowledge Base בלי לאמן את המודל.

Technical terminology should remain in English:
- Agent
- Prompt
- LLM
- RAG
- Context Window
- Embedding
- Vector DB
- Workflow
- Evaluation
- Guardrail
- Router

Do not force English onto users.
The goal is to expose them gradually to the terminology used outside the organization without
making the community feel inaccessible. This is identical on Telegram and WhatsApp.


---

## 15. Agent Skills

Implement skills as explicit capabilities rather than one huge prompt.

#### Skill 1 — Podcast Finder
Find:
- beginner AI podcasts;
- advanced AI/AGI podcasts;
- developer AI podcasts;
- Copilot content;
- Claude content;
- automation;
- testing.

#### Skill 2 — AI Basics
Explain:
- LLM;
- token;
- embedding;
- RAG;
- Agent;
- tool calling;
- context window;
- prompt engineering.

#### Skill 3 — Development with AI
Discuss:
- Copilot;
- Claude;
- AI-assisted coding;
- testing;
- automation;
- code review;
- architecture.

#### Skill 4 — Innovation Radar
Surface:
- new tools;
- important trends;
- interesting research;
- industry shifts.

#### Skill 5 — Community Content Curator
Prepare weekly content drafts.

#### Skill 6 — Knowledge Gap Detector
Identify topics the KB does not cover.

#### Skill 7 — Feedback Analyzer
Analyze negative feedback.

#### Skill 8 — Cost Optimizer
Analyze model usage and propose routing changes.

#### Skill 9 — Security Guard
Block unsafe requests and sensitive information; this skill owns the sensitive-data detection
step and is treated as a security control, not a normal skill subject to LDD tuning.

#### Skill 10 — Language/Formatting
Produce readable messages in Hebrew/English, formatted appropriately for the active platform
(Telegram Markdown vs WhatsApp formatting differ slightly — the adapter layer handles this).


---

## 16. Admin Agent Capabilities

The administrator should have a separate control surface through 1:1 messages (Telegram for
MVP).

Examples:
```text
/status
/cost
/weekly
/gaps
/pending
/prompts
/approve 123
/reject 123
/rollback
/incidents
```

`/incidents` (new) — lists recent sensitive-data events for review.

Do not make destructive commands easy to trigger accidentally.
Require confirmation for:
- prompt activation;
- rollback;
- budget changes;
- deletion.


---

## 17. Message Design

Messages should be short enough for mobile, on either platform.

Example weekly draft (posted by the admin into the WhatsApp Community):
```text
🚀 *This Week in AI*

🎧 *Podcast*
Why Agents are becoming the new interface
2–3 sentence Hebrew summary.

🛠 *Developer*
A practical look at AI-assisted development with Copilot.

🧠 *Think About It*
What changes when software can plan before it codes?

💬 *Question of the Week*
What AI capability would save you the most time?

Reply to the Agent anytime if you want recommendations.
```
Do not overuse emojis.


---

## 18. Onboarding

First DM (sent by the Telegram bot for MVP; identical content if/when WhatsApp is added):
```text
היי 👋
אני ה-Agent AI של קהילת ה-AI והחדשנות.
המטרה שלי היא לעזור לך:
• לגלות מה חדש בעולם ה-AI
• למצוא Podcasts וכתבות
• להבין מושגים וכלים
• לקבל רעיונות ל-Automation ו-Development
• למצוא תוכן שמתאים לרמה שלך

אפשר לכתוב לי בעברית או באנגלית.

⚠️ חשוב:
אל תשלחו לי מידע מסווג, קוד פנימי, credentials, או מידע רגיש של החברה.
הודעות כאלה נחסמות אוטומטית ולא מגיעות למודל.

אפשר פשוט לשאול:
"אני מתחיל ב-AI, מאיפה להתחיל?"
```

The exact message should be stored/configured, not hardcoded into workflow logic.


---

## 19. Out-of-Scope Behavior

The Agent should politely refuse:
- internal corporate information;
- personnel issues;
- politics;
- classified information;
- credentials;
- proprietary code;
- unrelated personal assistance;
- requests to bypass security.

The refusal should be short and redirect to the community's scope.


---

## 20. Error Handling

Every external dependency needs:
- timeout;
- retry;
- exponential backoff;
- maximum retry count;
- dead-letter path;
- admin alert.

Dependencies:
- Messaging platform API (Telegram now, WhatsApp later);
- LLM APIs;
- PostgreSQL;
- Redis.

Never silently drop an interaction.


---

## 21. Observability

Minimum dashboard:
- messages/day;
- unique users;
- cache-hit rate;
- model mix;
- input tokens;
- output tokens;
- cost/day;
- cost/month;
- projected monthly cost;
- latency;
- 👎 rate;
- unanswered questions;
- security blocks;
- sensitive-data incidents (count + category, never content);
- errors;
- breakdown by platform, once more than one adapter is active.

The dashboard can initially be a PostgreSQL/Metabase view or another lightweight internal
reporting mechanism.


---

## 22. Backup & Recovery

PostgreSQL:
- daily backup;
- retention policy;
- test restore periodically;
- store backups outside the primary container/volume;
- never store database credentials inside backup metadata.

Redis:
- treat as disposable cache;
- do not make Redis the source of truth.

PostgreSQL is the system of record.


---

## 23. Deployment Topology

For a real webhook endpoint:
```text
Internet
|
Telegram Bot API (MVP) / WhatsApp Cloud API (future)
|
HTTPS
|
Reverse Proxy
|
n8n
|
+-- PostgreSQL
+-- Redis
|
+-- OpenAI / Google / Anthropic
```

A laptop is suitable for local development and webhook testing.
Production webhooks require a reachable HTTPS endpoint, on either platform.

For the personal POC, do not expose a production-like service containing sensitive company
information from a personal machine/server.


---

## 24. Development Phases

Cursor must work sequentially.

#### Phase 0 — Architecture & Threat Model
Deliver:
- ADRs;
- trust boundaries;
- data-flow diagram;
- threat model;
- assumptions;
- MVP scope;
- explicit note that the messaging adapter is abstracted (Telegram active, WhatsApp future).

#### Phase 1 — Infrastructure
Create:
- Docker Compose;
- n8n;
- PostgreSQL + pgvector;
- Redis;
- reverse proxy configuration;
- .env.example;
- .gitignore;
- health checks.

#### Phase 2 — Database
Create:
- init.sql;
- migrations;
- indexes;
- triggers;
- model registry;
- budget policy;
- evaluation cases;
- sensitive_data_events table.

#### Phase 3 — Messaging Pipe (Telegram)
Build:
- Telegram webhook verification (via BotFather-issued token);
- inbound message parsing behind the adapter interface;
- idempotency;
- outbound message;
- minimal echo bot.

Do not add AI yet. Do not hardcode Telegram specifics outside the adapter module.

#### Phase 4 — Agent Core
Add:
- language detection;
- security classification;
- sensitive-data detection;
- intent router;
- RAG;
- semantic cache;
- budget guard;
- generation.

#### Phase 5 — Prompt System
Create:
- Base Prompt;
- Router Prompt;
- Evaluator Prompt;
- Digest Prompt;
- Security Prompt;
- Sensitive-Data Detection Prompt/rules.

Store versions in the database.

#### Phase 6 — LDD
Build:
- telemetry;
- feedback;
- evaluator;
- golden-question evaluation;
- human approval;
- rollback.

#### Phase 7 — Weekly Community Automation
Build:
- weekly digest;
- knowledge gap report;
- cost report;
- admin alerts.
Posting target remains the WhatsApp Community, via manual admin action.

#### Phase 8 — Pilot
Start with 3–5 trusted users on Telegram.
Measure:
- usefulness;
- accuracy;
- cost;
- adoption;
- security behavior;
- sensitive-data incidents.

#### Phase 9 — Expansion
Only after evidence:
- larger user group;
- additional knowledge;
- more skills;
- more model providers;
- WhatsApp Cloud API adapter, once Meta Developer Account access is available;
- possible enterprise integration.


---

## 25. Definition of Done — MVP

The MVP is complete when:
1. A user can DM the Agent (on Telegram).
2. Webhook delivery works reliably.
3. Duplicate messages are not processed twice.
4. Rate limiting works.
5. The security boundary works.
6. Sensitive-data detection works and reliably alerts the admin.
7. Hebrew/English mirroring works.
8. The Agent can search the curated KB.
9. Responses use the correct model tier.
10. Cost is recorded from actual usage.
11. Monthly budget is enforced.
12. Cached answers avoid unnecessary LLM calls.
13. Every interaction is logged.
14. Feedback can be captured.
15. Loop 3 produces proposals but cannot silently activate them.
16. Golden evaluation exists, including sensitive-data test cases.
17. Prompt rollback exists.
18. Weekly digest is generated.
19. The human administrator can copy the digest into the WhatsApp Community.
20. No sensitive corporate data is required for the MVP.
21. Failure paths are observable.
22. The messaging adapter is cleanly swappable — adding WhatsApp Cloud API later
    requires no changes below the webhook layer.


---

## 26. What Cursor Must NOT Do

Do not:
- build a bot inside the large WhatsApp Community;
- assume WhatsApp groups (or Telegram groups) work like Slack;
- auto-activate self-improving prompts without evaluation;
- put secrets in source code;
- rely on regex alone for data-loss prevention or sensitive-data detection;
- hardcode provider prices;
- hardcode model names throughout the workflow;
- hardcode the messaging platform outside the adapter layer;
- make Redis the source of truth;
- silently retry forever;
- expose internal company data to external LLMs;
- create autonomous posting into the WhatsApp Community in v1;
- fold sensitive-data events into normal telemetry or LDD training signal;
- generate the entire project in one step.


---

## 27. Cursor Operating Instructions

You are the implementation agent.

Rules:
1. Read this entire document before coding.
2. Inspect the repository before creating files.
3. Preserve existing project conventions.
4. Work phase by phase.
5. Do not skip validation.
6. Explain architectural decisions before major changes.
7. Generate tests for deterministic logic.
8. Never invent credentials.
9. Never print secrets.
10. Never activate a prompt change automatically.
11. Keep all behavior configurable.
12. Prefer small composable n8n workflows/sub-workflows.
13. Keep security logic deterministic wherever possible.
14. Keep LLMs responsible for reasoning, not authorization.
15. Treat every external input as untrusted.
16. Implement the messaging platform strictly behind an adapter interface; Telegram is the
    concrete implementation for the MVP, WhatsApp Cloud API is a future adapter, and no
    downstream logic may depend on which one is active.
17. Ask for confirmation before moving to the next phase.

Start with Phase 0: Architecture & Threat Model, then stop.
