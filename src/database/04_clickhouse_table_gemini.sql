-- 0. Garantir que o banco existe
CREATE DATABASE IF NOT EXISTS insurance;

-- 1. Tabela de Queue (Interface com Kafka/Redpanda)
CREATE TABLE IF NOT EXISTS insurance.outbox_queue
(
    before String,
    after String,
    op String,
    ts_ms Int64
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'event-bus:9092',
    kafka_topic_list = 'insurance.sys.transactional_outbox',
    kafka_group_name = 'clickhouse_consumer_group',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 1;


-- 2. Tabela de Armazenamento (Analytics)
-- CORREÇÃO AQUI: Engine usa occurred_at e Order By inclui event_id
CREATE TABLE IF NOT EXISTS insurance.outbox_analytics
(
    event_id UUID,
    correlation_id UUID,
    aggregate_type LowCardinality(String),
    aggregate_id UUID,
    event_type LowCardinality(String),
    payload String,
    region_code LowCardinality(String),
    occurred_at DateTime64(6),
    _ingested_at DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(occurred_at)
PARTITION BY toYYYYMM(occurred_at)
ORDER BY (region_code, aggregate_type, occurred_at, event_id);


-- 3. Materialized View
CREATE MATERIALIZED VIEW IF NOT EXISTS insurance.mv_outbox_analytics
TO insurance.outbox_analytics
AS
SELECT
    toUUID(JSONExtractString(after, 'event_id'))        AS event_id,
    toUUID(JSONExtractString(after, 'correlation_id')) AS correlation_id,

    CAST(
        JSONExtractString(after, 'aggregate_type'),
        'LowCardinality(String)'
    ) AS aggregate_type,

    toUUID(JSONExtractString(after, 'aggregate_id'))   AS aggregate_id,

    CAST(
        JSONExtractString(after, 'event_type'),
        'LowCardinality(String)'
    ) AS event_type,

    JSONExtractRaw(after, 'payload')                   AS payload,

    CAST(
        JSONExtractString(after, 'region_code'),
        'LowCardinality(String)'
    ) AS region_code,

    parseDateTime64BestEffort(
        JSONExtractString(after, 'occurred_at')
    ) AS occurred_at,

    now() AS _ingested_at
FROM insurance.outbox_queue
WHERE op = 'c';
