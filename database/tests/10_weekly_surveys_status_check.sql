-- Expected to FAIL: status is pinned to pending_approval/approved/results_recorded.
BEGIN;
INSERT INTO weekly_surveys (survey_type, status, submitted_by) VALUES ('topic_pick', 'bogus_status', 'test');
ROLLBACK;
