---
name: phase-workflow
description: Use whenever starting a new development phase or bug fix in this repo, or when the user approves a plan and it's time to implement. Encodes this project's required workflow — small approved phases, one git branch per phase/fix, commit-then-branch discipline. Also use when deciding whether something needs plan mode.
---

# Phase workflow (this repo's Final Rule)

Source: PREPARATION-CHECKLIST.md's Final Rule + the git workflow the user established
2026-08-14. This is not optional — it's how every unit of work in this repo proceeds.

## The loop

```
Plan (use EnterPlanMode for anything non-trivial)
  ↓
Implement (only after ExitPlanMode approval)
  ↓
Verify (run it, don't just claim it works)
  ↓
Human approval
  ↓
./scripts/verify-all.sh — must pass (see the "Pre-merge gate" section below)
  ↓
Commit the approved work to main
  ↓
Open a new branch for the next phase/fix
  ↓
Continue
```

## Rules

- **Never turn an architecture doc into a large codebase in one step.** One phase = one
  approved chunk of work, not "implement Phase 2-7 while I'm at it."
- **Git: one branch per phase or bug fix.** Before starting new work, make sure the previous
  approved work is committed to `main`, then `git checkout -b <descriptive-name>` for the new
  work. Merge back to `main` only after the user has approved the result — don't merge
  speculatively.
- **Branch naming:** short and descriptive of the unit of work (`phase-3-telegram-webhook`,
  `fix-webhook-idempotency`, `chore/dev-tooling`) — not generic (`update`, `wip`).
- **Don't invent open decisions** (budget numbers, eval sets, detection patterns, pricing) —
  surface them as things the user needs to bring, per `docs/architecture/mvp-scope.md`.
- **Before committing:** re-verify `.env` and `docs/links_and_details.md` are not staged
  (`git status --porcelain --ignored=matching`) — both must stay gitignored.
- Only commit/branch/merge when the user has actually approved the work in this session — a
  plan being approved is not the same as the implementation being approved.

## Pre-merge gate

`./scripts/verify-all.sh` is the single required check before any merge to `main` — infra
health, `docker compose config`, `dbmate status`, database schema regression tests
(`database/tests/run.sh`), and every adapter/service's unit tests. It's designed to grow: each
new phase that adds a testable service should add its test command as a new step (see the
Telegram adapter step for the pattern — check the directory exists, skip gracefully if not, so
the script doesn't need editing by phases that haven't started yet). If a phase adds a new kind
of check (e.g., an n8n workflow smoke test), add it here rather than leaving it as a one-off
manual step — that's exactly how the database regression tests came to exist (Phase 2's manual
`psql` checks were promoted into this script during Phase 3).

## When NOT to invoke this

Trivial fixes (typo, one-line config tweak) don't need a full plan-mode cycle or their own
branch — use judgment, but default to the full loop for anything touching architecture,
schema, or more than a couple of files.
