#!/usr/bin/env bash
# n8n Telegram workflow regression test (Phase 3-6). Exercises the deployed webhook over
# HTTP without needing a real Telegram round-trip (that still needs a live client - see
# .claude/skills/n8n-workflow-authoring/SKILL.md - this covers everything that CAN be
# automated: secret verification, idempotency, webhook_events/users writes, RAG matching,
# and Generation-phase tier routing/logging.
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

# Phase 4: a message containing a fake API key must be blocked, redacted, and audited -
# never reach interaction_logs.user_query in raw form (PROJECT-SPEC.md §4.2/§4.3).
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

# A clean message should still reach interaction_logs with PUBLIC classification.
CLEAN_UPDATE_ID="5$(date +%s)"
CLEAN_USER_ID="4$(date +%s)"
curl -s -o /dev/null -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "X-Telegram-Bot-Api-Secret-Token: $SECRET" \
  -d "{\"update_id\": $CLEAN_UPDATE_ID, \"message\": {\"message_id\": 1, \"from\": {\"id\": $CLEAN_USER_ID}, \"chat\": {\"id\": $CLEAN_USER_ID, \"type\": \"private\"}, \"date\": 1735689600, \"text\": \"What is RAG?\"}}"
sleep 1
clean_logged=$(psql_exec -tAc "SELECT count(*) FROM interaction_logs WHERE platform_user_id = '$CLEAN_USER_ID' AND security_classification = 'PUBLIC' AND sensitive_data_flagged = false" | tr -d '[:space:]')
if [ "$clean_logged" = "1" ]; then
  echo "[x] clean message logged with PUBLIC classification"
else
  echo "[ ] clean message logged with PUBLIC classification (found $clean_logged rows)"
  fail=1
fi

# Phase 5: RAG retrieval. Calls the real OpenAI embeddings API (tiny real cost, same as the
# sensitive-data/clean checks above) and the real seeded knowledge_base.
RAG_MATCH_UPDATE_ID="3$(date +%s)"
RAG_MATCH_USER_ID="2$(date +%s)"
curl -s -o /dev/null -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "X-Telegram-Bot-Api-Secret-Token: $SECRET" \
  -d "{\"update_id\": $RAG_MATCH_UPDATE_ID, \"message\": {\"message_id\": 1, \"from\": {\"id\": $RAG_MATCH_USER_ID}, \"chat\": {\"id\": $RAG_MATCH_USER_ID, \"type\": \"private\"}, \"date\": 1735689600, \"text\": \"Tell me about LangTalks podcast\"}}"
sleep 1
rag_match=$(psql_exec -tAc "SELECT intent || '|' || routed_model FROM interaction_logs WHERE platform_user_id = '$RAG_MATCH_USER_ID'" | tr -d '[:space:]')
if [ "$rag_match" = "kb_match|none" ]; then
  echo "[x] RAG query matching seeded content returns kb_match and short-circuits to Tier 0 (routed_model=none)"
else
  echo "[ ] RAG query matching seeded content returns kb_match and short-circuits to Tier 0 (got: $rag_match)"
  fail=1
fi

RAG_NOMATCH_UPDATE_ID="1$(date +%s)"
RAG_NOMATCH_USER_ID="19$(date +%s)"
curl -s -o /dev/null -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "X-Telegram-Bot-Api-Secret-Token: $SECRET" \
  -d "{\"update_id\": $RAG_NOMATCH_UPDATE_ID, \"message\": {\"message_id\": 1, \"from\": {\"id\": $RAG_NOMATCH_USER_ID}, \"chat\": {\"id\": $RAG_NOMATCH_USER_ID, \"type\": \"private\"}, \"date\": 1735689600, \"text\": \"best pizza recipe\"}}"
sleep 1
# Phase 5 had this return a static no_match template; Phase 6 (Generation) supersedes that -
# an unrelated query now gets a real generated answer instead of a canned "I don't know", as
# long as it does NOT fabricate a KB citation (intent must not be kb_match).
rag_nomatch=$(psql_exec -tAc "SELECT intent FROM interaction_logs WHERE platform_user_id = '$RAG_NOMATCH_USER_ID'" | tr -d '[:space:]')
if [ "$rag_nomatch" = "generated_tier1" ] || [ "$rag_nomatch" = "generated_tier2" ]; then
  echo "[x] unrelated RAG query does not fabricate a KB match; gets a real generated answer instead (intent: $rag_nomatch)"
else
  echo "[ ] unrelated RAG query does not fabricate a KB match (got intent: $rag_nomatch)"
  fail=1
fi

# Phase 6: Tier 1 (fast/cheap model) - a short, simple, KB-unrelated question should route to
# gpt-5.4-nano and get a real generated reply, logged with routed_model/tokens/cost.
TIER1_UPDATE_ID="33$(date +%s)"
TIER1_USER_ID="34$(date +%s)"
curl -s -o /dev/null -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "X-Telegram-Bot-Api-Secret-Token: $SECRET" \
  -d "{\"update_id\": $TIER1_UPDATE_ID, \"message\": {\"message_id\": 1, \"from\": {\"id\": $TIER1_USER_ID}, \"chat\": {\"id\": $TIER1_USER_ID, \"type\": \"private\"}, \"date\": 1735689600, \"text\": \"What's a quick way to reverse a string in Python?\"}}"
sleep 3
tier1_row=$(psql_exec -tAc "SELECT routed_model || '|' || intent || '|' || (cost_usd > 0)::text || '|' || (input_tokens > 0)::text || '|' || (output_tokens > 0)::text FROM interaction_logs WHERE platform_user_id = '$TIER1_USER_ID'")
if [ "$tier1_row" = "gpt-5.4-nano|generated_tier1|true|true|true" ]; then
  echo "[x] simple KB-unrelated question routes to Tier 1 (gpt-5.4-nano) with tokens/cost logged"
else
  echo "[ ] simple KB-unrelated question routes to Tier 1 (got: $tier1_row)"
  fail=1
fi

# Phase 6: Tier 2 (escalation model) - a complexity-signaling question should route to
# claude-sonnet-5.
TIER2_UPDATE_ID="35$(date +%s)"
TIER2_USER_ID="36$(date +%s)"
curl -s -o /dev/null -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "X-Telegram-Bot-Api-Secret-Token: $SECRET" \
  -d "{\"update_id\": $TIER2_UPDATE_ID, \"message\": {\"message_id\": 1, \"from\": {\"id\": $TIER2_USER_ID}, \"chat\": {\"id\": $TIER2_USER_ID, \"type\": \"private\"}, \"date\": 1735689600, \"text\": \"Please explain in detail how a hash table works internally and compare it to a binary search tree for lookup performance.\"}}"
sleep 3
tier2_row=$(psql_exec -tAc "SELECT routed_model || '|' || intent || '|' || (cost_usd > 0)::text || '|' || (input_tokens > 0)::text || '|' || (output_tokens > 0)::text FROM interaction_logs WHERE platform_user_id = '$TIER2_USER_ID'")
if [ "$tier2_row" = "claude-sonnet-5|generated_tier2|true|true|true" ]; then
  echo "[x] complexity-signaling question routes to Tier 2 (claude-sonnet-5) with tokens/cost logged"
else
  echo "[ ] complexity-signaling question routes to Tier 2 (got: $tier2_row)"
  fail=1
fi

# Phase 6: output-side sensitive-data check. Real LLMs won't reliably reproduce a fake secret
# on demand, so rather than forcing a flaky end-to-end Telegram round-trip, this verifies the
# same PATTERNS regex list used verbatim in the "Validate Tier 1/2 Output" nodes directly
# (unit-style), mirroring the input-side check further up. Runs inside the n8n container so it
# doesn't depend on a local node install.
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

psql_exec -c "DELETE FROM webhook_events WHERE platform_message_id IN ('$TEST_UPDATE_ID', '$SENSITIVE_UPDATE_ID', '$CLEAN_UPDATE_ID', '$RAG_MATCH_UPDATE_ID', '$RAG_NOMATCH_UPDATE_ID', '$TIER1_UPDATE_ID', '$TIER2_UPDATE_ID');" >/dev/null
psql_exec -c "DELETE FROM sensitive_data_events WHERE platform_user_id = '$SENSITIVE_USER_ID';" >/dev/null
psql_exec -c "DELETE FROM interaction_logs WHERE platform_user_id IN ('$TEST_USER_ID', '$SENSITIVE_USER_ID', '$CLEAN_USER_ID', '$RAG_MATCH_USER_ID', '$RAG_NOMATCH_USER_ID', '$TIER1_USER_ID', '$TIER2_USER_ID');" >/dev/null
psql_exec -c "DELETE FROM users WHERE platform_user_id IN ('$TEST_USER_ID', '$SENSITIVE_USER_ID', '$CLEAN_USER_ID', '$RAG_MATCH_USER_ID', '$RAG_NOMATCH_USER_ID', '$TIER1_USER_ID', '$TIER2_USER_ID');" >/dev/null

if [ "$fail" -eq 0 ]; then
  echo "All n8n Telegram workflow tests passed."
else
  echo "n8n Telegram workflow tests FAILED." >&2
fi
exit $fail
