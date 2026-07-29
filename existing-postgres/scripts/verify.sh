#!/bin/bash
# Runs verify.sql against TARGET_DB.
#
# The SQL is piped on stdin rather than passed with `psql -f`, because in docker
# mode `-f` would look for the file inside the container. stdin works in both modes
# and keeps scripts/ off any mount.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_connection

run_psql -X \
  -v cdm_schema="${CDM_SCHEMA}" \
  -v results_schema="${RESULTS_SCHEMA}" \
  -v temp_schema="${TEMP_SCHEMA}" \
  < "$(dirname "${BASH_SOURCE[0]}")/verify.sql"
