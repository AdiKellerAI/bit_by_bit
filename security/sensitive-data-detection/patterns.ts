export interface SensitiveDataPattern {
  id: string;
  category: string;
  description: string;
  regex: RegExp;
  severity: 'high' | 'medium' | 'low';
}

// PROJECT-SPEC.md §4.2: "regex/heuristics are a first-pass signal," and detection patterns
// are "living configuration, not a one-time hardcoded list." This file is that
// configuration. Patterns below are generic/technical, not Elbit-specific.
export const SENSITIVE_DATA_PATTERNS: SensitiveDataPattern[] = [
  {
    id: 'openai-api-key',
    category: 'credential',
    description: 'OpenAI-style API key (sk-...)',
    // \s? after the hyphen: confirmed via real Telegram testing that mobile keyboard
    // autocomplete can insert a space after "sk-" (e.g. "sk- abc123..."), which would
    // otherwise silently defeat this pattern. Worth checking other patterns for the same
    // class of issue if real-world testing turns up more examples.
    regex: /\bsk-\s?[A-Za-z0-9]{20,}\b/,
    severity: 'high',
  },
  {
    id: 'aws-access-key-id',
    category: 'credential',
    description: 'AWS access key ID',
    regex: /\bAKIA[0-9A-Z]{16}\b/,
    severity: 'high',
  },
  {
    id: 'google-api-key',
    category: 'credential',
    description: 'Google API key',
    regex: /\bAIza[0-9A-Za-z_-]{35}\b/,
    severity: 'high',
  },
  {
    id: 'bearer-token',
    category: 'credential',
    description: 'Bearer authorization token',
    regex: /\bBearer\s+[A-Za-z0-9._-]{20,}\b/i,
    severity: 'high',
  },
  {
    id: 'generic-secret-assignment',
    category: 'credential',
    description: 'A password/secret/api_key assigned inline (e.g. "password: hunter2")',
    regex: /\b(api[_-]?key|secret|token|password|passwd|pwd)\b\s*[:=]\s*['"]?[^\s'"]{6,}['"]?/i,
    severity: 'high',
  },
  {
    id: 'private-key-block',
    category: 'credential',
    description: 'PEM private key block',
    regex: /-----BEGIN\s+(RSA|EC|OPENSSH|DSA)?\s*PRIVATE KEY-----/,
    severity: 'high',
  },
  {
    id: 'email-address',
    category: 'personal_identifier',
    description: 'Email address',
    regex: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/,
    severity: 'medium',
  },
  {
    id: 'credit-card-like-number',
    category: 'personal_identifier',
    description: '13-19 digit sequence resembling a payment card number (no Luhn check yet)',
    regex: /\b(?:\d[ -]?){13,19}\b/,
    severity: 'medium',
  },
  {
    id: 'private-ipv4',
    category: 'internal_network',
    description: 'RFC1918 private IPv4 address',
    regex: /\b(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})\b/,
    severity: 'low',
  },

  // The following categories are explicitly named in PROJECT-SPEC.md §4.2 but need input
  // from Elbit's security team before real patterns can be written (org-specific vocabulary/
  // formats) — deliberately left empty, not an oversight. See PREPARATION-CHECKLIST.md §7.3.
  // - classification markings (company-specific "CONFIDENTIAL"/"TOP SECRET"-style wording)
  // - internal ticket/case/employee ID formats
  // - source-code fragment detection (regex-only is especially prone to false positives here;
  //   may need a different approach entirely, not just more patterns)
];
