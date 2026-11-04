# Same Postgres major as the database, for psql/pg_isready; curl + unzip for VOCAB_URL.
FROM postgres:16

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY init.sh /usr/local/bin/omop-init.sh
RUN chmod +x /usr/local/bin/omop-init.sh

CMD ["omop-init.sh"]
