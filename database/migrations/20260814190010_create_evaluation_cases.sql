-- migrate:up
-- No rows seeded: the golden evaluation set is prepared by you (PREPARATION-CHECKLIST §9),
-- not invented here.
CREATE TABLE evaluation_cases (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category            TEXT NOT NULL,
    question            TEXT NOT NULL,
    expected_behavior   TEXT,
    expected_language   TEXT,
    severity            TEXT,
    active               BOOLEAN NOT NULL DEFAULT true,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_evaluation_cases_category_active ON evaluation_cases (category, active);

-- migrate:down
DROP TABLE evaluation_cases;
