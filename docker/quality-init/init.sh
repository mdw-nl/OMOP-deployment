#!/bin/bash
# Prepares the OMOP database for the data quality apps by applying /sql/*.sql: a
# cdm_source row if missing, the dqd role and its dqd_results schema. Runs on every
# `make quality-up`; every statement is idempotent. Connects as an admin role through
# the standard PG* variables.
set -euo pipefail

CDM_SCHEMA="${CDM_SCHEMA:-cdm}"
# Repeated runs would otherwise log a NOTICE for every object that already exists.
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"

log() { echo "[quality-init] $*"; }
die() { echo "[quality-init] ERROR: $*" >&2; exit 1; }
# Single value, no headers or padding.
value() { psql -v ON_ERROR_STOP=1 -tAX -c "$1"; }

# apps/compose.yml requires no variables, as Compose resolves it even when the quality
# profile is off; the passwords are checked here instead.
for var in PGPASSWORD DQD_PASSWORD; do
  [[ -n "${!var:-}" ]] || die "${var} is empty, set it in .env"
done

log "waiting for ${PGHOST}:${PGPORT:-5432}/${PGDATABASE}"
for _ in $(seq 1 60); do
  pg_isready -q && break
  sleep 2
done
pg_isready -q || die "no Postgres at ${PGHOST}:${PGPORT:-5432} after 2 minutes"

[[ -n "$(value "SELECT to_regclass('${CDM_SCHEMA}.concept')")" ]] \
  || die "no CDM in schema '${CDM_SCHEMA}' of ${PGDATABASE}. Install the CDM first."
if [[ "$(value "SELECT count(*) FROM (SELECT 1 FROM ${CDM_SCHEMA}.concept LIMIT 1) c")" -eq 0 ]]; then
  log "WARNING: the vocabulary is empty, so most DQD checks will not be meaningful"
fi

for f in /sql/*.sql; do
  log "applying $(basename "$f")"
  psql -v ON_ERROR_STOP=1 --quiet -v cdm_schema="$CDM_SCHEMA" -f "$f"
done

log "database ready for the data quality apps"
