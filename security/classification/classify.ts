export type SecurityClassification = 'PUBLIC' | 'INTERNAL' | 'SENSITIVE' | 'CLASSIFIED';

// STUB, not a real classifier: always returns PUBLIC. PROJECT-SPEC.md §4.4's MVP policy is
// PUBLIC-may-proceed / everything-else-blocked, but without an LLM tier or org-specific
// signals there is no real basis yet to detect INTERNAL/SENSITIVE/CLASSIFIED content. This
// function, the IF branch that consumes it, and interaction_logs.security_classification are
// wired correctly so real classification logic drops in later without restructuring the
// pipeline. Do not treat this as a working security control on its own - the sensitive-data
// detector (security/sensitive-data-detection) is the real control at this phase.
export function classify(_text: string): SecurityClassification {
  return 'PUBLIC';
}
