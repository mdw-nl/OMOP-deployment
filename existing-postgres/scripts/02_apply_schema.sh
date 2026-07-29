#!/bin/bash
# Creates the three schemas, then applies the CDM 5.4 DDL and primary keys.
#
# Constraints and indices are deliberately left for 04_finalize.sh. OHDSI's
# documented order is DDL -> primary keys -> load data -> constraints -> indices;
# adding 176 foreign keys and 72 indices before CONCEPT_ANCESTOR (tens of millions
# of rows) is loaded is the difference between minutes and hours.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_connection

# Re-running would fail on the first CREATE TABLE anyway; fail early with a
# message that says what to do instead.
existing=$(cdm_table_count)
if [[ "$existing" != "0" && "${FORCE:-0}" != "1" ]]; then
  die "schema '${CDM_SCHEMA}' already contains ${existing} tables.
  To rebuild it from scratch, drop it first:
      make drop-schema
  Or inspect what is there:
      make verify"
fi

say "creating schemas: ${CDM_SCHEMA}, ${RESULTS_SCHEMA}, ${TEMP_SCHEMA}"
run_psql <<SQL
CREATE SCHEMA IF NOT EXISTS "${CDM_SCHEMA}";
-- results/temp stay empty; they exist so OHDSI Atlas/WebAPI, Achilles and cohort
-- generation can be added later without reworking the database.
CREATE SCHEMA IF NOT EXISTS "${RESULTS_SCHEMA}";
CREATE SCHEMA IF NOT EXISTS "${TEMP_SCHEMA}";

COMMENT ON SCHEMA "${CDM_SCHEMA}" IS 'OMOP CDM 5.4 clinical + vocabulary tables';
COMMENT ON SCHEMA "${RESULTS_SCHEMA}" IS 'OHDSI cohort/analysis output (Atlas, Achilles)';
COMMENT ON SCHEMA "${TEMP_SCHEMA}" IS 'Scratch space for OHDSI tooling';
SQL

if [[ "$SET_DB_SEARCH_PATH" == "true" ]]; then
  say "setting database search_path to ${CDM_SCHEMA}, ${RESULTS_SCHEMA}, public"
  run_psql -c "ALTER DATABASE \"${TARGET_DB}\" SET search_path TO \"${CDM_SCHEMA}\", \"${RESULTS_SCHEMA}\", public;"
else
  say "leaving database search_path untouched (SET_DB_SEARCH_PATH=false)"
  say "  qualify your queries as ${CDM_SCHEMA}.person, or set search_path per session/role."
fi

apply_ddl_step ddl
apply_ddl_step primary_keys

tables=$(cdm_table_count)
[[ "$tables" == "39" ]] || die "expected 39 tables in '${CDM_SCHEMA}', found ${tables}. The DDL did not fully apply."

echo
say "OMOP CDM 5.4 schema ready — ${tables} tables in ${TARGET_DB}.${CDM_SCHEMA}"
say "next: put Athena CSVs in place, then 'make load-vocab' and 'make finalize'"
