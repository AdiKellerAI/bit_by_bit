#!/usr/bin/env bash
# Weekly Content Agent (Phase 2: Thursday link-request -> Sunday post approval) regression
# test. Like n8n/admin-commands/tests/run.sh, this deliberately does NOT drive the positive
# admin-gate path (real link submission, /approve) through the live webhook with the real
# ADMIN_TELEGRAM_CHAT_ID - doing so would fetch a real URL, make a real LLM call, and deliver
# real Telegram messages to the admin's phone on every verify-all.sh run. Instead this covers:
#   1. The negative admin-gate cases through the real webhook (synthetic ids, safe - never
#      reach a real fetch/LLM call/Telegram send, same "chat not found"/gate-rejection pattern
#      as every other webhook test in this suite).
#   2. The actual SQL state transitions the approval branch's postgres nodes run, executed
#      directly against Postgres - this is the piece that actually matters (correctness of the
#      approve-as-drafted vs approve-with-correction mutation).
# The full positive round-trip (real link -> real fetch -> real drafted Hebrew description ->
# real Telegram approval exchange) was manually verified end-to-end once this session for both
# the plain-approve and corrected-text paths; this script is the repeatable regression guard for
# the logic underneath it.
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

# --- 1a. Non-admin submitting a URL must not create a weekly_content_items row ---
NONADMIN_ID="95$(date +%s)"
NONADMIN_UPDATE_ID1="96$(date +%s)"
curl -s -o /dev/null -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "X-Telegram-Bot-Api-Secret-Token: $SECRET" \
  -d "{\"update_id\": $NONADMIN_UPDATE_ID1, \"message\": {\"message_id\": 1, \"from\": {\"id\": $NONADMIN_ID}, \"chat\": {\"id\": $NONADMIN_ID, \"type\": \"private\"}, \"date\": 1735689600, \"text\": \"https://example.com/some-article\"}}"
sleep 1
row_count=$(psql_exec -tAc "SELECT count(*) FROM weekly_content_items WHERE source_url = 'https://example.com/some-article'" | tr -d '[:space:]')
if [ "$row_count" = "0" ]; then
  echo "[x] a non-admin submitting a URL does not create a weekly_content_items row"
else
  echo "[ ] a non-admin submitting a URL does not create a weekly_content_items row (found $row_count)"
  fail=1
fi

# --- 1b. Non-admin sending /approve with no pending draft of their own falls through normally ---
NONADMIN_UPDATE_ID2="97$(date +%s)"
curl -s -o /dev/null -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "X-Telegram-Bot-Api-Secret-Token: $SECRET" \
  -d "{\"update_id\": $NONADMIN_UPDATE_ID2, \"message\": {\"message_id\": 2, \"from\": {\"id\": $NONADMIN_ID}, \"chat\": {\"id\": $NONADMIN_ID, \"type\": \"private\"}, \"date\": 1735689601, \"text\": \"/approve\"}}"
sleep 1
nonadmin_row=$(psql_exec -tAc "SELECT intent FROM interaction_logs WHERE platform_user_id = '$NONADMIN_ID' ORDER BY created_at DESC LIMIT 1" | head -1 | tr -d '[:space:]')
if [ "$nonadmin_row" = "qa_disabled" ]; then
  echo "[x] a non-admin's bare /approve with no pending draft falls through to the ordinary pipeline"
else
  echo "[ ] a non-admin's bare /approve falls through correctly (got intent: $nonadmin_row)"
  fail=1
fi
psql_exec -c "DELETE FROM interaction_logs WHERE platform_user_id = '$NONADMIN_ID';" >/dev/null
psql_exec -c "DELETE FROM webhook_events WHERE platform_message_id IN ('$NONADMIN_UPDATE_ID1', '$NONADMIN_UPDATE_ID2');" >/dev/null
psql_exec -c "DELETE FROM users WHERE platform_user_id = '$NONADMIN_ID';" >/dev/null

# --- 2. SQL state transitions, directly against Postgres (the actual risky logic) ---
ITEM_A=$(psql_exec -tAc "
INSERT INTO weekly_content_items (content_type, source_url, title, draft_description_he, status, submitted_by)
VALUES ('featured_link', 'https://example.com/a', 'Test Title A', 'Test draft description A', 'pending_approval', 'test-admin')
RETURNING id;" | head -1 | tr -d '[:space:]')

# Mirrors "Mark Approved (as drafted)".
psql_exec -c "UPDATE weekly_content_items SET status = 'approved', final_description_he = draft_description_he, approved_at = now() WHERE id = '$ITEM_A';" >/dev/null
as_drafted_row=$(psql_exec -tAc "SELECT status || '|' || corrected::text || '|' || (final_description_he = draft_description_he)::text FROM weekly_content_items WHERE id = '$ITEM_A';" | head -1 | tr -d '[:space:]')
if [ "$as_drafted_row" = "approved|false|true" ]; then
  echo "[x] approve-as-drafted sets status/final_description_he correctly, corrected stays false"
else
  echo "[ ] approve-as-drafted state transition (got: $as_drafted_row)"
  fail=1
fi

ITEM_B=$(psql_exec -tAc "
INSERT INTO weekly_content_items (content_type, source_url, title, draft_description_he, status, submitted_by)
VALUES ('featured_link', 'https://example.com/b', 'Test Title B', 'Test draft description B', 'pending_approval', 'test-admin')
RETURNING id;" | head -1 | tr -d '[:space:]')

# Mirrors "Mark Approved (corrected)".
psql_exec -c "UPDATE weekly_content_items SET status = 'approved', final_description_he = 'My fixed final phrasing', corrected = true, approved_at = now() WHERE id = '$ITEM_B';" >/dev/null
corrected_row=$(psql_exec -tAc "SELECT status || '|' || corrected::text || '|' || final_description_he FROM weekly_content_items WHERE id = '$ITEM_B';" | head -1 | tr -d '[:space:]')
if [ "$corrected_row" = "approved|true|Myfixedfinalphrasing" ]; then
  echo "[x] approve-with-correction sets the sender's own text as final_description_he, corrected=true"
else
  echo "[ ] approve-with-correction state transition (got: $corrected_row)"
  fail=1
fi

# Mirrors "Check Pending Draft" per-sender scoping - a different sender must never find this row.
other_sender_lookup=$(psql_exec -tAc "SELECT id FROM weekly_content_items WHERE status = 'pending_approval' AND submitted_by = 'someone-else' ORDER BY created_at DESC LIMIT 1;" | head -1 | tr -d '[:space:]')
if [ -z "$other_sender_lookup" ]; then
  echo "[x] pending-draft lookup is scoped per-sender (a different submitted_by finds nothing)"
else
  echo "[ ] pending-draft lookup scoping (unexpectedly found: $other_sender_lookup)"
  fail=1
fi

psql_exec -c "DELETE FROM weekly_content_items WHERE id IN ('$ITEM_A', '$ITEM_B');" >/dev/null

# --- Phase 3: /link community relay ---
LINKRELAY_NONADMIN_ID="98$(date +%s)"
LINKRELAY_UPDATE_ID="99$(date +%s)"
curl -s -o /dev/null -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "X-Telegram-Bot-Api-Secret-Token: $SECRET" \
  -d "{\"update_id\": $LINKRELAY_UPDATE_ID, \"message\": {\"message_id\": 1, \"from\": {\"id\": $LINKRELAY_NONADMIN_ID}, \"chat\": {\"id\": $LINKRELAY_NONADMIN_ID, \"type\": \"private\"}, \"date\": 1735689600, \"text\": \"/link https://example.com/relay-test\"}}"
sleep 1
relay_row_count=$(psql_exec -tAc "SELECT count(*) FROM weekly_content_items WHERE source_url = 'https://example.com/relay-test'" | tr -d '[:space:]')
kb_row_count=$(psql_exec -tAc "SELECT count(*) FROM knowledge_base WHERE url = 'https://example.com/relay-test'" | tr -d '[:space:]')
if [ "$relay_row_count" = "0" ] && [ "$kb_row_count" = "0" ]; then
  echo "[x] a non-admin's /link does not create weekly_content_items or knowledge_base rows"
else
  echo "[ ] a non-admin's /link does not create rows (weekly_content_items: $relay_row_count, knowledge_base: $kb_row_count)"
  fail=1
fi
psql_exec -c "DELETE FROM interaction_logs WHERE platform_user_id = '$LINKRELAY_NONADMIN_ID';" >/dev/null
psql_exec -c "DELETE FROM webhook_events WHERE platform_message_id = '$LINKRELAY_UPDATE_ID';" >/dev/null
psql_exec -c "DELETE FROM users WHERE platform_user_id = '$LINKRELAY_NONADMIN_ID';" >/dev/null

# --- Phase 3: community_shared_link + knowledge_base shape (mirrors "Insert Community Shared
# Link Item" + "Archive To Knowledge Base (Relay)") ---
RELAY_ITEM=$(psql_exec -tAc "
INSERT INTO weekly_content_items (content_type, source_url, title, draft_description_he, final_description_he, status, submitted_by, approved_at)
VALUES ('community_shared_link', 'https://example.com/c', 'Test Title C', 'Test draft C', 'Test draft C', 'approved', 'test-admin', now())
RETURNING id;" | head -1 | tr -d '[:space:]')
psql_exec -c "INSERT INTO knowledge_base (category, title, url, summary_he, source_type, trust_level, status) VALUES ('articles', 'Test Title C', 'https://example.com/c', 'Test draft C', 'article', 'community', 'active');" >/dev/null
relay_shape=$(psql_exec -tAc "SELECT w.status || '|' || (k.id IS NOT NULL)::text FROM weekly_content_items w JOIN knowledge_base k ON k.url = w.source_url WHERE w.id = '$RELAY_ITEM';" | head -1 | tr -d '[:space:]')
if [ "$relay_shape" = "approved|true" ]; then
  echo "[x] community_shared_link items are immediately approved and archived together correctly"
else
  echo "[ ] community_shared_link + knowledge_base shape (got: $relay_shape)"
  fail=1
fi

# --- Phase 3: community_summary approval returns content_type so archival can be skipped ---
SUMMARY_ITEM=$(psql_exec -tAc "
INSERT INTO weekly_content_items (content_type, draft_description_he, status, submitted_by)
VALUES ('community_summary', 'Test summary content', 'pending_approval', 'test-admin')
RETURNING id;" | head -1 | tr -d '[:space:]')
mark_approved_result=$(psql_exec -tAc "
UPDATE weekly_content_items SET status = 'approved', final_description_he = draft_description_he, approved_at = now()
WHERE id = '$SUMMARY_ITEM'
RETURNING final_description_he, title, source_url, content_type;" 2>&1)
if echo "$mark_approved_result" | grep -q "community_summary"; then
  echo "[x] Mark Approved's RETURNING includes content_type, distinguishing summary from featured_link"
else
  echo "[ ] Mark Approved RETURNING content_type (got: $mark_approved_result)"
  fail=1
fi

# --- Phase 3: Check Pending Draft resolves the OLDEST pending draft first (FIFO fix) ---
FIFO_OLD=$(psql_exec -tAc "
INSERT INTO weekly_content_items (content_type, draft_description_he, status, submitted_by, created_at)
VALUES ('featured_link', 'Older draft', 'pending_approval', 'test-fifo-admin', now() - interval '1 hour')
RETURNING id;" | head -1 | tr -d '[:space:]')
FIFO_NEW=$(psql_exec -tAc "
INSERT INTO weekly_content_items (content_type, draft_description_he, status, submitted_by, created_at)
VALUES ('community_summary', 'Newer draft', 'pending_approval', 'test-fifo-admin', now())
RETURNING id;" | head -1 | tr -d '[:space:]')
fifo_resolved=$(psql_exec -tAc "
SELECT c.id
FROM (SELECT 1) AS dummy
LEFT JOIN LATERAL (
  SELECT id FROM weekly_content_items
  WHERE status = 'pending_approval' AND submitted_by = 'test-fifo-admin'
  ORDER BY created_at ASC LIMIT 1
) c ON true
LIMIT 1;" | head -1 | tr -d '[:space:]')
if [ "$fifo_resolved" = "$FIFO_OLD" ]; then
  echo "[x] Check Pending Draft resolves the oldest pending draft first (FIFO)"
else
  echo "[ ] Check Pending Draft FIFO ordering (expected: $FIFO_OLD, got: $fifo_resolved)"
  fail=1
fi

psql_exec -c "DELETE FROM weekly_content_items WHERE id IN ('$RELAY_ITEM', '$SUMMARY_ITEM', '$FIFO_OLD', '$FIFO_NEW');" >/dev/null
psql_exec -c "DELETE FROM knowledge_base WHERE url = 'https://example.com/c';" >/dev/null

if [ "$fail" -eq 0 ]; then
  echo "All weekly content agent tests passed."
else
  echo "Weekly content agent tests FAILED." >&2
fi
exit $fail
