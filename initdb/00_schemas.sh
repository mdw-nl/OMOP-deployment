#!/bin/bash
# Creates the three schemas. Runs once, on an empty data volume only.
#
# A shell script rather than plain .sql because the schema names come from the
# environment (.env) and the Postgres entrypoint does no substitution in .sql files.
set -euo pipefail

CDM_SCHEMA="${CDM_SCHEMA:-cdm}"
RESULTS_SCHEMA="${RESULTS_SCHEMA:-results}"
TEMP_SCHEMA="${TEMP_SCHEMA:-temp}"

echo "[initdb] creating schemas: ${CDM_SCHEMA}, ${RESULTS_SCHEMA}, ${TEMP_SCHEMA}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
CREATE SCHEMA IF NOT EXISTS "${CDM_SCHEMA}";
-- results/temp stay empty; they exist so OHDSI Atlas/WebAPI, Achilles and cohort
-- generation can be added later without rebuilding the data volume.
CREATE SCHEMA IF NOT EXISTS "${RESULTS_SCHEMA}";
CREATE SCHEMA IF NOT EXISTS "${TEMP_SCHEMA}";

ALTER DATABASE "${POSTGRES_DB}"
  SET search_path TO "${CDM_SCHEMA}", "${RESULTS_SCHEMA}", public;

COMMENT ON SCHEMA "${CDM_SCHEMA}" IS 'OMOP CDM 5.4 clinical + vocabulary tables';
COMMENT ON SCHEMA "${RESULTS_SCHEMA}" IS 'OHDSI cohort/analysis output (Atlas, Achilles)';
COMMENT ON SCHEMA "${TEMP_SCHEMA}" IS 'Scratch space for OHDSI tooling';
SQL
