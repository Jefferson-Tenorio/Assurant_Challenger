INSERT INTO sys.transactional_outbox
(
    correlation_id,
    aggregate_type,
    aggregate_id,
    event_type,
    payload,
    region_code
)
VALUES
(
    gen_random_uuid(),
    'POLICY',
    gen_random_uuid(),
    'POLICY_CREATED',
    '{"premio": 1000}',
    'BR'
);
