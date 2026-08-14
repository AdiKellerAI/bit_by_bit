import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeInbound, type TelegramUpdate } from './normalize.ts';

test('normalizes a text message update', () => {
  const update: TelegramUpdate = {
    update_id: 555,
    message: {
      message_id: 42,
      from: { id: 987654321, first_name: 'Adi' },
      chat: { id: 987654321, type: 'private' },
      date: 1735689600,
      text: 'Hello',
    },
  };

  assert.deepEqual(normalizeInbound(update), {
    platform: 'telegram',
    platform_user_id: '987654321',
    chat_id: '987654321',
    platform_message_id: '555',
    text: 'Hello',
    received_at: new Date(1735689600 * 1000).toISOString(),
  });
});

test('uses update_id, not message_id, for platform_message_id', () => {
  // message_id is only unique within a single chat; update_id is globally unique per bot.
  const update: TelegramUpdate = {
    update_id: 999,
    message: {
      message_id: 1,
      from: { id: 1 },
      chat: { id: 1, type: 'private' },
      date: 0,
      text: 'hi',
    },
  };

  assert.equal(normalizeInbound(update)?.platform_message_id, '999');
});

test('returns null when there is no message', () => {
  assert.equal(normalizeInbound({ update_id: 1 }), null);
});

test('returns null when the sender is missing', () => {
  const update: TelegramUpdate = {
    update_id: 1,
    message: { message_id: 1, chat: { id: 1, type: 'private' }, date: 0, text: 'hi' },
  };
  assert.equal(normalizeInbound(update), null);
});

test('returns null for non-text messages (e.g. photo, sticker)', () => {
  const update: TelegramUpdate = {
    update_id: 1,
    message: {
      message_id: 1,
      from: { id: 1 },
      chat: { id: 1, type: 'private' },
      date: 0,
    },
  };
  assert.equal(normalizeInbound(update), null);
});
