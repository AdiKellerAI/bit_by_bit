-- Security Prompt (PROJECT-SPEC.md §24 Phase 5 "Prompt System"). Deliberately advisory only,
-- confirmed with the user 2026-08-15: produces a real LLM classification signal, logged to
-- interaction_logs.security_signal (a column separate from the authoritative
-- security_classification the actual block/allow gate reads), but does NOT drive any gating
-- decision yet. classify.ts's always-PUBLIC stub is unchanged. This stays conservative on
-- purpose for a security-critical path in a defense-sector-adjacent project - don't wire this
-- signal to gate anything without an explicit follow-up decision once real classification data
-- has been reviewed.
-- Run manually: docker compose exec -T postgres psql -U $POSTGRES_USER -d $POSTGRES_DB
-- < database/seed/security-prompt.sql
INSERT INTO system_prompts (version_tag, prompt_type, role_description, prompt_text, few_shot_examples, is_active)
SELECT
  'v1',
  'security',
  'Advisory data-sensitivity classification signal, logged only, does not gate anything yet',
  'Classify the data-sensitivity level of the user message for an internal AI/dev community at a defense-sector-adjacent organization. Respond with ONLY a JSON object, no other text: {"classification": "PUBLIC|INTERNAL|SENSITIVE|CLASSIFIED", "reasoning": "<one short sentence>"}. PUBLIC: general questions, publicly known information, nothing company- or project-specific. INTERNAL: mentions internal company processes, non-public project names, or internal-only information without being overtly sensitive. SENSITIVE: discusses credentials, personal data, security vulnerabilities, or internal technical details that could cause real harm if exposed. CLASSIFIED: explicitly marked classified/restricted, or clearly government/defense classified material. When uncertain, prefer the higher (more restrictive) classification.',
  '[]'::jsonb,
  true
WHERE NOT EXISTS (SELECT 1 FROM system_prompts WHERE prompt_type = 'security' AND is_active = true);
