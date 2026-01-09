CREATE TABLE ingest.transactional_outbox_kafka
(
    before String,
    after String,
    op String,
    ts_ms Int64
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'redpanda:9092',
    kafka_topic_list = 'dbserver1.sys.transactional_outbox',
    kafka_group_name = 'clickhouse_outbox_consumer',
    kafka_format = 'JSONEachRow';

CREATE TABLE analytics.transactional_outbox_events
(
    event_id UUID,
    correlation_id UUID,
    saga_step LowCardinality(String),
    aggregate_type LowCardinality(String),
    aggregate_id UUID,
    event_type LowCardinality(String),
    payload String,
    region_code LowCardinality(String),
    occurred_at DateTime64(3),
    _ingested_at DateTime DEFAULT now()
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(occurred_at)
ORDER BY (aggregate_type, event_type, occurred_at);

CREATE MATERIALIZED VIEW ingest.mv_outbox_to_clickhouse
TO analytics.transactional_outbox_events
AS
SELECT
    toUUID(JSONExtractString(after, 'event_id'))        AS event_id,
    toUUID(JSONExtractString(after, 'correlation_id')) AS correlation_id,
    JSONExtractString(after, 'saga_step')               AS saga_step,
    JSONExtractString(after, 'aggregate_type')          AS aggregate_type,
    toUUID(JSONExtractString(after, 'aggregate_id'))   AS aggregate_id,
    JSONExtractString(after, 'event_type')              AS event_type,
    JSONExtractRaw(after, 'payload')                    AS payload,
    JSONExtractString(after, 'region_code')             AS region_code,
    parseDateTime64BestEffort(
        JSONExtractString(after, 'occurred_at')
    )                                                   AS occurred_at
FROM ingest.transactional_outbox_kafka
WHERE op = 'c';
