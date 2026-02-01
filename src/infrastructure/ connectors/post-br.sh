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

#!/bin/bash

# Configurações regionais BR
CONNECT_URL="http://localhost:8083/connectors"
CONNECTOR_JSON="outbox-connector-br.json"
SCHEMA_REGISTRY_INTERNAL="http://redpanda-br:8081"
WORKER_CONTAINER="cdc-worker-br"

echo "🚀 Criando connector Debezium (BR)..."

# 1. Envia o JSON de configuração para o Debezium Worker BR
curl -i -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  --data @"$CONNECTOR_JSON" \
  "$CONNECT_URL"

echo
echo "✅ Requisição do conector enviada para o Brasil."

# Pequena pausa para garantir que o motor de esquemas processou a inicialização
sleep 2

echo "🛡️ Configurando estratégia BACKWARD no Schema Registry (BR)..."

# 2. Configura a compatibilidade via rede interna do Docker
# Usamos o cdc-worker-br como ponte para o comando
docker exec -it $WORKER_CONTAINER curl -s -X PUT \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{"compatibility": "BACKWARD"}' \
  $SCHEMA_REGISTRY_INTERNAL/config

echo
echo "✅ Configuração de compatibilidade concluída no Brasil."