CREATE TABLE IF NOT EXISTS analytics.queue_us_raw
(
    json_raw String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'redpanda-us:9092',
    kafka_topic_list = 'us.core.sys.transactional_outbox',
    kafka_group_name = 'clickhouse_global_consumer',
    kafka_format = 'JSONAsString';
