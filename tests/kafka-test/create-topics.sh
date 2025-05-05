#!/bin/bash
# Script to set up Kafka topics for testing
# This script relies on Kafka's auto-topic creation feature

set -e

# Default values
BOOTSTRAP_SERVER="kafka:29092"
TOPIC="test-topic"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap-server)
      BOOTSTRAP_SERVER="$2"
      shift 2
      ;;
    --topic)
      TOPIC="$2"
      shift 2
      ;;
    --partitions)
      echo "Note: --partitions option is ignored, using auto-topic creation"
      shift 2
      ;;
    --replication-factor)
      echo "Note: --replication-factor option is ignored, using auto-topic creation"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --bootstrap-server <server>     Kafka bootstrap server (default: kafka:29092)"
      echo "  --topic <topic>                 Topic name to create (default: test-topic)"
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

echo "Setting up Kafka topic:"
echo "  Bootstrap Server: $BOOTSTRAP_SERVER"
echo "  Topic: $TOPIC"

# Ensure kafkacat/kcat is installed
if ! command -v kcat &> /dev/null && ! command -v kafkacat &> /dev/null; then
    echo "Installing kafkacat to work with Kafka..."
    apt-get update && apt-get install -y kafkacat
fi

# Determine which command is available
KCAT_CMD="kcat"
if ! command -v kcat &> /dev/null; then
    KCAT_CMD="kafkacat"
fi

# Verify broker connectivity
echo "Verifying connection to Kafka broker..."
$KCAT_CMD -b $BOOTSTRAP_SERVER -L -t $TOPIC 2>&1 | grep -q "Metadata for" || {
    echo "Warning: Unable to connect to Kafka broker at $BOOTSTRAP_SERVER"
    echo "Will attempt to publish anyway, which may auto-create the topic if enabled in Kafka"
}

# Send a single message to create the topic if it doesn't exist
echo "Sending a test message to ensure topic exists..."
echo "{\"test\":\"message\"}" | $KCAT_CMD -b $BOOTSTRAP_SERVER -t $TOPIC -P
echo "Topic '$TOPIC' should now exist (auto-created if enabled in Kafka)"

# List available topics
echo "Available topics:"
$KCAT_CMD -b $BOOTSTRAP_SERVER -L | grep "topic"
