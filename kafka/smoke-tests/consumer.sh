#!/bin/bash
# Kafka Consumer Smoke Test
# Consumes messages to verify consumer functionality

set -e

TOPIC="${TOPIC:-smoke-test-topic}"
BOOTSTRAP_SERVER="${BOOTSTRAP_SERVER:-localhost:9092}"
TIMEOUT="${TIMEOUT:-10}"

echo "=========================================="
echo "Kafka Consumer Smoke Test"
echo "=========================================="
echo "Bootstrap Server: $BOOTSTRAP_SERVER"
echo "Topic: $TOPIC"
echo "Timeout: ${TIMEOUT}s"
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

# Check if topic exists
echo "Checking topic '$TOPIC' exists..."
if ! docker exec kafka-smoke-test /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --describe \
    --topic "$TOPIC" >/dev/null 2>&1; then
    echo "ERROR: Topic '$TOPIC' does not exist. Run producer.sh first."
    exit 1
fi
echo "✓ Topic exists"
echo ""

# Get topic info
echo "Topic details:"
docker exec kafka-smoke-test /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --describe \
    --topic "$TOPIC"
echo ""

# Consume messages from beginning
echo "Consuming messages (timeout: ${TIMEOUT}s)..."
echo "----------------------------------------"

# Use timeout to limit consumption time
messages=$(timeout "$TIMEOUT" docker exec kafka-smoke-test /opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic "$TOPIC" \
    --from-beginning \
    --timeout-ms $((TIMEOUT * 1000)) 2>/dev/null || true)

if [ -n "$messages" ]; then
    echo "$messages"
    message_count=$(echo "$messages" | wc -l | tr -d ' ')
    echo "----------------------------------------"
    echo ""
    echo "=========================================="
    echo "✓ Consumer test completed successfully"
    echo "  Received $message_count messages from '$TOPIC'"
    echo "=========================================="
else
    echo "No messages received (topic may be empty)"
    echo "----------------------------------------"
    echo ""
    echo "=========================================="
    echo "⚠ Consumer test completed - no messages"
    echo "  Run producer.sh first to send messages"
    echo "=========================================="
fi