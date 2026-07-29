#!/bin/bash
# Shared helpers. Sourced by every script in scripts/; not meant to run directly.
#
# The whole point of this file is run_psql(): every script talks to Postgres through
# it, so switching between a host psql client and `docker exec` is a one-line change
# in .env instead of a rewrite.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DDL_DIR="${HERE}/ddl"

# --- config ----------------------------------------------------------------
if [[ -f "${HERE}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${HERE}/.env"
  set +a
else
  echo "ERROR: ${HERE}/.env not found. Run 'make init' and edit it." >&2
  exit 1
fi

PSQL_MODE="${PSQL_MODE:-host}"
DOCKER_CONTAINER="${DOCKER_CONTAINER:-postgres}"
TARGET_DB="${TARGET_DB:-omop}"
CREATE_DB="${CREATE_DB:-true}"
CDM_SCHEMA="${CDM_SCHEMA:-cdm}"
RESULTS_SCHEMA="${RESULTS_SCHEMA:-results}"
TEMP_SCHEMA="${TEMP_SCHEMA:-temp}"
SET_DB_SEARCH_PATH="${SET_DB_SEARCH_PATH:-true}"
VOCAB_DIR="${VOCAB_DIR:-./vocabulary}"

# --- output ----------------------------------------------------------------
say()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- psql ------------------------------------------------------------------
# Runs psql against $TARGET_DB unless PGDATABASE is overridden by the caller.
# Extra args are passed straight through (-c, -f, -v, ...). stdin is forwarded,
# so `sed ... | run_psql` works in both modes — the DDL never needs a mount.
run_psql() {
  local db="${PGDATABASE:-$TARGET_DB}"
  case "$PSQL_MODE" in
    host)
      command -v psql >/dev/null 2>&1 \
        || die "PSQL_MODE=host but no psql on PATH. Install it (brew install libpq) or set PSQL_MODE=docker."
      PGDATABASE="$db" psql -v ON_ERROR_STOP=1 --quiet "$@"
      ;;
    docker)
      command -v docker >/dev/null 2>&1 || die "PSQL_MODE=docker but no docker on PATH."
      docker exec -i \
        -e PGPASSWORD="${PGPASSWORD:-}" \
        -e PGUSER="${PGUSER:-postgres}" \
        -e PGDATABASE="$db" \
        "$DOCKER_CONTAINER" psql -v ON_ERROR_STOP=1 --quiet "$@"
      ;;
    *) die "PSQL_MODE must be 'host' or 'docker', got '${PSQL_MODE}'." ;;
  esac
}

# Single value, no headers or padding — for counts and existence checks.
psql_value() { run_psql -tAX "$@" | tr -d '[:space:]'; }

# The OHDSI scripts in ddl/ are templates: every table is
# `CREATE TABLE @cdmDatabaseSchema.person (...)`. Substitute on the way into psql
# and leave the vendored files byte-identical to upstream so updates stay diffable.
apply_ddl_step() {
  local step="$1"
  local file="${DDL_DIR}/OMOPCDM_postgresql_5.4_${step}.sql"
  [[ -f "$file" ]] || die "missing ${file}"
  say "applying ${step} -> ${TARGET_DB}.${CDM_SCHEMA}"
  sed "s/@cdmDatabaseSchema/${CDM_SCHEMA}/g" "$file" | run_psql
}

cdm_table_count() {
  psql_value -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = '${CDM_SCHEMA}';"
}

require_connection() {
  psql_value -c 'SELECT 1' >/dev/null 2>&1 \
    || die "cannot connect to '${TARGET_DB}' as '${PGUSER:-postgres}' (PSQL_MODE=${PSQL_MODE}). Run 'make check'."
}
