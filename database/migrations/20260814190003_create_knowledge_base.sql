-- migrate:up
CREATE TABLE knowledge_base (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category      TEXT NOT NULL,
    title         TEXT NOT NULL,
    url           TEXT,
    summary_he    TEXT,
    summary_en    TEXT,
    source_type   TEXT,
    trust_level   TEXT,
    -- 1536 dims targets OpenAI text-embedding-3-small (docs/architecture/adrs - Phase 2 plan);
    -- changing embedding models later requires a migration to resize this column.
    embedding     vector(1536),
    status        TEXT NOT NULL DEFAULT 'draft',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_knowledge_base_category ON knowledge_base (category);
CREATE INDEX idx_knowledge_base_embedding_hnsw ON knowledge_base
    USING hnsw (embedding vector_cosine_ops);

-- migrate:down
DROP TABLE knowledge_base;
