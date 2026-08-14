-- migrate:up
CREATE TABLE message_templates (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_name     TEXT NOT NULL,
    platform          TEXT NOT NULL CHECK (platform IN ('telegram', 'whatsapp')),
    purpose           TEXT,
    language          TEXT NOT NULL,
    approval_status   TEXT NOT NULL DEFAULT 'pending',
    last_synced_at    TIMESTAMPTZ,
    UNIQUE (template_name, platform, language)
);

-- migrate:down
DROP TABLE message_templates;
