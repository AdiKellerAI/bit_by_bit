-- Real, factual model_registry data (not invented) — see docs/architecture (Phase 5 plan)
-- for the pricing source. Separate from dbmate migrations, which stay schema-only; run this
-- manually: docker compose exec -T postgres psql -U $POSTGRES_USER -d $POSTGRES_DB < database/seed/model-registry.sql
-- Tier 1/2 generation models intentionally not seeded yet — that's the Generation phase.
INSERT INTO model_registry (
  provider, model_name, tier, input_price_per_1m_tokens, output_price_per_1m_tokens,
  cached_input_price_per_1m_tokens, effective_from, enabled, max_context
)
SELECT 'openai', 'text-embedding-3-small', 'embedding', 0.02, NULL, NULL, now(), true, 8191
WHERE NOT EXISTS (
  SELECT 1 FROM model_registry WHERE provider = 'openai' AND model_name = 'text-embedding-3-small'
);
