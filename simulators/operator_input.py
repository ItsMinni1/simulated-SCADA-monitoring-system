import json
import time
import argparse
import os
from kafka import KafkaProducer

# Configuration
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9094')
TOPIC = os.getenv('MANUAL_TOPIC', 'manual_data')

def log_entry(message, operator_id):
    """Sends a manual log entry to Kafka Topic B."""
    
    try:
        producer = KafkaProducer(
            bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
            value_serializer=lambda v: json.dumps(v).encode('utf-8')
        )
        
        entry = {
            'operator_id': operator_id,
            'timestamp': time.time(),
            'log_message': message,
            'type': 'MANUAL_ENTRY'
        }
        
        print(f"Logging entry: {entry}")
        producer.send(TOPIC, entry)
        producer.flush()
        print("Log entry published successfully.")

    except Exception as e:
        print(f"Failed to log entry: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="SCADA Manual Input CLI")
    parser.add_argument("message", help="The log message (e.g., 'Valve opened')")
    parser.add_argument("--id", default="OPERATOR_01", help="Operator ID")
    
    args = parser.parse_args()
    log_entry(args.message, args.id)
