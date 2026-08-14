#!/usr/bin/env bash
# Thin wrapper so this service is auto-discovered by scripts/verify-all.sh's
# */tests/run.sh convention (see .claude/skills/phase-workflow/SKILL.md).
# The actual tests are node:test files in the parent directory.
set -uo pipefail
cd "$(dirname "$0")/.."
node --experimental-strip-types --test *.test.ts
