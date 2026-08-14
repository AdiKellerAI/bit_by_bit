# Claude Code Kickoff Prompt

Paste the prompt below into the Claude Code extension in VS Code, in this repo, to start
development. It is written to make Claude Code review the architecture first and produce a
plan — not write code immediately, per this project's own rule (see
`PREPARATION-CHECKLIST.md`, Final Rule): *"Do not let Cursor/Claude turn an architecture
document into a large codebase in one step."*

---

```
I'm ready to start building the AI Community Agent described in this repo's docs. Before
writing any code, do the following:

1. Read these files in full, in this order:
   - docs/project_setup/PROJECT-SPEC.md
   - docs/project_setup/ARCHITECTURE-FLOWS.md
   - docs/project_setup/PREPARATION-CHECKLIST.md
   - docs/project_setup/PREREQUISITES.md
   - docs/links_and_details.md (live links, IDs, and account details already created during
     prerequisite setup — do NOT treat anything in here as a placeholder to fill in)

2. Do not read .env. Its values are already populated locally and must never be echoed,
   logged, or committed. .env.example (repo root) documents the expected keys without values.

3. Confirm your understanding of these load-bearing decisions before proposing anything that
   contradicts them:
   - The messaging channel is abstracted behind an adapter interface. Telegram is the only
     active adapter for the MVP; WhatsApp Cloud API is a scaffolded-but-inactive adapter,
     deferred until the Meta Developer Account is unblocked (PREREQUISITES.md §7-8).
   - The WhatsApp Community (human channel) is unrelated infrastructure — already set up,
     nothing to build for it.
   - Sensitive-data detection (PROJECT-SPEC.md §4.2, PREPARATION-CHECKLIST.md Phase 7.3) is a
     distinct, always-on security control, separate from general data classification — it
     must block before any LLM call, on every match, not just high-confidence ones.
   - PostgreSQL is the system of record; Redis is cache/session/rate-limit only, never
     authoritative (PREPARATION-CHECKLIST.md Phase 6).
   - LDD (self-improvement) changes always require human approval before activation
     (PROJECT-SPEC.md §8, PREPARATION-CHECKLIST.md Phase 10) — sensitive-data detection rules
     are explicitly out of scope for automatic LDD proposals.
   - The community is Hebrew-primary (PROJECT-SPEC.md §14, Language Strategy). The Agent
     mirrors the user's language (Hebrew in, Hebrew out; English in, English out) and keeps
     standard technical terms (Agent, Prompt, LLM, RAG, Context Window, Embedding, Vector DB,
     Workflow, Evaluation, Guardrail, Router) in English regardless. Any onboarding copy,
     system prompts, error messages, or sample questions you draft should default to Hebrew,
     not English, and should be reviewed with this in mind — not bolted on later.

4. Cross-check the "First Implementation Gate" (PREPARATION-CHECKLIST.md, Phase 16) against
   what's actually done per PREREQUISITES.md and docs/links_and_details.md. Call out anything
   still open (e.g. Docker/Postgres/Redis/n8n running locally, golden evaluation set,
   sensitive-data detection patterns, budget thresholds) — these are still my job to prepare,
   not yours to invent.

5. Identify any contradictions, missing dependencies, security risks, or ambiguities across
   the four docs.

6. Propose the initial repo scaffold (PREPARATION-CHECKLIST.md Phase 14 gives a starting
   structure) sized to what we actually need for Phase 0–1 of the recommended implementation
   order (Phase 18) — don't create empty directories for phases we're not starting yet.

7. Produce an implementation plan for the FIRST phase only (Architecture + Threat Model /
   Infrastructure — Phase 0-1 of PREPARATION-CHECKLIST.md Phase 18), not the whole system.
   Use Claude Code's plan mode for this.

8. List what still needs a human decision before you implement anything (e.g. hosting
   provider choice, domain, budget numbers, golden eval set contents).

9. Do not invent requirements beyond the docs. Do not replace an architectural decision
   without explaining why, and wait for my approval before implementing.

Work in small, approved phases from here on — plan, implement, test, review, approve,
continue — per PREPARATION-CHECKLIST.md's Final Rule.
```

---

**Before you paste this**, confirm `.env` is git-ignored (`git status` should not list it) and
that Docker/PostgreSQL/Redis/n8n are runnable locally if you want Claude Code's Phase 0-1 plan
to be actionable immediately rather than just architectural.
