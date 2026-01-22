CREATE EXTENSION IF NOT EXISTS "btree_gist";

CREATE TYPE currency_code_enum AS ENUM ('USD', 'BRL', 'EUR', 'GBP');

CREATE SCHEMA IF NOT EXISTS access;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS finance;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS sys;
CREATE SCHEMA IF NOT EXISTS utils;

CREATE TABLE access.customers_pii (
    customer_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name_encrypted BYTEA NOT NULL,
    tax_id_encrypted BYTEA NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone_encrypted TEXT NOT NULL,
    key_version_id INT NOT NULL,
    tax_id_blind_index VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT uq_customer_tax_id_active UNIQUE NULLS NOT DISTINCT (tax_id_blind_index, deleted_at)
);

CREATE INDEX idx_customers_email ON access.customers_pii(email) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_tax_blind ON access.customers_pii(tax_id_blind_index) WHERE deleted_at IS NULL;

CREATE TABLE core.policies (
    policy_version_id UUID PRIMARY KEY,
    policy_number VARCHAR(50) NOT NULL,
    customer_id UUID NOT NULL REFERENCES access.customers_pii(customer_id),
    idempotency_key VARCHAR(100),
    validity_period tstzrange NOT NULL,
    status VARCHAR(20) CHECK (status IN ('ACTIVE', 'SUSPENDED', 'CANCELLED')),
    product_code VARCHAR(50) NOT NULL,
    risk_attributes JSONB NOT NULL,
    version_id BIGINT DEFAULT 1,
    EXCLUDE USING GIST (
        policy_number WITH =, 
        validity_period WITH &&
    ) WITH (fillfactor = 90)
);

CREATE TABLE core.policy_coverages (
    coverage_id UUID DEFAULT gen_random_uuid(),
    policy_id UUID NOT NULL,
    coverage_type VARCHAR(50) NOT NULL,
    limit_amount DECIMAL(15,2) NOT NULL,
    deductible_amount DECIMAL(15,2) NOT NULL,
    validity_period tstzrange NOT NULL,
    EXCLUDE USING GIST (
        policy_id WITH =,
        coverage_type WITH =,
        validity_period WITH &&
    )
);

CREATE INDEX idx_policies_validity ON core.policies USING GIST (validity_period);

CREATE TABLE finance.claims (
    claim_id UUID NOT NULL DEFAULT gen_random_uuid(),
    policy_id UUID NOT NULL,
    policy_version_id UUID NOT NULL REFERENCES core.policies(policy_version_id),
    incident_date TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    idempotency_key UUID NOT NULL,
    status VARCHAR(20) DEFAULT 'OPEN',
    estimated_loss_amount DECIMAL(15,2),
    estimated_loss_currency currency_code_enum NOT NULL,
    approved_amount DECIMAL(15,2),
    rejection_reason TEXT,
    PRIMARY KEY (claim_id, created_at),
    CONSTRAINT uq_claims_idempotency UNIQUE (idempotency_key, created_at)
) PARTITION BY RANGE (created_at);

CREATE INDEX idx_claims_incident_date ON finance.claims (incident_date);

CREATE TABLE finance.claims_y2024m01 PARTITION OF finance.claims
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE audit.change_logs (
    log_id UUID DEFAULT gen_random_uuid(),
    table_name VARCHAR(50) NOT NULL,
    record_id UUID NOT NULL,
    operation VARCHAR(10) NOT NULL,
    changed_by VARCHAR(100) NOT NULL DEFAULT 'system',
    changed_at TIMESTAMPTZ DEFAULT NOW(),
    changes JSONB,
    PRIMARY KEY (log_id, changed_at)
) PARTITION BY RANGE (changed_at);

CREATE TABLE audit.change_logs_y2024m01 PARTITION OF audit.change_logs
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE INDEX idx_audit_changes_gin ON audit.change_logs USING GIN (changes);

CREATE TABLE sys.transactional_outbox (
    event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    correlation_id UUID NOT NULL,
    aggregate_type VARCHAR(50) NOT NULL,
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    payload JSONB NOT NULL,
    region_code VARCHAR(5) NOT NULL,
    occurred_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMPTZ NULL
) PARTITION BY RANGE (occurred_at);

CREATE INDEX idx_outbox_unprocessed ON sys.transactional_outbox (occurred_at) 
WHERE processed_at IS NULL;

CREATE TABLE sys.transactional_outbox_default PARTITION OF sys.transactional_outbox DEFAULT;

CREATE OR REPLACE FUNCTION utils.jsonb_diff_val(val1 JSONB, val2 JSONB)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
    v RECORD;
BEGIN
    result = val2;
    FOR v IN SELECT * FROM jsonb_each(val1) LOOP
        IF result @> jsonb_build_object(v.key, v.value) THEN
            result = result - v.key;
        ELSIF result ? v.key THEN
            CONTINUE;
        END IF;
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql PARALLEL SAFE IMMUTABLE;

CREATE OR REPLACE FUNCTION audit.log_changes_trigger()
RETURNS TRIGGER AS $$
DECLARE
    json_old JSONB;
    json_new JSONB;
    json_diff JSONB;
    rec_id UUID;
BEGIN
    IF (TG_TABLE_NAME = 'policies') THEN
        IF TG_OP = 'DELETE' THEN rec_id := OLD.policy_version_id;
        ELSE rec_id := NEW.policy_version_id; END IF;
    ELSIF (TG_TABLE_NAME = 'customers_pii') THEN
         IF TG_OP = 'DELETE' THEN rec_id := OLD.customer_id;
         ELSE rec_id := NEW.customer_id; END IF;
    ELSE
        BEGIN
            IF TG_OP = 'DELETE' THEN rec_id := OLD.id;
            ELSE rec_id := NEW.id; END IF;
        EXCEPTION WHEN OTHERS THEN
            rec_id := '00000000-0000-0000-0000-000000000000'::uuid; 
        END;
    END IF;

    IF (TG_OP = 'DELETE') THEN
        json_diff := to_jsonb(OLD);
    ELSE
        IF (TG_OP = 'INSERT') THEN
            json_diff := to_jsonb(NEW);
        ELSIF (TG_OP = 'UPDATE') THEN
            json_old := to_jsonb(OLD);
            json_new := to_jsonb(NEW);
            json_diff := utils.jsonb_diff_val(json_old, json_new);
            IF json_diff = '{}'::jsonb THEN RETURN NEW; END IF;
        END IF;
    END IF;

    INSERT INTO audit.change_logs (
        table_name, record_id, operation, changed_by, changes
    ) VALUES (
        TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME, rec_id, TG_OP,
        COALESCE(current_setting('app.current_user', true), 'system'), json_diff
    );
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_policies
AFTER INSERT OR UPDATE OR DELETE ON core.policies
FOR EACH ROW EXECUTE FUNCTION audit.log_changes_trigger();