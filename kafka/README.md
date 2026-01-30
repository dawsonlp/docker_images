# Kafka Docker Image

[![Docker Hub](https://img.shields.io/badge/docker-dawsonlp%2Fkafka-blue)](https://hub.docker.com/r/dawsonlp/kafka)

Pre-configured Apache Kafka with KRaft mode (no ZooKeeper) for development and testing.

## Quick Start

```bash
# Pull and run
docker run -d --name kafka -p 9092:9092 dawsonlp/kafka:latest

# Verify it's working
docker exec kafka /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092
```

Or with Docker Compose:

```bash
docker compose up -d
```

## Available Tags

| Tag | Kafka Version | Description |
|-----|---------------|-------------|
| `latest`, `4.1.1` | 4.1.1 | Stable release |
| `4.2.0-rc2` | 4.2.0-rc2 | Release candidate |

## Features

- **KRaft mode** - No ZooKeeper dependency
- **Multi-architecture** - ARM64 and AMD64 support
- **Multi-listener** - Host access (`:9092`) and container access (`:29092`)
- **Runtime config** - All settings via environment variables
- **Non-root** - Runs as `appuser` for security

## Usage

### From Host Machine

Connect to `localhost:9092`:

```python
from kafka import KafkaProducer
producer = KafkaProducer(bootstrap_servers='localhost:9092')
```

### From Other Containers

Connect to `kafka:29092` on the same Docker network:

```yaml
services:
  myapp:
    environment:
      KAFKA_BOOTSTRAP_SERVERS: kafka:29092
    networks:
      - kafka-network
```

## Configuration

All Kafka settings are configurable via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `KAFKA_ADVERTISED_LISTENERS` | `INTERNAL://kafka:29092,EXTERNAL://localhost:9092` | Advertised endpoints |
| `KAFKA_AUTO_CREATE_TOPICS_ENABLE` | `true` | Auto-create topics |
| `KAFKA_NUM_PARTITIONS` | `1` | Default partitions |
| `KAFKA_LOG_RETENTION_HOURS` | `168` | Log retention (7 days) |

See full configuration options in the [Dockerfile](./Dockerfile).

### Example: Custom Configuration

```yaml
services:
  kafka:
    image: dawsonlp/kafka:latest
    environment:
      KAFKA_NUM_PARTITIONS: "3"
      KAFKA_LOG_RETENTION_HOURS: "48"
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "false"
```

## Common Operations

```bash
# Create a topic
docker exec kafka /opt/kafka/bin/kafka-topics.sh \
  --create --topic my-topic --partitions 3 \
  --bootstrap-server localhost:9092

# List topics
docker exec kafka /opt/kafka/bin/kafka-topics.sh \
  --list --bootstrap-server localhost:9092

# Produce messages (interactive)
docker exec -it kafka /opt/kafka/bin/kafka-console-producer.sh \
  --topic my-topic --bootstrap-server localhost:9092

# Consume messages
docker exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --topic my-topic --from-beginning --bootstrap-server localhost:9092
```

## Data Persistence

Mount a volume to persist data across container restarts:

```yaml
volumes:
  - kafka-data:/var/lib/kafka/data
```

## Health Check

```bash
docker inspect --format='{{.State.Health.Status}}' kafka
```

## Building

```bash
# Build all versions and push
./build.sh

# Build locally only
./build.sh --local

# Build specific version
./build.sh 4.2.0-rc2
```

## Smoke Tests

```bash
cd smoke-tests
./run-smoke-test.sh
```

## Why KRaft?

Kafka 4.0+ uses KRaft (Kafka Raft) instead of ZooKeeper:
- Simplified deployment (single system)
- Better performance
- Reduced operational overhead

## License

Apache 2.0