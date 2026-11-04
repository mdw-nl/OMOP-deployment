.DEFAULT_GOAL := help
SHELL := /bin/bash

# Thin wrapper: every target delegates to scripts/, which read .env through
# lib/common.sh. Nothing here starts, stops or recreates one of your containers;
# the quality-* targets only manage the separate omop-apps compose project.
S := ./scripts

DDL_BASE  := https://raw.githubusercontent.com/OHDSI/CommonDataModel/main/inst/ddl/5.4/postgresql
DDL_FILES := ddl indices constraints primary_keys

.PHONY: help init check create-db schema load-vocab download-vocab finalize verify psql drop-schema install update-ddl quality-up quality-down quality-logs dqd

help: ## Show available targets
	@echo "OMOP CDM 5.4 -> existing PostgreSQL instance"
	@echo
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Order:  init -> (edit .env) -> check -> install -> load-vocab -> finalize -> verify"
	@echo "Then:   quality-up  (optional data quality checks + Superset dashboard)"

init: ## Create .env from .env.example
	@if [ -f .env ]; then \
	  echo ".env already exists — leaving it alone."; \
	else \
	  cp .env.example .env; \
	  echo "Created .env. Set PGUSER/PGPASSWORD and confirm PSQL_MODE, then run 'make check'."; \
	fi

check: ## Preflight: connectivity, server version, privileges, what already exists (read-only)
	@$(S)/00_check.sh

create-db: ## Create the target database if missing (skipped when CREATE_DB=false)
	@$(S)/01_create_database.sh

schema: ## Create schemas and apply the CDM 5.4 DDL + primary keys
	@$(S)/02_apply_schema.sh

install: ## create-db + schema, in order
	@$(MAKE) --no-print-directory create-db
	@$(MAKE) --no-print-directory schema

load-vocab: ## Load Athena vocabulary CSVs from VOCAB_DIR
	@$(S)/03_load_vocabulary.sh

download-vocab: ## Download the vocabulary zip at VOCAB_URL into VOCAB_DIR (host mode)
	@$(S)/download_vocabulary.sh

finalize: ## Apply FK constraints + indices, refresh statistics (run after load-vocab)
	@$(S)/04_finalize.sh

verify: ## Report schemas, table/key/index counts and row counts
	@$(S)/verify.sh

psql: ## Interactive psql session on the target database
	@$(S)/psql.sh

quality-up: ## Build and start DQD + Superset against TARGET_DB (omop-apps project)
	@$(S)/quality.sh up -d --build \
	  || { echo "Starting the quality apps failed. Init logs:"; $(S)/quality.sh logs quality-init superset-init; exit 1; }
	@echo "Superset: http://localhost:$$(sed -n 's/^SUPERSET_PORT=//p' .env | grep . || echo 8088)   DQD runs now and on DQD_SCHEDULE"

quality-down: ## Stop the data quality apps, keeping their volumes; your database is untouched
	@$(S)/quality.sh down

quality-logs: ## Tail the data quality app logs
	@$(S)/quality.sh logs -f

dqd: ## Run the data quality checks now
	@$(S)/quality.sh exec dqd /app/run_dqd.sh

drop-schema: ## DESTRUCTIVE: drop the OMOP schemas so you can rebuild (prompts first)
	@$(S)/drop_schema.sh

update-ddl: ## Re-download the OHDSI CDM 5.4 DDL scripts into ddl/
	@mkdir -p ddl
	@for f in $(DDL_FILES); do \
	  name=OMOPCDM_postgresql_5.4_$$f.sql; \
	  curl -sfL -o ddl/$$name $(DDL_BASE)/$$name \
	    && echo "  updated $$name" \
	    || { echo "  FAILED $$name"; exit 1; }; \
	done
	@echo "Vendored DDL refreshed. 'make drop-schema && make schema' to rebuild from it."
