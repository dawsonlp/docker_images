#!/bin/bash
# Kafka Producer Smoke Test
# Sends test messages to verify producer functionality

set -e

TOPIC="${TOPIC:-smoke-test-topic}"
BOOTSTRAP_SERVER="${BOOTSTRAP_SERVER:-localhost:9092}"
MESSAGE_COUNT="${MESSAGE_COUNT:-10}"

echo "=========================================="
echo "Kafka Producer Smoke Test"
echo "=========================================="
echo "Bootstrap Server: $BOOTSTRAP_SERVER"
echo "Topic: $TOPIC"
echo "Message Count: $MESSAGE_COUNT"
echo ""

# Wait for Kafka to be ready
echo "Waiting for Kafka to be ready..."
max_attempts=30
attempt=0
while ! docker exec kafka-smoke-test /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ $attempt -ge $max_attempts ]; then
        echo "ERROR: Kafka not ready after $max_attempts attempts"
        exit 1
    fi
    echo "  Attempt $attempt/$max_attempts - waiting..."
    sleep 2
done
echo "✓ Kafka is ready"
echo ""

# Create topic if it doesn't exist
echo "Creating topic '$TOPIC'..."
docker exec kafka-smoke-test /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --create \
    --topic "$TOPIC" \
    --partitions 3 \
    --replication-factor 1 \
    --if-not-exists
echo "✓ Topic created/verified"
echo ""

# Produce messages
echo "Producing $MESSAGE_COUNT messages..."
for i in $(seq 1 $MESSAGE_COUNT); do
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    message="{\"id\": $i, \"timestamp\": \"$timestamp\", \"data\": \"Smoke test message $i\"}"
    echo "$message" | docker exec -i kafka-smoke-test /opt/kafka/bin/kafka-console-producer.sh \
        --bootstrap-server localhost:9092 \
        --topic "$TOPIC"
    echo "  Sent message $i: $message"
done

echo ""
echo "=========================================="
echo "✓ Producer test completed successfully"
echo "  Sent $MESSAGE_COUNT messages to '$TOPIC'"
echo "=========================================="