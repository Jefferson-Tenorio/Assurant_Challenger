-- TODO: Crie um arquivo `queries.sql` no seu repo com consultas que mostram o poder do ClickHouse.
CREATE TABLE IF NOT EXISTS analytics.global_events_master
(
    event_id UUID,
    correlation_id UUID,
    aggregate_type String,
    aggregate_id UUID,
    event_type String,
    payload String,

    region_code LowCardinality(String),

    occurred_at DateTime64(3),
    processed_at Nullable(DateTime64(3)),

    ingested_at DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(occurred_at)
PARTITION BY toYYYYMM(occurred_at)
ORDER BY (region_code, event_type, occurred_at, event_id);

-- TODO:1.  **Script de Ataque:** Crie um loop que mande milhares de JSONs para o Redpanda.
-- TODO:2.  **Validação:** Rode o `docker stats` e veja o ClickHouse trabalhando.
-- TODO:3.  **Queries:** Teste as queries com a função `bar` que te passei acima.
-- TODO:4.  **Limpeza:** Aplique o `TTL`.

-- TODO:5 Stress test: gargalo costuma estar na leitura do Kafka/Redpanda, não no write do ClickHouse → use ≥ 3 partições no tópico insurance.sys.transactional_outbox e ajuste kafka_num_consumers = 3 para leitura paralela. ReplacingMergeTree não deduplica imediatamente (só durante merge em background) → durante o teste count() pode inflar; para números corretos use SELECT … FINAL ou OPTIMIZE TABLE … FINAL. JSONExtractString consome CPU → se o ClickHouse bater 100% CPU, o consumo do Redpanda geStress test: gargalo costuma estar na leitura do Kafka/Redpanda, não no write do ClickHouse → use ≥ 3 partições no tópico insurance.sys.transactional_outbox e ajuste kafka_num_consumers = 3 para leitura paralela. ReplacingMergeTree não deduplica imediatamente (só durante merge em background) → durante o teste count() pode inflar; para números corretos use SELECT … FINAL ou OPTIMIZE TABLE … FINAL. JSONExtractString consome CPU → se o ClickHouse bater 100% CPU, o consumo do Redpanda gera lag; monitore logs e alertas de kafka_max_block_size. Conexão ClickHouse: host localhost (fora do docker) ou analytical-db (mesma rede), porta 8123, user admin, pass admin123.ra lag; monitore logs e alertas de kafka_max_block_size. Conexão ClickHouse: host localhost (fora do docker) ou analytical-db (mesma rede), porta 8123, user admin, pass admin123.