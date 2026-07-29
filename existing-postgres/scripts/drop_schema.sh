#!/bin/bash
# Drops the OMOP schemas from TARGET_DB so the schema can be rebuilt.
# Destructive, and prompts before acting. Nothing outside the three OMOP schemas
# is touched — your other databases and schemas are untouched by design.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_connection

tables=$(cdm_table_count)
cat <<MSG
About to DROP these schemas from database '${TARGET_DB}':
    ${CDM_SCHEMA}       (${tables} tables — all OMOP data in them is lost)
    ${RESULTS_SCHEMA}
    ${TEMP_SCHEMA}

Nothing else in '${TARGET_DB}' or in any other database is affected.
MSG

read -r -p "Type the database name '${TARGET_DB}' to confirm: " answer
[[ "$answer" == "$TARGET_DB" ]] || die "aborted (got '${answer}')."

say "dropping schemas"
run_psql <<SQL
DROP SCHEMA IF EXISTS "${CDM_SCHEMA}" CASCADE;
DROP SCHEMA IF EXISTS "${RESULTS_SCHEMA}" CASCADE;
DROP SCHEMA IF EXISTS "${TEMP_SCHEMA}" CASCADE;
SQL

# Otherwise the database keeps a search_path pointing at schemas that no longer exist.
if [[ "$SET_DB_SEARCH_PATH" == "true" ]]; then
  say "resetting database search_path"
  run_psql -c "ALTER DATABASE \"${TARGET_DB}\" RESET search_path;"
fi

say "schemas dropped — 'make schema' to rebuild"
