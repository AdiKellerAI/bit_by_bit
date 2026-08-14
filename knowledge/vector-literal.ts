// Formats a raw embedding (array of floats) as a pgvector text literal, e.g. "[0.1,0.2,0.3]",
// suitable for a parameterized query cast with ::vector. Pure function — the one piece of the
// ingestion/retrieval path that's meaningfully unit-testable without a real embeddings API call.
export function toVectorLiteral(embedding: number[]): string {
  if (embedding.length === 0) {
    throw new Error('Cannot format an empty embedding as a vector literal');
  }
  return `[${embedding.join(',')}]`;
}
