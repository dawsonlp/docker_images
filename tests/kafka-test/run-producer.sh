#!/bin/bash
# Script to run the Kafka producer test

set -e

# Default values
BOOTSTRAP_SERVER="kafka:29092"
TOPIC="test-topic"
NUM_MESSAGES=10
DELAY=1.0

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
      echo "  --bootstrap-server <server>     Kafka bootstrap server (default: kafka:29092)"
      echo "  --topic <topic>                 Topic name to produce to (default: test-topic)"
      echo "  --messages <num>                Number of messages to produce (default: 10)"
      echo "  --delay <seconds>               Delay between messages in seconds (default: 1.0)"
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

echo "Running Kafka producer with the following configuration:"
echo "  Bootstrap Server: $BOOTSTRAP_SERVER"
echo "  Topic: $TOPIC"
echo "  Number of Messages: $NUM_MESSAGES"
echo "  Delay: $DELAY seconds"

# Ensure the topic exists
./create-topics.sh --bootstrap-server "$BOOTSTRAP_SERVER" --topic "$TOPIC"

# Run the producer
python3 producer.py \
  --bootstrap-server "$BOOTSTRAP_SERVER" \
  --topic "$TOPIC" \
  --messages "$NUM_MESSAGES" \
  --delay "$DELAY"
