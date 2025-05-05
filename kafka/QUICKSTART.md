# Kafka Container Quickstart

This quickstart guide shows you how to use our pre-built multi-architecture Kafka images for development.

## Pull the image

```bash
docker pull dawsonlp/kafka:latest
```

The image automatically works on both ARM64 (e.g., Mac M-series) and AMD64 platforms.

## Running Kafka for Local Development

### Option 1: Host-Only Access

Create a `docker-compose.yml` file:

```yaml
services:
  kafka:
    image: dawsonlp/kafka:latest
    container_name: kafka
    ports:
      - "9092:9092"
    volumes:
      - kafka-data:/var/lib/kafka/data
    restart: unless-stopped

volumes:
  kafka-data:
```

Start Kafka:

```bash
docker compose up -d
```

Connect from your host machine using `localhost:9092`.

### Option 2: Multi-Container with Docker Network

Create a `docker-compose.yml` file:

```yaml
services:
  kafka:
    image: dawsonlp/kafka:latest
    container_name: kafka
    ports:
      - "9092:9092"  # For host machine access
    volumes:
      - kafka-data:/var/lib/kafka/data
    networks:
      - kafka-network
    restart: unless-stopped

  # Example consumer application
  consumer-app:
    image: your-app-image:latest  # Replace with your application image
    depends_on:
      - kafka
    environment:
      - KAFKA_BOOTSTRAP_SERVERS=kafka:29092  # Use internal listener for container access
    networks:
      - kafka-network

volumes:
  kafka-data:

networks:
  kafka-network:
    name: kafka-network
```

Start the services:

```bash
docker compose up -d
```

- Host machine access: `localhost:9092`
- Container access: `kafka:29092`

## Working with Kafka Topics and Messages

### From Inside the Container

#### Creating a Topic

```bash
docker exec kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --create \
  --topic my-topic \
  --partitions 1 \
  --replication-factor 1
```

#### Listing Topics

```bash
docker exec kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --list
```

#### Producing Messages

```bash
# Using the console producer
docker exec -it kafka /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic my-topic

# Type messages, press Enter after each one
# Press Ctrl+D to exit
```

Alternatively, you can pipe a message:

```bash
echo "Hello Kafka!" | \
  docker exec -i kafka /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic my-topic
```

#### Consuming Messages

```bash
docker exec -it kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic my-topic \
  --from-beginning
```

Press Ctrl+C to stop the consumer.

## Installing Kafka Tools Locally

If you prefer to use Kafka tools directly from your laptop instead of through Docker exec commands, you can install them locally.

### macOS (using Homebrew)

```bash
# Install Kafka including command-line tools
brew install kafka

# Verify installation
kafka-topics --version
```

The Kafka tools will be available in your PATH.

### Linux (Ubuntu/Debian)

```bash
# Install Java (required for Kafka tools)
sudo apt update
sudo apt install default-jre

# Download Kafka 4.0.0 (latest version)
wget https://downloads.apache.org/kafka/4.0.0/kafka_2.13-4.0.0.tgz
tar -xzf kafka_2.13-4.0.0.tgz
cd kafka_2.13-4.0.0

# Use the tools directly from the bin directory
bin/kafka-topics.sh --version
```

You may want to add Kafka's bin directory to your PATH.

### Windows

1. Install Java JRE from [Oracle](https://www.oracle.com/java/technologies/downloads/) or [OpenJDK](https://adoptium.net/)
2. Download Kafka 4.0.0 from [Apache Kafka downloads](https://kafka.apache.org/downloads)
3. Extract the downloaded file to a directory like `C:\kafka`
4. Use the tools from the `bin\windows` directory:

```batch
C:\kafka\bin\windows\kafka-topics.bat --version
```

### Using Local Kafka Tools with Your Container

Once you have Kafka tools installed locally, you can use them to communicate with your Kafka container:

```bash
# Create a topic
kafka-topics --bootstrap-server localhost:9092 \
  --create --topic my-local-topic --partitions 1 --replication-factor 1

# List topics 
kafka-topics --bootstrap-server localhost:9092 --list

# Produce messages
kafka-console-producer --bootstrap-server localhost:9092 --topic my-local-topic

# Consume messages
kafka-console-consumer --bootstrap-server localhost:9092 --topic my-local-topic --from-beginning
```

Note: On Linux and Windows, depending on your installation, you might need to use `.sh` or `.bat` extensions (e.g., `kafka-topics.sh` instead of `kafka-topics`).

## Adding Kafka to Existing Docker Compose Projects

To incorporate Kafka into your existing Docker Compose project:

1. Add Kafka service to your docker-compose.yml:

```yaml
services:
  # Your existing services...
  
  kafka:
    image: dawsonlp/kafka:latest
    container_name: kafka
    ports:
      - "9092:9092"
    volumes:
      - kafka-data:/var/lib/kafka/data
    networks:
      - default  # Join your default network, or create a named network
    restart: unless-stopped

volumes:
  # Your existing volumes...
  kafka-data:
```

2. Configure your application to connect to Kafka:

- For services in the same Docker network: Use `kafka:29092` as bootstrap server
- For host applications: Use `localhost:9092` as bootstrap server

## Testing Your Kafka Setup

Here's a quick end-to-end test:

```bash
# Create a test topic
docker exec kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --create \
  --topic test-topic \
  --partitions 1 \
  --replication-factor 1

# Send some messages
for i in {1..5}; do
  echo "Test message $i" | \
  docker exec -i kafka /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic test-topic
done

# Verify the messages
docker exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic test-topic \
  --from-beginning \
  --max-messages 5
```

## Using Kafka with Python

Add this to your Python application:

```python
from kafka import KafkaProducer, KafkaConsumer
import json

# For production, consider setting up a proper logger
import logging
logging.basicConfig(level=logging.INFO)

# Producer Example
def send_message(topic, message, bootstrap_servers):
    producer = KafkaProducer(
        bootstrap_servers=bootstrap_servers,
        value_serializer=lambda v: json.dumps(v).encode('utf-8')
    )
    
    future = producer.send(topic, value=message)
    
    try:
        # Wait for the message to be delivered
        record_metadata = future.get(timeout=10)
        print(f"Message sent to {record_metadata.topic} partition {record_metadata.partition}")
    except Exception as e:
        print(f"Error sending message: {e}")
    finally:
        producer.close()

# Consumer Example
def consume_messages(topic, bootstrap_servers, timeout_ms=10000):
    consumer = KafkaConsumer(
        topic,
        bootstrap_servers=bootstrap_servers,
        auto_offset_reset='earliest',
        enable_auto_commit=True,
        group_id='my-group',
        value_deserializer=lambda x: json.loads(x.decode('utf-8')),
        consumer_timeout_ms=timeout_ms
    )
    
    try:
        for message in consumer:
            print(f"Received: {message.value}")
    except Exception as e:
        print(f"Error consuming messages: {e}")
    finally:
        consumer.close()

# Example usage
if __name__ == "__main__":
    # For host machine
    # bootstrap_servers = "localhost:9092"
    
    # For container
    bootstrap_servers = "kafka:29092"
    
    topic = "test-topic"
    
    # Send a message
    send_message(topic, {"key": "value", "timestamp": "2023-01-01T12:00:00"}, bootstrap_servers)
    
    # Consume messages
    consume_messages(topic, bootstrap_servers)
```

## Next Steps

For more detailed information, configuration options, and build instructions, see the [full README](./README.md).
