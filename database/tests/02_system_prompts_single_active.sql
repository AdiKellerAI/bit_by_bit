-- Expected to FAIL: PROJECT-SPEC.md §7.3 "only one production prompt version can be active"
-- (Phase 5 made this constraint per-type, not global - both rows use the same type here to
-- prove that still holds; see 03b_system_prompts_per_type.sql for the per-type behavior.)
BEGIN;
INSERT INTO system_prompts (version_tag, prompt_type, prompt_text, is_active) VALUES ('test-a', 'base', 'a', true);
INSERT INTO system_prompts (version_tag, prompt_type, prompt_text, is_active) VALUES ('test-b', 'base', 'b', true);
ROLLBACK;
