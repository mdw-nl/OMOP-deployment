# OMOP CDM 5.4 on PostgreSQL

A Docker Compose stack that stands up a PostgreSQL 16 database with the **OMOP Common
Data Model 5.4** schema, plus pgAdmin for browsing it, scheduled
[OHDSI Data Quality Dashboard](https://ohdsi.github.io/DataQualityDashboard/) checks, and
an Apache Superset dashboard of their results.

> Already running your own Postgres + pgAdmin? Use [existing-postgres/](existing-postgres/)
> instead — it adds the OMOP schema to a live instance without touching your compose
> file or data volume.

The schema is not hand-written: `ddl/` holds the official
[OHDSI CommonDataModel](https://github.com/OHDSI/CommonDataModel) scripts for
PostgreSQL 5.4, vendored unmodified so the stack builds offline and upgrades are a
clean diff (`make update-ddl`).

## Quickstart

```bash
make init                 # creates .env from the template
$EDITOR .env              # set the passwords (all *_PASSWORD variables)
# optional: unzip Athena CSVs into ./vocabulary, or set VOCAB_URL in .env
make up                   # starts the stack, applies the DDL, loads the vocabulary
make verify               # 39 tables in `cdm`; concept 8507 -> "Male" with a vocabulary
```

- Postgres: `localhost:5432`, database `omop`, user `omop`
- pgAdmin: <http://localhost:8080> — the OMOP server is pre-registered; enter
  `POSTGRES_PASSWORD` on first connect
- Superset: <http://localhost:8088> — sign in with `SUPERSET_ADMIN_USERNAME` /
  `SUPERSET_ADMIN_PASSWORD` and open the "OMOP Data Quality" dashboard

## Vocabulary

On every `make up` the `omop-init` container checks `cdm.concept`. When it is empty it
loads the vocabulary from, in this order:

1. the Athena CSVs in `./vocabulary` (see [existing-postgres/vocabulary/README.md](existing-postgres/vocabulary/README.md)
   for the Athena download);
2. the zip at `VOCAB_URL` in `.env`, downloaded once into the `omop_vocab_cache` volume.

With neither, the stack starts with an empty vocabulary. Load it later by hand:

```bash
# unzip Athena CSVs into ./vocabulary first
make load-vocab           # COPYs the nine vocabulary tables
make finalize             # FK constraints + indices + ANALYZE
make verify               # concept 8507 -> "Male"
```

`make logs-init` shows what `omop-init` did on the last start.

## Order matters

**DDL → vocabulary → `finalize`.**

Container init applies the DDL and primary keys only. Constraints and indices are held
back until the vocabulary is loaded, which is OHDSI's documented order — building the
foreign-key graph and every index before `CONCEPT_ANCESTOR` (tens of millions of rows)
is loaded makes the vocabulary load dramatically slower. `omop-init` follows this order
and runs `finalize` itself after loading the vocabulary. It skips statements the
vocabulary violates (some vocabulary packages do not satisfy every foreign key) instead
of stopping, so all other constraints and indices are still built; `make finalize`
stops at the first error.

Running `finalize` on an empty vocabulary works but warns: the constraints all reference
`cdm.concept`, so clinical inserts would fail until the vocabulary is there.

## Schemas

| Schema | Contents |
| --- | --- |
| `cdm` | All 39 CDM 5.4 tables — clinical and vocabulary |
| `results` | Empty. For OHDSI Atlas/WebAPI cohorts and Achilles output |
| `temp` | Empty. Scratch space for OHDSI tooling |
| `dqd_results` | Data quality check results, see [Data quality checks](#data-quality-checks-dqd) |

`results` and `temp` exist up front so Atlas/WebAPI can be added later without
rebuilding the data volume. Schema names are configurable in `.env`; changing
`CDM_SCHEMA` after the first boot requires `make reset`.

## Read-only vocabulary user

Set `VOCAB_READER_PASSWORD` (and optionally `VOCAB_READER_USER`, default
`vocab_reader`) in `.env` and container init creates a login role with `SELECT` on
the vocabulary tables only: `concept`, `concept_synonym`, `concept_relationship`,
`concept_ancestor`, `concept_class`, `relationship`, `vocabulary`, `domain`. It has
no access to clinical tables, `drug_strength` or `source_to_concept_map`.

Leave the password empty to skip it. On a volume that already exists, set it and run
`make vocab-reader`, which is also how you change the password later. Grants survive
`make load-vocab`, since that truncates rather than recreates the tables.

## Data quality checks (DQD)

The `dqd` container runs the [OHDSI Data Quality Dashboard](https://ohdsi.github.io/DataQualityDashboard/)
checks against the CDM when it starts and on the schedule in `DQD_SCHEDULE` (cron, UTC,
default `0 2 * * *`: every night at 02:00). `make dqd` runs them right away. It connects
as the `dqd` role (`DQD_PASSWORD`), which can read the CDM and owns the `dqd_results`
schema.

Every run is registered in `dqd_results.run_log` and its results are kept in
`dqd_results.check_results_history`, so earlier runs stay available for trends. The views
`dqd_results.v_check_results` and `dqd_results.v_run_summary` give one row per check and
per run. The JSON output of each run, which the DQD viewer can open, is kept in the
`omop_dqd_output` volume.

The vocabulary tables and the cohort tables are not checked: the first are DQD's
default exclusions, the second hold analysis results rather than source data.

## Data quality dashboard (Superset)

[Apache Superset](https://superset.apache.org/) on <http://localhost:8088> shows the DQD
results in the "OMOP Data Quality" dashboard: pass rate, results per Kahn category and
context, failed checks per CDM table, a list of all failed checks of the latest run, and
the trend over all runs. Its metadata lives in a `superset` database on the same Postgres
server. Dashboards query the OMOP database as `superset_reader`, a read-only role on
`cdm` and `dqd_results`, so new charts can also use the CDM tables.

`superset-init` imports the dashboard from [docker/superset/assets](docker/superset/assets)
on every start, which overwrites changes made to it in the UI. To keep changes, export
the dashboard (dashboard menu "Download" > "Export YAML"), replace the contents of
`docker/superset/assets` with the contents of the exported zip, and run `make up`.

## Targets

| Target | Description |
| --- | --- |
| `make init` | Create `.env` from `.env.example` |
| `make up` | Build and start the stack, wait until `omop-init` is done |
| `make down` | Stop, keeping data |
| `make ps` / `make logs` | Status / tail Postgres logs |
| `make logs-init` | Show what `omop-init` did on the last start |
| `make dqd` / `make logs-dqd` | Run the data quality checks now / tail their logs |
| `make psql` | Interactive psql session |
| `make load-vocab` | Load Athena CSVs from `./vocabulary` |
| `make finalize` | Apply constraints + indices, refresh statistics |
| `make vocab-reader` | Create/update the read-only vocabulary role on a running stack |
| `make verify` | Report schemas, table/key/index counts, row counts |
| `make update-ddl` | Re-download the OHDSI DDL into `ddl/` |
| `make reset` | **Destroys the volume** and rebuilds the schema (prompts first) |

## How it fits together

```
docker-compose.yml     postgres:16, pgadmin4, omop-init, dqd and superset, named volumes
.env                   credentials, ports, schema names, Postgres tuning (gitignored)
ddl/                   vendored OHDSI 5.4 scripts — do not edit
initdb/                runs once, on an empty volume only
  00_schemas.sh          creates cdm / results / temp
  01_apply_ddl.sh        substitutes @cdmDatabaseSchema, applies DDL + primary keys
  02_vocab_reader.sh     optional read-only role on the vocabulary tables
docker/omop-init/      runs on every start, each step skipped when already done
  init.sh                vocabulary from ./vocabulary or VOCAB_URL, finalize, sql/
  sql/                   cdm_source placeholder row, dqd/superset roles, dqd_results schema
docker/dqd/            DQD checks on start and on DQD_SCHEDULE (R, supercronic)
docker/superset/       Superset image, config and the dashboard assets
scripts/
  load_vocabulary.sh     truncate + COPY the nine vocabulary tables
  finalize.sh            constraints + indices + ANALYZE
  verify.sql             health report
vocabulary/            drop Athena CSVs here (gitignored, mounted read-only)
```

Two details worth knowing if you edit these:

- The OHDSI scripts are **templates**. Every table is
  `CREATE TABLE @cdmDatabaseSchema.person (...)`; the placeholder is substituted with
  `sed` on the way into `psql`, leaving `ddl/` byte-identical to upstream.
- Athena CSVs are tab-delimited and **unquoted**, yet concept names legitimately
  contain `"`. The `COPY` calls set `QUOTE E'\b'` — a character that cannot occur in
  the data — because the default CSV quote char aborts the load partway through.

## Persistence and reset

Data lives in the named volume `omop_pgdata`, so `make down` keeps it. The
`initdb/` scripts only run when that volume is empty — to rebuild the schema from
changed DDL, use `make reset`.

## Not included

No ETL, no synthetic data, no OHDSI WebAPI/Atlas containers. The `results` and `temp`
schemas are the hook for adding Atlas later.
