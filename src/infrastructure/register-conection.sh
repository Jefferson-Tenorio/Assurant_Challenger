#!/bin/sh
set -e

# URL for Kafka Connect REST API inside docker-compose network
URL="http://debezium-connector:8083/connectors"
NAME="insurance-outbox-connector"
CONFIG_FILE="/insurance-outbox-connector.json" # corrected mount path
PROCESSED_CONFIG="/tmp/config-processed.json"

echo "⏳ Waiting for Kafka Connect..."
until curl -sf "$URL" >/dev/null; do
  sleep 5
done

echo "🔎 Checking if connector already exists..."

# If the connector is already registered, exit gracefully.
if curl -sf "$URL/$NAME" >/dev/null; then
  echo "✅ Connector already exists. Nothing to do."
  exit 0
fi

echo "⚙️ Replacing environment variables in connector JSON..."
# Replace placeholders (${DB_USER}, ${DB_PASSWORD}) with actual env values
sed -e "s|\${DB_USER}|$DB_USER|g" \
    -e "s|\${DB_PASSWORD}|$DB_PASSWORD|g" \
    "$CONFIG_FILE" > "$PROCESSED_CONFIG"

echo "🚀 Creating Debezium connector..."

# POST the processed JSON to Kafka Connect REST API
curl -sf -X POST \
  -H "Content-Type: application/json" \
  -d @"$PROCESSED_CONFIG" \
  "$URL"

echo "🎉 Connector created successfully"