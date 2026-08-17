-- Expected to FAIL: content_type is pinned to featured_link/community_summary.
BEGIN;
INSERT INTO weekly_content_items (content_type, submitted_by) VALUES ('bogus_type', 'test');
ROLLBACK;
