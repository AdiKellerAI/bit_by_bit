#!/usr/bin/env bash
# Thin wrapper for scripts/verify-all.sh's */tests/run.sh auto-discovery convention.
set -uo pipefail
cd "$(dirname "$0")/.."
node --experimental-strip-types --test *.test.ts
