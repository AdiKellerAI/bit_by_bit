import { timingSafeEqual } from 'node:crypto';

export function verifySecretToken(
  headerValue: string | undefined,
  expectedSecret: string,
): boolean {
  // Fail closed: an unconfigured secret must never be treated as "no check needed."
  if (!expectedSecret || !headerValue) {
    return false;
  }

  const a = Buffer.from(headerValue);
  const b = Buffer.from(expectedSecret);
  if (a.length !== b.length) {
    return false;
  }
  return timingSafeEqual(a, b);
}
