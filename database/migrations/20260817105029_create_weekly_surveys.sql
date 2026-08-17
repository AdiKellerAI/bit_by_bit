-- migrate:up
-- Phase 4 of the WhatsApp Community Content Agent (see CLAUDE.md): a weekly, rotating-type
-- survey drafted by the agent, approved by Adi, and posted as a native WhatsApp Poll (no
-- official API can post/read polls in a pre-existing group - same constraint documented for
-- weekly_content_items). Kept as its own table rather than folded into weekly_content_items:
-- surveys have a genuinely different shape (options, a three-stage lifecycle ending in
-- results_recorded, no source_url).
CREATE TABLE weekly_surveys (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    survey_type text NOT NULL CHECK (survey_type IN
        ('topic_pick', 'format_preference', 'content_retro', 'open_interest', 'cadence_checkin')),
    options jsonb,
    draft_text text,
    final_text text,
    corrected boolean NOT NULL DEFAULT false,
    status text NOT NULL DEFAULT 'pending_approval' CHECK (status IN
        ('pending_approval', 'approved', 'results_recorded')),
    results_text text,
    submitted_by text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    approved_at timestamptz,
    results_recorded_at timestamptz
);

-- migrate:down
DROP TABLE weekly_surveys;
