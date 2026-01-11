#!/usr/bin/env bash
set -u

docker compose -f /opt/streamlab/management/docker-compose.yml run --rm watchtower --run-once --monitor-only

exit 0

