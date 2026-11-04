# Same Postgres major as the database, for psql (15+ for \getenv) and pg_isready.
FROM postgres:16

COPY init.sh /usr/local/bin/quality-init.sh
COPY sql /sql
RUN chmod +x /usr/local/bin/quality-init.sh

CMD ["quality-init.sh"]
