-- migrate:up
-- NOTE: platform_message_id is the sole PK, matching ARCHITECTURE-FLOWS.md §3's ERD exactly.
-- This is a known future collision risk once a second platform (WhatsApp) is active — two
-- platforms could in principle issue the same message id. Flagged in the Phase 2 plan;
-- revisit as a composite PK (platform, platform_message_id) when WhatsApp adapter work starts.
CREATE TABLE webhook_events (
    platform_message_id   TEXT PRIMARY KEY,
    platform               TEXT NOT NULL CHECK (platform IN ('telegram', 'whatsapp')),
    received_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed                BOOLEAN NOT NULL DEFAULT false,
    processing_status        TEXT,
    error_code                TEXT,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_webhook_events_processing_status ON webhook_events (processing_status);

-- migrate:down
DROP TABLE webhook_events;
