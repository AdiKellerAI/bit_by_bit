-- migrate:up
-- No row seeded: real budget thresholds are an open decision (flagged in the Phase 0-1 gate
-- check), not invented in this migration. The application should treat an empty table as
-- "no policy configured" and fail safely (PROJECT-SPEC.md §3 principle 10), not assume NORMAL.
CREATE TABLE budget_policy (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    monthly_budget_usd      NUMERIC,
    daily_budget_usd         NUMERIC,
    warning_threshold         NUMERIC,
    hard_stop_threshold       NUMERIC,
    cheap_model_policy        TEXT,
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- migrate:down
DROP TABLE budget_policy;
