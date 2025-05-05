FROM python:3.13-slim

# Install necessary tools for testing
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        netcat-openbsd \
        curl \
        kafkacat \
        jq \
        bash && \
    rm -rf /var/lib/apt/lists/*

# Install Python Kafka client
RUN pip install --no-cache-dir kafka-python

# Set working directory
WORKDIR /tests

# Copy test scripts
COPY *.py /tests/
COPY *.sh /tests/

# Make scripts executable
RUN chmod +x /tests/*.sh

ENTRYPOINT ["/bin/bash"]
