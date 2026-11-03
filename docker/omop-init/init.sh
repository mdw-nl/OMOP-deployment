#!/bin/bash
# Prepares the OMOP database: loads the vocabulary and finalizes the CDM. Runs on every
# `make up`; every step is idempotent and skipped when already done:
#
#   1. wait for the database and check the CDM tables created by initdb
#   2. load the vocabulary when CDM_SCHEMA.concept is empty: Athena CSVs from
#      /vocabulary if present, otherwise the zip at VOCAB_URL if set
#   3. apply the FK constraints and indices once the vocabulary is there
#
# Steps 2 and 3 reuse scripts/load_vocabulary.sh and scripts/finalize.sh (mounted at
# /scripts) and can be switched off with INIT_LOAD_VOCAB / INIT_FINALIZE.
# Connection settings come from the standard PG* variables.
set -euo pipefail

CDM_SCHEMA="${CDM_SCHEMA:-cdm}"
CACHE_DIR=/vocab_cache
# load_vocabulary.sh and finalize.sh address the database through these.
export POSTGRES_USER="$PGUSER" POSTGRES_DB="$PGDATABASE"
# Repeated runs would otherwise log a NOTICE for every object that already exists.
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"

log() { echo "[init] $*"; }
die() { echo "[init] ERROR: $*" >&2; exit 1; }
# Single value, no headers or padding.
value() { psql -v ON_ERROR_STOP=1 -tAX -c "$1"; }

concepts() { value "SELECT count(*) FROM (SELECT 1 FROM ${CDM_SCHEMA}.concept LIMIT 1) c"; }
fks() {
  value "SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
         WHERE n.nspname = '${CDM_SCHEMA}' AND c.contype = 'f'"
}

# --- 1. database -------------------------------------------------------------
log "waiting for ${PGHOST}:${PGPORT:-5432}/${PGDATABASE}"
until pg_isready -q; do sleep 2; done

# Checks the CDM tables by name, as listed in the vendored DDL, so other tables in the
# schema (an ETL's staging tables, views) do not stop the start.
cdm_tables=$(grep -oE 'CREATE TABLE @cdmDatabaseSchema\.[A-Za-z_]+' /ddl/OMOPCDM_postgresql_5.4_ddl.sql \
  | sed 's/.*\.//' | sort -u | tr '\n' ' ')
[[ -n "$cdm_tables" ]] || die "no CREATE TABLE statements found in /ddl/OMOPCDM_postgresql_5.4_ddl.sql"
missing=$(value "SELECT string_agg(t, ', ' ORDER BY t)
                   FROM unnest(string_to_array(trim('${cdm_tables}'), ' ')) t
                  WHERE to_regclass(format('%I.%I', '${CDM_SCHEMA}', t)) IS NULL")
[[ -z "$missing" ]] \
  || die "CDM tables missing in '${CDM_SCHEMA}': ${missing}. Apply the CDM DDL first."
log "all $(wc -w <<< "$cdm_tables" | tr -d ' ') CDM tables present in '${CDM_SCHEMA}'"

# --- 2. vocabulary -----------------------------------------------------------
if [[ "${INIT_LOAD_VOCAB:-true}" != true ]]; then
  log "INIT_LOAD_VOCAB=${INIT_LOAD_VOCAB} — not loading the vocabulary"
elif [[ "$(concepts)" -ne 0 ]]; then
  log "vocabulary already loaded"
elif [[ -f /vocabulary/CONCEPT.csv ]]; then
  log "loading the vocabulary from ./vocabulary"
  VOCAB_DIR=/vocabulary bash /scripts/load_vocabulary.sh
elif [[ -n "${VOCAB_URL:-}" ]]; then
  # The zip stays in the cache volume, so a reload does not download it again.
  zip="${CACHE_DIR}/vocabulary.zip"
  if [[ ! -f "$zip" ]]; then
    # Not logging the URL itself: download links can carry a token.
    log "downloading the vocabulary from VOCAB_URL"
    curl -fL --retry 3 -o "${zip}.part" "$VOCAB_URL"
    mv "${zip}.part" "$zip"
  fi
  extract="${CACHE_DIR}/extracted"
  rm -rf "$extract"
  mkdir -p "$extract"
  log "extracting the vocabulary"
  unzip -q "$zip" -d "$extract"
  concept_csv=$(find "$extract" -name CONCEPT.csv -print -quit)
  [[ -n "$concept_csv" ]] || die "the VOCAB_URL zip contains no CONCEPT.csv"
  VOCAB_DIR="$(dirname "$concept_csv")" bash /scripts/load_vocabulary.sh
  # The extracted CSVs are many gigabytes; only the zip is kept.
  rm -rf "$extract"
else
  log "no CSVs in ./vocabulary and no VOCAB_URL — the vocabulary stays empty."
  log "load it later with 'make load-vocab && make finalize'."
fi

# --- 3. constraints and indices ----------------------------------------------
# Finalized when foreign keys or the first index of the indices script exist.
if [[ "${INIT_FINALIZE:-true}" != true ]]; then
  log "INIT_FINALIZE=${INIT_FINALIZE} — not applying constraints and indices"
elif [[ "$(concepts)" -eq 0 ]]; then
  log "vocabulary empty — not applying constraints and indices yet"
elif [[ "$(fks)" -ne 0 || -n "$(value "SELECT to_regclass('${CDM_SCHEMA}.idx_person_id')")" ]]; then
  log "constraints and indices already applied"
else
  log "applying constraints and indices; statements the vocabulary violates are skipped"
  FINALIZE_ON_ERROR_STOP=0 bash /scripts/finalize.sh
fi

log "OMOP database ready"
