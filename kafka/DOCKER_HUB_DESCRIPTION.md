# kafka

A pre-configured Apache Kafka container with multi-listener setup for development and testing. This image runs Kafka 4.0.0+ with KRaft mode (no ZooKeeper required).

## Features

- **Multi-architecture** support (arm64 and amd64)
- **KRaft mode** - no ZooKeeper dependency
- **Multi-listener configuration**:
  - Host machine access via `localhost:9092`
  - Container-to-container access via `kafka:29092`
- **Ready for Docker networks** - works seamlessly with other containers
- **Debugging utilities** included - simplifies troubleshooting
- **Persistent volume** for data storage
- **Single-node** setup perfect for development

## Quick Usage

```bash
# Pull the image
docker pull dawsonlp/kafka:latest

# Start with Docker Compose
docker compose up -d
```

### Host Machine Connection

Connect to Kafka from your host machine:

```bash
kafka-topics --bootstrap-server localhost:9092 --list
```

### Container-to-Container Connection

Other containers can connect to Kafka using this configuration:

```yaml
services:
  your-app:
    # Your application configuration...
    environment:
      - KAFKA_BOOTSTRAP_SERVERS=kafka:29092
    networks:
      - kafka-network

networks:
  kafka-network:
    external: true
    name: kafka-network
```

## Full Documentation

For complete documentation, including Docker Compose examples, Python code samples, and local Kafka tools setup, visit the [GitHub repository](https://github.com/dawsonlp/docker_images).
