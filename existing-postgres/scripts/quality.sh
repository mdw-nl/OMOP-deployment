#!/bin/bash
# Runs docker compose on ../apps/compose.yml, the data quality apps, as the separate
# compose project omop-apps: it starts only those containers and never touches yours.
# Usage: quality.sh <compose arguments>, e.g. `quality.sh up -d --build`.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

command -v docker >/dev/null 2>&1 || die "the data quality apps need docker."

# The apps reach your Postgres through OMOP_DB_*. host.docker.internal is the Docker
# host, which works when your Postgres port is published there.
export OMOP_DB_HOST="${OMOP_DB_HOST:-host.docker.internal}"
export OMOP_DB_PORT="${OMOP_DB_PORT:-${PGPORT:-5432}}"
export OMOP_DB_NAME="$TARGET_DB"
export OMOP_DB_ADMIN_USER="${PGUSER:-postgres}"
export OMOP_DB_ADMIN_PASSWORD="${PGPASSWORD:-}"

exec docker compose --project-name omop-apps --file "${HERE}/../apps/compose.yml" \
  --profile quality "$@"
