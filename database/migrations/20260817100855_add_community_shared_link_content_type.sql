-- migrate:up
-- Phase 3 (see CLAUDE.md) starts actually using the 'community_shared_link' content_type that
-- phase 2's migration comment already anticipated - relayed links get their own row (status
-- 'approved' immediately, no separate approval prompt), distinct from the featured link Adi
-- picks each week and the compiled Thursday summary of the week's relayed links.
ALTER TABLE weekly_content_items DROP CONSTRAINT weekly_content_items_content_type_check;
ALTER TABLE weekly_content_items ADD CONSTRAINT weekly_content_items_content_type_check
    CHECK (content_type IN ('featured_link', 'community_shared_link', 'community_summary'));

-- migrate:down
ALTER TABLE weekly_content_items DROP CONSTRAINT weekly_content_items_content_type_check;
ALTER TABLE weekly_content_items ADD CONSTRAINT weekly_content_items_content_type_check
    CHECK (content_type IN ('featured_link', 'community_summary'));
