import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toVectorLiteral } from './vector-literal.ts';

test('formats a small embedding array as a pgvector literal', () => {
  assert.equal(toVectorLiteral([0.1, 0.2, 0.3]), '[0.1,0.2,0.3]');
});

test('formats a single-element array', () => {
  assert.equal(toVectorLiteral([1]), '[1]');
});

test('handles negative numbers', () => {
  assert.equal(toVectorLiteral([-0.5, 0, 0.5]), '[-0.5,0,0.5]');
});

test('throws on an empty embedding', () => {
  assert.throws(() => toVectorLiteral([]));
});
