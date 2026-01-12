CREATE DATABASE IF NOT EXISTS insurance;

-- 1. Tabela de Queue (Mapeando SEU JSON exato)
CREATE TABLE IF NOT EXISTS insurance.outbox_queue
(
    event_id String,
    correlation_id String,
    aggregate_type String,
    aggregate_id String,
    event_type String,
    payload String,
    region_code String,
    occurred_at String
    -- O ClickHouse ignora campos do JSON que não estiverem listados aqui (ex: trace_parent), o que é bom.
)
ENGINE = Kafka
SETTINGS    
    kafka_broker_list = 'event-bus:9092',
    kafka_topic_list = 'insurance.sys.transactional_outbox',
    kafka_group_name = 'clickhouse_consumer_group',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 1,
    kafka_max_block_size = 1048576;

-- 2. Tabela de Analytics (Mantive igual, pois a estrutura final é boa)
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
ORDER BY (region_code, aggregate_type, event_type, occurred_at, event_id);

-- 3. Materialized View (Simplificada: Lê direto da coluna, sem extrair de 'after')
CREATE MATERIALIZED VIEW IF NOT EXISTS insurance.mv_outbox_analytics
TO insurance.outbox_analytics
AS
SELECT
    toUUIDOrZero(event_id)         AS event_id,
    toUUIDOrZero(correlation_id)   AS correlation_id,
    CAST(aggregate_type, 'LowCardinality(String)') AS aggregate_type,
    toUUIDOrZero(aggregate_id)     AS aggregate_id,
    CAST(event_type, 'LowCardinality(String)')     AS event_type,
    
    payload                        AS payload,
    
    CAST(region_code, 'LowCardinality(String)')    AS region_code,
    
    -- Parse da data que vem como String no JSON
    parseDateTime64BestEffortOrNull(occurred_at)   AS occurred_at,
    
    now() AS _ingested_at
FROM insurance.outbox_queue;
-- Removi o WHERE op = 'c' pois seu JSON não tem operação de create/update.
-- Assim os eventos são mantidos e a arquitetura de não perder dados funciona melhor.