# Threat Model

Companion to: PROJECT-SPEC.md §4, ARCHITECTURE-FLOWS.md §2 and §13-14.
Scope: MVP (Telegram-only adapter, public-data-only POC per PROJECT-SPEC.md §4.1).

## 1. Trust boundaries

From ARCHITECTURE-FLOWS.md §2, two boundaries matter:

```text
TRUST BOUNDARY A — External Messaging Boundary
User / Telegram  --(untrusted)-->  n8n

TRUST BOUNDARY B — External AI Boundary
n8n  --(only after classification + sensitive-data detection pass)-->  LLM providers
```

Everything between the two boundaries (n8n, PostgreSQL, Redis) is inside the trust perimeter.
Both boundaries must be crossed only through the security pipeline — no code path may call an
LLM provider or accept a webhook payload without first going through the steps below.

## 2. Assets

- User messages (may contain attempted secrets/PII despite policy — see §4.2 below).
- Knowledge base content (public-only, but still a prompt-injection vector if compromised).
- System prompts / prompt versions (integrity matters — a corrupted active prompt affects
  every user).
- LLM provider API keys, database credentials, webhook secret (see PROJECT-SPEC.md §4.3).
- Interaction logs and sensitive_data_events (contain redacted excerpts, not raw secrets, but
  are still sensitive as an aggregate record of user behavior).
- Admin control surface (`/approve`, `/rollback`, budget changes — PROJECT-SPEC.md §16).

## 3. Threats by boundary crossing (STRIDE-lite)

### 3.1 Inbound webhook (Trust Boundary A)
| Threat | Control |
|---|---|
| Spoofed requests not actually from Telegram | Verify `TELEGRAM_WEBHOOK_SECRET` on every inbound webhook call before any processing (PREPARATION-CHECKLIST.md §10 "Save: TELEGRAM_WEBHOOK_SECRET"). |
| Replay / duplicate delivery | Idempotency check against `webhook_events` (keyed by `platform_message_id`) before any further processing — first node in Loop 1 (ARCHITECTURE-FLOWS.md §4). |
| Flood / spam to exhaust budget or rate | Rate limiting via Redis, second node in Loop 1, before security classification even runs. |

### 3.2 Security classification bypass
| Threat | Control |
|---|---|
| Message crafted to look PUBLIC when it's actually INTERNAL/SENSITIVE | Classification is deterministic-first where possible (PROJECT-SPEC.md §27 rule 13); Tier-2 LLM-assisted classification is a fallback, not the only line of defense. Unclear cases are flagged, not silently passed (PROJECT-SPEC.md §4.2 closing line). |
| Classification step itself unreachable/erroring | Fail closed — no LLM call proceeds if the classification step cannot render a decision (PROJECT-SPEC.md §3 principle 10, "fail safely"). |

### 3.3 Sensitive-data detector bypass (see ADR-0003)
| Threat | Control |
|---|---|
| False negative — a secret/credential/PII string not matched by current patterns | Detector patterns are living config, reviewed with security-team input, not a one-time list (PROJECT-SPEC.md §4.2). Regex is explicitly a first-pass signal only, not the full boundary (ARCHITECTURE-FLOWS.md §14). |
| False positive rate erodes trust / usability | Review cadence for false positives/negatives with the admin (PREPARATION-CHECKLIST.md §7.3) — a Phase 6+ operational concern, not solved by this phase. |
| Detected event silently dropped instead of alerting | Every positive match writes to `sensitive_data_events` AND notifies admin, unconditionally — not just logged (PROJECT-SPEC.md §4.2(d)). |

### 3.4 Prompt injection via retrieved knowledge
| Threat | Control |
|---|---|
| A KB article (even if publicly sourced) contains text designed to override system instructions | Agent must structurally distinguish system instructions / developer instructions / retrieved knowledge / user content (PROJECT-SPEC.md §4.6); retrieved articles must never override system policy. Prompt-injection screening is its own pipeline step after sensitive-data detection (PROJECT-SPEC.md §4.5). |

### 3.5 Budget / cost abuse
| Threat | Control |
|---|---|
| High-volume querying to run up LLM spend | Budget Guard checks actual usage-derived cost before model selection; budget states (NORMAL/WARNING/RESTRICTED/HARD_STOP) throttle to cheaper tiers or refuse paid generation entirely (PROJECT-SPEC.md §13). |
| Cost calculated from guessed averages, masking real overspend | Cost is computed from actual provider usage only — input/cached-input/output cost — never an averaged estimate (PROJECT-SPEC.md §13 "Cost calculation"). |

### 3.6 Admin control-surface abuse
| Threat | Control |
|---|---|
| Accidental or malicious destructive admin command (rollback, prompt activation, budget change) | Require explicit confirmation for these specific commands (PROJECT-SPEC.md §16). |
| Compromised admin Telegram account | Out of scope for this phase — noted as an open item; admin identity verification approach is not yet defined (see mvp-scope.md open items). |

### 3.7 Dependency failure (Redis, PostgreSQL, LLM providers)
| Threat | Control |
|---|---|
| Redis unavailable mid-request | Per ADR-0002, no feature may depend on Redis alone for correctness beyond cache warmth/rate-limit windows; degraded behavior (e.g., skip cache, fail rate-limit open or closed — to be decided per feature in Phase 4) must be explicit, not accidental. |
| PostgreSQL unavailable | System of record — if unreachable, fail safely (no silent data loss, no unlogged interactions); every external dependency needs timeout/retry/backoff/dead-letter/admin alert (PROJECT-SPEC.md §20). |
| LLM provider outage or error | Same error-handling contract: timeout, retry with exponential backoff, max retry count, dead-letter path, admin alert. Never silently drop an interaction. |

## 4. Explicitly out of scope for this threat model (MVP boundary)

Per PROJECT-SPEC.md §4.1: no internal company documents, source code, tickets, internal
architecture, or internal names/org info are ingested. The POC is public-data-only and must
not be presented as approved for production corporate data. Threats specific to
internal-data handling are therefore not modeled here — they become relevant only after the
Elbit security/IT review in §4.7.

## 5. Open item: data-classification category mismatch

PROJECT-SPEC.md §4.4 defines four categories: `PUBLIC / INTERNAL / SENSITIVE / CLASSIFIED`.
PREPARATION-CHECKLIST.md §7.1 defines five: `PUBLIC / INTERNAL / CONFIDENTIAL / PERSONAL /
SECRET`. PROJECT-SPEC.md self-identifies as "the master specification... source of truth for
Cursor/implementation" (document header), so its four-category model is treated as
authoritative for implementation. The five-category list in PREPARATION-CHECKLIST.md predates
this and should be reconciled or explicitly retired when the security rules are finalized with
Elbit's security team (PREPARATION-CHECKLIST.md §7) — flagged here so it isn't silently
implemented twice with two different vocabularies.
