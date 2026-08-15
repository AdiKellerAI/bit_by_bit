-- Router Prompt (PROJECT-SPEC.md §24 Phase 5 "Prompt System"). Formalizes what was already
-- live, hardcoded inline in n8n/workflows/telegram-echo-bot.json's "Classify Intent" node
-- since the Phase 4 intent-router work - moved verbatim into system_prompts here, not
-- rewritten, since this exact wording is already proven in production. The workflow now
-- fetches this row at runtime via "Get Router Prompt" instead of hardcoding it.
-- Run manually: docker compose exec -T postgres psql -U $POSTGRES_USER -d $POSTGRES_DB
-- < database/seed/router-prompt.sql
INSERT INTO system_prompts (version_tag, prompt_type, role_description, prompt_text, few_shot_examples, is_active)
SELECT
  'v1',
  'router',
  'Classifies intent/complexity/needs_kb for a message before RAG and tier routing',
  'Classify the user message. Respond with ONLY a JSON object, no other text: {"intent": "question|greeting|feedback|off_topic|clarification", "complexity": "simple|complex", "needs_kb": true|false}',
  '[]'::jsonb,
  true
WHERE NOT EXISTS (SELECT 1 FROM system_prompts WHERE prompt_type = 'router' AND is_active = true);
