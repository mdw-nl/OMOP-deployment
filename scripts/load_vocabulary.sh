#!/bin/bash
# Loads the OMOP standardized vocabulary from Athena CSVs mounted at /vocabulary.
# Runs inside the postgres container:  make load-vocab
#
# Idempotent: truncates the nine vocabulary tables first, so a re-run replaces
# rather than duplicates. Safe to run before or after clinical data exists —
# no clinical table is touched.
set -euo pipefail

CDM_SCHEMA="${CDM_SCHEMA:-cdm}"
VOCAB_DIR="${VOCAB_DIR:-/vocabulary}"

# Athena ships these names in uppercase. CONCEPT first and CONCEPT_ANCESTOR last is
# not required (FKs are added later by finalize.sh) but keeps the log readable.
FILES=(
  CONCEPT
  VOCABULARY
  DOMAIN
  CONCEPT_CLASS
  RELATIONSHIP
  CONCEPT_RELATIONSHIP
  CONCEPT_SYNONYM
  DRUG_STRENGTH
  CONCEPT_ANCESTOR
)

missing=()
for f in "${FILES[@]}"; do
  [[ -f "${VOCAB_DIR}/${f}.csv" ]] || missing+=("${f}.csv")
done

if (( ${#missing[@]} > 0 )); then
  cat >&2 <<MSG
ERROR: ${#missing[@]} vocabulary file(s) not found in ./vocabulary:

$(printf '  - %s\n' "${missing[@]}")

Download them from https://athena.ohdsi.org (free OHDSI account required):
  1. Download tab  ->  pick your vocabularies (SNOMED, RxNorm, LOINC, ICD10CM ... )
  2. Wait for the email, download the zip
  3. Unzip the CSVs directly into ./vocabulary (no nested folder)
Then re-run: make load-vocab
MSG
  exit 1
fi

psql_run() {
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --quiet "$@"
}

echo "==> truncating vocabulary tables in '${CDM_SCHEMA}'"
# One transaction so a failure leaves the previous contents in place.
psql_run <<SQL
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
  echo "==> loading ${f}.csv -> ${table}"
  # Athena CSVs are tab-delimited and UNQUOTED, while concept names legitimately
  # contain double quotes (e.g. chemical names). Postgres' default CSV quote char
  # would swallow a delimiter mid-row and abort the load, so point QUOTE at a
  # control character that cannot appear in the data.
  # Dates arrive as YYYYMMDD, which Postgres casts to `date` natively.
  psql_run -c "\\copy ${table} FROM '${VOCAB_DIR}/${f}.csv' WITH (FORMAT csv, DELIMITER E'\\t', HEADER true, QUOTE E'\\b', ENCODING 'UTF8')"
done

echo "==> row counts"
psql_run -c "
SELECT 'concept'              AS table, count(*) FROM ${CDM_SCHEMA}.concept
UNION ALL SELECT 'vocabulary',            count(*) FROM ${CDM_SCHEMA}.vocabulary
UNION ALL SELECT 'domain',                count(*) FROM ${CDM_SCHEMA}.domain
UNION ALL SELECT 'concept_class',         count(*) FROM ${CDM_SCHEMA}.concept_class
UNION ALL SELECT 'relationship',          count(*) FROM ${CDM_SCHEMA}.relationship
UNION ALL SELECT 'concept_relationship',  count(*) FROM ${CDM_SCHEMA}.concept_relationship
UNION ALL SELECT 'concept_synonym',       count(*) FROM ${CDM_SCHEMA}.concept_synonym
UNION ALL SELECT 'drug_strength',         count(*) FROM ${CDM_SCHEMA}.drug_strength
UNION ALL SELECT 'concept_ancestor',      count(*) FROM ${CDM_SCHEMA}.concept_ancestor;"

echo
echo "Vocabulary loaded. Next: make finalize   (adds FK constraints + indices)"
