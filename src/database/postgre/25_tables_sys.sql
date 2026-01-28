CREATE TABLE sys.idempotency_registry(
    idempotency_key UUID PRIMARY KEY,
    stored_result JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE sys.idempotency_registry
    SET (fillfactor = 80);

CREATE INDEX idx_idempotency_cleaup ON sys.idempotency_registry (created_at);