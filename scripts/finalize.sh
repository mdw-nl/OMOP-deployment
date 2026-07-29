#!/bin/bash
# Applies the OHDSI foreign-key constraints and indices, then refreshes planner stats.
# Runs inside the postgres container:  make finalize
#
# Do this AFTER the vocabulary (and any clinical data) is loaded — that is the
# documented OHDSI order, and it is much faster than loading into an indexed,
# fully-constrained schema.
set -euo pipefail

CDM_SCHEMA="${CDM_SCHEMA:-cdm}"
DDL_DIR=/ddl

# The FK constraints all point at cdm.concept. Applying them against an empty
# vocabulary "succeeds" but leaves a schema no ETL can insert into, so warn.
concepts=$(psql -tAX --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -c "SELECT count(*) FROM ${CDM_SCHEMA}.concept;")
if [[ "$concepts" -eq 0 ]]; then
  echo "WARNING: ${CDM_SCHEMA}.concept is empty — constraints will be created, but any" >&2
  echo "         clinical insert referencing a concept_id will fail until you run" >&2
  echo "         'make load-vocab'. Continuing in 5s (Ctrl-C to abort)." >&2
  sleep 5
fi

for step in constraints indices; do
  file="${DDL_DIR}/OMOPCDM_postgresql_5.4_${step}.sql"
  echo "==> applying ${step}"
  sed "s/@cdmDatabaseSchema/${CDM_SCHEMA}/g" "$file" \
    | psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --quiet
done

echo "==> analyzing schema '${CDM_SCHEMA}'"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --quiet \
  -c "ANALYZE;"

fks=$(psql -tAX --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c "
  SELECT count(*) FROM pg_constraint c
  JOIN pg_namespace n ON n.oid = c.connamespace
  WHERE n.nspname = '${CDM_SCHEMA}' AND c.contype = 'f';")

echo "Done — ${fks} foreign keys in place, indices built, statistics refreshed."
