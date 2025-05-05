#!/bin/bash
set -e

# Create log directory if it doesn't exist
mkdir -p /var/lib/kafka/data

# Check if the cluster ID file exists
CLUSTER_ID_FILE="/var/lib/kafka/data/cluster_id"
if [ ! -f "$CLUSTER_ID_FILE" ]; then
    echo "Generating new cluster ID..."
    CLUSTER_ID=$(bin/kafka-storage.sh random-uuid)
    echo $CLUSTER_ID > "$CLUSTER_ID_FILE"
    echo "Generated cluster ID: $CLUSTER_ID"
else
    CLUSTER_ID=$(cat "$CLUSTER_ID_FILE")
    echo "Using existing cluster ID: $CLUSTER_ID"
fi

# Check if storage is already formatted
if [ ! -f "/var/lib/kafka/data/meta.properties" ]; then
    echo "Formatting storage directories..."
    bin/kafka-storage.sh format -t $CLUSTER_ID -c config/kraft/server.properties
    echo "Storage formatted successfully."
else
    echo "Storage already formatted. Skipping format step."
fi

echo "Starting Kafka server..."
exec bin/kafka-server-start.sh config/kraft/server.properties
