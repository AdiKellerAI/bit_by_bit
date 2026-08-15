-- migrate:up
-- Closes the "semantic cache" gap in PROJECT-SPEC.md Phase 4 Agent Core - see
-- docs/architecture/data-flow.md and ARCHITECTURE-FLOWS.md §1/§4: sits after sensitive-data
-- detection, before the intent router/RAG, so a near-duplicate query can be answered at $0
-- instead of a real LLM call (PROJECT-SPEC.md §13's cost hierarchy). Same pgvector pattern as
-- knowledge_base (20260814190003_create_knowledge_base.sql). expires_at operationalizes
-- PROJECT-SPEC.md §9's "same knowledge freshness" cache-hit criterion - no separate freshness
-- column needed, a plain WHERE expires_at > now() filter handles it.
CREATE TABLE semantic_cache (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    query_embedding   vector(1536) NOT NULL,
    query_text        TEXT NOT NULL,
    language          TEXT NOT NULL,
    intent            TEXT NOT NULL,
    response_text     TEXT NOT NULL,
    routed_model      TEXT NOT NULL,
    input_tokens      INTEGER,
    output_tokens     INTEGER,
    cost_usd          NUMERIC,
    retrieved_kb_ids  JSONB,
    hit_count         INTEGER NOT NULL DEFAULT 0,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at        TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_semantic_cache_embedding_hnsw ON semantic_cache
    USING hnsw (query_embedding vector_cosine_ops);
CREATE INDEX idx_semantic_cache_expires ON semantic_cache (expires_at);

-- migrate:down
DROP TABLE semantic_cache;
