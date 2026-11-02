-- Role and results schema for the OHDSI Data Quality Dashboard (DQD) runs.
-- Expects -v cdm_schema=...; the password is read from DQD_PASSWORD with \getenv rather
-- than interpolated, so it never appears in the SQL text or on a command line.
SELECT 'CREATE ROLE dqd LOGIN'
 WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dqd') \gexec
\getenv dqd_password DQD_PASSWORD
ALTER ROLE dqd PASSWORD :'dqd_password';

SELECT format('GRANT CONNECT ON DATABASE %I TO dqd', current_database()) \gexec
-- DQD only reads the CDM; its results go to its own schema
GRANT USAGE ON SCHEMA :"cdm_schema" TO dqd;
GRANT SELECT ON ALL TABLES IN SCHEMA :"cdm_schema" TO dqd;
CREATE SCHEMA IF NOT EXISTS dqd_results AUTHORIZATION dqd;

SET ROLE dqd;

CREATE TABLE IF NOT EXISTS dqd_results.run_log (
    run_id          uuid PRIMARY KEY,
    cdm_source_name text,
    dqd_version     text,
    started_at      timestamptz NOT NULL,
    finished_at     timestamptz,
    status          text NOT NULL,
    error           text
);

-- DQD recreates its dqdashboard_results table on every run, so each run is copied to this table
CREATE TABLE IF NOT EXISTS dqd_results.check_results_history (
    run_id                uuid NOT NULL REFERENCES dqd_results.run_log (run_id) ON DELETE CASCADE,
    checkid               text,
    check_name            text,
    check_level           text,
    check_description     text,
    cdm_table_name        text,
    cdm_field_name        text,
    concept_id            text,
    unit_concept_id       text,
    sql_file              text,
    category              text,
    subcategory           text,
    context               text,
    num_violated_rows     bigint,
    pct_violated_rows     double precision,
    num_denominator_rows  bigint,
    threshold_value       integer,
    is_error              integer,
    not_applicable        integer,
    failed                integer,
    passed                integer,
    not_applicable_reason text,
    warning               text,
    error                 text,
    notes_value           text,
    execution_time        text,
    query_text            text
);
CREATE INDEX IF NOT EXISTS check_results_history_run_id ON dqd_results.check_results_history (run_id);

-- One row per check per successful run, with a single status column
CREATE OR REPLACE VIEW dqd_results.v_check_results AS
SELECT r.run_id,
       l.started_at AS run_started_at,
       l.cdm_source_name,
       l.started_at = max(l.started_at) OVER () AS is_latest_run,
       r.checkid,
       r.check_name,
       r.check_level,
       r.check_description,
       r.cdm_table_name,
       r.cdm_field_name,
       r.concept_id,
       r.unit_concept_id,
       r.category,
       coalesce(r.subcategory, '') AS subcategory,
       r.context,
       CASE WHEN r.is_error = 1 THEN 'Error'
            WHEN r.not_applicable = 1 THEN 'Not applicable'
            WHEN r.failed = 1 THEN 'Failed'
            ELSE 'Passed' END AS check_status,
       r.num_violated_rows,
       r.pct_violated_rows * 100 AS pct_violated_rows,
       r.num_denominator_rows,
       r.threshold_value,
       r.not_applicable_reason,
       r.error,
       r.notes_value
  FROM dqd_results.check_results_history r
  JOIN dqd_results.run_log l USING (run_id)
 WHERE l.status = 'success';

-- Summary per successful run; the pass percentage only counts applicable checks, as DQD does
CREATE OR REPLACE VIEW dqd_results.v_run_summary AS
SELECT run_id,
       run_started_at,
       cdm_source_name,
       is_latest_run,
       count(*) AS total_checks,
       count(*) FILTER (WHERE check_status = 'Passed') AS passed,
       count(*) FILTER (WHERE check_status = 'Failed') AS failed,
       count(*) FILTER (WHERE check_status = 'Error') AS errors,
       count(*) FILTER (WHERE check_status = 'Not applicable') AS not_applicable,
       round(100.0 * count(*) FILTER (WHERE check_status = 'Passed')
             / nullif(count(*) FILTER (WHERE check_status IN ('Passed', 'Failed', 'Error')), 0), 1) AS pct_passed
  FROM dqd_results.v_check_results
 GROUP BY run_id, run_started_at, cdm_source_name, is_latest_run;

RESET ROLE;
