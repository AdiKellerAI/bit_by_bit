-- Expected to FAIL: interaction_logs.platform_user_id must reference an existing user
BEGIN;
INSERT INTO interaction_logs (platform_user_id, platform) VALUES ('no-such-user', 'telegram');
ROLLBACK;
