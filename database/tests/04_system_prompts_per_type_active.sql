-- Expected to SUCCEED: different prompt_types can each have their own active row at the same
-- time - proves the Phase 5 migration (20260815140000_add_prompt_type_to_system_prompts.sql)
-- made the uniqueness constraint per-type, not still the original global one. Deactivates the
-- real router/security rows first so the test inserts don't collide with production data, then
-- rolls back everything regardless of outcome.
BEGIN;
UPDATE system_prompts SET is_active = false WHERE prompt_type IN ('router', 'security') AND is_active = true;
INSERT INTO system_prompts (version_tag, prompt_type, prompt_text, is_active) VALUES ('test-router', 'router', 'r', true);
INSERT INTO system_prompts (version_tag, prompt_type, prompt_text, is_active) VALUES ('test-security', 'security', 's', true);
ROLLBACK;
