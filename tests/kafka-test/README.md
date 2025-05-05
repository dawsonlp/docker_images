# Kafka Test Environment

This directory contains a self-contained test environment for the `dawsonlp/lpd-basic-kafka:latest` image. It provides scripts for producing and consuming messages to verify the Kafka functionality.

## Contents

- `docker-compose.yml` - Docker Compose configuration for running Kafka and the test client
- `Dockerfile` - Python-based test client image with necessary tools
- `producer.py` - Python script for producing messages to Kafka
- `consumer.py` - Python script for consuming messages from Kafka
- `create-topics.sh` - Helper script for creating Kafka topics
- `run-producer.sh` - Wrapper script for running the producer
- `run-consumer.sh` - Wrapper script for running the consumer
- `test-kafka.sh` - End-to-end test script that demonstrates the full workflow

## Quick Start

### 1. Start the Environment

```bash
docker compose up -d
```

This will start:
- A Kafka broker using the `dawsonlp/lpd-basic-kafka:latest` image
- A test client container with necessary tools

### 2. Enter the Test Client Container

```bash
docker compose exec test-client bash
```

### 3. Create a Test Topic

```bash
./create-topics.sh
```

This creates a default topic named `test-topic` with 1 partition and replication factor of 1.

### 4. Produce Test Messages

```bash
./run-producer.sh
```

This produces 10 messages to the `test-topic`.

### 5. Consume Test Messages

```bash
./run-consumer.sh --from-beginning
```

This consumes messages from the beginning of the `test-topic`.

### 6. Shutdown the Environment

```bash
docker compose down -v
```

## Script Options

### create-topics.sh

```
Options:
  --bootstrap-server <server>     Kafka bootstrap server (default: localhost:9092)
  --topic <topic>                 Topic name to create (default: test-topic)
  --help                          Show this help message
```

Note: This script uses kafkacat/kcat to auto-create topics by sending test messages.

### run-producer.sh

```
Options:
  --bootstrap-server <server>     Kafka bootstrap server (default: kafka:9092)
  --topic <topic>                 Topic name to produce to (default: test-topic)
  --messages <num>                Number of messages to produce (default: 10)
  --delay <seconds>               Delay between messages in seconds (default: 1.0)
  --help                          Show this help message
```

### run-consumer.sh

```
Options:
  --bootstrap-server <server>     Kafka bootstrap server (default: kafka:9092)
  --topic <topic>                 Topic name to consume from (default: test-topic)
  --group <group-id>              Consumer group ID (default: test-consumer-group)
  --from-beginning                Read messages from the beginning
  --timeout <ms>                  Consumer poll timeout in ms (default: 30000)
  --max-messages <num>            Maximum number of messages to consume (0 for unlimited, default: 0)
  --help                          Show this help message
```

## Full Example Workflow

Here's a complete workflow example to test the Kafka container:

```bash
# Start the environment
docker compose up -d

# Enter the test client
docker compose exec test-client bash

# Create a topic with 3 partitions
./create-topics.sh --topic test-example --partitions 3

# Produce 20 messages with 0.5 second delay
./run-producer.sh --topic test-example --messages 20 --delay 0.5

# Consume messages from the beginning
./run-consumer.sh --topic test-example --from-beginning

# In another terminal, start a second consumer with a different group
docker compose exec test-client bash
./run-consumer.sh --topic test-example --group another-group --from-beginning

# Clean up when done
docker compose down -v
```

## Customizing the Test Environment

You can modify the `docker-compose.yml` file to change the configuration of the Kafka broker or test client. The environment variables in the Kafka service can be adjusted to test different configurations.
