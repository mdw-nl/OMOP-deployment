#!/bin/bash
# Opens an interactive psql session on TARGET_DB.
#
# Not routed through run_psql(): an interactive session needs a TTY (`docker exec -it`)
# and must not force ON_ERROR_STOP or --quiet.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

case "$PSQL_MODE" in
  host)
    command -v psql >/dev/null 2>&1 || die "no psql on PATH (brew install libpq), or set PSQL_MODE=docker."
    exec psql -d "$TARGET_DB" "$@"
    ;;
  docker)
    exec docker exec -it \
      -e PGPASSWORD="${PGPASSWORD:-}" \
      -e PGUSER="${PGUSER:-postgres}" \
      "$DOCKER_CONTAINER" psql -d "$TARGET_DB" "$@"
    ;;
  *) die "PSQL_MODE must be 'host' or 'docker', got '${PSQL_MODE}'." ;;
esac
