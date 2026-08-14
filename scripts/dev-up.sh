#!/usr/bin/env bash
# Starts Colima (if not already running) and brings up the local infra stack,
# waiting until every service reports healthy. See docs/architecture/adrs/0005.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! colima status >/dev/null 2>&1; then
  echo "Starting Colima..."
  colima start --cpu 2 --memory 4 --disk 20
fi

if [ ! -f .env ]; then
  echo "Missing .env - copy .env.example to .env and fill in real values first." >&2
  exit 1
fi

docker compose up -d

echo "Waiting for services to become healthy..."
services="postgres redis n8n reverse-proxy"
for i in $(seq 1 60); do
  all_healthy=true
  for svc in $services; do
    status=$(docker compose ps -q "$svc" | xargs -I{} docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' {} 2>/dev/null || echo "missing")
    if [ "$status" != "healthy" ] && [ "$status" != "no-healthcheck" ]; then
      all_healthy=false
    fi
  done
  if [ "$all_healthy" = true ]; then
    echo "All services healthy."
    docker compose ps
    exit 0
  fi
  sleep 2
done

echo "Timed out waiting for services to become healthy." >&2
docker compose ps
exit 1
