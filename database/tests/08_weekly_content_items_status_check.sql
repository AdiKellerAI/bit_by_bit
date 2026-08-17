-- Expected to FAIL: status is pinned to pending_approval/approved.
BEGIN;
INSERT INTO weekly_content_items (content_type, status, submitted_by) VALUES ('featured_link', 'bogus_status', 'test');
ROLLBACK;
