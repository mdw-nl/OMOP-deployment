#!/bin/bash
# Applies the vendored OHDSI CDM 5.4 DDL, then the primary keys.
#
# The OHDSI scripts in ddl/ are templates, not runnable SQL: every table is
# `CREATE TABLE @cdmDatabaseSchema.person (...)`. We substitute the placeholder
# on the way into psql and leave the vendored files untouched, so `make update-ddl`
# stays a clean diff against upstream.
#
# Constraints and indices are deliberately NOT applied here. OHDSI's documented
# order is DDL -> primary keys -> load data -> constraints -> indices; building the
# FK graph and every index before the vocabulary is loaded makes that load far
# slower. Run `make finalize` after `make load-vocab`.
set -euo pipefail

CDM_SCHEMA="${CDM_SCHEMA:-cdm}"
DDL_DIR=/ddl

for step in ddl primary_keys; do
  file="${DDL_DIR}/OMOPCDM_postgresql_5.4_${step}.sql"
  if [[ ! -f "$file" ]]; then
    echo "[initdb] ERROR: missing $file — run 'make update-ddl' on the host." >&2
    exit 1
  fi
  echo "[initdb] applying ${step} into schema '${CDM_SCHEMA}'"
  sed "s/@cdmDatabaseSchema/${CDM_SCHEMA}/g" "$file" \
    | psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --quiet
done

# Fail the boot loudly rather than leaving a half-built schema that reports healthy.
tables=$(psql -tAX --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = '${CDM_SCHEMA}';")
if [[ "$tables" -ne 39 ]]; then
  echo "[initdb] ERROR: expected 39 tables in '${CDM_SCHEMA}', found ${tables}." >&2
  exit 1
fi

echo "[initdb] OMOP CDM 5.4 ready — ${tables} tables in '${CDM_SCHEMA}'."
echo "[initdb] next: drop Athena CSVs in ./vocabulary, then 'make load-vocab && make finalize'."
