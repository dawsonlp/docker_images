# PostgreSQL Batteries-Included
# Multi-architecture support (arm64 + amd64)
#
# Includes: PostGIS, pgvector, pgrouting, full-text search, and essential utilities
#
# Tags:
#   dawsonlp/postgres-batteries-inc:latest - Latest stable PostgreSQL 18
#   dawsonlp/postgres-batteries-inc:18     - PostgreSQL 18

ARG PG_MAJOR=18
FROM postgres:${PG_MAJOR}

# Re-declare ARG after FROM for use in labels
ARG PG_MAJOR

LABEL org.opencontainers.image.title="PostgreSQL Batteries-Included" \
      org.opencontainers.image.description="PostgreSQL with PostGIS, pgvector, Apache AGE, pgrouting, and essential extensions" \
      org.opencontainers.image.version="${PG_MAJOR}" \
      org.opencontainers.image.authors="dawsonlp" \
      org.opencontainers.image.vendor="dawsonlp" \
      org.opencontainers.image.source="https://github.com/dawsonlp/docker_images"

# Extension versions
ENV POSTGIS_VERSION=3
ENV AGE_VERSION=PG18/v1.7.0-rc0

# Install all extensions from packages
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        # ===== SPATIAL EXTENSIONS =====
        postgresql-${PG_MAJOR}-postgis-${POSTGIS_VERSION} \
        postgresql-${PG_MAJOR}-postgis-${POSTGIS_VERSION}-scripts \
        postgis \
        postgresql-${PG_MAJOR}-pgrouting \
        # ===== VECTOR EXTENSION =====
        postgresql-${PG_MAJOR}-pgvector \
        # ===== BUILT-IN CONTRIB =====
        postgresql-contrib \
        # ===== UTILITIES =====
        curl \
        wget \
        unzip \
        ca-certificates \
        gdal-bin \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*;

# Build and install Apache AGE from source
# AGE requires source compilation (no apt package for PG18)
# flex and bison are needed for the Cypher parser
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        postgresql-server-dev-${PG_MAJOR} \
        flex \
        bison \
        git \
    ; \
    git clone --branch ${AGE_VERSION} --single-branch --depth 1 \
        https://github.com/apache/age.git /tmp/age; \
    cd /tmp/age; \
    make PG_CONFIG=/usr/lib/postgresql/${PG_MAJOR}/bin/pg_config install; \
    cd /; \
    rm -rf /tmp/age; \
    apt-get purge -y --auto-remove \
        build-essential \
        postgresql-server-dev-${PG_MAJOR} \
        flex \
        bison \
        git \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*;

# Copy initialization scripts
COPY ./init-scripts/ /docker-entrypoint-initdb.d/

# Copy helper scripts for TIGER data loading
COPY ./scripts/load-tiger-nation.sh /usr/local/bin/load-tiger-nation.sh
COPY ./scripts/load-tiger-state-direct.sh /usr/local/bin/load-tiger-state-direct.sh
COPY ./scripts/load-tiger-data.sh /usr/local/bin/load-tiger-data.sh
RUN chmod +x /usr/local/bin/load-tiger-nation.sh \
             /usr/local/bin/load-tiger-state-direct.sh \
             /usr/local/bin/load-tiger-data.sh

# Create directories for TIGER data and processing
RUN mkdir -p /var/lib/postgresql/tiger_data \
             /gisdata/temp \
             /gisdata/downloads \
             /gisdata/scripts && \
    chown -R postgres:postgres /var/lib/postgresql/tiger_data /gisdata && \
    chmod 755 /gisdata /gisdata/temp /gisdata/downloads /gisdata/scripts

# Expose PostgreSQL port
EXPOSE 5432

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pg_isready -U postgres -d postgres || exit 1

# Use the default postgres entrypoint
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["postgres", "-c", "shared_preload_libraries=age"]
