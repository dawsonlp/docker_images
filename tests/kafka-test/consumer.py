#!/usr/bin/env python3
"""
Kafka Consumer Test Script

This script consumes messages from a specified Kafka topic.
"""

import json
import sys
import signal
import argparse
from kafka import KafkaConsumer

# Global flag for controlling consumption loop
running = True

def parse_args():
    parser = argparse.ArgumentParser(description='Kafka Consumer Test')
    parser.add_argument('--bootstrap-server', default='kafka:29092', 
                        help='Kafka bootstrap server (default: kafka:29092)')
    parser.add_argument('--topic', default='test-topic', 
                        help='Kafka topic to consume from (default: test-topic)')
    parser.add_argument('--group', default='test-consumer-group', 
                        help='Consumer group ID (default: test-consumer-group)')
    parser.add_argument('--from-beginning', action='store_true',
                        help='Read messages from the beginning')
    parser.add_argument('--timeout', type=int, default=30000,
                        help='Consumer poll timeout in ms (default: 30000)')
    parser.add_argument('--max-messages', type=int, default=0,
                        help='Maximum number of messages to consume (0 for unlimited, default: 0)')
    return parser.parse_args()

def signal_handler(sig, frame):
    global running
    print("Interrupt received, stopping consumer...")
    running = False

def create_consumer(args):
    print(f"Creating consumer connecting to {args.bootstrap_server}...")
    auto_offset_reset = 'earliest' if args.from_beginning else 'latest'
    
    try:
        consumer = KafkaConsumer(
            args.topic,
            bootstrap_servers=[args.bootstrap_server],
            group_id=args.group,
            auto_offset_reset=auto_offset_reset,
            value_deserializer=lambda v: json.loads(v.decode('utf-8')),
            key_deserializer=lambda v: v.decode('utf-8') if v else None,
            consumer_timeout_ms=args.timeout
        )
        print(f"Successfully connected to Kafka at {args.bootstrap_server}")
        print(f"Subscribed to topic: {args.topic}")
        return consumer
    except Exception as e:
        print(f"Error creating consumer: {str(e)}")
        sys.exit(1)

def main():
    args = parse_args()
    
    # Register signal handler for graceful shutdown
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    consumer = create_consumer(args)
    
    message_count = 0
    print(f"Waiting for messages on topic '{args.topic}'...")
    
    try:
        for message in consumer:
            if not running:
                break
                
            partition = message.partition
            offset = message.offset
            key = message.key
            value = message.value
            
            print(f"\nReceived message:")
            print(f"  Topic: {message.topic}")
            print(f"  Partition: {partition}")
            print(f"  Offset: {offset}")
            print(f"  Key: {key}")
            print(f"  Value: {json.dumps(value, indent=2)}")
            
            message_count += 1
            
            if args.max_messages > 0 and message_count >= args.max_messages:
                print(f"Reached maximum message count ({args.max_messages})")
                break
                
    except Exception as e:
        print(f"Error consuming messages: {str(e)}")
    finally:
        # Close consumer if it exists
        if 'consumer' in locals():
            consumer.close()
            print("\nConsumer closed")
            
    print(f"Total messages consumed: {message_count}")

if __name__ == "__main__":
    main()
