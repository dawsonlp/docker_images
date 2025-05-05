#!/bin/bash
# Script to run the Kafka consumer test

set -e

# Default values
BOOTSTRAP_SERVER="kafka:29092"
TOPIC="test-topic"
GROUP="test-consumer-group"
FROM_BEGINNING=false
TIMEOUT=30000
MAX_MESSAGES=0

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
    --group)
      GROUP="$2"
      shift 2
      ;;
    --from-beginning)
      FROM_BEGINNING=true
      shift
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --max-messages)
      MAX_MESSAGES="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --bootstrap-server <server>     Kafka bootstrap server (default: kafka:29092)"
      echo "  --topic <topic>                 Topic name to consume from (default: test-topic)"
      echo "  --group <group-id>              Consumer group ID (default: test-consumer-group)"
      echo "  --from-beginning                Read messages from the beginning"
      echo "  --timeout <ms>                  Consumer poll timeout in ms (default: 30000)"
      echo "  --max-messages <num>            Maximum number of messages to consume (0 for unlimited, default: 0)"
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

echo "Running Kafka consumer with the following configuration:"
echo "  Bootstrap Server: $BOOTSTRAP_SERVER"
echo "  Topic: $TOPIC"
echo "  Consumer Group: $GROUP"
echo "  From Beginning: $FROM_BEGINNING"
echo "  Timeout: $TIMEOUT ms"
echo "  Max Messages: $MAX_MESSAGES (0 = unlimited)"

# Build the command with appropriate flags
CMD="python3 consumer.py --bootstrap-server \"$BOOTSTRAP_SERVER\" --topic \"$TOPIC\" --group \"$GROUP\" --timeout $TIMEOUT --max-messages $MAX_MESSAGES"

# Add from-beginning flag if enabled
if [ "$FROM_BEGINNING" = true ]; then
  CMD="$CMD --from-beginning"
fi

# Run the consumer
echo "Starting consumer..."
eval "$CMD"
