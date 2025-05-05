#!/bin/bash
# Simple script to test Kafka setup with both producer and consumer

set -e

# Default values
KAFKA_CONTAINER="kafka-test-broker"
BOOTSTRAP_SERVER="localhost:9092"
TOPIC="test-topic"
NUM_MESSAGES=5
DELAY=0.5

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kafka-container)
      KAFKA_CONTAINER="$2"
      shift 2
      ;;
    --bootstrap-server)
      BOOTSTRAP_SERVER="$2"
      shift 2
      ;;
    --topic)
      TOPIC="$2"
      shift 2
      ;;
    --messages)
      NUM_MESSAGES="$2"
      shift 2
      ;;
    --delay)
      DELAY="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --kafka-container <name>        Kafka container name (default: kafka-test-broker)"
      echo "  --bootstrap-server <server>     Kafka bootstrap server (default: kafka:9092)"
      echo "  --topic <topic>                 Topic name to test with (default: test-topic)"
      echo "  --messages <num>                Number of messages to produce (default: 5)"
      echo "  --delay <seconds>               Delay between messages in seconds (default: 0.5)"
      echo "  --help                          Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

echo "========== KAFKA TEST WORKFLOW =========="
echo ""
echo "Using the following configuration:"
echo "  Kafka Container: $KAFKA_CONTAINER"
echo "  Bootstrap Server: $BOOTSTRAP_SERVER"
echo "  Topic: $TOPIC"
echo "  Number of Messages: $NUM_MESSAGES"
echo "  Delay: $DELAY seconds"
echo ""

# Step 1: Create the topic
echo "========== STEP 1: CREATING TOPIC =========="
./create-topics.sh --bootstrap-server "$BOOTSTRAP_SERVER" --topic "$TOPIC" --partitions 3

# Step 2: Produce messages in the background
echo ""
echo "========== STEP 2: PRODUCING MESSAGES =========="
echo "Starting producer to send $NUM_MESSAGES messages..."
./run-producer.sh --bootstrap-server "$BOOTSTRAP_SERVER" --topic "$TOPIC" --messages "$NUM_MESSAGES" --delay "$DELAY"

# Step 3: Consume messages
echo ""
echo "========== STEP 3: CONSUMING MESSAGES =========="
echo "Starting consumer to read messages from the beginning..."
echo "Press Ctrl+C to stop consuming after messages are received."
./run-consumer.sh --bootstrap-server "$BOOTSTRAP_SERVER" --topic "$TOPIC" --from-beginning --max-messages "$NUM_MESSAGES"

echo ""
echo "========== TEST COMPLETE =========="
echo "Kafka test workflow completed successfully!"
