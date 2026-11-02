#!/bin/bash
set -euo pipefail

if [ "${DQD_RUN_ON_START:-true}" = "true" ]; then
    /app/run_dqd.sh || echo "DQD run failed, see the log above"
fi

echo "${DQD_SCHEDULE:-0 2 * * *} /app/run_dqd.sh" > /tmp/crontab
echo "Scheduling DQD runs: $(cat /tmp/crontab)"
exec supercronic /tmp/crontab
