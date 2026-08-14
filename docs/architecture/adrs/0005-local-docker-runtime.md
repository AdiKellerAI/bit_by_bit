# ADR-0005: Local Docker runtime is Colima + Docker CLI, not Docker Desktop

## Status
Accepted

## Context
PROJECT-SPEC.md §5 and §23 specify Docker/Docker Compose as core local infrastructure, and
PREPARATION-CHECKLIST.md Phase 16's First Implementation Gate requires "Docker works" before
implementation starts. Neither document mandates a specific Docker runtime/distribution - this
is a local-machine choice, not an architectural one, made explicitly during Phase 0-1 planning
(2026-08-14) since Docker was not installed on the development machine at all.

Two realistic options on macOS:
- **Docker Desktop**: GUI app, most familiar, requires a one-time manual install + EULA
  acceptance that cannot be scripted, and has licensing terms for larger-organization
  commercial use that don't need to be relitigated for a personal POC.
- **Colima + Docker CLI + Docker Compose plugin**: a lightweight Lima-based VM providing the
  Docker daemon, fully installable and startable via Homebrew with no GUI interaction, no
  licensing question, and the same `docker`/`docker compose` CLI surface either way.

## Decision
Use Colima as the local Docker runtime: `brew install colima docker docker-compose`, then
`colima start`. The Docker Compose plugin is wired via `~/.docker/config.json`
(`cliPluginsExtraDirs`) rather than Docker Desktop's built-in plugin directory.

## Consequences
- Every command in this repo's docs/scripts that says "docker compose ..." assumes a running
  Colima VM (`colima start`), not Docker Desktop. `scripts/dev-up.sh` starts Colima
  automatically if it isn't running.
- Anyone else working on this repo on macOS without Docker Desktop already installed should
  follow the same Colima path for consistency; Docker Desktop would also work (same CLI
  surface) but isn't the documented/scripted default.
- This choice is local-machine tooling, not part of the deployed system - the eventual
  pilot/production host (PROJECT-SPEC.md §23 Deployment Topology) will run Docker via whatever
  the chosen hosting provider supports, which is a separate, still-open decision.
