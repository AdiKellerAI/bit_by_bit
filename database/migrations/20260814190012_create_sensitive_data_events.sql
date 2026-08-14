-- migrate:up
-- Per ADR-0003: deliberately no relationship to interaction_logs or any Loop 3/LDD table.
-- This table is never joined into LDD training queries.
CREATE TABLE sensitive_data_events (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    platform_user_id    TEXT NOT NULL REFERENCES users (platform_user_id),
    category            TEXT,
    detector            TEXT,
    redacted_excerpt    TEXT,
    action_taken         TEXT,
    admin_notified        BOOLEAN NOT NULL DEFAULT false,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_sensitive_data_events_user_created
    ON sensitive_data_events (platform_user_id, created_at);

-- migrate:down
DROP TABLE sensitive_data_events;
