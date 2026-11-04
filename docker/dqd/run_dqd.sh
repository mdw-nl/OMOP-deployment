#!/bin/bash
# Runs DQD once; the lock prevents a scheduled run from overlapping with a running one
flock -n -E 75 /tmp/dqd.lock Rscript /app/run_dqd.R
status=$?
if [ "$status" = 75 ]; then
    echo "Another DQD run is in progress, skipping this run" >&2
fi
exit "$status"
