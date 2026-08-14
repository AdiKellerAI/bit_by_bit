#!/usr/bin/env bash
# Pre-merge verification gate. Run this before merging any branch back to main
# (see .claude/skills/phase-workflow/SKILL.md) - it should catch anything a
# phase/fix accidentally broke in what already worked.
#
# Convention: every service/component keeps its own regression checks in a
# `tests/run.sh` script (e.g. database/tests/run.sh, n8n/tests/run.sh,
# services/messaging-adapters/telegram/tests/run.sh). This script auto-discovers and
# runs all of them, so a new phase adding a new service is covered automatically -
# add your checks under <your-path>/tests/run.sh, you should not need to edit this file.
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

while IFS= read -r test_script; do
  component=$(dirname "$(dirname "$test_script")")
  # </dev/null: a test script's `docker compose exec` (even with -T) can otherwise inherit
  # and drain this loop's process-substitution stdin, silently skipping later iterations.
  run_step "$component tests" bash "$test_script" </dev/null
done < <(find . -type f -name run.sh -path '*/tests/run.sh' | sort)

if [ "$overall_fail" -eq 0 ]; then
  echo "ALL CHECKS PASSED - safe to merge."
else
  echo "ONE OR MORE CHECKS FAILED - do not merge until fixed." >&2
fi
exit $overall_fail
