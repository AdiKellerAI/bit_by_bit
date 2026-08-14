-- migrate:up
CREATE TABLE users (
    platform_user_id   TEXT PRIMARY KEY,
    platform            TEXT NOT NULL CHECK (platform IN ('telegram', 'whatsapp')),
    display_name         TEXT,
    preferred_language   TEXT,
    interaction_count    INTEGER NOT NULL DEFAULT 0,
    first_seen_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    status                TEXT NOT NULL DEFAULT 'active',
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_platform ON users (platform);

-- migrate:down
DROP TABLE users;
