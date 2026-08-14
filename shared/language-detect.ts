export type DetectedLanguage = 'he' | 'en';

const HEBREW_RANGE = /[֐-׿]/;

// Tier-0/no-LLM heuristic (PROJECT-SPEC.md §5): presence of any Hebrew-range character means
// Hebrew, per the Hebrew-primary language strategy (§14) - the Agent mirrors whichever
// language the user actually wrote in, so this only needs to distinguish the two scripts the
// community uses, not do full language identification.
export function detectLanguage(text: string): DetectedLanguage {
  return HEBREW_RANGE.test(text) ? 'he' : 'en';
}
