-- migrate:up
-- No rows seeded: real model names/tiers/pricing are an open decision (PREPARATION-CHECKLIST
-- Phase 4/16), not invented in this migration.
CREATE TABLE model_registry (
    id                                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider                          TEXT NOT NULL,
    model_name                        TEXT NOT NULL,
    tier                              TEXT,
    input_price_per_1m_tokens          NUMERIC,
    output_price_per_1m_tokens         NUMERIC,
    cached_input_price_per_1m_tokens   NUMERIC,
    effective_from                     TIMESTAMPTZ,
    enabled                            BOOLEAN NOT NULL DEFAULT true,
    max_context                        INTEGER,
    created_at                         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_model_registry_tier_enabled ON model_registry (tier, enabled);

-- migrate:down
DROP TABLE model_registry;
