FROM rocker/r-ver:4.5.2

ARG DQD_VERSION=2.9.1
ARG SUPERCRONIC_VERSION=v0.2.49
ARG TARGETARCH

RUN apt-get update \
    && apt-get install -y --no-install-recommends default-jdk-headless curl ca-certificates \
    && R CMD javareconf \
    && rm -rf /var/lib/apt/lists/*

# Cron for containers, logs the scheduled runs to stdout
RUN case "$TARGETARCH" in \
        arm64) SHA=02aa0cb229ba09050cba6638059dadb9eedc2276632ea43d6a57a2f8c1629dd5 ;; \
        *)     TARGETARCH=amd64; SHA=a53ae236602c7338aba3fbaff40bda6300eae3b9fedb8261eb06cfe3724430c1 ;; \
    esac \
    && curl -fsSL -o /usr/local/bin/supercronic \
        "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-${TARGETARCH}" \
    && echo "$SHA  /usr/local/bin/supercronic" | sha256sum -c - \
    && chmod +x /usr/local/bin/supercronic

# Binary packages from the current Posit Package Manager snapshot
RUN export CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME") \
    && Rscript -e 'options(repos = c(CRAN = sprintf("https://p3m.dev/cran/__linux__/%s/latest", Sys.getenv("CODENAME")))); \
        install.packages(c("DatabaseConnector", "DataQualityDashboard")); \
        stopifnot(packageVersion("DataQualityDashboard") == Sys.getenv("DQD_VERSION")); \
        DatabaseConnector::downloadJdbcDrivers("postgresql", pathToDriver = "/jdbc")'

ENV DATABASECONNECTOR_JAR_FOLDER=/jdbc
COPY run_dqd.R run_dqd.sh entrypoint.sh /app/
RUN chmod +x /app/*.sh

ENTRYPOINT ["/app/entrypoint.sh"]
