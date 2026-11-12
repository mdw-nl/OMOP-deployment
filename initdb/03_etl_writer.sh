#!/bin/bash
# Creates the login role the ETL pipeline writes with: INSERT and DELETE on the
# tables in the CDM schema, and nothing more (no SELECT, UPDATE, TRUNCATE or DDL).
# Runs once on an empty data volume; on an existing one, run `make etl-writer`.
#
# Without SELECT, DELETE works only without a WHERE clause on table columns
# (Postgres needs SELECT on every column a WHERE reads).
#
# Skipped when ETL_WRITER_PASSWORD is empty. Idempotent: re-running resets the
# password and re-applies the grants.
set -euo pipefail

CDM_SCHEMA="${CDM_SCHEMA:-cdm}"
ETL_WRITER_USER="${ETL_WRITER_USER:-omop_etl_writer}"

if [[ -z "${ETL_WRITER_PASSWORD:-}" ]]; then
  echo "[initdb] ETL_WRITER_PASSWORD not set — skipping ETL writer role."
  exit 0
fi

echo "[initdb] creating ETL writer role '${ETL_WRITER_USER}' on '${CDM_SCHEMA}'"

# The password is read with \getenv rather than interpolated by the shell, so it
# never appears in the SQL text or on a command line.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --quiet \
  -v role="$ETL_WRITER_USER" <<SQL
SELECT format('CREATE ROLE %I LOGIN', :'role')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'role') \gexec

\getenv pw ETL_WRITER_PASSWORD
ALTER ROLE :"role" PASSWORD :'pw';

GRANT CONNECT ON DATABASE "${POSTGRES_DB}" TO :"role";
GRANT USAGE ON SCHEMA "${CDM_SCHEMA}" TO :"role";
GRANT INSERT, DELETE ON ALL TABLES IN SCHEMA "${CDM_SCHEMA}" TO :"role";
SQL

echo "[initdb] '${ETL_WRITER_USER}' can insert into and delete from the tables in '${CDM_SCHEMA}'."
