import { test } from 'node:test';
import assert from 'node:assert/strict';
import { detectLanguage } from './language-detect.ts';

test('detects Hebrew text', () => {
  assert.equal(detectLanguage('אני מתחיל ב-AI, מאיפה להתחיל?'), 'he');
});

test('detects English text', () => {
  assert.equal(detectLanguage('What is RAG?'), 'en');
});

test('treats mixed Hebrew/English (Heblish) as Hebrew', () => {
  assert.equal(detectLanguage('אפשר להשתמש ב-RAG כדי לתת ל-Agent גישה ל-Knowledge Base'), 'he');
});

test('treats empty string as English (default)', () => {
  assert.equal(detectLanguage(''), 'en');
});
