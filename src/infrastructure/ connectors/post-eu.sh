#!/bin/bash

# Configurações regionais
CONNECT_URL="http://localhost:18083/connectors"
CONNECTOR_JSON="outbox-connector-us.json"
SCHEMA_REGISTRY_INTERNAL="http://redpanda-us:8081"

echo "🚀 Criando connector Debezium (US)..."

# Criar o conector
curl -i -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  --data @"$CONNECTOR_JSON" \
  "$CONNECT_URL"

echo
echo "✅ Requisição do conector enviada"

# Aguarda 2 segundos para o Debezium registrar o primeiro esquema
sleep 2

echo "🛡️ Configurando estratégia BACKWARD no Schema Registry (US)..."

# Usamos o próprio container do Debezium US para rodar o curl interno
# Isso evita depender do nome do container do console estar certo ou errado
docker exec -it cdc-worker-us curl -X PUT \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{"compatibility": "BACKWARD"}' \
  $SCHEMA_REGISTRY_INTERNAL/config

echo
echo "✅ Configuração de compatibilidade concluída nos EUA."