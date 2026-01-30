#!/bin/bash

CONNECT_URL="http://localhost:18083/connectors"
CONNECTOR_JSON="outbox-connector-us.json"

echo "🚀 Criando connector Debezium (US)..."

curl -i -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  --data @"$CONNECTOR_JSON" \
  "$CONNECT_URL"

echo
echo "✅ Requisição enviada"

docker exec -it infrastructure-console-br-1 curl -X PUT \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{"compatibility": "BACKWARD"}' \
  http://redpanda-us:8081/config