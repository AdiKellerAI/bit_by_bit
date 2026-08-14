# MVP Scope & Assumptions

Companion to: PROJECT-SPEC.md §3, §4.1, §19, §25.

## 1. What the Agent is supposed to do

A 1:1 assistant, reachable via Telegram for the MVP, that helps employees discover AI/tech
content, learn AI concepts, find podcasts/articles/tools, and get development-with-AI ideas
(PROJECT-SPEC.md §1, §2.2, §15 Skills 1-4). It mirrors the user's language (Hebrew/English,
PROJECT-SPEC.md §14) and answers from a curated knowledge base via RAG.

## 2. Who interacts with it

- End users: employees, starting with 3-5 trusted pilot users (PROJECT-SPEC.md §24 Phase 8).
- Administrator: a separate 1:1 control surface with commands like `/status`, `/cost`,
  `/approve`, `/incidents` (PROJECT-SPEC.md §16).

## 3. Channel for the MVP

Telegram is primary and the only active adapter. WhatsApp Cloud API is deferred (ADR-0001).
The WhatsApp Community (human-run Announcements + Sandbox) is separate, already-set-up
infrastructure — not built as part of this project.

## 4. What the Agent must NOT do (PROJECT-SPEC.md §19, §26)

- Answer internal corporate information, personnel issues, politics, classified information,
  credentials, proprietary code, or unrelated personal assistance.
- Bypass security on request.
- Post directly into the WhatsApp Community (weekly content is admin-reviewed and
  manually posted).
- Auto-activate self-improving prompt changes without evaluation + human approval (ADR-0004).

## 5. What information it is allowed to use

PUBLIC information only for the POC: curated podcasts, articles, tools, publicly available AI
knowledge. Synthetic test users only (PROJECT-SPEC.md §4.1).

## 6. What information it must never use

Internal company documents, source code, tickets, internal architecture, internal names or
organizational information (unless explicitly approved), classified/proprietary/sensitive
company information (PROJECT-SPEC.md §4.1).

## 7. What counts as a successful answer

Not yet quantified — this is explicitly your input to prepare
(PREPARATION-CHECKLIST.md §0.1 "MVP success criteria": answer quality, response latency, cost
per conversation, conversations handled, % requiring human intervention, % unsafe/incorrect
answers, sensitive-data detection accuracy with false negatives as the priority to minimize,
user feedback quality). Listed here as an open item, not invented.

## 8. What counts as a failure

- An unsafe or incorrect answer reaching a user.
- A sensitive-data detection false negative (a secret/PII/classified-looking string that
  should have been blocked, wasn't).
- An interaction silently dropped instead of logged (PROJECT-SPEC.md §20).
- A prompt change activated without passing golden evaluation + human approval.

## 9. Sensitive-data incident definition and required response

A sensitive-data incident is any positive match from the detector in ADR-0003 — credential-
shaped strings, personal identifiers, classification markings, internal ticket/case numbers,
internal hostnames/IP ranges, source-code fragments, or other org-specific patterns
(PROJECT-SPEC.md §4.2). Required response, every time, no exceptions for apparent intent:
block before any LLM call, safe non-judgmental redirect to the user, write to
`sensitive_data_events`, notify the admin.

## 10. Definition of Done — MVP (PROJECT-SPEC.md §25, restated as a checklist)

1. A user can DM the Agent on Telegram.
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
22. The messaging adapter is cleanly swappable.

This phase (Phase 0-1) delivers none of these directly — it delivers the architecture
documentation and the local infrastructure that later phases build on top of.
