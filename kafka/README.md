# Kafka Docker Image

A pre-configured Apache Kafka container with multi-listener setup for development and testing. This image runs Kafka 4.0.0+ with KRaft mode (no ZooKeeper required).

> **Quick Start Available**: For immediate usage instructions, see the [Quickstart Guide](./QUICKSTART.md).

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

## What is KRaft Mode?

KRaft (Kafka Raft) is the consensus protocol that replaces ZooKeeper in Apache Kafka 4.0.0 (the latest version). Using KRaft mode provides several advantages:

- **Simplified Architecture**: No need for a separate ZooKeeper ensemble
- **Reduced Operational Overhead**: Fewer components to manage and monitor
- **Enhanced Scalability**: Better performance for large metadata operations
- **Streamlined Deployment**: Single system to configure and maintain

## Technical Specifications

- Base Image: `apache/kafka:latest`
- Configured for KRaft mode (both controller and broker roles)
- Single-node setup for development purposes
- Multiple listener configuration:
  - EXTERNAL listener (9092): For access from host machine
  - INTERNAL listener (29092): For access from other containers in Docker network
  - CONTROLLER listener (9093): For Kafka's internal controller communication

## Networking Configuration

The Kafka image is configured with a multi-listener setup that enables access from different network contexts:

1. **Host Machine Access**:
   - Connect using `localhost:9092`
   - Uses the EXTERNAL listener

2. **Container-to-Container Access**:
   - Connect using `kafka:29092` 
   - Uses the INTERNAL listener
   - Requires containers to be on the same Docker network

3. **Docker Network Setup**:
   ```yaml
   # Add this to your docker-compose.yml
   services:
     your-service:
       # ... other configuration ...
       networks:
         - kafka-network
   
   networks:
     kafka-network:
       external: true
       name: kafka-network
   ```

## Building and Pushing to Registry

1. Build the image locally:
```bash
cd kafka
docker build -t kafka:latest .
```

2. Tag the image with your registry information:
```bash
docker tag kafka:latest [registry-url]/[namespace]/kafka:latest
```
(Replace `[registry-url]` with your Docker registry URL and `[namespace]` with your organization or username)

3. Push the image to the registry:
```bash
docker push [registry-url]/[namespace]/kafka:latest
```

## Building Multi-Architecture Images

This project supports building Docker images for multiple architectures (arm64 and amd64) using Docker BuildX. This allows the same image to work seamlessly on different platforms, including ARM64-based machines (like M-series Macs) and standard AMD64-based Linux servers.

### Setting up Docker BuildX

1. Create and use a new builder instance:
```bash
docker buildx create --name multiarch-builder --use
docker buildx inspect --bootstrap
```

2. Ensure QEMU emulation support is available (required for building non-native architectures):
```bash
docker run --privileged --rm tonistiigi/binfmt:latest --install all
```

### Building and Pushing Multi-Architecture Images

To build and push the image for both arm64 and amd64 architectures in one command:

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -t docker.io/your-username/kafka:latest \
  -f Dockerfile \
  --push .
```

This command:
- Builds for both Linux AMD64 and ARM64 platforms
- Tags the image with your registry information
- Pushes it directly to the registry
- Creates a manifest list that will automatically serve the right architecture

### How Architecture Selection Works

When a multi-architecture image is pushed to a registry:
1. Docker creates separate images for each architecture
2. A manifest list is generated pointing to each architecture-specific image
3. The tag you specify (e.g., `latest`) refers to this manifest list

When a client pulls the image:
- Docker automatically detects the client machine's architecture
- The registry serves the correct architecture-specific image
- No special commands or tags are needed - the same `docker pull` command works everywhere

### Verifying Multi-Architecture Support

To verify that your image supports multiple architectures:

```bash
docker manifest inspect your-username/kafka:latest
```

This will show all the platforms supported by the image.

## Usage

Pull the image from the registry:
```bash
docker pull your-username/kafka:latest
```

Run with Docker Compose:
```bash
docker compose up -d
```

To use the image from the registry in your Docker Compose file, update the `image` field:
```yaml
services:
  kafka:
    image: your-username/kafka:latest
    # other configuration...
```

## Configuration

The image comes with a default configuration suitable for development environments. Key configurations include:

- Node ID: 1
- Process Roles: broker, controller
- Controller Quorum Voters: 1@localhost:9093
- Listeners:
  - INTERNAL://0.0.0.0:29092 (for container access)
  - EXTERNAL://0.0.0.0:9092 (for host access)
  - CONTROLLER://0.0.0.0:9093 (for internal controller communication)
- Advertised Listeners:
  - INTERNAL://kafka:29092 (advertised to other containers)
  - EXTERNAL://localhost:9092 (advertised to host)

## Testing

For testing examples, see the [tests/kafka-test](../tests/kafka-test) directory.

## Design Decisions

1. Using KRaft mode (instead of ZooKeeper) for simplified architecture
2. Configuring as a combined node (both broker and controller) to minimize resource usage for dev environments
3. Including necessary Linux utilities for debugging purposes
4. Providing data persistence through Docker volumes
5. Implementing multi-listener configuration to support both host and container access
