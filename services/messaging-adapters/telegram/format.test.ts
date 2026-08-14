import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatOutbound, buildEchoText } from './format.ts';

test('formats a normal-length message unchanged', () => {
  assert.deepEqual(formatOutbound('123', 'hello'), { chat_id: '123', text: 'hello' });
});

test("truncates messages over Telegram's 4096 char limit", () => {
  const long = 'a'.repeat(5000);
  const result = formatOutbound('123', long);
  assert.equal(result.text.length, 4096);
  assert.ok(result.text.endsWith('…'));
});

test('leaves a message exactly at the limit unchanged', () => {
  const exact = 'a'.repeat(4096);
  assert.equal(formatOutbound('123', exact).text, exact);
});

test('builds echo text', () => {
  assert.equal(buildEchoText('hi'), 'echo: hi');
});
