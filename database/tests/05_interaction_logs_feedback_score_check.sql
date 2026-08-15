-- Expected to FAIL: PROJECT-SPEC.md §10's feedback vocabulary is binary ("feedback 1"/
-- "feedback 0", same shape as a thumbs up/down), so feedback_score must reject anything else.
BEGIN;
INSERT INTO users (platform_user_id, platform) VALUES ('test-feedback-check-user', 'telegram');
INSERT INTO interaction_logs (platform_user_id, platform, feedback_score) VALUES ('test-feedback-check-user', 'telegram', 2);
ROLLBACK;
