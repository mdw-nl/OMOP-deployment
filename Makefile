.DEFAULT_GOAL := help
SHELL := /bin/bash

COMPOSE := docker compose
DC_EXEC := $(COMPOSE) exec -T postgres

# Read .env so targets can echo ports and pass schema names to psql.
ifneq (,$(wildcard .env))
include .env
export
endif

CDM_SCHEMA     ?= cdm
RESULTS_SCHEMA ?= results
TEMP_SCHEMA    ?= temp
POSTGRES_DB    ?= omop
POSTGRES_USER  ?= omop
POSTGRES_PORT  ?= 5432
PGADMIN_PORT   ?= 8080
VOCAB_READER_USER ?= vocab_reader

DDL_BASE := https://raw.githubusercontent.com/OHDSI/CommonDataModel/main/inst/ddl/5.4/postgresql
DDL_FILES := ddl indices constraints primary_keys

.PHONY: help init up down logs ps psql load-vocab finalize vocab-reader verify update-ddl reset

help: ## Show available targets
	@echo "OMOP CDM 5.4 on Postgres"
	@echo
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "First run:  make init  ->  edit .env  ->  make up"
	@echo "Then:       make load-vocab  ->  make finalize"

init: ## Create .env from .env.example
	@if [ -f .env ]; then \
	  echo ".env already exists — leaving it alone."; \
	else \
	  cp .env.example .env; \
	  echo "Created .env — set POSTGRES_PASSWORD and PGADMIN_PASSWORD before 'make up'."; \
	fi

up: ## Start Postgres + pgAdmin and wait for the schema to be ready
	@test -f .env || { echo "No .env — run 'make init' first."; exit 1; }
	$(COMPOSE) up -d
	@echo "Waiting for Postgres to become healthy (the DDL applies during init)..."
	@for i in $$(seq 1 60); do \
	  status=$$(docker inspect -f '{{.State.Health.Status}}' omop-postgres 2>/dev/null || echo starting); \
	  if [ "$$status" = "healthy" ]; then \
	    echo "Postgres healthy on localhost:$(POSTGRES_PORT)   pgAdmin: http://localhost:$(PGADMIN_PORT)"; \
	    exit 0; \
	  fi; \
	  if [ "$$status" = "unhealthy" ]; then break; fi; \
	  sleep 2; \
	done; \
	echo "Postgres did not come up healthy. Recent logs:"; \
	$(COMPOSE) logs --tail=40 postgres; \
	exit 1

down: ## Stop the stack, keeping data
	$(COMPOSE) down

logs: ## Tail Postgres logs
	$(COMPOSE) logs -f postgres

ps: ## Show container status
	$(COMPOSE) ps

psql: ## Open an interactive psql session
	$(COMPOSE) exec postgres psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

load-vocab: ## Load Athena vocabulary CSVs from ./vocabulary
	$(DC_EXEC) bash /scripts/load_vocabulary.sh

finalize: ## Apply FK constraints + indices (run after load-vocab)
	$(DC_EXEC) bash /scripts/finalize.sh

# initdb only runs on an empty volume; this applies the same script to a running one.
# `up` first recreates the container if .env changed, so it sees the new password.
vocab-reader: ## Create/update the read-only vocabulary role (VOCAB_READER_* in .env)
	@test -n "$(VOCAB_READER_PASSWORD)" || { echo "Set VOCAB_READER_PASSWORD in .env first."; exit 1; }
	$(COMPOSE) up -d postgres
	$(DC_EXEC) bash /docker-entrypoint-initdb.d/02_vocab_reader.sh

verify: ## Report schema, key/index and row counts
	@$(DC_EXEC) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -X -q \
	  -v cdm_schema=$(CDM_SCHEMA) \
	  -v results_schema=$(RESULTS_SCHEMA) \
	  -v temp_schema=$(TEMP_SCHEMA) \
	  -v vocab_reader=$(VOCAB_READER_USER) \
	  -f /scripts/verify.sql

update-ddl: ## Re-download the OHDSI CDM 5.4 DDL scripts into ddl/
	@mkdir -p ddl
	@for f in $(DDL_FILES); do \
	  name=OMOPCDM_postgresql_5.4_$$f.sql; \
	  curl -sfL -o ddl/$$name $(DDL_BASE)/$$name \
	    && echo "  updated $$name" \
	    || { echo "  FAILED $$name"; exit 1; }; \
	done
	@echo "Vendored DDL refreshed. 'make reset' to rebuild the database from it."

reset: ## DESTROY the data volume and rebuild the schema from scratch
	@echo "This deletes the omop_pgdata volume — all data in $(POSTGRES_DB) is lost."
	@read -p "Type 'yes' to continue: " ans; [ "$$ans" = "yes" ] || { echo "Aborted."; exit 1; }
	$(COMPOSE) down -v
	@$(MAKE) --no-print-directory up
