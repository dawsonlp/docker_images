#!/bin/bash
# Full Kafka Smoke Test Runner
# Starts Kafka, produces messages, consumes them, and cleans up

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_TAG="${IMAGE_TAG:-4.2.0-rc2}"
TOPIC="smoke-test-topic"
MESSAGE_COUNT=5

echo "=========================================="
echo "Kafka Smoke Test Suite"
echo "=========================================="
echo "Image: dawsonlp/kafka:$IMAGE_TAG"
echo "Topic: $TOPIC"
echo "Messages: $MESSAGE_COUNT"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    docker compose down -v 2>/dev/null || true
    echo "✓ Cleanup complete"
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Step 1: Start Kafka
echo "Step 1: Starting Kafka container..."
echo "----------------------------------------"
docker compose up -d
echo ""

# Wait for container to be healthy (fail fast - 30 seconds max)
echo "Waiting for Kafka to become healthy..."
max_attempts=15
attempt=0
while [ "$(docker inspect --format='{{.State.Health.Status}}' kafka-smoke-test 2>/dev/null)" != "healthy" ]; do
    attempt=$((attempt + 1))
    if [ $attempt -ge $max_attempts ]; then
        echo "ERROR: Kafka did not become healthy after $max_attempts attempts"
        echo ""
        echo "Container logs:"
        docker logs kafka-smoke-test --tail 50
        exit 1
    fi
    printf "  Attempt %d/%d - status: %s\r" "$attempt" "$max_attempts" "$(docker inspect --format='{{.State.Health.Status}}' kafka-smoke-test 2>/dev/null || echo 'starting')"
    sleep 2
done
echo ""
echo "✓ Kafka is healthy"
echo ""

# Show Kafka version
echo "Kafka version:"
docker exec kafka-smoke-test /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 --version 2>/dev/null || true
echo ""

# Step 2: Create topic
echo "Step 2: Creating test topic..."
echo "----------------------------------------"
docker exec kafka-smoke-test /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --create \
    --topic "$TOPIC" \
    --partitions 3 \
    --replication-factor 1 \
    --if-not-exists
echo "✓ Topic '$TOPIC' created"
echo ""

# Step 3: Produce messages
echo "Step 3: Producing messages..."
echo "----------------------------------------"
for i in $(seq 1 $MESSAGE_COUNT); do
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    message="{\"id\": $i, \"timestamp\": \"$timestamp\", \"test\": \"smoke-test\"}"
    echo "$message" | docker exec -i kafka-smoke-test /opt/kafka/bin/kafka-console-producer.sh \
        --bootstrap-server localhost:9092 \
        --topic "$TOPIC" 2>/dev/null
    echo "  → Sent: $message"
done
echo "✓ Produced $MESSAGE_COUNT messages"
echo ""

# Small delay to ensure messages are committed
sleep 2

# Step 4: Consume messages
echo "Step 4: Consuming messages..."
echo "----------------------------------------"
consumed_messages=$(docker exec kafka-smoke-test /opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic "$TOPIC" \
    --from-beginning \
    --timeout-ms 10000 2>/dev/null || true)

if [ -n "$consumed_messages" ]; then
    echo "$consumed_messages" | while read -r msg; do
        echo "  ← Received: $msg"
    done
    consumed_count=$(echo "$consumed_messages" | grep -c '^{' || echo "0")
    echo "✓ Consumed $consumed_count messages"
else
    echo "ERROR: No messages consumed"
    exit 1
fi
echo ""

# Step 5: Verify topic metadata
echo "Step 5: Verifying topic metadata..."
echo "----------------------------------------"
docker exec kafka-smoke-test /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --describe \
    --topic "$TOPIC"
echo ""

echo "=========================================="
echo "✓ SMOKE TEST PASSED"
echo "=========================================="
echo ""
echo "Summary:"
echo "  Image:     dawsonlp/kafka:$IMAGE_TAG"
echo "  Topic:     $TOPIC"
echo "  Produced:  $MESSAGE_COUNT messages"
echo "  Consumed:  $consumed_count messages"
echo ""
echo "The Kafka 4.2.0-rc2 image is working correctly!"