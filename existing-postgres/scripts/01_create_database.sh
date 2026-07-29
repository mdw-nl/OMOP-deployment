#!/bin/bash
# Creates TARGET_DB inside your existing Postgres instance, if it is missing.
# Skip this entirely when CREATE_DB=false (OMOP going into an existing database).
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

if [[ "$CREATE_DB" != "true" ]]; then
  say "CREATE_DB=false — using existing database '${TARGET_DB}', nothing to create."
  exit 0
fi

exists=$(PGDATABASE=postgres psql_value -c "SELECT count(*) FROM pg_database WHERE datname = '${TARGET_DB}';")
if [[ "$exists" != "0" ]]; then
  say "database '${TARGET_DB}' already exists — leaving it alone."
  exit 0
fi

# CREATE DATABASE cannot run inside a transaction block, hence the bare -c.
# UTF8 + a deterministic collation: vocabulary concept names are multilingual.
say "creating database '${TARGET_DB}'"
PGDATABASE=postgres run_psql -c "CREATE DATABASE \"${TARGET_DB}\" WITH ENCODING 'UTF8' TEMPLATE template0;"

say "database '${TARGET_DB}' created — next: make schema"
