FROM apache/superset:6.1.0

USER root
# The image does not ship database drivers
RUN uv pip install --python /app/.venv/bin/python --no-cache psycopg2-binary==2.9.10

COPY superset_config.py /app/pythonpath/superset_config.py
COPY init.sh /app/docker/omop-init.sh
COPY assets /app/omop-assets
RUN chmod +x /app/docker/omop-init.sh

USER superset
