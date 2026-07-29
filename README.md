# OMOP CDM 5.4 on PostgreSQL

A Docker Compose stack that stands up a PostgreSQL 16 database with the **OMOP Common
Data Model 5.4** schema, plus pgAdmin for browsing it.

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
$EDITOR .env              # set POSTGRES_PASSWORD and PGADMIN_PASSWORD
make up                   # starts Postgres + pgAdmin, applies the DDL, waits for healthy
make verify               # 39 tables in `cdm`, empty vocabulary
```

- Postgres: `localhost:5432`, database `omop`, user `omop`
- pgAdmin: <http://localhost:8080> — the OMOP server is pre-registered; enter
  `POSTGRES_PASSWORD` on first connect

Then load the vocabulary (see [vocabulary/README.md](vocabulary/README.md) for the
Athena download):

```bash
# unzip Athena CSVs into ./vocabulary first
make load-vocab           # COPYs the nine vocabulary tables
make finalize             # FK constraints + indices + ANALYZE
make verify               # concept 8507 -> "Male"
```

## Order matters

**`up` → `load-vocab` → `finalize`.**

Container init applies the DDL and primary keys only. Constraints and indices are held
back until `make finalize`, which is OHDSI's documented order — building the foreign-key
graph and every index before `CONCEPT_ANCESTOR` (tens of millions of rows) is loaded
makes the vocabulary load dramatically slower.

Running `finalize` on an empty vocabulary works but warns: the constraints all reference
`cdm.concept`, so clinical inserts would fail until the vocabulary is there.

## Schemas

| Schema | Contents |
| --- | --- |
| `cdm` | All 39 CDM 5.4 tables — clinical and vocabulary |
| `results` | Empty. For OHDSI Atlas/WebAPI cohorts and Achilles output |
| `temp` | Empty. Scratch space for OHDSI tooling |

`results` and `temp` exist up front so Atlas/WebAPI can be added later without
rebuilding the data volume. Schema names are configurable in `.env`; changing
`CDM_SCHEMA` after the first boot requires `make reset`.

## Targets

| Target | Description |
| --- | --- |
| `make init` | Create `.env` from `.env.example` |
| `make up` | Start the stack, wait for healthy |
| `make down` | Stop, keeping data |
| `make ps` / `make logs` | Status / tail Postgres logs |
| `make psql` | Interactive psql session |
| `make load-vocab` | Load Athena CSVs from `./vocabulary` |
| `make finalize` | Apply constraints + indices, refresh statistics |
| `make verify` | Report schemas, table/key/index counts, row counts |
| `make update-ddl` | Re-download the OHDSI DDL into `ddl/` |
| `make reset` | **Destroys the volume** and rebuilds the schema (prompts first) |

## How it fits together

```
docker-compose.yml     postgres:16 + pgadmin4, healthcheck, named volumes
.env                   credentials, ports, schema names, Postgres tuning (gitignored)
ddl/                   vendored OHDSI 5.4 scripts — do not edit
initdb/                runs once, on an empty volume only
  00_schemas.sh          creates cdm / results / temp
  01_apply_ddl.sh        substitutes @cdmDatabaseSchema, applies DDL + primary keys
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
