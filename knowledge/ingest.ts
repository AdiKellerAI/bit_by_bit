import { readFileSync } from 'node:fs';
import { Pool } from 'pg';
import { toVectorLiteral } from './vector-literal.ts';

interface SeedEntry {
  category: string;
  title: string;
  url: string;
  summary_en: string;
  summary_he: string;
  source_type: string;
  trust_level: string;
}

const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const DATABASE_URL = process.env.DATABASE_URL;

if (!OPENAI_API_KEY) {
  throw new Error('OPENAI_API_KEY is not set - run with: node --env-file=../.env ...');
}
if (!DATABASE_URL) {
  throw new Error('DATABASE_URL is not set - run with: node --env-file=../.env ...');
}

async function embed(text: string): Promise<number[]> {
  const response = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${OPENAI_API_KEY}`,
    },
    body: JSON.stringify({
      model: 'text-embedding-3-small',
      input: text,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`OpenAI embeddings API error ${response.status}: ${body}`);
  }

  const data = (await response.json()) as { data: Array<{ embedding: number[] }> };
  return data.data[0].embedding;
}

async function main(): Promise<void> {
  const seedPath = new URL('./seed.json', import.meta.url);
  const entries: SeedEntry[] = JSON.parse(readFileSync(seedPath, 'utf-8'));

  const pool = new Pool({ connectionString: DATABASE_URL, ssl: false });

  try {
    for (const entry of entries) {
      // Embedding text includes both languages - an English-only embedding measurably
      // under-matched real Hebrew queries during Phase 5 testing (best match landed at
      // cosine distance ~0.55, just over the 0.5 threshold, for a Hebrew query about a
      // Hebrew-language seeded podcast). Since the community is Hebrew-primary
      // (PROJECT-SPEC.md §14), this needed a real fix, not just a documented limitation.
      const embedding = await embed(`${entry.title}. ${entry.summary_en} ${entry.summary_he}`);
      const vectorLiteral = toVectorLiteral(embedding);

      const existing = await pool.query('SELECT id FROM knowledge_base WHERE title = $1', [
        entry.title,
      ]);

      if (existing.rows.length > 0) {
        await pool.query(
          `UPDATE knowledge_base
           SET category = $1, url = $2, summary_he = $3, summary_en = $4,
               source_type = $5, trust_level = $6, embedding = $7::vector,
               status = 'published', updated_at = now()
           WHERE id = $8`,
          [
            entry.category,
            entry.url,
            entry.summary_he,
            entry.summary_en,
            entry.source_type,
            entry.trust_level,
            vectorLiteral,
            existing.rows[0].id,
          ],
        );
        console.log(`Updated:  ${entry.title}`);
      } else {
        await pool.query(
          `INSERT INTO knowledge_base
             (category, title, url, summary_he, summary_en, source_type, trust_level, embedding, status)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8::vector, 'published')`,
          [
            entry.category,
            entry.title,
            entry.url,
            entry.summary_he,
            entry.summary_en,
            entry.source_type,
            entry.trust_level,
            vectorLiteral,
          ],
        );
        console.log(`Inserted: ${entry.title}`);
      }
    }
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
