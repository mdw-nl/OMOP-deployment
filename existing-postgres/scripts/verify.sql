-- Health report for an OMOP CDM 5.4 deployment.  Run with:  make verify
-- The Makefile passes -v cdm_schema=... -v results_schema=... -v temp_schema=...
\set ON_ERROR_STOP on
\pset footer off

-- Resolve the unqualified table names below, regardless of SET_DB_SEARCH_PATH.
SELECT set_config('search_path', :'cdm_schema' || ',public', false) AS search_path;

\echo
\echo === where ===
SELECT current_database() AS database, current_user AS "user", version() AS server;

\echo
\echo === schemas ===
SELECT nspname AS schema,
       (SELECT count(*) FROM information_schema.tables t WHERE t.table_schema = n.nspname) AS tables
FROM pg_namespace n
WHERE nspname IN (:'cdm_schema', :'results_schema', :'temp_schema')
ORDER BY 1;

\echo
\echo === CDM 5.4 structure ===
\echo 'after "make schema":    39 tables, 28 primary keys,   0 foreign keys,  28 indexes'
\echo 'after "make finalize":  39 tables, 28 primary keys, 176 foreign keys, 100 indexes'
\echo
SELECT
  (SELECT count(*) FROM information_schema.tables
    WHERE table_schema = :'cdm_schema')                       AS tables,
  (SELECT count(*) FROM pg_constraint c
     JOIN pg_namespace n ON n.oid = c.connamespace
    WHERE n.nspname = :'cdm_schema' AND c.contype = 'p')      AS primary_keys,
  (SELECT count(*) FROM pg_constraint c
     JOIN pg_namespace n ON n.oid = c.connamespace
    WHERE n.nspname = :'cdm_schema' AND c.contype = 'f')      AS foreign_keys,
  (SELECT count(*) FROM pg_indexes
    WHERE schemaname = :'cdm_schema')                         AS indexes;

\echo
\echo === vocabulary row counts (all zero until "make load-vocab") ===
  SELECT 'concept'             AS table, count(*) AS rows FROM concept
UNION ALL SELECT 'vocabulary',           count(*) FROM vocabulary
UNION ALL SELECT 'domain',               count(*) FROM domain
UNION ALL SELECT 'concept_class',        count(*) FROM concept_class
UNION ALL SELECT 'relationship',         count(*) FROM relationship
UNION ALL SELECT 'concept_relationship', count(*) FROM concept_relationship
UNION ALL SELECT 'concept_synonym',      count(*) FROM concept_synonym
UNION ALL SELECT 'drug_strength',        count(*) FROM drug_strength
UNION ALL SELECT 'concept_ancestor',     count(*) FROM concept_ancestor
ORDER BY 1;

\echo
\echo === sanity: concept 8507 should be "Male" once the vocabulary is loaded ===
SELECT concept_id, concept_name, vocabulary_id, domain_id
FROM concept WHERE concept_id = 8507;

\echo
\echo === clinical tables (populated by your ETL) ===
  SELECT 'person'                AS table, count(*) AS rows FROM person
UNION ALL SELECT 'observation_period',    count(*) FROM observation_period
UNION ALL SELECT 'visit_occurrence',      count(*) FROM visit_occurrence
UNION ALL SELECT 'condition_occurrence',  count(*) FROM condition_occurrence
UNION ALL SELECT 'drug_exposure',         count(*) FROM drug_exposure
UNION ALL SELECT 'measurement',           count(*) FROM measurement
UNION ALL SELECT 'observation',           count(*) FROM observation
ORDER BY 1;
