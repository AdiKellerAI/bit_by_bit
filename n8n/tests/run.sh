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

psql_exec -c "DELETE FROM webhook_events WHERE platform_message_id = '$TEST_UPDATE_ID';" >/dev/null
psql_exec -c "DELETE FROM users WHERE platform_user_id = '$TEST_USER_ID';" >/dev/null

if [ "$fail" -eq 0 ]; then
  echo "All n8n Telegram workflow tests passed."
else
  echo "n8n Telegram workflow tests FAILED." >&2
fi
exit $fail
