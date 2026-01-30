# Kafka Docker Image with KRaft Mode
# Multi-architecture support (arm64 + amd64)
#
# Build args:
#   KAFKA_VERSION - Apache Kafka version (default: 4.1.1)
#
# Tags:
#   dawsonlp/kafka:latest    - Stable release (4.1.1)
#   dawsonlp/kafka:4.1.1     - Specific stable version
#   dawsonlp/kafka:4.2.0-rc2 - Release candidate

ARG KAFKA_VERSION=4.1.1
FROM apache/kafka:${KAFKA_VERSION}

# Re-declare ARG after FROM to use in LABEL
ARG KAFKA_VERSION

LABEL org.opencontainers.image.title="Kafka KRaft" \
      org.opencontainers.image.description="Apache Kafka with KRaft mode for development" \
      org.opencontainers.image.version="${KAFKA_VERSION}" \
      org.opencontainers.image.authors="dawsonlp" \
      org.opencontainers.image.source="https://github.com/dawsonlp/docker_images"

# Default KRaft configuration (can be overridden at runtime)
ENV KAFKA_NODE_ID=1 \
    KAFKA_PROCESS_ROLES=broker,controller \
    KAFKA_CONTROLLER_QUORUM_VOTERS=1@localhost:9093 \
    KAFKA_LISTENERS=INTERNAL://0.0.0.0:29092,EXTERNAL://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093 \
    KAFKA_ADVERTISED_LISTENERS=INTERNAL://kafka:29092,EXTERNAL://localhost:9092 \
    KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT \
    KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
    KAFKA_INTER_BROKER_LISTENER_NAME=INTERNAL \
    KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
    KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 \
    KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1 \
    KAFKA_LOG_DIRS=/var/lib/kafka/data \
    KAFKA_AUTO_CREATE_TOPICS_ENABLE=true \
    KAFKA_DELETE_TOPIC_ENABLE=true \
    KAFKA_LOG_RETENTION_HOURS=168 \
    KAFKA_LOG_SEGMENT_BYTES=1073741824

# Install debugging utilities as root
USER root
RUN set -e; \
    if command -v apt-get >/dev/null 2>&1; then \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            net-tools \
            netcat-openbsd \
            curl \
            procps \
            vim \
            jq && \
        rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
        apk --no-cache add \
            net-tools \
            netcat-openbsd \
            curl \
            procps \
            vim \
            jq; \
    elif command -v microdnf >/dev/null 2>&1; then \
        microdnf install -y \
            net-tools \
            nc \
            curl \
            procps-ng \
            vim-minimal \
            jq && \
        microdnf clean all; \
    fi

# Create directories with proper ownership for appuser (UID 1000 in apache/kafka)
# Use chown (secure) instead of chmod 777 (insecure)
RUN mkdir -p /var/lib/kafka/data /opt/kafka/config/kraft && \
    chown -R appuser:appuser /var/lib/kafka/data && \
    chown -R appuser:appuser /opt/kafka/config/kraft && \
    chmod -R 755 /var/lib/kafka/data && \
    chmod -R 755 /opt/kafka/config/kraft

# Copy startup script
COPY startup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/startup.sh

# Switch back to non-root user (appuser is defined in apache/kafka base image)
USER appuser

# Set working directory
WORKDIR /opt/kafka

# Define volume for data persistence
VOLUME ["/var/lib/kafka/data"]

# Expose ports
# 9092 - External listener (host access)
# 29092 - Internal listener (container-to-container)
EXPOSE 9092 29092

# Health check using Kafka CLI
HEALTHCHECK --interval=30s --timeout=10s --start-period=45s --retries=3 \
    CMD /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 >/dev/null 2>&1 || exit 1

# Entrypoint generates config at runtime and starts Kafka
ENTRYPOINT ["/usr/local/bin/startup.sh"]