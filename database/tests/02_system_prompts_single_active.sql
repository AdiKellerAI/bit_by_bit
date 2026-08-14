-- Expected to FAIL: PROJECT-SPEC.md §7.3 "only one production prompt version can be active"
BEGIN;
INSERT INTO system_prompts (version_tag, prompt_text, is_active) VALUES ('test-a', 'a', true);
INSERT INTO system_prompts (version_tag, prompt_text, is_active) VALUES ('test-b', 'b', true);
ROLLBACK;
