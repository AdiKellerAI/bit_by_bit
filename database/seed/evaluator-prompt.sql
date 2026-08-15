-- Evaluator Prompt (PROJECT-SPEC.md §24 Phase 5 "Prompt System"). Stored and versioned now;
-- has NO consumer yet - Phase 6 "LDD" builds Loop 3 (the nightly job that actually invokes
-- this prompt against sanitized failing/flagged interactions). Output schema is PROJECT-SPEC.md
-- §11's exact required JSON shape, quoted verbatim. "Must never activate its own changes" is
-- also from §11 - the evaluator only ever produces a prompt_change_proposals row (status
-- 'pending'); activation is a separate human-approval step per ADR-0004, which this prompt
-- does not and must not perform.
-- Run manually: docker compose exec -T postgres psql -U $POSTGRES_USER -d $POSTGRES_DB
-- < database/seed/evaluator-prompt.sql
INSERT INTO system_prompts (version_tag, prompt_type, role_description, prompt_text, few_shot_examples, is_active)
SELECT
  'v1',
  'evaluator',
  'Analyzes flagged/failing interactions and proposes a Base Prompt change; never activates it (no consumer yet, Phase 6 LDD)',
  'You are the evaluator in a prompt-improvement loop for an internal AI/dev community assistant. You will be given a small set of sanitized interaction examples (user query, agent response, and why each was flagged - low feedback score, needs_review, or similar). Analyze what went wrong and propose a specific, minimal change to the assistant''s Base Prompt that would fix it, without introducing new problems. Respond with ONLY a JSON object, no other text: {"problem": "<what went wrong, one or two sentences>", "root_cause": "<why it happened>", "proposed_prompt_change": "<the specific text change to the Base Prompt>", "new_examples": [], "expected_benefit": "<what improves>", "risk": "<what could go wrong with this change>", "confidence": "<low|medium|high>"}. You never activate this change yourself - you only produce a candidate proposal for human review. Do not claim the change is already in effect.',
  '[]'::jsonb,
  true
WHERE NOT EXISTS (SELECT 1 FROM system_prompts WHERE prompt_type = 'evaluator' AND is_active = true);
