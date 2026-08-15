-- migrate:up
-- status already existed (DEFAULT 'pending') but had no vocabulary pinned down - same pattern
-- as the feedback_score CHECK added for the telemetry/feedback sub-phase, now that the nightly
-- evaluator will actually write real status values (PROJECT-SPEC.md §11's pending -> approved/
-- rejected flow, ADR-0004).
ALTER TABLE prompt_change_proposals ADD CONSTRAINT prompt_change_proposals_status_check
    CHECK (status IN ('pending', 'approved', 'rejected'));

-- Golden Evaluation cost is tracked but deliberately does not gate on budget_policy (that
-- budget governs user-facing traffic, not this internal admin process) - this column makes the
-- real cost auditable by the admin instead of only logged to console.
ALTER TABLE prompt_change_proposals ADD COLUMN evaluation_cost_usd NUMERIC;

-- migrate:down
ALTER TABLE prompt_change_proposals DROP COLUMN evaluation_cost_usd;
ALTER TABLE prompt_change_proposals DROP CONSTRAINT prompt_change_proposals_status_check;
