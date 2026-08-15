-- Expected to FAIL: PROJECT-SPEC.md §11's flow only ever produces pending/approved/rejected.
BEGIN;
INSERT INTO prompt_change_proposals (status) VALUES ('bogus');
ROLLBACK;
