#!/bin/bash
# Preflight: can we reach the server, what version is it, and what is already there?
# Read-only — changes nothing. Run this first:  make check
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

say "mode: PSQL_MODE=${PSQL_MODE}$( [[ $PSQL_MODE == docker ]] && echo " container=${DOCKER_CONTAINER}" )"

# Connect to a database we know exists, not TARGET_DB — it may not exist yet.
version=$(PGDATABASE=postgres psql_value -c 'SHOW server_version;') \
  || die "cannot reach Postgres. Check PGHOST/PGPORT/PGUSER/PGPASSWORD (host mode) or DOCKER_CONTAINER (docker mode)."
say "server version: ${version}"

major="${version%%.*}"
if (( major < 12 )); then
  warn "Postgres ${major} is older than 12. The CDM 5.4 DDL is plain SQL and will likely apply,"
  warn "but OHDSI tooling targets 12+ and this combination is untested here."
fi

say "current user: $(PGDATABASE=postgres psql_value -c 'SELECT current_user;')"

# Creating a database and schemas both need real privileges; find out now rather
# than halfway through the DDL.
if [[ "$CREATE_DB" == "true" ]]; then
  can_create=$(PGDATABASE=postgres psql_value -c "SELECT rolcreatedb OR rolsuper FROM pg_roles WHERE rolname = current_user;")
  [[ "$can_create" == "t" ]] \
    || die "CREATE_DB=true but '${PGUSER}' lacks CREATEDB. Grant it, use a superuser, or set CREATE_DB=false."
fi

exists=$(PGDATABASE=postgres psql_value -c "SELECT count(*) FROM pg_database WHERE datname = '${TARGET_DB}';")
if [[ "$exists" == "0" ]]; then
  say "target database '${TARGET_DB}': does not exist yet"
  [[ "$CREATE_DB" == "true" ]] \
    || die "CREATE_DB=false but '${TARGET_DB}' does not exist. Create it yourself or set CREATE_DB=true."
  say "OK — next: make create-db"
else
  say "target database '${TARGET_DB}': exists"
  tables=$(cdm_table_count)
  if [[ "$tables" == "0" ]]; then
    say "schema '${CDM_SCHEMA}': empty or absent — next: make schema"
  else
    warn "schema '${CDM_SCHEMA}' already holds ${tables} tables."
    warn "'make schema' will refuse to run; use 'make verify' to inspect, or drop the schema first."
  fi

  # Adding schemas to a database other applications use is the case where
  # SET_DB_SEARCH_PATH=true would quietly affect them.
  if [[ "$CREATE_DB" != "true" && "$SET_DB_SEARCH_PATH" == "true" ]]; then
    warn "CREATE_DB=false with SET_DB_SEARCH_PATH=true: this rewrites the default search_path"
    warn "for EVERY client of '${TARGET_DB}', including your existing applications."
    warn "Set SET_DB_SEARCH_PATH=false unless '${TARGET_DB}' is dedicated to OMOP."
  fi
fi

echo
say "preflight passed"
