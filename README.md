# AI Community Agent

A self-improving 1:1 AI assistant (Telegram for the MVP) for an internal AI & development
community, with a separate human-run WhatsApp Community for announcements/discussion. Source
of truth for scope, architecture, and rules: [`docs/project_setup/PROJECT-SPEC.md`](docs/project_setup/PROJECT-SPEC.md).

Full docs:
- [`docs/project_setup/PROJECT-SPEC.md`](docs/project_setup/PROJECT-SPEC.md) - product spec, security model, architecture, phases.
- [`docs/project_setup/ARCHITECTURE-FLOWS.md`](docs/project_setup/ARCHITECTURE-FLOWS.md) - diagrams, ERD, sequence flows.
- [`docs/project_setup/PREPARATION-CHECKLIST.md`](docs/project_setup/PREPARATION-CHECKLIST.md) - preparation phases and the First Implementation Gate.
- [`docs/architecture/`](docs/architecture/) - ADRs, threat model, data-flow, MVP scope (this repo's Phase 0 deliverables).

## Status

Phase 0-2 done: Architecture + Threat Model, Infrastructure, and Database schema (see
[`docs/architecture/`](docs/architecture/) and [`database/migrations/`](database/migrations/)).
No messaging code or n8n workflows exist yet (Phase 3+).

## Local development

Prerequisites: [Homebrew](https://brew.sh).

```sh
# 1. Install and start the local Docker runtime (Colima - see docs/architecture/adrs/0005)
brew install colima docker docker-compose
mkdir -p ~/.docker
jq '. + {"cliPluginsExtraDirs": ["/opt/homebrew/lib/docker/cli-plugins"]}' \
  ~/.docker/config.json > /tmp/docker_config.json.new && mv /tmp/docker_config.json.new ~/.docker/config.json
colima start --cpu 2 --memory 4 --disk 20
docker context use colima

# 2. Configure secrets locally (never commit .env)
cp .env.example .env
# fill in real values in .env - see docs/project_setup/PREREQUISITES.md

# 3. Bring up Postgres + pgvector, Redis, n8n, reverse-proxy
./scripts/dev-up.sh

# 4. Check status any time
./scripts/dev-status.sh
```

n8n is reachable at `http://localhost:5678` (through the local reverse proxy). No workflows
are configured yet - that starts in Phase 3.

## Security note

`docs/links_and_details.md` contains live credentials/IDs and is gitignored - never remove it
from `.gitignore`, and never put secrets in any other tracked file. See
`docs/project_setup/PROJECT-SPEC.md` §4.3.
