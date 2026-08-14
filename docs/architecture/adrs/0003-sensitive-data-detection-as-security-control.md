# ADR-0003: Sensitive-data detection is a distinct, always-on security control

## Status
Accepted

## Context
PROJECT-SPEC.md §4.2 introduces sensitive-data monitoring as something beyond the general
data-classification gate in §4.4: it watches *what users type*, independent of intent, and
treats any match as an incident rather than a soft signal. ARCHITECTURE-FLOWS.md §13 draws it
as a separate node (`SENSDET`) after `SEC` (classification) and before `CACHE`, with its own
failure path straight to an admin alert — not merged into the classification step's blocked
path.

## Decision
Sensitive-data detection is implemented as its own pipeline step, distinct from data
classification, with these properties (PROJECT-SPEC.md §4.2, PREPARATION-CHECKLIST.md §7.3):
- Runs on every inbound message, after classification, before cache/RAG/any LLM call.
- A positive match on *any* pattern — not just high-confidence ones — always: blocks the
  message from reaching an LLM, sends a short non-judgmental safe redirect to the user, writes
  a row to the dedicated `sensitive_data_events` table, and notifies the administrator.
- Detection patterns (credential-shaped strings, personal identifiers, classification
  markings, internal ticket/case numbers, internal hostnames/IPs, source-code fragments) are
  living configuration, not a one-time hardcoded list — expected to be refined with input from
  the organization's security team.
- Regex/heuristics are a first-pass signal only; this is explicitly not treated as a complete
  DLP system (ARCHITECTURE-FLOWS.md §14: `Regex == DLP` is called out as the wrong model).
- Events from this detector are never fed into Loop 3 (LDD) as training signal — they are an
  audit/incident trail reviewed only by a human (PROJECT-SPEC.md §11, "Explicitly excluded").

## Consequences
- `sensitive_data_events` is a separate table from `interaction_logs`, even though
  `interaction_logs` also carries `sensitive_data_flagged`/`sensitive_data_category` columns
  for visibility on the interaction row itself (ARCHITECTURE-FLOWS.md §3).
- The detector's ruleset is out of scope for Loop 3/LDD automatic proposals entirely — see
  ADR-0004. Changes to detection patterns go through manual security review, not the
  evaluator → golden-eval → approval pipeline used for prompts.
- Detection pattern content itself (the actual regexes/heuristics) is not authored in this
  phase — it needs input from Elbit's security team per PREPARATION-CHECKLIST.md §7.3 and is
  listed as an open human-decision item, not something invented here.
