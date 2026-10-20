#!/bin/bash
# Creates a login role that can SELECT the vocabulary tables and nothing else.
# Runs once on an empty data volume; on an existing one, run `make vocab-reader`.
#
# Skipped when VOCAB_READER_PASSWORD is empty. Vocabulary and clinical tables share
# the CDM schema, so the grant names each table — a schema-wide grant would expose
# person, visit_occurrence, etc. Idempotent: re-running resets the password and
# re-applies the grants.
set -euo pipefail

CDM_SCHEMA="${CDM_SCHEMA:-cdm}"
VOCAB_READER_USER="${VOCAB_READER_USER:-vocab_reader}"

if [[ -z "${VOCAB_READER_PASSWORD:-}" ]]; then
  echo "[initdb] VOCAB_READER_PASSWORD not set — skipping read-only vocabulary role."
  exit 0
fi

echo "[initdb] creating read-only role '${VOCAB_READER_USER}' on the vocabulary tables"

# The password is read with \getenv rather than interpolated by the shell, so it
# never appears in the SQL text or on a command line.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --quiet \
  -v role="$VOCAB_READER_USER" <<SQL
SELECT format('CREATE ROLE %I LOGIN', :'role')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'role') \gexec

\getenv pw VOCAB_READER_PASSWORD
ALTER ROLE :"role" PASSWORD :'pw';

GRANT CONNECT ON DATABASE "${POSTGRES_DB}" TO :"role";
GRANT USAGE ON SCHEMA "${CDM_SCHEMA}" TO :"role";
GRANT SELECT ON
  "${CDM_SCHEMA}".concept,
  "${CDM_SCHEMA}".concept_synonym,
  "${CDM_SCHEMA}".concept_relationship,
  "${CDM_SCHEMA}".concept_ancestor,
  "${CDM_SCHEMA}".concept_class,
  "${CDM_SCHEMA}".relationship,
  "${CDM_SCHEMA}".vocabulary,
  "${CDM_SCHEMA}".domain
TO :"role";
SQL

echo "[initdb] '${VOCAB_READER_USER}' can read the vocabulary tables in '${CDM_SCHEMA}'."
