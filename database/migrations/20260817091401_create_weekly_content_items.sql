-- migrate:up
-- WhatsApp Community Content Agent phase 2 (see CLAUDE.md). content_type already distinguishes
-- this phase's 'featured_link' from phase 3's planned 'community_summary' so this table serves
-- both without a schema change later. draft_description_he (what the agent wrote) and
-- final_description_he (what Adi actually approved, corrected marking whether they differ) is
-- what phase 4's LDD retargeting needs to learn from - captured now since it's already flowing
-- through this table, not backfilled later.
CREATE TABLE weekly_content_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    content_type text NOT NULL CHECK (content_type IN ('featured_link', 'community_summary')),
    source_url text,
    title text,
    draft_description_he text,
    final_description_he text,
    corrected boolean NOT NULL DEFAULT false,
    status text NOT NULL DEFAULT 'pending_approval' CHECK (status IN ('pending_approval', 'approved')),
    target_post_date date,
    submitted_by text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    approved_at timestamptz
);

-- migrate:down
DROP TABLE weekly_content_items;
