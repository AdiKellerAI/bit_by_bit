# ADR-0001: Messaging channel abstracted behind an adapter interface

## Status
Accepted

## Context
The Agent's 1:1 channel and the human WhatsApp Community are two independent surfaces
(PROJECT-SPEC.md §0). The original plan assumed the Agent channel and the WhatsApp Cloud API
were the same decision - they are not. The Meta Developer Account required for WhatsApp Cloud
API is currently blocked on SMS verification (PREREQUISITES.md §7), with no fixed unblock
date. A Telegram bot, created via @BotFather, requires no business verification, no SMS
gateway, and was available immediately (PREREQUISITES.md §6).

## Decision
The Agent's inbound/outbound messaging is implemented behind a messaging-adapter interface.
Telegram Bot API is the only concrete, active adapter for the MVP. WhatsApp Cloud API is a
second adapter, scaffolded but inactive, to be added later without changing anything below the
webhook layer (PROJECT-SPEC.md §0 item 4, §27 rule 16).

Concretely:
- Every inbound message is normalized into one internal message shape before it reaches any
  downstream logic (security, cache, RAG, cost routing, LDD).
- Every outbound message is formatted from that same internal shape by an adapter-specific
  "format outbound message" step (ARCHITECTURE-FLOWS.md §1, Adapter boundary note).
- No Telegram-specific type, field, or API call may appear outside the adapter module.
- The database schema is already platform-agnostic: `platform_user_id` + `platform` column,
  not `telegram_id` (ARCHITECTURE-FLOWS.md §3, Changes from the original design).

## Consequences
- Adding WhatsApp Cloud API later is a drop-in second adapter, not a rewrite - this is
  PROJECT-SPEC.md §25 Definition-of-Done item 22.
- Until WhatsApp Cloud API is added, all "platform" values in the database will be `telegram`
  in practice; code must not assume this is permanent.
- The WhatsApp Community (human channel) has no dependency on this decision at all - see
  ADR context in PROJECT-SPEC.md §0 items 1 and 5-7; it is unaffected infrastructure.
