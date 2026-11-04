#!/bin/bash
# Prepares the Superset metadata database, the admin user and the OMOP data quality dashboard
set -euo pipefail

# apps/compose.yml requires no variables, so the passwords are checked here.
for var in SUPERSET_ADMIN_PASSWORD SUPERSET_DB_PASSWORD SUPERSET_READER_PASSWORD; do
    [ -n "${!var:-}" ] || { echo "ERROR: ${var} is empty, set it in .env" >&2; exit 1; }
done

SECRET_FILE="$SUPERSET_HOME/secret_key"
if [ -z "${SUPERSET_SECRET_KEY:-}" ] && [ ! -s "$SECRET_FILE" ]; then
    python -c "import secrets; print(secrets.token_urlsafe(42))" > "$SECRET_FILE"
fi

superset db upgrade
superset fab create-admin \
    --username "${SUPERSET_ADMIN_USERNAME:-admin}" \
    --password "$SUPERSET_ADMIN_PASSWORD" \
    --firstname Superset --lastname Admin --email admin@omop.tld || true
superset init

# Import the dashboard (also overwrites changes made in the UI to these assets)
if [ -f /app/omop-assets/metadata.yaml ]; then
    READER_URI=$(python -c "import os, urllib.parse as u; e = os.environ.get; print('postgresql+psycopg2://superset_reader:%s@%s:%s/%s' % (u.quote(os.environ['SUPERSET_READER_PASSWORD'], safe=''), e('OMOP_DB_HOST', 'postgres'), e('OMOP_DB_PORT', '5432'), e('OMOP_DB_NAME', 'omop')))")
    rm -rf /tmp/omop_dqd && cp -r /app/omop-assets /tmp/omop_dqd
    # Exported assets do not contain passwords
    READER_URI="$READER_URI" python - <<'PY'
import os, pathlib, re
for f in pathlib.Path("/tmp/omop_dqd/databases").glob("*.yaml"):
    f.write_text(re.sub(r"^sqlalchemy_uri: .*$", "sqlalchemy_uri: " + os.environ["READER_URI"], f.read_text(), flags=re.M))
PY
    (cd /tmp && python -m zipfile -c /tmp/omop_dqd.zip omop_dqd)
    superset import-dashboards --path /tmp/omop_dqd.zip --username "${SUPERSET_ADMIN_USERNAME:-admin}"
    superset set-database-uri --database_name "OMOP" --uri "$READER_URI"
fi
