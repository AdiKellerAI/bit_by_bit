# Data Flow

Companion to: PROJECT-SPEC.md §6, ARCHITECTURE-FLOWS.md §1 and §4.
This document annotates the diagrams already in ARCHITECTURE-FLOWS.md with explicit
trust-boundary crossings, rather than redrawing them - see that document for the full mermaid
source (§1 Core Architecture, §4 Loop 1 Real-Time Sequence).

## 1. Real-time request lifecycle, annotated

```text
User (Telegram)
  |
  |  ═══ TRUST BOUNDARY A: External Messaging Boundary ═══
  v
n8n Webhook  ─────────────────────────────────────────────  entry point; verify
  |                                                          TELEGRAM_WEBHOOK_SECRET here
  v
Idempotency (Redis)        ─ dedup on platform_message_id (webhook_events)
  |
  v
Rate Limit (Redis)         ─ per-user throttle
  |
  v
Security Classification    ─ PUBLIC/INTERNAL/SENSITIVE/CLASSIFIED decision (PROJECT-SPEC §4.4)
  |
  +--blocked--> Safe refusal + security telemetry (PostgreSQL)
  |
  v
Sensitive-Data Detection   ─ distinct step, see ADR-0003 (PROJECT-SPEC §4.2)
  |
  +--flagged--> Safe redirect + sensitive_data_events row + Admin Alert
  |
  v
Semantic Cache (Redis + PostgreSQL)
  |
  +--hit--> Send response (cost = $0)
  |
  v  (miss)
Intent / Complexity Router  ─ Tier 1 model call, cheap
  |
  v
RAG  ─────────────────────  PostgreSQL + pgvector similarity search over knowledge_base
  |
  v
Budget Guard                ─ checks budget_policy state (NORMAL/WARNING/RESTRICTED/HARD_STOP)
  |
  v
Model Selection              ─ model_registry lookup, never a hardcoded model name
  |
  |  ═══ TRUST BOUNDARY B: External AI Boundary ═══
  v
Generation (Tier 1 or Tier 2 LLM provider)
  |
  |  ═══ back across Trust Boundary B ═══
  v
Response Validation
  |
  v
Send via Messaging Adapter  ─ formats using Telegram-adapter-specific step only
  |
  |  ═══ back across Trust Boundary A ═══
  v
User (Telegram)

Telemetry: every branch above (including blocked/flagged/throttled paths) writes to
PostgreSQL - interaction_logs for normal flow, sensitive_data_events for the detector,
security telemetry for classification blocks. Nothing is silently dropped (PROJECT-SPEC §20).
```

## 2. What crosses each boundary

- **Trust Boundary A** (User ↔ n8n): raw user text, Telegram metadata (user id, message id) in;
  formatted response text out. Nothing here is trusted until it passes idempotency + rate
  limit + classification + sensitive-data detection.
- **Trust Boundary B** (n8n ↔ LLM providers): only messages that passed classification
  (PUBLIC) and sensitive-data detection (clean) reach this boundary. What crosses out is the
  generated response, plus token/cost usage metadata that comes back and is never guessed
  (PROJECT-SPEC §13).

## 3. Async loops (not part of the real-time path)

```text
Loop 3 (nightly): interaction_logs (sanitized, excludes sensitive_data_events)
  --> Evaluator --> candidate prompt (inactive) --> Golden Eval --> Human Approval --> activate

Loop 4 (weekly): aggregated interaction_logs + cost data
  --> Digest Generator --> Admin --> manual post --> WhatsApp Community
```

Both loops read from PostgreSQL only; neither has a path that writes directly to an active
system_prompts row or posts directly into the WhatsApp Community - both require the human
step shown (ADR-0004; PROJECT-SPEC §6 hard boundary: "The Agent does not post directly into
ANN or SANDBOX").

## 4. Messaging-adapter isolation

Per ADR-0001, the "Messaging Provider" subgraph in ARCHITECTURE-FLOWS.md §1 is the only place
channel-specific code lives. Everything from the `Webhook` node onward in the diagram above is
channel-agnostic - normalize-inbound and format-outbound are the only two points where a
Telegram-specific (or future WhatsApp-specific) implementation is selected.
