FROM apache/kafka:latest

# Set environment variables for KRaft mode
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
    KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1

# Install debugging utilities
# We're using USER root to ensure we have permissions to install packages
USER root
RUN set -e; \
    if command -v apt-get >/dev/null 2>&1; then \
        # Debian/Ubuntu based image \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            net-tools \
            netcat \
            curl \
            procps \
            vim && \
        rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
        # Alpine based image \
        apk --no-cache add \
            net-tools \
            netcat-openbsd \
            curl \
            procps \
            vim; \
    else \
        echo "Unsupported package manager"; \
        exit 1; \
    fi

# Create a directory for Kafka data (remaining as root)
RUN mkdir -p /var/lib/kafka/data && \
    # Ensure permissions are set correctly for the Kafka data directory
    chmod -R 777 /var/lib/kafka/data

# Create kraft directory and ensure server.properties exists
RUN mkdir -p /opt/kafka/config/kraft && \
    echo "node.id=${KAFKA_NODE_ID}" > /opt/kafka/config/kraft/server.properties && \
    echo "process.roles=${KAFKA_PROCESS_ROLES}" >> /opt/kafka/config/kraft/server.properties && \
    echo "controller.quorum.voters=${KAFKA_CONTROLLER_QUORUM_VOTERS}" >> /opt/kafka/config/kraft/server.properties && \
    echo "listeners=${KAFKA_LISTENERS}" >> /opt/kafka/config/kraft/server.properties && \
    echo "advertised.listeners=${KAFKA_ADVERTISED_LISTENERS}" >> /opt/kafka/config/kraft/server.properties && \
    echo "listener.security.protocol.map=${KAFKA_LISTENER_SECURITY_PROTOCOL_MAP}" >> /opt/kafka/config/kraft/server.properties && \
    echo "controller.listener.names=${KAFKA_CONTROLLER_LISTENER_NAMES}" >> /opt/kafka/config/kraft/server.properties && \
    echo "inter.broker.listener.name=${KAFKA_INTER_BROKER_LISTENER_NAME}" >> /opt/kafka/config/kraft/server.properties && \
    echo "offsets.topic.replication.factor=${KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR}" >> /opt/kafka/config/kraft/server.properties && \
    echo "transaction.state.log.replication.factor=${KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR}" >> /opt/kafka/config/kraft/server.properties && \
    echo "transaction.state.log.min.isr=${KAFKA_TRANSACTION_STATE_LOG_MIN_ISR}" >> /opt/kafka/config/kraft/server.properties

# Copy startup script
COPY startup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/startup.sh

# Set working directory
WORKDIR /opt/kafka

# Define volume for data persistence
VOLUME ["/var/lib/kafka/data"]

# Expose Kafka port
EXPOSE 9092 9093

# Set entrypoint to our startup script
ENTRYPOINT ["/usr/local/bin/startup.sh"]
