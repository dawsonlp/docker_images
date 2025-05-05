#!/usr/bin/env python3
"""
Kafka Producer Test Script

This script sends messages to a specified Kafka topic.
"""

import json
import time
import sys
import random
import argparse
from datetime import datetime
from kafka import KafkaProducer

def parse_args():
    parser = argparse.ArgumentParser(description='Kafka Producer Test')
    parser.add_argument('--bootstrap-server', default='kafka:29092', 
                        help='Kafka bootstrap server (default: kafka:29092)')
    parser.add_argument('--topic', default='test-topic', 
                        help='Kafka topic to produce to (default: test-topic)')
    parser.add_argument('--messages', type=int, default=10, 
                        help='Number of messages to produce (default: 10)')
    parser.add_argument('--delay', type=float, default=1.0, 
                        help='Delay between messages in seconds (default: 1.0)')
    return parser.parse_args()

def create_producer(bootstrap_server):
    print(f"Connecting to Kafka at {bootstrap_server}...")
    for attempt in range(5):
        try:
            producer = KafkaProducer(
                bootstrap_servers=[bootstrap_server],
                value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                key_serializer=lambda v: v.encode('utf-8') if v else None
            )
            print(f"Successfully connected to Kafka at {bootstrap_server}")
            return producer
        except Exception as e:
            print(f"Connection attempt {attempt+1} failed: {str(e)}")
            if attempt < 4:
                wait_time = 2 ** attempt
                print(f"Retrying in {wait_time} seconds...")
                time.sleep(wait_time)
            else:
                print("All connection attempts failed")
                raise

def generate_message(msg_id):
    return {
        "id": msg_id,
        "timestamp": datetime.now().isoformat(),
        "value": random.randint(1, 100),
        "message": f"Test message {msg_id}"
    }

def main():
    args = parse_args()
    
    try:
        producer = create_producer(args.bootstrap_server)
        
        print(f"Starting to send {args.messages} messages to topic '{args.topic}'")
        for i in range(1, args.messages + 1):
            message = generate_message(i)
            key = f"key-{i}"
            
            # Send message
            future = producer.send(args.topic, key=key, value=message)
            # Wait for message to be sent
            record_metadata = future.get(timeout=10)
            
            print(f"Sent message {i}/{args.messages}:")
            print(f"  Topic: {record_metadata.topic}")
            print(f"  Partition: {record_metadata.partition}")
            print(f"  Offset: {record_metadata.offset}")
            print(f"  Key: {key}")
            print(f"  Value: {json.dumps(message, indent=2)}")
            
            if i < args.messages:
                time.sleep(args.delay)
        
        # Flush to ensure all messages are sent
        producer.flush()
        print("All messages sent successfully")
    
    except Exception as e:
        print(f"Error: {str(e)}")
        sys.exit(1)
    finally:
        # Close producer if it exists
        if 'producer' in locals():
            producer.close()
            print("Producer closed")

if __name__ == "__main__":
    main()
