.DEFAULT_GOAL := help
SHELL := /bin/bash

# Thin wrapper: every target delegates to scripts/, which read .env through
# lib/common.sh. Nothing here starts, stops or recreates a container.
S := ./scripts

DDL_BASE  := https://raw.githubusercontent.com/OHDSI/CommonDataModel/main/inst/ddl/5.4/postgresql
DDL_FILES := ddl indices constraints primary_keys

.PHONY: help init check create-db schema load-vocab finalize verify psql drop-schema install update-ddl

help: ## Show available targets
	@echo "OMOP CDM 5.4 -> existing PostgreSQL instance"
	@echo
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Order:  init -> (edit .env) -> check -> install -> load-vocab -> finalize -> verify"

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

finalize: ## Apply FK constraints + indices, refresh statistics (run after load-vocab)
	@$(S)/04_finalize.sh

verify: ## Report schemas, table/key/index counts and row counts
	@$(S)/verify.sh

psql: ## Interactive psql session on the target database
	@$(S)/psql.sh

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
