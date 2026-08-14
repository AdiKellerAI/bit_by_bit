import { test } from 'node:test';
import assert from 'node:assert/strict';
import { detectSensitiveData } from './detect.ts';

test('flags an OpenAI-style API key', () => {
  const result = detectSensitiveData('here is my key sk-abcdefghijklmnopqrstuvwxyz123456');
  assert.equal(result.flagged, true);
  assert.equal(result.detector, 'openai-api-key');
  assert.equal(result.category, 'credential');
});

test('flags an OpenAI-style key even with a stray space after the hyphen (real mobile-keyboard case)', () => {
  const result = detectSensitiveData('My key is sk- ajahdhhchvjxnj287347');
  assert.equal(result.flagged, true);
  assert.equal(result.detector, 'openai-api-key');
});

test('flags an AWS access key id', () => {
  const result = detectSensitiveData('AKIAABCDEFGHIJKLMNOP is my key');
  assert.equal(result.flagged, true);
  assert.equal(result.detector, 'aws-access-key-id');
});

test('flags a private key block', () => {
  const result = detectSensitiveData('-----BEGIN RSA PRIVATE KEY-----\nMIIExyz...');
  assert.equal(result.flagged, true);
  assert.equal(result.detector, 'private-key-block');
});

test('flags an inline password assignment', () => {
  const result = detectSensitiveData('password: hunter2isnotgood');
  assert.equal(result.flagged, true);
  assert.equal(result.detector, 'generic-secret-assignment');
});

test('flags an email address as a personal identifier', () => {
  const result = detectSensitiveData('contact me at adi.keller@example.com please');
  assert.equal(result.flagged, true);
  assert.equal(result.category, 'personal_identifier');
});

test('flags a private RFC1918 IP address', () => {
  const result = detectSensitiveData('the server is at 10.0.4.12 internally');
  assert.equal(result.flagged, true);
  assert.equal(result.detector, 'private-ipv4');
});

test('does not flag an ordinary question', () => {
  const result = detectSensitiveData('What is RAG and how does it help with an AI agent?');
  assert.equal(result.flagged, false);
  assert.equal(result.category, undefined);
});

test('does not flag Hebrew text with no sensitive content', () => {
  const result = detectSensitiveData('אני מתחיל ב-AI, מאיפה להתחיל?');
  assert.equal(result.flagged, false);
});

test('redacted excerpt masks the match but keeps surrounding context', () => {
  const result = detectSensitiveData('my key is sk-abcdefghijklmnopqrstuvwxyz123456 ok?');
  assert.equal(result.flagged, true);
  assert.ok(result.redactedExcerpt);
  assert.ok(!result.redactedExcerpt!.includes('sk-abcdefghijklmnopqrstuvwxyz123456'));
  assert.ok(result.redactedExcerpt!.includes('my key is'));
});
