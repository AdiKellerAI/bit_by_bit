-- migrate:up
CREATE TABLE prompt_change_proposals (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    current_prompt_id     UUID REFERENCES system_prompts (id),
    proposed_prompt        TEXT,
    proposed_examples       JSONB,
    rationale                TEXT,
    source_interactions      JSONB,
    evaluation_score          NUMERIC,
    status                    TEXT NOT NULL DEFAULT 'pending',
    approved_by                TEXT,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_prompt_change_proposals_status ON prompt_change_proposals (status);

-- migrate:down
DROP TABLE prompt_change_proposals;
