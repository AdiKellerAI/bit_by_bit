# ADR-0004: LDD changes always require human approval before activation

## Status
Accepted

## Context
Loop-Driven Development (LDD) is the project's mechanism for the Agent to improve itself
over time (PROJECT-SPEC.md §8, §11). Left unconstrained, an evaluator that can both propose
and activate changes is a self-modifying system with no human checkpoint - explicitly rejected
by Product Principle 3 ("Human approval before autonomous behavioral change,"
PROJECT-SPEC.md §3) and by PREPARATION-CHECKLIST.md Phase 10.

## Decision
Loop 3 (Meta-Learning) always follows: Evaluator → Candidate (stored inactive) → Golden
Evaluation → (fail → reject) / (pass → Human Approval) → activate (PROJECT-SPEC.md §11 flow
diagram). The evaluator's structured output (`problem`, `root_cause`,
`proposed_prompt_change`, `new_examples`, `expected_benefit`, `risk`, `confidence`) is a
proposal, never a mutation. "The evaluator must never activate its own changes" is stated
verbatim in PROJECT-SPEC.md §11.

Additionally, and separately: sensitive-data detection rules are explicitly out of scope for
automatic LDD proposals of any kind - changes there require a distinct, manual security review
process, not the prompt-improvement pipeline (PROJECT-SPEC.md §8, PREPARATION-CHECKLIST.md
Phase 10, ADR-0003).

## Consequences
- `prompt_change_proposals` (PROJECT-SPEC.md §7.10) is a first-class table with `status`,
  `approved_by`, and `evaluation_score` - an explicit audit trail between learning and
  activation.
- `system_prompts` versions are never deleted (PROJECT-SPEC.md §7.3); rollback is always
  possible via the Prompt Lifecycle state machine (ARCHITECTURE-FLOWS.md §8).
- Admin commands `/approve`, `/reject`, `/rollback` (PROJECT-SPEC.md §16) are the only path
  from candidate to active - there is no code path that skips this.
- This ADR is a statement of an already-decided architectural boundary; it is listed here so
  Phase 6 (LDD implementation) has no ambiguity about whether an "auto-activate if confidence
  is high enough" shortcut is ever acceptable. It is not.
