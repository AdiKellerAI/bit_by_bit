-- migrate:up
-- PROJECT-SPEC.md Phase 5's Security Prompt gets a real LLM classification call, but per an
-- explicit, deliberately conservative decision it stays advisory-only for now (see
-- database/seed/security-prompt.sql) - the actual block/allow gate is unchanged. This column
-- is kept separate from the authoritative security_classification column on purpose, so the
-- advisory signal can never be mistaken for (or accidentally wired to) the real gate.
ALTER TABLE interaction_logs ADD COLUMN security_signal TEXT
    CHECK (security_signal IN ('PUBLIC', 'INTERNAL', 'SENSITIVE', 'CLASSIFIED'));
ALTER TABLE interaction_logs ADD COLUMN security_signal_reasoning TEXT;

-- migrate:down
ALTER TABLE interaction_logs DROP COLUMN security_signal_reasoning;
ALTER TABLE interaction_logs DROP COLUMN security_signal;
