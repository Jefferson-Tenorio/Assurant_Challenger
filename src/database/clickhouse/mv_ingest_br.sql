CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.mv_ingest_br
TO analytics.global_events_master
AS
SELECT
    JSONExtract(json_raw, 'after', 'event_id', 'String')::UUID AS event_id,
    JSONExtract(json_raw, 'after', 'correlation_id', 'String')::UUID AS correlation_id,
    JSONExtract(json_raw, 'after', 'aggregate_type', 'String') AS aggregate_type,
    JSONExtract(json_raw, 'after', 'aggregate_id', 'String')::UUID AS aggregate_id,
    JSONExtract(json_raw, 'after', 'event_type', 'String') AS event_type,
    JSONExtract(json_raw, 'after', 'payload', 'String') AS payload,

    'BR' AS region_code,

    toDateTime64(
        JSONExtract(json_raw, 'after', 'occurred_at', 'Int64') / 1000000, 3
    ) AS occurred_at,

    CASE
        WHEN JSONExtractRaw(json_raw, 'after', 'processed_at') = 'null'
            THEN NULL
        ELSE toDateTime64(
            JSONExtract(json_raw, 'after', 'processed_at', 'Int64') / 1000000, 3
        )
    END AS processed_at,

    now() AS ingested_at
FROM analytics.queue_br_raw
WHERE length(json_raw) > 0;
