#!/usr/bin/env bash
# n8n Telegram workflow regression test. Exercises the deployed webhook over HTTP without
# needing a real Telegram round-trip (see .claude/skills/n8n-workflow-authoring/SKILL.md -
# this covers everything that CAN be automated: secret verification, idempotency,
# webhook_events/users writes, sensitive-data screening, and the qa-disabled path.
#
# WhatsApp Community Content Agent phase 1 turned off the 1:1 Q&A/RAG/generation path (see
# CLAUDE.md) - every message that reaches Sensitive Data Flagged?'s false branch now ends at
# a fixed qa_disabled log row instead of a real generation. The RAG-match/no-match, Tier 1/
# Tier 2 routing, semantic cache, Security Prompt signal, and base-prompt-selection tests that
# used to live here tested real generation behavior on a path that's now intentionally
# unreachable - removed rather than left red. That coverage isn't lost, just dormant: it can
# be restored from git history (see the commit that added this comment) if Q&A is ever
# re-enabled, since the underlying nodes/logic are still in the workflow file, only orphaned.
set -uo pipefail
cd "$(dirname "$0")/../.."

PG_USER=$(grep -E '^POSTGRES_USER=' .env | cut -d= -f2-)
PG_DB=$(grep -E '^POSTGRES_DB=' .env | cut -d= -f2-)
SECRET=$(grep -E '^TELEGRAM_WEBHOOK_SECRET=' .env | cut -d= -f2-)

if [ -z "$PG_USER" ] || [ -z "$PG_DB" ] || [ -z "$SECRET" ]; then
  echo "FAIL: POSTGRES_USER/POSTGRES_DB/TELEGRAM_WEBHOOK_SECRET not set in .env" >&2
  exit 1
fi

# Update this if n8n/workflows/telegram-echo-bot.json's workflow id or webhook "path"
# parameter ever changes - see the n8n-workflow-authoring skill for why the URL has this
# shape (workflow id appears twice) in this n8n version.
URL="http://localhost:5678/webhook/telegram-echo-bot-phase3/webhook/telegram-webhook"

TEST_UPDATE_ID="9$(date +%s)"
TEST_USER_ID="8$(date +%s)"

fail=0
psql_exec() { docker compose exec -T postgres psql -U "$PG_USER" -d "$PG_DB" "$@"; }

code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "X-Telegram-Bot-Api-Secret-Token: wrong-secret-for-testing" \
  -d '{"update_id": 1, "message": {"message_id": 1, "from": {"id": 1}, "chat": {"id": 1, "type": "private"}, "date": 0, "text": "x"}}')
if [ "$code" = "401" ]; then
  echo "[x] wrong secret rejected with 401"
else
  echo "[ ] wrong secret rejected with 401 (got $code)"
  fail=1
fi

curl -s -o /dev/null -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "X-Telegram-Bot-Api-Secret-Token: $SECRET" \
  -d "{\"update_id\": $TEST_UPDATE_ID, \"message\": {\"message_id\": 1, \"from\": {\"id\": $TEST_USER_ID}, \"chat\": {\"id\": $TEST_USER_ID, \"type\": \"private\"}, \"date\": 1735689600, \"text\": \"verify-all test\"}}"
sleep 1
row_count=$(psql_exec -tAc "SELECT count(*) FROM webhook_events WHERE platform_message_id = '$TEST_UPDATE_ID'" | tr -d '[:space:]')
if [ "$row_count" = "1" ]; then
  echo "[x] valid message recorded in webhook_events"
else
  echo "[ ] valid message recorded in webhook_events (found $row_count rows)"
  fail=1
fi

body=$(curl -s -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "X-Telegram-Bot-Api-Secret-Token: $SECRET" \
  -d "{\"update_id\": $TEST_UPDATE_ID, \"message\": {\"message_id\": 1, \"from\": {\"id\": $TEST_USER_ID}, \"chat\": {\"id\": $TEST_USER_ID, \"type\": \"private\"}, \"date\": 1735689600, \"text\": \"verify-all test\"}}")
if [ "$body" = "duplicate" ]; then
  echo "[x] replayed update_id detected as duplicate"
else
  echo "[ ] replayed update_id detected as duplicate (got: $body)"
  fail=1
fi

# Sensitive-data detection is a distinct, always-on pre-LLM control (ADR-0003) - it runs
# regardless of whether Q&A is enabled, and phase 1 deliberately did not touch it. A message
# containing a fake API key must still be blocked, redacted, and audited - never reach
# interaction_logs.user_query in raw form.
SENSITIVE_UPDATE_ID="7$(date +%s)"
SENSITIVE_USER_ID="6$(date +%s)"
curl -s -o /dev/null -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "X-Telegram-Bot-Api-Secret-Token: $SECRET" \
  -d "{\"update_id\": $SENSITIVE_UPDATE_ID, \"message\": {\"message_id\": 1, \"from\": {\"id\": $SENSITIVE_USER_ID}, \"chat\": {\"id\": $SENSITIVE_USER_ID, \"type\": \"private\"}, \"date\": 1735689600, \"text\": \"here is my key sk-abcdefghijklmnopqrstuvwxyz123456\"}}"
sleep 1
event_count=$(psql_exec -tAc "SELECT count(*) FROM sensitive_data_events WHERE platform_user_id = '$SENSITIVE_USER_ID' AND detector = 'openai-api-key'" | tr -d '[:space:]')
if [ "$event_count" = "1" ]; then
  echo "[x] sensitive-data message recorded in sensitive_data_events"
else
  echo "[ ] sensitive-data message recorded in sensitive_data_events (found $event_count rows)"
  fail=1
fi
raw_secret_stored=$(psql_exec -tAc "SELECT count(*) FROM interaction_logs WHERE platform_user_id = '$SENSITIVE_USER_ID' AND user_query LIKE '%sk-abcdefghijklmnopqrstuvwxyz123456%'" | tr -d '[:space:]')
if [ "$raw_secret_stored" = "0" ]; then
  echo "[x] raw secret is not stored in interaction_logs.user_query"
else
  echo "[ ] raw secret is not stored in interaction_logs.user_query (found $raw_secret_stored rows containing it)"
  fail=1
fi
flagged_logged=$(psql_exec -tAc "SELECT count(*) FROM interaction_logs WHERE platform_user_id = '$SENSITIVE_USER_ID' AND sensitive_data_flagged = true" | tr -d '[:space:]')
if [ "$flagged_logged" = "1" ]; then
  echo "[x] flagged interaction_logs row created"
else
  echo "[ ] flagged interaction_logs row created (found $flagged_logged rows)"
  fail=1
fi

# A clean message reaches the qa_disabled path with language/classification populated (still
# computed - that's upstream of the disabled cut), no model/tokens/cost (nothing downstream ran).
CLEAN_UPDATE_ID="5$(date +%s)"
CLEAN_USER_ID="4$(date +%s)"
curl -s -o /dev/null -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "X-Telegram-Bot-Api-Secret-Token: $SECRET" \
  -d "{\"update_id\": $CLEAN_UPDATE_ID, \"message\": {\"message_id\": 1, \"from\": {\"id\": $CLEAN_USER_ID}, \"chat\": {\"id\": $CLEAN_USER_ID, \"type\": \"private\"}, \"date\": 1735689600, \"text\": \"What is RAG?\"}}"
sleep 1
clean_row=$(psql_exec -tAc "SELECT intent || '|' || security_classification || '|' || (language IS NOT NULL)::text || '|' || (routed_model IS NULL)::text || '|' || (cost_usd IS NULL)::text FROM interaction_logs WHERE platform_user_id = '$CLEAN_USER_ID'" | tr -d '[:space:]')
if [ "$clean_row" = "qa_disabled|PUBLIC|true|true|true" ]; then
  echo "[x] clean message reaches qa_disabled with language/classification tracked, no model/cost"
else
  echo "[ ] clean message reaches qa_disabled with tracking intact (got: $clean_row)"
  fail=1
fi

# Rate limit: 10 messages/60s per user, checked before the qa_disabled path - unaffected by Q&A
# being on/off. Fire 12 rapid requests (no sleep between) for one user; 11th/12th throttled.
RATE_LIMIT_USER_ID="21$(date +%s)"
RATE_LIMIT_PREFIX="21$(date +%s)"
for i in $(seq 1 12); do
  curl -s -o /dev/null -X POST "$URL" \
    -H "Content-Type: application/json" \
    -H "X-Telegram-Bot-Api-Secret-Token: $SECRET" \
    -d "{\"update_id\": ${RATE_LIMIT_PREFIX}${i}, \"message\": {\"message_id\": $i, \"from\": {\"id\": $RATE_LIMIT_USER_ID}, \"chat\": {\"id\": $RATE_LIMIT_USER_ID, \"type\": \"private\"}, \"date\": 1735689600, \"text\": \"rate limit test message\"}}"
done
sleep 2
rate_limited_count=$(psql_exec -tAc "SELECT count(*) FROM interaction_logs WHERE platform_user_id = '$RATE_LIMIT_USER_ID' AND intent = 'rate_limited'" | tr -d '[:space:]')
allowed_count=$(psql_exec -tAc "SELECT count(*) FROM interaction_logs WHERE platform_user_id = '$RATE_LIMIT_USER_ID' AND intent != 'rate_limited'" | tr -d '[:space:]')
if [ "$rate_limited_count" = "2" ] && [ "$allowed_count" = "10" ]; then
  echo "[x] 11th/12th rapid request from one user is rate-limited (10 allowed, 2 throttled)"
else
  echo "[ ] 11th/12th rapid request from one user is rate-limited (got: $allowed_count allowed, $rate_limited_count throttled)"
  fail=1
fi

# Output-side sensitive-data check. Unit-style: verifies the same PATTERNS regex list used
# verbatim in the (now-dormant) "Validate Tier 1/2 Output" nodes, independent of whether that
# generation path is reachable - the regex list itself is still correct and worth guarding.
SENSITIVE_CHECK_JS=$(mktemp)
cat > "$SENSITIVE_CHECK_JS" <<'JSEOF'
const PATTERNS = [
  { id: 'openai-api-key', category: 'credential', regex: /\bsk-\s?[A-Za-z0-9]{20,}\b/ },
  { id: 'aws-access-key-id', category: 'credential', regex: /\bAKIA[0-9A-Z]{16}\b/ },
  { id: 'google-api-key', category: 'credential', regex: /\bAIza[0-9A-Za-z_-]{35}\b/ },
  { id: 'bearer-token', category: 'credential', regex: /\bBearer\s+[A-Za-z0-9._-]{20,}\b/i },
  { id: 'generic-secret-assignment', category: 'credential', regex: /\b(api[_-]?key|secret|token|password|passwd|pwd)\b\s*[:=]\s*['"]?[^\s'"]{6,}['"]?/i },
  { id: 'private-key-block', category: 'credential', regex: /-----BEGIN\s+(RSA|EC|OPENSSH|DSA)?\s*PRIVATE KEY-----/ },
  { id: 'email-address', category: 'personal_identifier', regex: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/ },
  { id: 'credit-card-like-number', category: 'personal_identifier', regex: /\b(?:\d[ -]?){13,19}\b/ },
  { id: 'private-ipv4', category: 'internal_network', regex: /\b(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})\b/ },
];

function flaggedFor(text) {
  for (const p of PATTERNS) { if (p.regex.test(text)) return true; }
  return false;
}

const secretText = 'Sure, here is a working example: sk-abcdefghijklmnopqrstuvwxyz123456';
const cleanText = 'RAG combines retrieval with generation to ground LLM answers in real documents.';

console.log(flaggedFor(secretText) ? 'SECRET_FLAGGED' : 'SECRET_NOT_FLAGGED');
console.log(flaggedFor(cleanText) ? 'CLEAN_FLAGGED' : 'CLEAN_NOT_FLAGGED');
JSEOF
chmod 644 "$SENSITIVE_CHECK_JS"
docker compose cp "$SENSITIVE_CHECK_JS" n8n:/tmp/sensitive-check.js >/dev/null
sensitive_check_output=$(docker compose exec -T n8n node /tmp/sensitive-check.js)
rm -f "$SENSITIVE_CHECK_JS"
if echo "$sensitive_check_output" | grep -q '^SECRET_FLAGGED$' && echo "$sensitive_check_output" | grep -q '^CLEAN_NOT_FLAGGED$'; then
  echo "[x] output-side sensitive-data PATTERNS flag a leaked secret and pass clean generated text"
else
  echo "[ ] output-side sensitive-data PATTERNS check failed (got: $sensitive_check_output)"
  fail=1
fi

psql_exec -c "DELETE FROM webhook_events WHERE platform_message_id IN ('$TEST_UPDATE_ID', '$SENSITIVE_UPDATE_ID', '$CLEAN_UPDATE_ID') OR platform_message_id LIKE '${RATE_LIMIT_PREFIX}%';" >/dev/null
psql_exec -c "DELETE FROM sensitive_data_events WHERE platform_user_id = '$SENSITIVE_USER_ID';" >/dev/null
psql_exec -c "DELETE FROM interaction_logs WHERE platform_user_id IN ('$TEST_USER_ID', '$SENSITIVE_USER_ID', '$CLEAN_USER_ID', '$RATE_LIMIT_USER_ID');" >/dev/null
psql_exec -c "DELETE FROM users WHERE platform_user_id IN ('$TEST_USER_ID', '$SENSITIVE_USER_ID', '$CLEAN_USER_ID', '$RATE_LIMIT_USER_ID');" >/dev/null

if [ "$fail" -eq 0 ]; then
  echo "All n8n Telegram workflow tests passed."
else
  echo "n8n Telegram workflow tests FAILED." >&2
fi
exit $fail
