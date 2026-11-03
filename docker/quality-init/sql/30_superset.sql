-- Metadata database for Superset and a read-only role for its dashboards.
-- Expects -v cdm_schema=...; passwords are read with \getenv, see 20_dqd.sql.
-- superset_reader can read the CDM as well, so new charts can use it. That includes
-- patient-level data, see the README warning.
SELECT 'CREATE ROLE superset LOGIN'
 WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'superset') \gexec
\getenv superset_db_password SUPERSET_DB_PASSWORD
ALTER ROLE superset PASSWORD :'superset_db_password';
SELECT 'CREATE DATABASE superset OWNER superset'
 WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'superset') \gexec

SELECT 'CREATE ROLE superset_reader LOGIN'
 WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'superset_reader') \gexec
\getenv superset_reader_password SUPERSET_READER_PASSWORD
ALTER ROLE superset_reader PASSWORD :'superset_reader_password';
ALTER ROLE superset_reader SET default_transaction_read_only = on;

SELECT format('GRANT CONNECT ON DATABASE %I TO superset_reader', current_database()) \gexec
GRANT USAGE ON SCHEMA :"cdm_schema", dqd_results TO superset_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA :"cdm_schema", dqd_results TO superset_reader;
-- DQD recreates tables in dqd_results on every run
ALTER DEFAULT PRIVILEGES FOR ROLE dqd IN SCHEMA dqd_results GRANT SELECT ON TABLES TO superset_reader;
