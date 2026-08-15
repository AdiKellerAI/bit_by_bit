#!/usr/bin/env bash
# Nightly Evaluator workflow (Phase 6 LDD, Loop 3 sub-phase 1) regression test. Requires the
# local stack up (./scripts/dev-up.sh) and the workflow imported/published (see
# n8n/workflows/nightly-evaluator.json and the n8n-workflow-authoring skill for the deploy
# sequence). This is NOT reachable via webhook (it's Schedule Trigger, not Webhook) - manual
# execution goes through the n8n CLI's `execute` command instead.
#
# Real cost/time warning: this makes real Evaluator/Synthesize (claude-sonnet-5) and 22 Golden
# Eval + 1 judge (gpt-5.4-nano) LLM calls, same as the RAG/Tier1/Tier2/cache tests already in
# n8n/tests/run.sh make real calls - roughly $0.03-0.05 and 30-60 seconds for this one test.
set -uo pipefail
cd "$(dirname "$0")/../../.."

PG_USER=$(grep -E '^POSTGRES_USER=' .env | cut -d= -f2-)
PG_DB=$(grep -E '^POSTGRES_DB=' .env | cut -d= -f2-)

if [ -z "$PG_USER" ] || [ -z "$PG_DB" ]; then
  echo "FAIL: POSTGRES_USER/POSTGRES_DB not set in .env" >&2
  exit 1
fi

fail=0
psql_exec() { docker compose exec -T postgres psql -U "$PG_USER" -d "$PG_DB" "$@"; }

TEST_USER_ID="72$(date +%s)"
psql_exec -c "INSERT INTO users (platform_user_id, platform) VALUES ('$TEST_USER_ID', 'telegram');" >/dev/null
FLAGGED_ID=$(psql_exec -tAc "
INSERT INTO interaction_logs (platform_user_id, platform, user_query, agent_response, intent, feedback_score, needs_review, security_classification, sensitive_data_flagged)
VALUES ('$TEST_USER_ID', 'telegram', 'Tell me about LangTalks podcast', 'It is a podcast about something unrelated', 'generated_tier1_question', 0, true, 'PUBLIC', false)
RETURNING id;" | head -1 | tr -d '[:space:]')

# Uses a separate broker port (5680) so this one-off execution doesn't conflict with the main
# n8n process's own task broker already listening on 5679 - see CLAUDE.md / n8n-workflow-authoring
# skill for why (N8N_RUNNERS_BROKER_PORT, confirmed by reading @n8n/config's runners.config.js).
execute_output=$(docker compose exec -T -e N8N_RUNNERS_BROKER_PORT=5680 n8n n8n execute --id=nightly-evaluator-phase6 --rawOutput 2>&1)
if echo "$execute_output" | grep -q '"status": "success"'; then
  echo "[x] nightly evaluator workflow executes successfully"
else
  echo "[ ] nightly evaluator workflow executes successfully"
  echo "$execute_output" | tail -30 >&2
  fail=1
fi

proposal_row=$(psql_exec -tAc "
SELECT status || '|' || (evaluation_score IS NOT NULL)::text || '|' || (evaluation_cost_usd > 0)::text
FROM prompt_change_proposals
WHERE source_interactions @> '[\"$FLAGGED_ID\"]'::jsonb
ORDER BY created_at DESC LIMIT 1;" | head -1 | tr -d '[:space:]')
if [[ "$proposal_row" == "pending|true|true" ]] || [[ "$proposal_row" == "rejected|true|true" ]]; then
  echo "[x] a scored prompt_change_proposals row is created, referencing the flagged interaction"
else
  echo "[ ] a scored prompt_change_proposals row is created, referencing the flagged interaction (got: $proposal_row)"
  fail=1
fi

psql_exec -c "DELETE FROM prompt_change_proposals WHERE source_interactions @> '[\"$FLAGGED_ID\"]'::jsonb;" >/dev/null
psql_exec -c "DELETE FROM interaction_logs WHERE id = '$FLAGGED_ID';" >/dev/null
psql_exec -c "DELETE FROM users WHERE platform_user_id = '$TEST_USER_ID';" >/dev/null

if [ "$fail" -eq 0 ]; then
  echo "All nightly evaluator tests passed."
else
  echo "Nightly evaluator tests FAILED." >&2
fi
exit $fail
