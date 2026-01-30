#!/bin/bash
set -e

echo "=========================================="
echo "Kafka KRaft Startup Script"
echo "=========================================="

# Create data directory if it doesn't exist
mkdir -p /var/lib/kafka/data

# Generate server.properties at runtime from environment variables
# This allows runtime configuration overrides
CONFIG_FILE="/opt/kafka/config/kraft/server.properties"

echo "Generating Kafka configuration..."
cat > "$CONFIG_FILE" << EOF
# KRaft Configuration - Generated at runtime
# $(date)

# Node Configuration
node.id=${KAFKA_NODE_ID:-1}
process.roles=${KAFKA_PROCESS_ROLES:-broker,controller}
controller.quorum.voters=${KAFKA_CONTROLLER_QUORUM_VOTERS:-1@localhost:9093}

# Listener Configuration
listeners=${KAFKA_LISTENERS:-INTERNAL://0.0.0.0:29092,EXTERNAL://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093}
advertised.listeners=${KAFKA_ADVERTISED_LISTENERS:-INTERNAL://kafka:29092,EXTERNAL://localhost:9092}
listener.security.protocol.map=${KAFKA_LISTENER_SECURITY_PROTOCOL_MAP:-INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT}
controller.listener.names=${KAFKA_CONTROLLER_LISTENER_NAMES:-CONTROLLER}
inter.broker.listener.name=${KAFKA_INTER_BROKER_LISTENER_NAME:-INTERNAL}

# Replication Configuration
offsets.topic.replication.factor=${KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR:-1}
transaction.state.log.replication.factor=${KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR:-1}
transaction.state.log.min.isr=${KAFKA_TRANSACTION_STATE_LOG_MIN_ISR:-1}

# Log Configuration
log.dirs=${KAFKA_LOG_DIRS:-/var/lib/kafka/data}
log.retention.hours=${KAFKA_LOG_RETENTION_HOURS:-168}
log.segment.bytes=${KAFKA_LOG_SEGMENT_BYTES:-1073741824}
log.retention.check.interval.ms=${KAFKA_LOG_RETENTION_CHECK_INTERVAL_MS:-300000}

# Topic Configuration
auto.create.topics.enable=${KAFKA_AUTO_CREATE_TOPICS_ENABLE:-true}
delete.topic.enable=${KAFKA_DELETE_TOPIC_ENABLE:-true}
num.partitions=${KAFKA_NUM_PARTITIONS:-1}
default.replication.factor=${KAFKA_DEFAULT_REPLICATION_FACTOR:-1}

# Network Configuration
num.network.threads=${KAFKA_NUM_NETWORK_THREADS:-3}
num.io.threads=${KAFKA_NUM_IO_THREADS:-8}
socket.send.buffer.bytes=${KAFKA_SOCKET_SEND_BUFFER_BYTES:-102400}
socket.receive.buffer.bytes=${KAFKA_SOCKET_RECEIVE_BUFFER_BYTES:-102400}
socket.request.max.bytes=${KAFKA_SOCKET_REQUEST_MAX_BYTES:-104857600}

# Group Coordinator Configuration
group.initial.rebalance.delay.ms=${KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS:-0}
EOF

echo "Configuration generated at $CONFIG_FILE"
echo ""

# Display key configuration values
echo "Kafka Configuration Summary:"
echo "  Node ID:           ${KAFKA_NODE_ID:-1}"
echo "  Process Roles:     ${KAFKA_PROCESS_ROLES:-broker,controller}"
echo "  Listeners:         ${KAFKA_LISTENERS:-INTERNAL://0.0.0.0:29092,EXTERNAL://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093}"
echo "  Advertised:        ${KAFKA_ADVERTISED_LISTENERS:-INTERNAL://kafka:29092,EXTERNAL://localhost:9092}"
echo "  Log Directory:     ${KAFKA_LOG_DIRS:-/var/lib/kafka/data}"
echo ""

# Cluster ID management
CLUSTER_ID_FILE="/var/lib/kafka/data/cluster_id"
if [ ! -f "$CLUSTER_ID_FILE" ]; then
    echo "Generating new cluster ID..."
    CLUSTER_ID=$(/opt/kafka/bin/kafka-storage.sh random-uuid)
    echo "$CLUSTER_ID" > "$CLUSTER_ID_FILE"
    echo "Generated cluster ID: $CLUSTER_ID"
else
    CLUSTER_ID=$(cat "$CLUSTER_ID_FILE")
    echo "Using existing cluster ID: $CLUSTER_ID"
fi

# Check if storage needs formatting
if [ ! -f "/var/lib/kafka/data/meta.properties" ]; then
    echo "Formatting storage directories..."
    /opt/kafka/bin/kafka-storage.sh format -t "$CLUSTER_ID" -c "$CONFIG_FILE"
    echo "Storage formatted successfully."
else
    echo "Storage already formatted. Skipping format step."
fi

echo ""
echo "=========================================="
echo "Starting Kafka server..."
echo "=========================================="
exec /opt/kafka/bin/kafka-server-start.sh "$CONFIG_FILE"