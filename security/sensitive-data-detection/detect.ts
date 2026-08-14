import { SENSITIVE_DATA_PATTERNS } from './patterns.ts';

export interface SensitiveDataDetectionResult {
  flagged: boolean;
  category?: string;
  detector?: string;
  redactedExcerpt?: string;
}

const REDACTION_CONTEXT_CHARS = 15;

// PREPARATION-CHECKLIST.md §13: store a redacted excerpt, not the raw sensitive content.
// Masks only the matched substring, keeps surrounding context so an admin can still judge
// intent without seeing the actual secret.
function redact(text: string, match: RegExpMatchArray): string {
  const start = match.index ?? 0;
  const end = start + match[0].length;
  const before = text.slice(Math.max(0, start - REDACTION_CONTEXT_CHARS), start);
  const after = text.slice(end, end + REDACTION_CONTEXT_CHARS);
  return `${before}${'*'.repeat(Math.min(match[0].length, 12))}${after}`.trim();
}

export function detectSensitiveData(text: string): SensitiveDataDetectionResult {
  for (const pattern of SENSITIVE_DATA_PATTERNS) {
    const match = text.match(pattern.regex);
    if (match) {
      return {
        flagged: true,
        category: pattern.category,
        detector: pattern.id,
        redactedExcerpt: redact(text, match),
      };
    }
  }
  return { flagged: false };
}
