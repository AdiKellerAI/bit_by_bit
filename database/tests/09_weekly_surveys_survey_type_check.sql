-- Expected to FAIL: survey_type is pinned to the five defined rotation types.
BEGIN;
INSERT INTO weekly_surveys (survey_type, submitted_by) VALUES ('bogus_type', 'test');
ROLLBACK;
