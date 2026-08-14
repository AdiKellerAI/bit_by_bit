#!/usr/bin/env bash
# Point-in-time check matching PREPARATION-CHECKLIST.md §5.3's local-env verification list.
# Deliberately does not check "LLM API works" or "Telegram bot responds" - those belong to
# Phase 4 and Phase 3 respectively, not this phase.
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
