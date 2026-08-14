-- migrate:up
CREATE TABLE interaction_logs (
    id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id                TEXT,
    platform_user_id          TEXT NOT NULL REFERENCES users (platform_user_id),
    platform                  TEXT NOT NULL CHECK (platform IN ('telegram', 'whatsapp')),
    user_query                TEXT,
    agent_response             TEXT,
    routed_model               TEXT,
    input_tokens                INTEGER,
    output_tokens               INTEGER,
    cached_input_tokens         INTEGER,
    cost_usd                    NUMERIC,
    feedback_score               SMALLINT,
    needs_review                 BOOLEAN NOT NULL DEFAULT false,
    cache_hit                    BOOLEAN NOT NULL DEFAULT false,
    intent                       TEXT,
    -- PROJECT-SPEC.md §4.4's 4-tier list, treated as authoritative over the differing
    -- 5-tier list in PREPARATION-CHECKLIST.md §7.1 — see docs/architecture/threat-model.md §5.
    security_classification      TEXT CHECK (security_classification IN
                                    ('PUBLIC', 'INTERNAL', 'SENSITIVE', 'CLASSIFIED')),
    sensitive_data_flagged       BOOLEAN NOT NULL DEFAULT false,
    sensitive_data_category      TEXT,
    prompt_version_id            UUID REFERENCES system_prompts (id),
    retrieved_kb_ids             JSONB,
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_interaction_logs_user_created ON interaction_logs (platform_user_id, created_at);
CREATE INDEX idx_interaction_logs_needs_review ON interaction_logs (needs_review)
    WHERE needs_review = true;
CREATE INDEX idx_interaction_logs_prompt_version ON interaction_logs (prompt_version_id);

-- migrate:down
DROP TABLE interaction_logs;
