-- Real, factual model_registry data (not invented) - see docs/architecture (Phase 5 plan)
-- for the pricing source. Separate from dbmate migrations, which stay schema-only; run this
-- manually: docker compose exec -T postgres psql -U $POSTGRES_USER -d $POSTGRES_DB < database/seed/model-registry.sql
INSERT INTO model_registry (
  provider, model_name, tier, input_price_per_1m_tokens, output_price_per_1m_tokens,
  cached_input_price_per_1m_tokens, effective_from, enabled, max_context
)
SELECT 'openai', 'text-embedding-3-small', 'embedding', 0.02, NULL, NULL, now(), true, 8191
WHERE NOT EXISTS (
  SELECT 1 FROM model_registry WHERE provider = 'openai' AND model_name = 'text-embedding-3-small'
);

-- Generation phase (Phase 6): Tier 1 (fast/cheap) and Tier 2 (escalation) models.
INSERT INTO model_registry (
  provider, model_name, tier, input_price_per_1m_tokens, output_price_per_1m_tokens,
  cached_input_price_per_1m_tokens, effective_from, enabled, max_context
)
SELECT 'openai', 'gpt-5.4-nano', '1', 0.20, 1.25, NULL, now(), true, 128000
WHERE NOT EXISTS (
  SELECT 1 FROM model_registry WHERE provider = 'openai' AND model_name = 'gpt-5.4-nano'
);

-- Intro pricing through 2026-08-31; full price afterward is $3.00/$15.00 per 1M tokens.
INSERT INTO model_registry (
  provider, model_name, tier, input_price_per_1m_tokens, output_price_per_1m_tokens,
  cached_input_price_per_1m_tokens, effective_from, enabled, max_context
)
SELECT 'anthropic', 'claude-sonnet-5', '2', 2.00, 10.00, NULL, now(), true, 1000000
WHERE NOT EXISTS (
  SELECT 1 FROM model_registry WHERE provider = 'anthropic' AND model_name = 'claude-sonnet-5'
);
