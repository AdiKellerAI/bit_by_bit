#!/usr/bin/env bash
# Pre-merge verification gate. Run this before merging any branch back to main
# (see .claude/skills/phase-workflow/SKILL.md) — it should catch anything a
# phase/fix accidentally broke in what already worked.
set -uo pipefail
cd "$(dirname "$0")/.."

overall_fail=0
run_step() {
  local name="$1"
  shift
  echo "=== $name ==="
  if "$@"; then
    echo "--- $name: PASS ---"
  else
    echo "--- $name: FAIL ---"
    overall_fail=1
  fi
  echo
}

run_step "Infra health" ./scripts/dev-status.sh
run_step "docker-compose config valid" docker compose config -q
run_step "dbmate migrations up to date" dbmate status --exit-code
run_step "Database schema regression tests" ./database/tests/run.sh

if [ -d services/messaging-adapters/telegram ]; then
  run_step "Telegram adapter unit tests" bash -c \
    "cd services/messaging-adapters/telegram && node --experimental-strip-types --test *.test.ts"
else
  echo "=== Telegram adapter unit tests: SKIPPED (services/messaging-adapters/telegram not present yet) ==="
  echo
fi

if [ "$overall_fail" -eq 0 ]; then
  echo "ALL CHECKS PASSED — safe to merge."
else
  echo "ONE OR MORE CHECKS FAILED — do not merge until fixed." >&2
fi
exit $overall_fail
