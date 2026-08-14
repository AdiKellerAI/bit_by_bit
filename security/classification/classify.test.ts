import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classify } from './classify.ts';

test('is a stub that always returns PUBLIC (see comment in classify.ts)', () => {
  assert.equal(classify('anything at all'), 'PUBLIC');
  assert.equal(classify(''), 'PUBLIC');
  assert.equal(classify('this sure sounds internal and confidential'), 'PUBLIC');
});
