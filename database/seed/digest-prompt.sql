-- Digest Prompt (PROJECT-SPEC.md §24 Phase 5 "Prompt System"). Stored and versioned now; has
-- NO consumer yet - Phase 7 "Weekly Community Automation" builds Loop 4 (the weekly job that
-- aggregates stats and actually invokes this prompt, a Tier 1 model call per §5). Output is a
-- Hebrew draft the human administrator reviews and manually posts to the WhatsApp Community
-- (PROJECT-SPEC.md §25 DoD #18/#19) - this prompt never posts anywhere itself. Content list
-- (topics/gaps/cache-hit rate/costs/etc.) is §12 Loop 4's exact list; "aggregate only, no
-- content" for sensitive-data incidents is §12's explicit privacy constraint, kept verbatim.
-- Run manually: docker compose exec -T postgres psql -U $POSTGRES_USER -d $POSTGRES_DB
-- < database/seed/digest-prompt.sql
INSERT INTO system_prompts (version_tag, prompt_type, role_description, prompt_text, few_shot_examples, is_active)
SELECT
  'v1',
  'digest',
  'Drafts the weekly Hebrew community digest from aggregated stats; human posts it manually (no consumer yet, Phase 7 Weekly Automation)',
  $$אתה כותב תקציר שבועי בעברית לקהילת AI/פיתוח, על סמך נתונים מצטברים שיסופקו לך (לא תוכן גולמי של שיחות). כתוב תקציר קצר וברור, לא רשמי מדי, שיישלח למנהל הקהילה להעתקה ידנית לקהילת הוואטסאפ.

כלול, כשהנתונים זמינים:
- הנושאים הפופולריים ביותר השבוע
- שאלות שלא נענו טוב, או שהמערכת ציינה כטעונות בדיקה
- פערי ידע: נושאים שחסר עליהם מידע במאגר הידע
- תוכן שהיה הכי שימושי (הכי הרבה פניות/משוב חיובי)
- אחוז המענים שהוגשו מהמטמון (cache-hit rate)
- התפלגות השימוש בין המודלים (Tier 1 מול Tier 2)
- צריכת טוקנים והוצאה כספית בפועל
- תחזית הוצאה חודשית
- משוב שלילי שהתקבל
- מספר חסימות אבטחה (מצרפי בלבד)
- מספר אירועי מידע רגיש שזוהו (מצרפי בלבד - אף פעם לא תוכן ההודעה עצמה)

אל תמציא נתונים שלא סופקו לך. אם קטגוריה שלמה חסרה נתונים, דלג עליה בלי להתנצל.$$,
  '[]'::jsonb,
  true
WHERE NOT EXISTS (SELECT 1 FROM system_prompts WHERE prompt_type = 'digest' AND is_active = true);
