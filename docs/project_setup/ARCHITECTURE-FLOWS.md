System Architecture, Schema & Flows - Self-Improving AI Community Agent
Companion to: PROJECT-SPEC.md
Purpose: visual and technical reference for Cursor
Status: Updated after Meta Developer Account SMS-verification blocker - Agent channel decoupled from WhatsApp

## 0. Channel Decision (Update)

Two separate, independent surfaces exist in this system. They do **not** share an onboarding
path, an API, or a blocker:

```text
SURFACE 1 - Human Community           SURFACE 2 - Agent (1:1 assistant)
WhatsApp Community                    Telegram Bot (primary, MVP)
Created via regular WhatsApp app      Created via @BotFather
(NOT WhatsApp Business app -          No Meta Developer Account needed
 Communities unsupported there)       No SMS verification needed
Owned by a trusted household          WhatsApp Cloud API (future/optional,
member's regular account, with        once Meta Developer Account unblocks,
project owner added as full admin     using the WhatsApp Business number)
No Meta Developer Account needed
No SMS verification needed
Human-administered, always
```

Rationale: the Meta Developer Account SMS-verification flow blocked creation of a WhatsApp
Business number for the Agent. That blocker has **no effect** on creating a WhatsApp
Community - Communities are a native WhatsApp-app feature with no developer/API dependency.
Separately, WhatsApp Communities are not available inside the WhatsApp Business app at all
(a platform limitation, not a blocker) - so the Community is created from a regular WhatsApp
account, with the project owner added as a full admin immediately after creation for
continuity of control. The Agent side is rebuilt around a **messaging-adapter abstraction**,
with Telegram Bot API as the concrete adapter for the MVP, and WhatsApp Cloud API as a second
adapter to be added later without touching any downstream logic (security, RAG, cost
routing, LDD).

This means: build and validate the entire system now. Swap or add the WhatsApp Cloud API
adapter later as a drop-in, once Meta unblocks - it changes one node group in n8n, nothing else.

## 1. Core Architecture

```mermaid
flowchart TB
subgraph COMMUNITY["Human WhatsApp Community"]
ANN["Announcements\nHuman Admin"]
SANDBOX["Sandbox / Discussion\nHuman Admin"]
end
subgraph AGENT["Agent Surface"]
USER["Employee"]
DM["1:1 Chat\nAgent Bot"]
end
subgraph PROVIDER["Messaging Provider (adapter)"]
TG["Telegram Bot API\n(active, MVP)"]
WA["WhatsApp Cloud API\n(future adapter, blocked pending\nMeta Developer Account)"]
end
subgraph EDGE["Public HTTPS Edge"]
RP["Reverse Proxy / TLS"]
end
subgraph N8N["n8n"]
WH["Webhook"]
IDEM["Idempotency"]
RATE["Rate Limit"]
SEC["Security Classification"]
SENSDET["Sensitive-Data Detector\n(secrets / PII / classified markers)"]
CACHE["Semantic Cache"]
ROUTER["Intent / Complexity Router"]
RAG["RAG"]
BUDGET["Budget Guard"]
MODEL["Model Selector"]
GEN["Generation"]
VALID["Response Validator"]
SEND["Send"]
LOG["Telemetry"]
ALERT["Admin Alert"]
end
subgraph DATA["Data"]
PG[("PostgreSQL + pgvector")]
REDIS[("Redis")]
end
subgraph LLM["LLM Providers"]
T1["Tier 1\nCheap/Fast"]
T2["Tier 2\nAdvanced"]
end
subgraph LDD["Async LDD"]
EVAL["Loop 3\nEvaluator"]
GOLD["Golden Evaluation"]
APPROVAL["Human Approval"]
OPT["Loop 4\nWeekly Optimizer"]
end
USER <--> DM
DM <--> TG
DM -.future.-> WA
TG --> RP
WA -.future.-> RP
RP --> WH
WH --> IDEM
IDEM --> RATE
RATE --> SEC
SEC --> SENSDET
SENSDET -->|flagged| ALERT
SENSDET -->|clean| CACHE
ALERT --> LOG
CACHE -->|hit| SEND
CACHE -->|miss| ROUTER
ROUTER --> RAG
RAG --> PG
RAG --> BUDGET
BUDGET --> MODEL
MODEL --> T1
MODEL --> T2
T1 --> GEN
T2 --> GEN
GEN --> VALID
VALID --> SEND
SEND --> TG
SEND -.future.-> WA
SEND --> LOG
LOG --> PG
IDEM <--> REDIS
RATE <--> REDIS
CACHE <--> REDIS
CACHE <--> PG
EVAL --> PG
EVAL --> GOLD
GOLD --> APPROVAL
APPROVAL --> PG
OPT --> PG
OPT --> APPROVAL
APPROVAL --> ANN
APPROVAL --> SANDBOX
```

Hard boundary (unchanged)
The Agent does not post directly into ANN or SANDBOX, regardless of which messaging adapter
it uses.
The administrator is the publication gate.

Adapter boundary (new)
The Messaging Provider subgraph is the only place channel-specific code lives. Everything
below the `WH["Webhook"]` node is channel-agnostic - it must never contain Telegram- or
WhatsApp-specific logic. n8n implements this as a small "normalize inbound message" /
"format outbound message" sub-workflow pair per adapter, both producing/consuming the same
internal message shape.

## 2. Trust Boundaries

```text
TRUST BOUNDARY A
User / Messaging App (Telegram now, WhatsApp later)
|
v
-------------------------------
External Messaging Boundary
-------------------------------
|
v
n8n
|
+----------------------+
| |
v v
PostgreSQL Redis
|
v
-------------------------------
External AI Boundary
-------------------------------
|
+--> Tier 1 Provider
|
+--> Tier 2 Provider
```

Security classification, and now the sensitive-data detector, must both complete before
crossing the external AI boundary - independent of which messaging boundary the message
arrived through.

## 3. Database ERD

```mermaid
erDiagram
USERS {
string platform_user_id PK
string platform
string display_name
string preferred_language
int interaction_count
timestamp first_seen_at
timestamp last_seen_at
string status
timestamp created_at
timestamp updated_at
}
KNOWLEDGE_BASE {
uuid id PK
string category
string title
string url
text summary_he
text summary_en
string source_type
string trust_level
vector embedding
string status
timestamp created_at
timestamp updated_at
}
SYSTEM_PROMPTS {
uuid id PK
string version_tag
text role_description
text prompt_text
jsonb few_shot_examples
boolean is_active
string created_by
timestamp created_at
}
INTERACTION_LOGS {
uuid id PK
string session_id
string platform_user_id FK
string platform
text user_query
text agent_response
string routed_model
int input_tokens
int output_tokens
int cached_input_tokens
numeric cost_usd
smallint feedback_score
boolean needs_review
boolean cache_hit
string intent
string security_classification
boolean sensitive_data_flagged
string sensitive_data_category
uuid prompt_version_id
jsonb retrieved_kb_ids
timestamp created_at
}
WEBHOOK_EVENTS {
string platform_message_id PK
string platform
timestamp received_at
boolean processed
string processing_status
string error_code
timestamp created_at
}
MESSAGE_TEMPLATES {
uuid id PK
string template_name
string platform
string purpose
string language
string approval_status
timestamp last_synced_at
}
MODEL_REGISTRY {
uuid id PK
string provider
string model_name
string tier
numeric input_price_per_1m
numeric output_price_per_1m
numeric cached_input_price_per_1m
timestamp effective_from
boolean enabled
}
BUDGET_POLICY {
uuid id PK
numeric monthly_budget_usd
numeric daily_budget_usd
numeric warning_threshold
numeric hard_stop_threshold
string cheap_model_policy
timestamp updated_at
}
EVALUATION_CASES {
uuid id PK
string category
text question
text expected_behavior
string expected_language
string severity
boolean active
}
PROMPT_CHANGE_PROPOSALS {
uuid id PK
uuid current_prompt_id
text proposed_prompt
jsonb proposed_examples
text rationale
jsonb source_interactions
numeric evaluation_score
string status
string approved_by
timestamp created_at
}
SENSITIVE_DATA_EVENTS {
uuid id PK
string platform_user_id FK
string category
string detector
text redacted_excerpt
string action_taken
boolean admin_notified
timestamp created_at
}
USERS ||--o{ INTERACTION_LOGS : sends
SYSTEM_PROMPTS ||--o{ INTERACTION_LOGS : "used by"
KNOWLEDGE_BASE ||--o{ INTERACTION_LOGS : "retrieved by"
USERS ||--o{ SENSITIVE_DATA_EVENTS : triggers
```

Changes from the original design:
- `whatsapp_id` renamed to `platform_user_id` with a companion `platform` column
  (`telegram` | `whatsapp`), everywhere it appeared, so the schema is channel-agnostic.
- New `SENSITIVE_DATA_EVENTS` table: a dedicated, append-only log of every time the
  sensitive-data detector fires, separate from general interaction telemetry, so it can be
  reviewed/audited on its own and never silently mixed into normal logs.
- `INTERACTION_LOGS` gains `sensitive_data_flagged` and `sensitive_data_category` so the
  detector's verdict is visible directly on the interaction row too.

knowledge_base and prompt relationships in interaction_logs remain logical references stored
as IDs/JSONB because one response may use multiple KB records.

## 4. Loop 1 - Real-Time Sequence

```mermaid
sequenceDiagram
participant U as User
participant PLAT as Messaging Platform
participant N8N as n8n
participant R as Redis
participant PG as PostgreSQL
participant T1 as Tier 1
participant T2 as Tier 2
participant AD as Admin
U->>PLAT: 1:1 message
PLAT->>N8N: webhook
N8N->>R: idempotency check
alt duplicate
N8N-->>PLAT: 200 OK / no-op
else new event
N8N->>R: rate limit check
alt over limit
N8N->>PLAT: throttle response
else allowed
N8N->>N8N: security classification
alt blocked
N8N->>PLAT: safe refusal
N8N->>PG: security telemetry
else allowed
N8N->>N8N: sensitive-data detection
alt flagged
N8N->>PLAT: safe refusal / redirect
N8N->>PG: sensitive_data_events row
N8N->>AD: admin alert
else clean
N8N->>PG: semantic cache lookup
alt cache hit
N8N->>PLAT: cached answer
N8N->>PG: log cache_hit=true, cost=0
else cache miss
N8N->>T1: classify intent
T1-->>N8N: intent + complexity
N8N->>PG: RAG similarity search
PG-->>N8N: relevant KB
N8N->>PG: budget check
alt restricted budget
N8N->>T1: cheap-tier generation
else normal budget
alt simple
N8N->>T1: generate
else complex
N8N->>T2: generate
end
end
T1-->>N8N: response + usage
T2-->>N8N: response + usage
N8N->>N8N: validate output
N8N->>PLAT: send response
N8N->>PG: log interaction
end
end
end
end
end
```

## 5. State Machine - User Message

```mermaid
stateDiagram-v2
[*] --> Received
Received --> DuplicateCheck
DuplicateCheck --> Discarded: duplicate
DuplicateCheck --> RateLimitCheck: new
RateLimitCheck --> Throttled: limit exceeded
RateLimitCheck --> SecurityCheck: allowed
SecurityCheck --> Blocked: unsafe
SecurityCheck --> SensitiveDataCheck: allowed
SensitiveDataCheck --> Flagged: secret/PII/classified detected
SensitiveDataCheck --> CacheCheck: clean
CacheCheck --> CacheHit: safe high-confidence match
CacheCheck --> Routing: miss
Routing --> RAG
RAG --> BudgetCheck
BudgetCheck --> Restricted: budget warning/limit
BudgetCheck --> Generating: normal
Restricted --> GeneratingCheap
Generating --> Validating
GeneratingCheap --> Validating
Validating --> Sent: valid
Validating --> Fallback: invalid
Fallback --> Sent
CacheHit --> Sent
Sent --> Logged
Logged --> AwaitingFeedback
AwaitingFeedback --> FeedbackReceived: explicit feedback
AwaitingFeedback --> [*]: timeout
FeedbackReceived --> ReviewFlagged: negative/ambiguous
FeedbackReceived --> [*]: positive
ReviewFlagged --> Loop3Queue
Loop3Queue --> [*]
Blocked --> Logged
Flagged --> AdminAlerted
AdminAlerted --> Logged
Throttled --> Logged
Discarded --> [*]
```

## 6. Loop 2 - Telemetry & Feedback

```mermaid
flowchart LR
MSG["Agent Interaction"] --> LOG["Interaction Log"]
FEEDBACK["👍 / 👎 / explicit feedback"] --> MATCH["Match Agent Message"]
MATCH --> LOG
REPEAT["Repeated near-duplicate query"] --> SIGNAL["Implicit Failure Signal"]
SIGNAL --> LOG
SENSDET["Sensitive-Data Event"] --> SLOG["Sensitive Data Log"]
SLOG --> ADMINFEED["Admin Notification"]
LOG --> REVIEW{"Needs Review?"}
REVIEW -->|No| END1["No action"]
REVIEW -->|Yes| L3["Loop 3 queue"]
```

Important:
Implicit feedback is evidence, not proof. Sensitive-data events are never fed into Loop 3 as
training signal - they go to the admin only, kept in a separate audit trail.

## 7. Loop 3 - Meta-Learning

```mermaid
sequenceDiagram
participant C as Nightly Cron
participant PG as PostgreSQL
participant E as Evaluator LLM
participant G as Golden Eval
participant A as Admin
participant P as Prompt Store
C->>PG: Fetch negative/review interactions
PG-->>C: sanitized batch
C->>E: Evaluate failures
E-->>C: structured proposal
C->>P: Store candidate as inactive
C->>G: Run candidate against golden questions
G-->>C: evaluation result
alt failed
C->>P: Mark candidate eval_failed
C->>A: Notify failure
else passed
C->>A: Request approval
alt approved
A->>C: approve
C->>P: activate candidate
C->>P: deactivate old version
else rejected
A->>C: reject
C->>P: keep candidate inactive
end
end
```

The evaluator cannot activate itself.

## 8. Prompt Lifecycle

```mermaid
stateDiagram-v2
[*] --> Drafted
Drafted --> PendingApproval
PendingApproval --> Evaluation
Evaluation --> EvalFailed
Evaluation --> AwaitingHumanApproval: passed
AwaitingHumanApproval --> Rejected
AwaitingHumanApproval --> Active: approved
Active --> Superseded: newer prompt activated
Rejected --> [*]
EvalFailed --> [*]
Superseded --> [*]
```

Never delete historical prompt versions.

## 9. Loop 4 - Weekly Optimization

```mermaid
sequenceDiagram
participant C as Weekly Cron
participant PG as PostgreSQL
participant G as Digest Generator
participant A as Admin
participant GROUP as WhatsApp Community
C->>PG: Aggregate week
PG-->>C: topics, gaps, costs, feedback
C->>G: Generate digest
G-->>C: Hebrew draft
C->>PG: Calculate MTD spend
C->>PG: Calculate projected spend
alt projected over budget
C->>PG: Apply safe routing policy
C->>A: Budget alert
end
C->>A: Weekly digest + knowledge gaps
A->>GROUP: Manual post
A->>PG: Optional KB additions
```

Note: the weekly digest is posted into the WhatsApp Community regardless of which platform
the Agent itself runs on - the Community stays WhatsApp-native at all times.

## 10. Cost Routing

```mermaid
flowchart TD
A["Incoming Query"] --> B{"Cache hit?"}
B -->|Yes| C["Return cached\n$0 LLM cost"]
B -->|No| D{"Security allowed?"}
D -->|No| E["Safe refusal"]
D -->|Yes| D2{"Sensitive data detected?"}
D2 -->|Yes| E2["Safe refusal + admin alert"]
D2 -->|No| F{"Budget state?"}
F -->|Hard Stop| G["No paid model\nfallback message"]
F -->|Restricted| H["Tier 1 only"]
F -->|Normal| I{"Complexity?"}
I -->|Simple| J["Tier 1"]
I -->|Complex| K["Tier 2"]
H --> L["Generate"]
J --> L
K --> L
L --> M["Actual usage"]
M --> N["Cost calculation"]
N --> O["Telemetry"]
```

## 11. Deployment Topology

```mermaid
flowchart LR
subgraph INTERNET["Public Internet"]
TG["Telegram Bot API\n(active)"]
WA["WhatsApp Cloud API\n(future)"]
LLM1["LLM Provider 1"]
LLM2["LLM Provider 2"]
end
subgraph HOST["Approved Host / VPS for POC"]
RP["Reverse Proxy + HTTPS"]
N8N["n8n"]
PG["PostgreSQL + pgvector"]
REDIS["Redis"]
end
TG -->|HTTPS webhook| RP
WA -.future HTTPS webhook.-> RP
RP --> N8N
N8N --> PG
N8N --> REDIS
N8N -->|outbound| TG
N8N -.future outbound.-> WA
N8N -->|outbound| LLM1
N8N -->|outbound| LLM2
```

A laptop may be used for development.
A production webhook requires a publicly reachable HTTPS endpoint - true for both Telegram
Bot API and WhatsApp Cloud API.

## 12. Failure Paths

```mermaid
flowchart TD
A["External API Call"] --> B{"Success?"}
B -->|Yes| C["Continue"]
B -->|No| D{"Retryable?"}
D -->|Yes| E["Exponential Backoff"]
E --> F{"Retries Remaining?"}
F -->|Yes| A
F -->|No| DLQ["Dead Letter / Failure Log"]
D -->|No| DLQ
DLQ --> ADMIN["Admin Alert"]
```

## 13. Security Flow (Updated)

```mermaid
flowchart TB
A["User Message"] --> B["Normalize"]
B --> C["Classify Data"]
C -->|CLASSIFIED| X["Block"]
C -->|SENSITIVE| X
C -->|INTERNAL| Y["Block in MVP"]
C -->|PUBLIC| C2["Sensitive-Data Detector\n(secrets, credentials, PII,\nclassification markers, ticket/employee IDs)"]
C2 -->|flagged| X2["Block + Admin Alert"]
C2 -->|clean| D["Prompt Injection Screening"]
D --> E["Scope Validation"]
E -->|Out of Scope| Z["Safe Redirect"]
E -->|Allowed| F["External LLM"]
X --> G["Security Telemetry"]
X2 --> G2["Sensitive Data Telemetry + Admin Notify"]
Z --> G
F --> H["Response Validation"]
H --> I["Send via Messaging Adapter"]
```

The sensitive-data detector is a distinct step from data classification: classification
decides whether content is allowed to leave the trust boundary; the detector specifically
looks for things a user typed that they should not have typed at all (secrets, credentials,
personal data, anything resembling classified markings), and its firing is always
admin-visible, not just logged.

## 14. Security Design Principle

Do not implement:
```text
Regex == DLP
```
Implement:
```text
Heuristics
+
Policy
+
Data classification
+
Sensitive-data detection (secrets/PII/classified markers)
+
Least privilege
+
Human review
+
Provider controls
```

The POC should remain public-data-only until the organization approves a production data-flow
architecture. This holds regardless of which messaging platform is in front of it.

## 15. Model Registry

The workflows should not contain logic like:
```text
if complex:
use claude-3.5-sonnet
```
Instead:
```text
Router
|
v
model_registry
|
+--> provider
+--> model
+--> tier
+--> pricing
+--> enabled
```
This allows model replacement without rewriting workflows.

## 16. Golden Evaluation Set

Minimum categories:
1. AI basics
2. RAG
3. Agents
4. Copilot
5. AI development
6. Podcasts
7. AGI
8. Hebrew response
9. English response
10. Heblish terminology
11. Security refusal
12. Prompt injection
13. Out-of-scope question
14. Unknown knowledge
15. Budget-restricted behavior
16. Sensitive-data / secret-leak attempt (new)

Each candidate prompt must be evaluated against the same baseline, on whichever platform the
Agent is currently running.

## 17. MVP Validation

The MVP is successful when:
```text
Telegram DM (or WhatsApp DM once available)
|
v
Webhook
|
v
Idempotency
|
v
Security Classification
|
v
Sensitive-Data Detection
|
v
Cache / Router / RAG / Budget
|
v
Response
|
v
Telemetry
|
v
Feedback
|
v
LDD proposal
|
v
Golden Eval
|
v
Human Approval
```

And the weekly output is:
```text
Agent
|
+--> weekly content
+--> knowledge gaps
+--> cost report
+--> quality report
+--> sensitive-data incident summary
|
v
Admin
|
v
WhatsApp Community (human-run, unchanged)
```
