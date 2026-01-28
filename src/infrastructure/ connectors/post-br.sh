#!/bin/bash

CONNECT_URL="http://localhost:8083/connectors/"
CONNECTOR_JSON="outbox-connector-br.json"

echo "🚀 Criando connector Debezium (BR)..."

curl -i -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  --data @"$CONNECTOR_JSON" \
  "$CONNECT_URL"

echo
echo "✅ Requisição enviada"


docker exec -it insurance-event-console-br curl -X PUT \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{"compatibility": "BACKWARD"}' \
  http://redpanda-br:8081/config

  docker exec -it insurance-event-console-br curl -X PUT \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{"compatibility": "BACKWARD"}' \
  http://redpanda-us:8081/config