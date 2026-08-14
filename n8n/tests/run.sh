#!/usr/bin/env bash
# n8n Telegram workflow regression test (Phase 3). Exercises the deployed webhook over
# HTTP without needing a real Telegram round-trip (that still needs a live client — see
# .claude/skills/n8n-workflow-authoring/SKILL.md — this covers everything that CAN be
# automated: secret verification, idempotency, and the webhook_events/users writes).
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
# parameter ever changes — see the n8n-workflow-authoring skill for why the URL has this
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

# Phase 4: a message containing a fake API key must be blocked, redacted, and audited —
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
rag_match=$(psql_exec -tAc "SELECT intent FROM interaction_logs WHERE platform_user_id = '$RAG_MATCH_USER_ID'" | tr -d '[:space:]')
if [ "$rag_match" = "kb_match" ]; then
  echo "[x] RAG query matching seeded content returns kb_match"
else
  echo "[ ] RAG query matching seeded content returns kb_match (got: $rag_match)"
  fail=1
fi

RAG_NOMATCH_UPDATE_ID="1$(date +%s)"
RAG_NOMATCH_USER_ID="19$(date +%s)"
curl -s -o /dev/null -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "X-Telegram-Bot-Api-Secret-Token: $SECRET" \
  -d "{\"update_id\": $RAG_NOMATCH_UPDATE_ID, \"message\": {\"message_id\": 1, \"from\": {\"id\": $RAG_NOMATCH_USER_ID}, \"chat\": {\"id\": $RAG_NOMATCH_USER_ID, \"type\": \"private\"}, \"date\": 1735689600, \"text\": \"best pizza recipe\"}}"
sleep 1
rag_nomatch=$(psql_exec -tAc "SELECT intent FROM interaction_logs WHERE platform_user_id = '$RAG_NOMATCH_USER_ID'" | tr -d '[:space:]')
if [ "$rag_nomatch" = "no_match" ]; then
  echo "[x] unrelated RAG query returns no_match (does not fabricate an answer)"
else
  echo "[ ] unrelated RAG query returns no_match (got: $rag_nomatch)"
  fail=1
fi

psql_exec -c "DELETE FROM webhook_events WHERE platform_message_id IN ('$TEST_UPDATE_ID', '$SENSITIVE_UPDATE_ID', '$CLEAN_UPDATE_ID', '$RAG_MATCH_UPDATE_ID', '$RAG_NOMATCH_UPDATE_ID');" >/dev/null
psql_exec -c "DELETE FROM sensitive_data_events WHERE platform_user_id = '$SENSITIVE_USER_ID';" >/dev/null
psql_exec -c "DELETE FROM interaction_logs WHERE platform_user_id IN ('$TEST_USER_ID', '$SENSITIVE_USER_ID', '$CLEAN_USER_ID', '$RAG_MATCH_USER_ID', '$RAG_NOMATCH_USER_ID');" >/dev/null
psql_exec -c "DELETE FROM users WHERE platform_user_id IN ('$TEST_USER_ID', '$SENSITIVE_USER_ID', '$CLEAN_USER_ID', '$RAG_MATCH_USER_ID', '$RAG_NOMATCH_USER_ID');" >/dev/null

if [ "$fail" -eq 0 ]; then
  echo "All n8n Telegram workflow tests passed."
else
  echo "n8n Telegram workflow tests FAILED." >&2
fi
exit $fail
