#!/usr/bin/env bash
# Repeatable version of the Phase 2 manual schema verification. Run directly, or via
# scripts/verify-all.sh. Requires the local stack to be up (./scripts/dev-up.sh).
set -uo pipefail
cd "$(dirname "$0")/../.."

PG_USER=$(grep -E '^POSTGRES_USER=' .env | cut -d= -f2-)
PG_DB=$(grep -E '^POSTGRES_DB=' .env | cut -d= -f2-)

if [ -z "$PG_USER" ] || [ -z "$PG_DB" ]; then
  echo "FAIL: POSTGRES_USER/POSTGRES_DB not set in .env" >&2
  exit 1
fi

fail=0

run_sql_file() {
  docker compose exec -T postgres psql -U "$PG_USER" -d "$PG_DB" -v ON_ERROR_STOP=1 < "$1"
}

table_count=$(docker compose exec -T postgres psql -U "$PG_USER" -d "$PG_DB" -tAc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" | tr -d '[:space:]')
if [ "$table_count" = "14" ]; then
  echo "[x] all 14 tables present"
else
  echo "[ ] all 14 tables present (found $table_count)"
  fail=1
fi

if run_sql_file "$(dirname "$0")/02_system_prompts_single_active.sql" >/tmp/dbtest_02.log 2>&1; then
  echo "[ ] system_prompts rejects a second active row (insert unexpectedly succeeded)"
  fail=1
else
  echo "[x] system_prompts rejects a second active row"
fi

if run_sql_file "$(dirname "$0")/03_interaction_logs_fk.sql" >/tmp/dbtest_03.log 2>&1; then
  echo "[ ] interaction_logs rejects unknown platform_user_id (insert unexpectedly succeeded)"
  fail=1
else
  echo "[x] interaction_logs rejects unknown platform_user_id"
fi

if run_sql_file "$(dirname "$0")/04_system_prompts_per_type_active.sql" >/tmp/dbtest_04.log 2>&1; then
  echo "[x] system_prompts allows different prompt_types to be active simultaneously"
else
  echo "[ ] system_prompts allows different prompt_types to be active simultaneously (insert unexpectedly failed)"
  cat /tmp/dbtest_04.log >&2
  fail=1
fi

if run_sql_file "$(dirname "$0")/05_interaction_logs_feedback_score_check.sql" >/tmp/dbtest_05.log 2>&1; then
  echo "[ ] interaction_logs rejects an out-of-range feedback_score (insert unexpectedly succeeded)"
  fail=1
else
  echo "[x] interaction_logs rejects an out-of-range feedback_score"
fi

if run_sql_file "$(dirname "$0")/06_prompt_change_proposals_status_check.sql" >/tmp/dbtest_06.log 2>&1; then
  echo "[ ] prompt_change_proposals rejects an invalid status (insert unexpectedly succeeded)"
  fail=1
else
  echo "[x] prompt_change_proposals rejects an invalid status"
fi

if run_sql_file "$(dirname "$0")/07_weekly_content_items_content_type_check.sql" >/tmp/dbtest_07.log 2>&1; then
  echo "[ ] weekly_content_items rejects an invalid content_type (insert unexpectedly succeeded)"
  fail=1
else
  echo "[x] weekly_content_items rejects an invalid content_type"
fi

if run_sql_file "$(dirname "$0")/08_weekly_content_items_status_check.sql" >/tmp/dbtest_08.log 2>&1; then
  echo "[ ] weekly_content_items rejects an invalid status (insert unexpectedly succeeded)"
  fail=1
else
  echo "[x] weekly_content_items rejects an invalid status"
fi

if [ "$fail" -eq 0 ]; then
  echo "All database tests passed."
else
  echo "Database tests FAILED." >&2
fi
exit $fail
