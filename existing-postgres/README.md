# OMOP CDM 5.4 → an existing PostgreSQL

Adds the **OMOP Common Data Model 5.4** schema to a PostgreSQL instance you already
run. Use this instead of the stack in the parent folder when you have your own
`docker-compose.yml` with Postgres and pgAdmin.

**This folder never starts, stops, or recreates a container, and never touches a data
volume.** Every operation is SQL sent to your running database.

## Why this exists as a separate folder

The parent folder deploys OMOP through `docker-entrypoint-initdb.d`, which **only runs
when the Postgres data directory is empty**. Your instance already has data, so those
init scripts would never fire no matter how you mounted them — mounting them and
expecting tables to appear is the most common way this fails silently.

On an existing instance the DDL has to be a one-off operation against the live
database. That is what these scripts do.

## Quickstart

```bash
make init            # creates .env
$EDITOR .env         # set PGUSER/PGPASSWORD, pick PSQL_MODE
make check           # read-only preflight — run this first
make install         # creates the database, schemas, tables and primary keys
make verify          # expect 39 tables, 28 primary keys
```

Then the vocabulary (see [vocabulary/README.md](vocabulary/README.md) for the Athena
download):

```bash
make load-vocab      # COPYs the nine vocabulary tables
make finalize        # FK constraints + indices + ANALYZE
make verify          # concept 8507 -> "Male"
```

`make check` is worth running before anything else. It confirms connectivity, reports
the server version, verifies your role has the privileges the later steps need, and
tells you whether OMOP is already installed — all without writing anything.

## Two choices to make in `.env`

### Where OMOP lives — `TARGET_DB` / `CREATE_DB`

**A dedicated `omop` database** (`CREATE_DB=true`, the default) is the recommended
setup. One Postgres instance can host many databases at no cost, and you get full
isolation: no name collisions, no shared `search_path`, per-database backups, and
`make drop-schema` for a clean slate.

**Schemas inside an existing database** (`CREATE_DB=false`, `TARGET_DB=your_db`) only
makes sense if you need to join OMOP tables against your existing tables in a single
query. If you go this way, **also set `SET_DB_SEARCH_PATH=false`** — otherwise
`ALTER DATABASE ... SET search_path` changes default name resolution for every
existing client of that database. `make check` warns about this combination.

### How psql reaches Postgres — `PSQL_MODE`

This is really a question about the vocabulary CSVs, because `\copy` reads files from
wherever the psql **client** runs.

| | `PSQL_MODE=host` | `PSQL_MODE=docker` |
| --- | --- | --- |
| Needs `psql` on your Mac | yes (`brew install libpq`) | no |
| Changes to your compose file | **none** | read-only mount for the CSVs |
| `VOCAB_DIR` is | a path on this machine | a path inside the container |
| Vocabulary load speed | slower — streams over the connection | faster — read off the filesystem |

Start with `host`. It requires nothing of your existing setup. Switch to `docker` only
if the vocabulary load is too slow, which matters because a realistic Athena download
is 10–25 GB unzipped — then add to your Postgres service:

```yaml
volumes:
  - /abs/path/to/vocabulary:/vocabulary:ro
```

and set `VOCAB_DIR=/vocabulary`. Before recreating the container, confirm your Postgres
data is on a **named** volume, not an anonymous one, or the recreate loses it.

Do not use `docker cp` for the CSVs — it duplicates tens of gigabytes into the
container's writable layer.

## Order matters

**`install` → `load-vocab` → `finalize`.**

`make install` stops after the DDL and primary keys. Constraints and indices are held
back until `make finalize`, which is OHDSI's documented order — adding 176 foreign keys
and 72 indices before `CONCEPT_ANCESTOR` (tens of millions of rows) lands is the
difference between minutes and hours.

`make finalize` on an empty vocabulary works but warns: every FK references
`cdm.concept`, so clinical inserts would fail until the vocabulary is there.

## Targets

| Target | Description |
| --- | --- |
| `make init` | Create `.env` from `.env.example` |
| `make check` | Read-only preflight: connection, version, privileges, current state |
| `make create-db` | Create `TARGET_DB` if missing (no-op when `CREATE_DB=false`) |
| `make schema` | Create schemas, apply DDL + primary keys |
| `make install` | `create-db` then `schema` |
| `make load-vocab` | Load Athena CSVs from `VOCAB_DIR` |
| `make finalize` | Constraints + indices + `ANALYZE` |
| `make verify` | Schemas, table/key/index counts, row counts, sanity query |
| `make psql` | Interactive psql on `TARGET_DB` |
| `make drop-schema` | **Destructive**: drop the three OMOP schemas (prompts first) |
| `make update-ddl` | Re-download the OHDSI DDL into `ddl/` |

## Layout

```
.env                 connection, target database, schema names, vocab path (gitignored)
ddl/                 vendored OHDSI CDM 5.4 scripts — do not edit
lib/common.sh        config loading + run_psql(); the host/docker switch lives here
scripts/
  00_check.sh          read-only preflight
  01_create_database.sh
  02_apply_schema.sh   schemas + DDL + primary keys
  03_load_vocabulary.sh
  04_finalize.sh       constraints + indices + ANALYZE
  drop_schema.sh       destructive rebuild path
  verify.sh / verify.sql
vocabulary/          default CSV location in host mode (gitignored)
```

Everything goes through `run_psql()` in [lib/common.sh](lib/common.sh), so switching
between a host psql client and `docker exec` is one line in `.env` rather than a
rewrite. SQL is piped on **stdin** rather than passed with `psql -f`, because in docker
mode `-f` would look for the file inside the container — which also means `ddl/` and
`scripts/` never need to be mounted.

## Two details worth knowing if you edit these

The OHDSI scripts are **templates**, not runnable SQL. Every table is
`CREATE TABLE @cdmDatabaseSchema.person (...)` — 526 occurrences across the four files.
`apply_ddl_step()` substitutes the placeholder with `sed` on the way into `psql`,
leaving `ddl/` byte-identical to upstream so `make update-ddl` stays a clean diff.

Athena CSVs are tab-delimited and **unquoted**, yet concept names legitimately contain
`"`. The `COPY` calls set `QUOTE E'\b'` — a character that cannot occur in the data —
because Postgres' default CSV quote character swallows a delimiter mid-row and aborts
the load partway through. Dates arrive as `YYYYMMDD`, which Postgres casts to `date`
natively, so no staging columns are needed.

## pgAdmin

Your existing pgAdmin needs no changes beyond registering the new database: right-click
the server → **Refresh**, and if you used a dedicated `TARGET_DB` it appears under
*Databases*. The CDM tables are under `omop → Schemas → cdm → Tables`.

## Not included

No ETL, no synthetic data, no OHDSI WebAPI/Atlas. The `results` and `temp` schemas are
created empty as the hook for adding Atlas later.
