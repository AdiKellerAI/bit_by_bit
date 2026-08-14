import { test } from 'node:test';
import assert from 'node:assert/strict';
import { verifySecretToken } from './verifySecret.ts';

test('accepts a matching secret', () => {
  assert.equal(verifySecretToken('abc123', 'abc123'), true);
});

test('rejects a mismatched secret', () => {
  assert.equal(verifySecretToken('wrong', 'abc123'), false);
});

test('rejects a mismatched secret of a different length', () => {
  assert.equal(verifySecretToken('short', 'a-much-longer-secret'), false);
});

test('rejects when the header is missing', () => {
  assert.equal(verifySecretToken(undefined, 'abc123'), false);
});

test('fails closed when the expected secret is empty/unconfigured', () => {
  assert.equal(verifySecretToken('anything', ''), false);
});
