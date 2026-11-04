# Runs the OHDSI Data Quality Dashboard checks against the CDM and stores the results of
# every run in dqd_results.check_results_history, registered in dqd_results.run_log.
library(DatabaseConnector)

env <- function(name, default) {
  value <- Sys.getenv(name, "")
  if (value == "") default else value
}

cdmSchema <- env("CDM_SCHEMA", "cdm")
resultsSchema <- "dqd_results"
resultColumns <- paste(
  "checkid, check_name, check_level, check_description, cdm_table_name, cdm_field_name,",
  "concept_id, unit_concept_id, sql_file, category, subcategory, context, num_violated_rows,",
  "pct_violated_rows, num_denominator_rows, threshold_value, is_error, not_applicable, failed,",
  "passed, not_applicable_reason, warning, error, notes_value, execution_time, query_text"
)

# Pass the settings as values, DQD threads cannot evaluate the lazily captured expressions
connectionDetails <- do.call(createConnectionDetails, list(
  dbms = "postgresql",
  server = sprintf("%s/%s", env("DQD_DB_HOST", "postgres"), env("DQD_DB_NAME", "omop")),
  port = as.integer(env("DQD_DB_PORT", "5432")),
  user = env("DQD_DB_USER", "dqd"),
  password = env("DQD_DB_PASSWORD", "dqd")
))

connection <- connect(connectionDetails)
quote <- function(value) DBI::dbQuoteString(connection, as.character(value))
# First value of a single value query
queryValue <- function(sql) querySql(connection, sql)[[1]][1]

# The ETL's own row rather than the quality-init placeholder, see 10_cdm_source.sql
cdmSourceName <- queryValue(sprintf(
  "SELECT cdm_source_name FROM %s.cdm_source ORDER BY cdm_holder = 'Placeholder (quality-init)' NULLS FIRST LIMIT 1",
  cdmSchema
))
if (is.na(cdmSourceName)) cdmSourceName <- "OMOP CDM"
runId <- queryValue("SELECT gen_random_uuid()::text")

# run_dqd.sh holds a lock for the whole run, so a run still marked as running was
# interrupted (container stopped or killed) and will never finish. Assumes one dqd
# container per database.
executeSql(connection, sprintf(
  "UPDATE %s.run_log SET status = 'failed', finished_at = now(), error = 'Interrupted, the run did not finish' WHERE status = 'running'",
  resultsSchema
), progressBar = FALSE, reportOverallTime = FALSE)

executeSql(connection, sprintf(
  "INSERT INTO %s.run_log (run_id, cdm_source_name, dqd_version, started_at, status) VALUES (%s, %s, %s, now(), 'running')",
  resultsSchema, quote(runId), quote(cdmSourceName), quote(packageVersion("DataQualityDashboard"))
), progressBar = FALSE, reportOverallTime = FALSE)

status <- tryCatch({
  # Never copy the results of a previous run
  executeSql(connection, sprintf("DROP TABLE IF EXISTS %s.dqdashboard_results", resultsSchema),
    progressBar = FALSE, reportOverallTime = FALSE
  )

  # DQD (<= 2.9.1) fails when disconnecting a NULL connection at exit when running with
  # multiple threads, after all results are written. That error is logged and ignored;
  # the copy below fails if the results table is missing, and the row count check still applies
  tryCatch(DataQualityDashboard::executeDqChecks(
    connectionDetails = connectionDetails,
    cdmDatabaseSchema = cdmSchema,
    resultsDatabaseSchema = resultsSchema,
    vocabDatabaseSchema = cdmSchema,
    cdmSourceName = cdmSourceName,
    cdmVersion = "5.4",
    numThreads = as.integer(env("DQD_THREADS", "1")),
    outputFolder = "/output",
    outputFile = sprintf("dqd-%s.json", runId),
    writeToTable = TRUE,
    writeTableName = "dqdashboard_results",
    # DQD defaults, plus the cohort tables which hold analysis results instead of source data
    tablesToExclude = c(
      "CONCEPT", "VOCABULARY", "CONCEPT_ANCESTOR", "CONCEPT_RELATIONSHIP", "CONCEPT_CLASS", "CONCEPT_SYNONYM",
      "RELATIONSHIP", "DOMAIN", "PACK_CONTENT", "CONCEPT_METADATA", "CONCEPT_RELATIONSHIP_METADATA",
      "COHORT", "COHORT_DEFINITION"
    )
  ), error = function(e) {
    if (!grepl("applied to an object of class \"NULL\"", conditionMessage(e), fixed = TRUE)) stop(e)
    message(sprintf("Ignoring a known DQD error at the end of the run: %s", conditionMessage(e)))
  })

  executeSql(connection, sprintf(
    "INSERT INTO %1$s.check_results_history (run_id, %2$s) SELECT %3$s, %2$s FROM %1$s.dqdashboard_results",
    resultsSchema, resultColumns, quote(runId)
  ), progressBar = FALSE, reportOverallTime = FALSE)

  # DQD only logs a warning when writing its results table fails
  checks <- queryValue(sprintf(
    "SELECT count(*) FROM %s.check_results_history WHERE run_id = %s", resultsSchema, quote(runId)
  ))
  if (checks == 0) stop("DQD did not write any check results")

  executeSql(connection, sprintf(
    "UPDATE %s.run_log SET status = 'success', finished_at = now() WHERE run_id = %s", resultsSchema, quote(runId)
  ), progressBar = FALSE, reportOverallTime = FALSE)
  message(sprintf("DQD run %s finished, %d check results stored", runId, checks))
  0
}, error = function(e) {
  executeSql(connection, sprintf(
    "UPDATE %s.run_log SET status = 'failed', finished_at = now(), error = %s WHERE run_id = %s",
    resultsSchema, quote(conditionMessage(e)), quote(runId)
  ), progressBar = FALSE, reportOverallTime = FALSE)
  message(sprintf("DQD run %s failed: %s", runId, conditionMessage(e)))
  1
})

# on.exit() has no effect outside a function, so disconnect here
disconnect(connection)
quit(status = status)
