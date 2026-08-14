-- migrate:up
CREATE TABLE system_prompts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version_tag         TEXT NOT NULL,
    role_description    TEXT,
    prompt_text         TEXT NOT NULL,
    few_shot_examples   JSONB,
    is_active           BOOLEAN NOT NULL DEFAULT false,
    created_by          TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- PROJECT-SPEC.md §7.3: "Only one production prompt version can be active."
CREATE UNIQUE INDEX idx_system_prompts_one_active ON system_prompts (is_active)
    WHERE is_active = true;

-- migrate:down
DROP TABLE system_prompts;
