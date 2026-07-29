#!/bin/bash
# Loads the OMOP standardized vocabulary from Athena CSVs.
#
# Idempotent: truncates the nine vocabulary tables first, so a re-run replaces
# rather than duplicates. Never touches a clinical table.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_connection

# Athena ships these names in uppercase. Order is cosmetic — foreign keys are not
# in place yet (04_finalize.sh adds them) — but CONCEPT first and the huge
# CONCEPT_ANCESTOR last makes the progress log readable.
FILES=(
  CONCEPT VOCABULARY DOMAIN CONCEPT_CLASS RELATIONSHIP
  CONCEPT_RELATIONSHIP CONCEPT_SYNONYM DRUG_STRENGTH CONCEPT_ANCESTOR
)

# `\copy` resolves paths on the psql CLIENT side, which differs by mode:
#   host   -> VOCAB_DIR is on this machine
#   docker -> VOCAB_DIR is inside the container, so it needs a read-only mount
file_exists() {
  if [[ "$PSQL_MODE" == "docker" ]]; then
    docker exec "$DOCKER_CONTAINER" test -f "$1" 2>/dev/null
  else
    [[ -f "$1" ]]
  fi
}

missing=()
for f in "${FILES[@]}"; do
  file_exists "${VOCAB_DIR}/${f}.csv" || missing+=("${f}.csv")
done

if (( ${#missing[@]} > 0 )); then
  {
    echo "ERROR: ${#missing[@]} of ${#FILES[@]} vocabulary files not found in ${VOCAB_DIR}"
    echo "       (resolved on the ${PSQL_MODE} side, because PSQL_MODE=${PSQL_MODE})"
    echo
    printf '  - %s\n' "${missing[@]}"
    echo
    echo "Download them from https://athena.ohdsi.org — see vocabulary/README.md."
    if [[ "$PSQL_MODE" == "docker" ]]; then
      echo
      echo "In docker mode the CSVs must be visible INSIDE container '${DOCKER_CONTAINER}'."
      echo "Add a read-only mount to your Postgres service and recreate it:"
      echo "    volumes:"
      echo "      - /abs/path/to/vocabulary:/vocabulary:ro"
      echo "then set VOCAB_DIR=/vocabulary in .env."
      echo "Alternatively set PSQL_MODE=host to read the CSVs straight off this machine."
    fi
  } >&2
  exit 1
fi

say "truncating vocabulary tables in ${TARGET_DB}.${CDM_SCHEMA}"
# One transaction, so a failure leaves the previous contents intact.
run_psql <<SQL
BEGIN;
TRUNCATE TABLE
  ${CDM_SCHEMA}.concept_ancestor,
  ${CDM_SCHEMA}.concept_synonym,
  ${CDM_SCHEMA}.concept_relationship,
  ${CDM_SCHEMA}.drug_strength,
  ${CDM_SCHEMA}.relationship,
  ${CDM_SCHEMA}.concept_class,
  ${CDM_SCHEMA}.domain,
  ${CDM_SCHEMA}.vocabulary,
  ${CDM_SCHEMA}.concept;
COMMIT;
SQL

for f in "${FILES[@]}"; do
  table="${CDM_SCHEMA}.$(echo "$f" | tr '[:upper:]' '[:lower:]')"
  say "loading ${f}.csv -> ${table}"
  # Athena CSVs are tab-delimited and UNQUOTED, yet concept names legitimately
  # contain double quotes (chemical and device names especially). Postgres' default
  # CSV quote character would swallow a delimiter mid-row and abort the load, so
  # point QUOTE at a control character that cannot occur in the data.
  # Dates arrive as YYYYMMDD, which Postgres casts to `date` natively.
  run_psql -c "\\copy ${table} FROM '${VOCAB_DIR}/${f}.csv' WITH (FORMAT csv, DELIMITER E'\\t', HEADER true, QUOTE E'\\b', ENCODING 'UTF8')"
done

echo
say "row counts"
run_psql -c "
  SELECT 'concept'             AS table, count(*) AS rows FROM ${CDM_SCHEMA}.concept
UNION ALL SELECT 'vocabulary',           count(*) FROM ${CDM_SCHEMA}.vocabulary
UNION ALL SELECT 'domain',               count(*) FROM ${CDM_SCHEMA}.domain
UNION ALL SELECT 'concept_class',        count(*) FROM ${CDM_SCHEMA}.concept_class
UNION ALL SELECT 'relationship',         count(*) FROM ${CDM_SCHEMA}.relationship
UNION ALL SELECT 'concept_relationship', count(*) FROM ${CDM_SCHEMA}.concept_relationship
UNION ALL SELECT 'concept_synonym',      count(*) FROM ${CDM_SCHEMA}.concept_synonym
UNION ALL SELECT 'drug_strength',        count(*) FROM ${CDM_SCHEMA}.drug_strength
UNION ALL SELECT 'concept_ancestor',     count(*) FROM ${CDM_SCHEMA}.concept_ancestor
ORDER BY 1;"

echo
say "vocabulary loaded — next: make finalize"
