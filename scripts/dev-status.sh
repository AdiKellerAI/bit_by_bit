#!/usr/bin/env bash
# Point-in-time check matching PREPARATION-CHECKLIST.md §5.3's local-env verification list.
# Deliberately does not check "LLM API works" or "does the bot reply correctly" - only that
# the public tunnel Telegram uses to reach this machine is actually up (added 2026-08-15: a
# stuck cloudflared quick tunnel silently stopped routing while n8n itself tested fine on
# localhost - verify-all.sh/n8n/tests/run.sh only ever hit localhost directly, so neither
# would have caught a dead tunnel; this is the only check that does).
cd "$(dirname "$0")/.."

pass() { echo "[x] $1"; }
fail() { echo "[ ] $1"; }

if colima status >/dev/null 2>&1; then pass "Docker (Colima) works"; else fail "Docker (Colima) works"; fi

if docker compose ps postgres 2>/dev/null | grep -q "healthy"; then
  pass "PostgreSQL works"
else
  fail "PostgreSQL works"
fi

if docker compose ps redis 2>/dev/null | grep -q "healthy"; then
  pass "Redis works"
else
  fail "Redis works"
fi

if docker compose ps n8n 2>/dev/null | grep -q "healthy"; then
  pass "n8n works"
else
  fail "n8n works"
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  pass "Git repository works"
else
  fail "Git repository works"
fi

WEBHOOK_URL=$(grep -E '^WEBHOOK_URL=' .env 2>/dev/null | cut -d= -f2-)
if [ -z "$WEBHOOK_URL" ]; then
  fail "Public webhook tunnel reachable (WEBHOOK_URL not set in .env)"
else
  # 401 is the CORRECT response here (no valid secret token sent) - it proves the request
  # reached n8n through the tunnel, not that authentication passed. Any other result (000,
  # 502, 504, timeout) means the tunnel itself is down, not an n8n/workflow problem.
  # Update the workflow id below if n8n/workflows/telegram-echo-bot.json's ever changes.
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X POST \
    "${WEBHOOK_URL}/webhook/telegram-echo-bot-phase3/webhook/telegram-webhook" \
    -H "Content-Type: application/json" -d '{}')
  if [ "$code" = "401" ]; then
    pass "Public webhook tunnel reachable (Telegram can reach n8n)"
  else
    fail "Public webhook tunnel reachable (got HTTP '${code:-timeout}', expected 401 - restart your tunnel and re-run setWebhook)"
  fi
fi
