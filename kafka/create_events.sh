#!/bin/bash

# Kafka and Schema Registry details (now pointing to your local forwarded ports)
TOPIC="myevent"
BOOTSTRAP="localhost:9094" # Forwarded Kafka port
SCHEMA_REGISTRY_URL="http://localhost:8081" # Forwarded Schema Registry port

# The Avro schema for the 'myevent' topic (value schema)
# This MUST match the schema registered with your Schema Registry for 'myevent-value'
SCHEMA='{
    "fields": [
      {
        "name": "id",
        "type": "string",
        "doc": "Unique identifier for the event"
      },
      {
        "name": "value",
        "type": "int",
        "doc": "Some integer value to aggregate"
      },
      {
        "name": "event_time",
        "type": {
          "type": "long",
          "logicalType": "timestamp-millis"
        },
        "doc": "Timestamp of the event in milliseconds since the epoch"
      },
      {
        "name": "category",
        "type": ["null", "string"],
        "default": null,
        "doc": "Optional category for grouping"
      }
    ],
    "type": "record",
    "name": "MyEvent",
    "namespace": "com.example.avro"
    }'

# The command to run the Avro Console Producer on your host
# Make sure 'kafka-avro-console-producer' is in your system's PATH, or use its full path
AVRO_PRODUCER_COMMAND="kafka-avro-console-producer"

# Check if the producer command is available on the host system
if ! command -v "$AVRO_PRODUCER_COMMAND" &> /dev/null
then
    echo "ERROR: '$AVRO_PRODUCER_COMMAND' command not found."
    echo "Please ensure Confluent Platform client tools are installed and in your PATH."
    exit 1
fi

echo "Starting to send Avro messages to topic '$TOPIC' every 5–10 seconds..."
echo "Press Ctrl+C to stop."

while true; do
  # Generate random data matching the Avro schema
  ID=$(uuidgen)
  VALUE=$(( RANDOM % 100 ))
  # Get current timestamp in milliseconds
  EVENT_TIME=$(date +%s%N | cut -b1-13)
  CATEGORIES=("A" "B" "C" "D" "E" "null")
  CATEGORY_RAW=${CATEGORIES[$RANDOM % ${#CATEGORIES[@]}]} # Store raw category
  
  CATEGORY_JSON="" # Initialize category JSON part
  if [[ "$CATEGORY_RAW" == "null" ]]; then
    CATEGORY_JSON="null" # For Avro null in union, it's just 'null'
  else
    # For Avro string in union, it needs {"string": "VALUE"}
    CATEGORY_JSON="{\"string\":\"$CATEGORY_RAW\"}"
  fi

  # Construct the full message with the correctly formatted category
  MESSAGE="{\"id\":\"$ID\",\"value\":$VALUE,\"event_time\":$EVENT_TIME,\"category\":$CATEGORY_JSON}"

  echo "Sending: $MESSAGE"

  # Execute the Avro Console Producer directly on the host
  echo "$MESSAGE" | "$AVRO_PRODUCER_COMMAND" \
    --bootstrap-server "$BOOTSTRAP" \
    --topic "$TOPIC" \
    --property schema.registry.url="$SCHEMA_REGISTRY_URL" \
    --property value.schema="$SCHEMA" \
    --property value.schema.literal=true \
    --producer-property acks=all # Corrected from --producer.property to --producer-property
  
  # Check the exit code of the last command
  if [ $? -ne 0 ]; then
    echo "ERROR: Avro Console Producer command failed (exit code $?). Exiting."
    break # Exit the loop on critical failure
  else
    echo "Sent successfully."
  fi

  sleep $((5 + RANDOM % 6)) # wait 5–10 seconds
done