-- =======================================================================================
-- FILE: 04_setup_clickhouse.sql
-- DESCRIPTION: ClickHouse setup for ingesting events from Redpanda (Kafka protocol).
-- NOTES:
--  - Assumes outbox events are written as JSON in the Debezium "after" envelope.
--  - Timestamp fields are expected as Unix epoch microseconds (adjust if different).
--  - Materialized view extracts and normalizes fields into the `analytics.events_history` table.
-- DATE: 2025-12-25
-- =======================================================================================

CREATE DATABASE IF NOT EXISTS analytics;

-- 1. DESTINATION TABLE (PHYSICAL STORAGE)
CREATE TABLE IF NOT EXISTS analytics.events_history
(
    event_id UUID,
    event_type String,
    occurred_at DateTime64(3),
    region_code LowCardinality(String),
    aggregate_id UUID,
    amount Decimal(18, 2),
    product_code LowCardinality(String),
    raw_payload String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(occurred_at)
ORDER BY (region_code, event_type, occurred_at)
TTL occurred_at + INTERVAL 5 YEAR; -- data retention: 5 years
-- 2. KAFKA ENGINE TABLE (STREAM SOURCE)
CREATE TABLE IF NOT EXISTS analytics.kafka_stream
(
    raw_message String
) 
ENGINE = Kafka
SETTINGS 
    kafka_broker_list = 'event-bus:9092',
    kafka_topic_list = 'insurance.sys.transactional_outbox',
    kafka_group_name = 'clickhouse_consumer_group',
    kafka_format = 'JSONAsString', -- receives the raw message as JSON string
    kafka_num_consumers = 1,
    kafka_max_block_size = 1048576;
-- 3. MATERIALIZED VIEW (REAL-TIME ETL)
-- The view parses the Debezium envelope (expects an "after" object) and
-- normalizes fields into the target table. Adjust JSON paths if the format differs.
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.mv_kafka_to_history TO analytics.events_history
AS
SELECT
    -- Convert to UUID when possible; null if value is missing/invalid
    toUUIDOrNull(JSONExtractString(JSONExtractRaw(raw_message, 'after'), 'event_id')) AS event_id,
    
    JSONExtractString(JSONExtractRaw(raw_message, 'after'), 'event_type') AS event_type,
    
    -- Timestamp conversion: using microseconds epoch (Debezium may emit micros)
    fromUnixTimestamp64Micro(
        JSONExtractUInt(JSONExtractRaw(raw_message, 'after'), 'occurred_at')
    ) AS occurred_at,
    
    JSONExtractString(JSONExtractRaw(raw_message, 'after'), 'region_code') AS region_code,
    
    toUUIDOrNull(JSONExtractString(JSONExtractRaw(raw_message, 'after'), 'aggregate_id')) AS aggregate_id,

    -- Extract amount/premium with fallbacks and convert to Decimal(18,2)
    toDecimal64(
        if(
            JSONHas(JSONExtractRaw(JSONExtractString(JSONExtractRaw(raw_message, 'after'), 'payload')), 'amount'),
            JSONExtractFloat(JSONExtractString(JSONExtractRaw(raw_message, 'after'), 'payload'), 'amount'),
            if(
                JSONHas(JSONExtractRaw(JSONExtractString(JSONExtractRaw(raw_message, 'after'), 'payload')), 'premium'),
                JSONExtractFloat(JSONExtractString(JSONExtractRaw(raw_message, 'after'), 'payload'), 'premium'),
                0.0
            )
        ),
        2
    ) AS amount,

    -- product_code inside the payload object
    JSONExtractString(JSONExtractString(JSONExtractRaw(raw_message, 'after'), 'payload'), 'product_code') AS product_code,

    -- raw payload as string for full fidelity and debugging
    JSONExtractString(JSONExtractRaw(raw_message, 'after'), 'payload') AS raw_payload

FROM analytics.kafka_stream
WHERE 
    JSONHas(raw_message, 'after') = 1 
    AND length(JSONExtractRaw(raw_message, 'after')) > 2;