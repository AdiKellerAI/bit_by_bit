-- migrate:up
-- Closes gaps in PROJECT-SPEC.md §10 "Loop 2 - Telemetry & Feedback"'s exact collection list
-- (query, response, model, token usage, actual cost, latency, cache hit, intent, language, RAG
-- documents, feedback, security classification, sensitive-data flag, prompt version, platform):
-- language was computed every request but never persisted; latency was never computed at all.
-- platform_response_message_id lets a later "feedback 1"/"feedback 0" reply be matched back to
-- the specific answer being rated, not just "whatever this user asked most recently."
ALTER TABLE interaction_logs ADD COLUMN language TEXT;
ALTER TABLE interaction_logs ADD COLUMN latency_ms INTEGER;
ALTER TABLE interaction_logs ADD COLUMN platform_response_message_id TEXT;

-- feedback_score already existed (original migration) but nothing ever wrote to it. Pin down
-- its vocabulary now that real values will be written: PROJECT-SPEC.md §10's explicit fallback
-- command is "feedback 1" / "feedback 0", the same binary shape as a thumbs up/down reaction.
ALTER TABLE interaction_logs ADD CONSTRAINT interaction_logs_feedback_score_check
    CHECK (feedback_score IN (0, 1));

-- migrate:down
ALTER TABLE interaction_logs DROP CONSTRAINT interaction_logs_feedback_score_check;
ALTER TABLE interaction_logs DROP COLUMN platform_response_message_id;
ALTER TABLE interaction_logs DROP COLUMN latency_ms;
ALTER TABLE interaction_logs DROP COLUMN language;
