-- migrate:up
-- Closes a real schema gap for PROJECT-SPEC.md Phase 5 "Prompt System": system_prompts had no
-- column distinguishing prompt kinds, so only one prompt could ever be active system-wide (a
-- single partial unique index on is_active). Phase 5 needs Base/Router/Evaluator/Digest/
-- Security prompts each independently active - add a type discriminator and make the
-- uniqueness constraint per-type instead of global. The DEFAULT 'base', dropped right after,
-- backfills the existing Base Prompt row for free with no separate UPDATE needed.
ALTER TABLE system_prompts ADD COLUMN prompt_type TEXT NOT NULL DEFAULT 'base';
ALTER TABLE system_prompts ALTER COLUMN prompt_type DROP DEFAULT;
ALTER TABLE system_prompts ADD CONSTRAINT system_prompts_type_check
    CHECK (prompt_type IN ('base', 'router', 'evaluator', 'digest', 'security'));

DROP INDEX idx_system_prompts_one_active;
CREATE UNIQUE INDEX idx_system_prompts_one_active_per_type ON system_prompts (prompt_type)
    WHERE is_active = true;

-- migrate:down
DROP INDEX idx_system_prompts_one_active_per_type;
ALTER TABLE system_prompts DROP CONSTRAINT system_prompts_type_check;
ALTER TABLE system_prompts DROP COLUMN prompt_type;
CREATE UNIQUE INDEX idx_system_prompts_one_active ON system_prompts (is_active)
    WHERE is_active = true;
