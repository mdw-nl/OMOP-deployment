#!/bin/bash
# Applies the OHDSI foreign-key constraints and indices, then refreshes planner stats.
#
# Run AFTER the vocabulary (and any clinical data) is loaded. That is both the
# documented OHDSI order and much faster than loading into a fully indexed,
# fully constrained schema.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_connection

tables=$(cdm_table_count)
[[ "$tables" == "39" ]] || die "expected 39 tables in '${CDM_SCHEMA}', found ${tables}. Run 'make schema' first."

# Every FK points at cdm.concept. Applying them against an empty vocabulary
# "succeeds" but leaves a schema no ETL can insert into, so make that explicit.
concepts=$(psql_value -c "SELECT count(*) FROM ${CDM_SCHEMA}.concept;")
if [[ "$concepts" == "0" ]]; then
  warn "${CDM_SCHEMA}.concept is empty. Constraints will be created, but any clinical"
  warn "insert referencing a concept_id will fail until you run 'make load-vocab'."
  warn "Continuing in 5s (Ctrl-C to abort)."
  sleep 5
fi

apply_ddl_step constraints
apply_ddl_step indices

say "analyzing ${TARGET_DB}.${CDM_SCHEMA}"
run_psql -c 'ANALYZE;'

fks=$(psql_value -c "
  SELECT count(*) FROM pg_constraint c
  JOIN pg_namespace n ON n.oid = c.connamespace
  WHERE n.nspname = '${CDM_SCHEMA}' AND c.contype = 'f';")
idx=$(psql_value -c "SELECT count(*) FROM pg_indexes WHERE schemaname = '${CDM_SCHEMA}';")

echo
say "done — ${fks} foreign keys, ${idx} indexes, statistics refreshed"
say "expected: 176 foreign keys, 100 indexes"
