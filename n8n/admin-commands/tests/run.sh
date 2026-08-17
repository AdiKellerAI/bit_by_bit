#!/usr/bin/env bash
# Admin commands (Phase 6 LDD sub-phase 3: /pending, /prompts, /approve, /reject, /rollback)
# regression test. Deliberately does NOT drive the positive admin-gate path through the live
# webhook with the real ADMIN_TELEGRAM_CHAT_ID - doing so would deliver real Telegram messages
# to the admin's phone on every verify-all.sh run, forever (confirmed with Adi, 2026-08-15,
# this is a real DB-mutation feature, not something to spam-test). Instead this covers:
#   1. The command-parsing regex (same one used in the "Parse Admin Command" node), in isolation.
#   2. The actual SQL state transitions the workflow's nodes run (approve/confirm/reject/rollback),
#      executed directly against Postgres, with explicit save/restore of the REAL active base
#      prompt - this is the piece that actually matters (correctness of the mutation), and it's
#      exercised without needing n8n or a live Telegram send at all.
#   3. The negative admin-gate case (wrong chat_id) through the real webhook - safe, uses a
#      synthetic id, never delivers a real message (same "chat not found" pattern as every other
#      webhook test in this suite).
# The full positive round-trip (real chat_id -> real command -> real Telegram reply) was manually
# verified end-to-end once this session for every command and edge case; this script is the
# repeatable regression guard for the logic underneath it.
set -uo pipefail
cd "$(dirname "$0")/../../.."

PG_USER=$(grep -E '^POSTGRES_USER=' .env | cut -d= -f2-)
PG_DB=$(grep -E '^POSTGRES_DB=' .env | cut -d= -f2-)
SECRET=$(grep -E '^TELEGRAM_WEBHOOK_SECRET=' .env | cut -d= -f2-)
URL="http://localhost:5678/webhook/telegram-echo-bot-phase3/webhook/telegram-webhook"

if [ -z "$PG_USER" ] || [ -z "$PG_DB" ] || [ -z "$SECRET" ]; then
  echo "FAIL: POSTGRES_USER/POSTGRES_DB/TELEGRAM_WEBHOOK_SECRET not set in .env" >&2
  exit 1
fi

fail=0
psql_exec() { docker compose exec -T postgres psql -U "$PG_USER" -d "$PG_DB" "$@"; }

# --- 1. Command-parsing regex, in isolation (mirrors the exact logic in "Parse Admin Command") ---
PARSE_CHECK_JS=$(mktemp)
cat > "$PARSE_CHECK_JS" <<'JSEOF'
function parse(text) {
  let command = null, proposal_id = null, m;
  if ((m = text.match(/^\/approve\s+(\S+)$/i))) { command = 'approve'; proposal_id = m[1]; }
  else if ((m = text.match(/^\/reject\s+(\S+)$/i))) { command = 'reject'; proposal_id = m[1]; }
  else if ((m = text.match(/^\/confirm\s+approve\s+(\S+)$/i))) { command = 'confirm_approve'; proposal_id = m[1]; }
  else if (/^\/confirm\s+rollback$/i.test(text)) { command = 'confirm_rollback'; }
  else if (/^\/rollback$/i.test(text)) { command = 'rollback'; }
  else if (/^\/pending$/i.test(text)) { command = 'pending'; }
  else if (/^\/prompts$/i.test(text)) { command = 'prompts'; }
  return { command, proposal_id };
}
const cases = [
  ['/pending', { command: 'pending', proposal_id: null }],
  ['/prompts', { command: 'prompts', proposal_id: null }],
  ['/approve abc-123', { command: 'approve', proposal_id: 'abc-123' }],
  ['/reject abc-123', { command: 'reject', proposal_id: 'abc-123' }],
  ['/confirm approve abc-123', { command: 'confirm_approve', proposal_id: 'abc-123' }],
  ['/confirm rollback', { command: 'confirm_rollback', proposal_id: null }],
  ['/rollback', { command: 'rollback', proposal_id: null }],
  ['/approve', { command: null, proposal_id: null }],
  ['what is /pending anyway', { command: null, proposal_id: null }],
];
let allPass = true;
for (const [text, expected] of cases) {
  const got = parse(text);
  const pass = got.command === expected.command && got.proposal_id === expected.proposal_id;
  if (!pass) { allPass = false; console.log('MISMATCH', text, JSON.stringify(got), JSON.stringify(expected)); }
}
console.log(allPass ? 'PARSE_OK' : 'PARSE_FAIL');
JSEOF
chmod 644 "$PARSE_CHECK_JS"
docker compose cp "$PARSE_CHECK_JS" n8n:/tmp/admin-parse-check.js >/dev/null
parse_output=$(docker compose exec -T n8n node /tmp/admin-parse-check.js)
rm -f "$PARSE_CHECK_JS"
if echo "$parse_output" | grep -q '^PARSE_OK$'; then
  echo "[x] admin command regex parses every command/argument shape correctly"
else
  echo "[ ] admin command regex parsing (got: $parse_output)"
  fail=1
fi

# --- 2. Negative admin-gate case via the real webhook (synthetic id, safe, never delivers) ---
NONADMIN_ID="93$(date +%s)"
NONADMIN_UPDATE_ID="94$(date +%s)"
curl -s -o /dev/null -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "X-Telegram-Bot-Api-Secret-Token: $SECRET" \
  -d "{\"update_id\": $NONADMIN_UPDATE_ID, \"message\": {\"message_id\": 1, \"from\": {\"id\": $NONADMIN_ID}, \"chat\": {\"id\": $NONADMIN_ID, \"type\": \"private\"}, \"date\": 1735689600, \"text\": \"/pending\"}}"
sleep 2
nonadmin_row=$(psql_exec -tAc "SELECT intent FROM interaction_logs WHERE platform_user_id = '$NONADMIN_ID'" | head -1 | tr -d '[:space:]')
# Q&A is disabled (WhatsApp Community Content Agent phase 1) - the ordinary pipeline a non-admin
# falls through to now ends at qa_disabled instead of a real generation. generated_tier1_*/
# generated_tier2_* are kept here for when Q&A is ever re-enabled, not dead cruft.
if [[ "$nonadmin_row" == generated_tier1_* ]] || [[ "$nonadmin_row" == generated_tier2_* ]] || [ "$nonadmin_row" = "rate_limited" ] || [ "$nonadmin_row" = "qa_disabled" ]; then
  echo "[x] a non-admin sending /pending is NOT treated as an admin command (falls through to ordinary pipeline)"
else
  echo "[ ] a non-admin sending /pending is not treated as an admin command (got intent: $nonadmin_row)"
  fail=1
fi
psql_exec -c "DELETE FROM semantic_cache WHERE query_text = '/pending';" >/dev/null
psql_exec -c "DELETE FROM interaction_logs WHERE platform_user_id = '$NONADMIN_ID';" >/dev/null
psql_exec -c "DELETE FROM webhook_events WHERE platform_message_id = '$NONADMIN_UPDATE_ID';" >/dev/null
psql_exec -c "DELETE FROM users WHERE platform_user_id = '$NONADMIN_ID';" >/dev/null

# --- 3. SQL state transitions, directly against Postgres (the actual risky logic) ---
ORIGINAL_BASE_ID=$(psql_exec -tAc "SELECT id FROM system_prompts WHERE prompt_type = 'base' AND is_active = true;" | head -1 | tr -d '[:space:]')
if [ -z "$ORIGINAL_BASE_ID" ]; then
  echo "[ ] a real active base prompt exists to save/restore around this test - aborting" >&2
  exit 1
fi

PROPOSAL_A=$(psql_exec -tAc "
INSERT INTO prompt_change_proposals (current_prompt_id, proposed_prompt, rationale, evaluation_score, evaluation_cost_usd, status)
VALUES ('$ORIGINAL_BASE_ID', 'AUTOMATED TEST CANDIDATE PROMPT', 'Problem: test', 0.95, 0.01, 'pending')
RETURNING id;" | head -1 | tr -d '[:space:]')

# Mirrors "Get Proposal For Approve": must find it, status pending.
approve_lookup=$(psql_exec -tAc "SELECT status FROM prompt_change_proposals WHERE id::text = '$PROPOSAL_A';" | head -1 | tr -d '[:space:]')
if [ "$approve_lookup" = "pending" ]; then
  echo "[x] proposal lookup by id finds the pending proposal (mirrors Get Proposal For Approve)"
else
  echo "[ ] proposal lookup by id finds the pending proposal (got: $approve_lookup)"
  fail=1
fi

# Mirrors "Deactivate Current Base Prompt" -> "Activate New Base Prompt" -> "Mark Proposal Approved".
psql_exec -c "UPDATE system_prompts SET is_active = false WHERE prompt_type = 'base' AND is_active = true;" >/dev/null
NEW_ID=$(psql_exec -tAc "
INSERT INTO system_prompts (version_tag, prompt_type, prompt_text, is_active, created_by)
VALUES ('v' || ((SELECT count(*) FROM system_prompts WHERE prompt_type = 'base')), 'base', 'AUTOMATED TEST CANDIDATE PROMPT', true, 'test')
RETURNING id;" | head -1 | tr -d '[:space:]')
psql_exec -c "UPDATE prompt_change_proposals SET status = 'approved', approved_by = 'test-admin' WHERE id::text = '$PROPOSAL_A';" >/dev/null

activation_check=$(psql_exec -tAc "SELECT is_active::text FROM system_prompts WHERE id = '$NEW_ID';" | head -1 | tr -d '[:space:]')
old_deactivated=$(psql_exec -tAc "SELECT is_active::text FROM system_prompts WHERE id = '$ORIGINAL_BASE_ID';" | head -1 | tr -d '[:space:]')
proposal_status=$(psql_exec -tAc "SELECT status FROM prompt_change_proposals WHERE id::text = '$PROPOSAL_A';" | head -1 | tr -d '[:space:]')
if [ "$activation_check" = "true" ] && [ "$old_deactivated" = "false" ] && [ "$proposal_status" = "approved" ]; then
  echo "[x] activation deactivates the old base prompt, activates the new one, marks the proposal approved"
else
  echo "[ ] activation state transition (new active: $activation_check, old deactivated: $old_deactivated, proposal status: $proposal_status)"
  fail=1
fi

# Mirrors "Find Rollback Target": most recently superseded base version.
rollback_target=$(psql_exec -tAc "SELECT id FROM system_prompts WHERE prompt_type = 'base' AND is_active = false ORDER BY created_at DESC LIMIT 1;" | head -1 | tr -d '[:space:]')
if [ "$rollback_target" = "$ORIGINAL_BASE_ID" ]; then
  echo "[x] rollback target correctly resolves to the just-superseded (original) base prompt"
else
  echo "[ ] rollback target resolution (expected: $ORIGINAL_BASE_ID, got: $rollback_target)"
  fail=1
fi

# Mirrors "Deactivate Current Base Prompt (Rollback)" -> "Reactivate Rollback Target".
psql_exec -c "UPDATE system_prompts SET is_active = false WHERE prompt_type = 'base' AND is_active = true;" >/dev/null
psql_exec -c "UPDATE system_prompts SET is_active = true WHERE id = '$ORIGINAL_BASE_ID';" >/dev/null
final_active=$(psql_exec -tAc "SELECT id FROM system_prompts WHERE prompt_type = 'base' AND is_active = true;" | head -1 | tr -d '[:space:]')
if [ "$final_active" = "$ORIGINAL_BASE_ID" ]; then
  echo "[x] rollback correctly restores the original base prompt as active"
else
  echo "[ ] rollback restoration (expected: $ORIGINAL_BASE_ID, got: $final_active)"
  fail=1
fi

# Mirrors "Reject Proposal": WITH-CTE UPDATE...RETURNING pattern, only affects pending rows.
PROPOSAL_B=$(psql_exec -tAc "
INSERT INTO prompt_change_proposals (proposed_prompt, rationale, evaluation_score, evaluation_cost_usd, status)
VALUES ('AUTOMATED TEST CANDIDATE B', 'Problem: test2', 0.5, 0.01, 'pending')
RETURNING id;" | head -1 | tr -d '[:space:]')
reject_result=$(psql_exec -tAc "
WITH updated AS (
  UPDATE prompt_change_proposals SET status = 'rejected', approved_by = 'test-admin' WHERE id::text = '$PROPOSAL_B' AND status = 'pending' RETURNING id
)
SELECT u.id FROM (SELECT 1) AS dummy LEFT JOIN updated u ON true LIMIT 1;" | head -1 | tr -d '[:space:]')
reject_again=$(psql_exec -tAc "
WITH updated AS (
  UPDATE prompt_change_proposals SET status = 'rejected', approved_by = 'test-admin' WHERE id::text = '$PROPOSAL_B' AND status = 'pending' RETURNING id
)
SELECT u.id FROM (SELECT 1) AS dummy LEFT JOIN updated u ON true LIMIT 1;" | head -1 | tr -d '[:space:]')
if [ -n "$reject_result" ] && [ -z "$reject_again" ]; then
  echo "[x] reject applies once and is a no-op on an already-rejected proposal (defensive WITH-CTE pattern)"
else
  echo "[ ] reject state transition (first: '$reject_result', second: '$reject_again')"
  fail=1
fi

# --- Cleanup + final state verification (this test mutates the real active base prompt) ---
psql_exec -c "DELETE FROM system_prompts WHERE id = '$NEW_ID';" >/dev/null
psql_exec -c "DELETE FROM prompt_change_proposals WHERE id::text IN ('$PROPOSAL_A', '$PROPOSAL_B');" >/dev/null

final_check=$(psql_exec -tAc "SELECT id::text || '|' || is_active::text FROM system_prompts WHERE prompt_type = 'base' AND is_active = true;" | head -1 | tr -d '[:space:]')
if [ "$final_check" = "${ORIGINAL_BASE_ID}|true" ]; then
  echo "[x] real active base prompt fully restored to its pre-test state"
else
  echo "[ ] real active base prompt NOT fully restored (got: $final_check, expected: ${ORIGINAL_BASE_ID}|true)" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "All admin command tests passed."
else
  echo "Admin command tests FAILED." >&2
fi
exit $fail
