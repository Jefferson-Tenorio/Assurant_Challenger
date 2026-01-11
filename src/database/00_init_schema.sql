-- DESCRIPTION: Initial database structure (DDL), partitioning, security (RLS), and CDC.
-- 1. INITIAL SETTINGS AND EXTENSIONS

CREATE SCHEMA IF NOT EXISTS vault;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS billing;
CREATE SCHEMA IF NOT EXISTS sys;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enumerated types
CREATE TYPE policy_status AS ENUM ('QUOTE', 'ISSUED', 'ACTIVE', 'CANCELLED', 'EXPIRED');
CREATE TYPE claim_status AS ENUM ('OPEN', 'IN_REVIEW', 'APPROVED', 'REJECTED', 'PAID');
CREATE TYPE payment_status AS ENUM ('PENDING', 'PAID', 'FAILED', 'REFUNDED');

-- 2. TABLE CREATION (DEPENDENCY ORDER IS CRITICAL)
-- 2.1. VAULT (SENSITIVE DATA - DEPENDENCY LEVEL 0)
CREATE TABLE vault.customer_pii (
    pii_token UUID NOT NULL,
    full_name_enc BYTEA NOT NULL,
    tax_id_enc  BYTEA NOT NULL,    -- CPF/TaxID encrypted
    email_enc BYTEA,
    date_of_birth DATE,
    region_code VARCHAR(5) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    anonymized_at TIMESTAMP WITH TIME ZONE, -- Para "Right to be forgotten"
    retention_until TIMESTAMP WITH TIME ZONE, -- Purga automática (ILM)
    PRIMARY KEY (pii_token, region_code) 
) PARTITION BY LIST (region_code);

-- Partitions
CREATE TABLE vault.customer_pii_br PARTITION OF vault.customer_pii FOR VALUES IN ('BR');
CREATE TABLE vault.customer_pii_us PARTITION OF vault.customer_pii FOR VALUES IN ('US');
CREATE TABLE vault.customer_pii_eu PARTITION OF vault.customer_pii FOR VALUES IN ('EU');


-- 2.2. CORE POLICIES (LEVEL 1 - DEPENDS ON VAULT)
CREATE TABLE core.policies (
    policy_id UUID NOT NULL,
    pii_token UUID NOT NULL,
    region_code VARCHAR(5) NOT NULL,
    product_code VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    fraud_risk_score FLOAT DEFAULT 0.0,
    last_fraud_check TIMESTAMP WITH TIME ZONE,
    PRIMARY KEY (policy_id, region_code),
    FOREIGN KEY (pii_token, region_code) REFERENCES vault.customer_pii (pii_token, region_code)
) PARTITION BY LIST (region_code);

-- Partitions
CREATE TABLE core.policies_br PARTITION OF core.policies FOR VALUES IN ('BR');
CREATE TABLE core.policies_us PARTITION OF core.policies FOR VALUES IN ('US');
CREATE TABLE core.policies_eu PARTITION OF core.policies FOR VALUES IN ('EU');


-- 2.3. POLICY VERSIONS (LEVEL 2 - DEPENDS ON POLICIES)
CREATE TABLE core.policy_versions (
    version_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    policy_id UUID NOT NULL,
    region_code VARCHAR(5) NOT NULL,
    status policy_status NOT NULL,
    premium_amount DECIMAL(18, 2) NOT NULL,
    coverage_limit DECIMAL(18, 2) NOT NULL,

    valid_from TIMESTAMP WITH TIME ZONE NOT NULL,
    valid_to TIMESTAMP WITH TIME ZONE NOT NULL,

    system_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    superseded_at TIMESTAMP WITH TIME ZONE,

    metadata JSONB,
    version_number INT NOT NULL,

    PRIMARY KEY (version_id, region_code),
    FOREIGN KEY (policy_id, region_code) REFERENCES core.policies (policy_id, region_code)
) PARTITION BY LIST (region_code);

-- Partitions
CREATE TABLE core.policy_versions_br PARTITION OF core.policy_versions FOR VALUES IN ('BR');
CREATE TABLE core.policy_versions_us PARTITION OF core.policy_versions FOR VALUES IN ('US');
CREATE TABLE core.policy_versions_eu PARTITION OF core.policy_versions FOR VALUES IN ('EU');


-- 2.4. BILLING (LEVEL 2 - DEPENDS ON POLICIES)
CREATE TABLE billing.installments (
    installment_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    policy_id UUID NOT NULL,
    region_code VARCHAR(5) NOT NULL,
    amount DECIMAL(18,2) NOT NULL,
    due_date DATE NOT NULL,
    payment_method VARCHAR(20),
    transaction_ref TEXT,
    status payment_status NOT NULL DEFAULT 'PENDING',
    PRIMARY KEY (installment_id, region_code),
    FOREIGN KEY (policy_id, region_code) REFERENCES core.policies (policy_id, region_code)
) PARTITION BY LIST (region_code);

-- Partitions
CREATE TABLE billing.installments_br PARTITION OF billing.installments FOR VALUES IN ('BR');
CREATE TABLE billing.installments_us PARTITION OF billing.installments FOR VALUES IN ('US');
CREATE TABLE billing.installments_eu PARTITION OF billing.installments FOR VALUES IN ('EU');


-- 2.5. CLAIMS (LEVEL 2 - DEPENDS ON POLICIES)
CREATE TABLE core.claims (
    claim_id UUID NOT NULL,
    policy_id UUID NOT NULL,
    region_code VARCHAR(5) NOT NULL,
    incident_date TIMESTAMP WITH TIME ZONE NOT NULL,
    reported_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    estimated_payout DECIMAL(18, 2),
    actual_payout DECIMAL(18, 2),
    
    idempotency_key TEXT,
    -- Composite unique constraint to support partitioning
    UNIQUE (idempotency_key, region_code),
    
    metadata JSONB,
    status claim_status DEFAULT 'OPEN',
    PRIMARY KEY (claim_id, region_code),
    FOREIGN KEY (policy_id, region_code) REFERENCES core.policies (policy_id, region_code)
) PARTITION BY LIST (region_code);

-- Partitions
CREATE TABLE core.claims_br PARTITION OF core.claims FOR VALUES IN ('BR');
CREATE TABLE core.claims_us PARTITION OF core.claims FOR VALUES IN ('US');
CREATE TABLE core.claims_eu PARTITION OF core.claims FOR VALUES IN ('EU');


-- 2.6. TRANSACTIONAL OUTBOX (INFRASTRUCTURE)
CREATE TABLE sys.transactional_outbox (
    event_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    correlation_id UUID NOT NULL, 
    saga_step VARCHAR(100),
    aggregate_type VARCHAR(50) NOT NULL,
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    payload JSONB NOT NULL,
    trace_parent TEXT, 
    region_code VARCHAR(5) NOT NULL,
    occurred_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_outbox_unprocessed ON sys.transactional_outbox (processed_at) WHERE processed_at IS NULL;


-- 3. SECURITY: ROW LEVEL SECURITY (RLS)

-- Enable RLS on parent tables
ALTER TABLE core.policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault.customer_pii ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.installments ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.policy_versions ENABLE ROW LEVEL SECURITY;

-- Enable RLS on partitions (best practice to ensure correct cascading)
-- BR
ALTER TABLE core.policies_br ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault.customer_pii_br ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.installments_br ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.claims_br ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.policy_versions_br ENABLE ROW LEVEL SECURITY;
-- US
ALTER TABLE core.policies_us ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault.customer_pii_us ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.installments_us ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.claims_us ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.policy_versions_us ENABLE ROW LEVEL SECURITY;
-- EU
ALTER TABLE core.policies_eu ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault.customer_pii_eu ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.installments_eu ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.claims_eu ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.policy_versions_eu ENABLE ROW LEVEL SECURITY;

-- CREATION OF ACCESS POLICIES
-- Note: Policies are defined on the parent and should be replicated to children or inherited.
-- We apply them explicitly here to ensure robustness.

-- Policies for Core Policies
CREATE POLICY regional_isolation ON core.policies
    FOR ALL USING (region_code = current_setting('app.current_region', true));
CREATE POLICY regional_isolation ON core.policies_br
    FOR ALL USING (region_code = current_setting('app.current_region', true));
CREATE POLICY regional_isolation ON core.policies_us
    FOR ALL USING (region_code = current_setting('app.current_region', true));
CREATE POLICY regional_isolation ON core.policies_eu
    FOR ALL USING (region_code = current_setting('app.current_region', true));

-- Policies for Vault
CREATE POLICY regional_isolation ON vault.customer_pii
    FOR ALL USING (region_code = current_setting('app.current_region', true));
CREATE POLICY regional_isolation ON vault.customer_pii_br
    FOR ALL USING (region_code = current_setting('app.current_region', true));
CREATE POLICY regional_isolation ON vault.customer_pii_us
    FOR ALL USING (region_code = current_setting('app.current_region', true));
CREATE POLICY regional_isolation ON vault.customer_pii_eu
    FOR ALL USING (region_code = current_setting('app.current_region', true));

-- Policies for Billing
CREATE POLICY regional_isolation ON billing.installments
    FOR ALL USING (region_code = current_setting('app.current_region', true));
CREATE POLICY regional_isolation ON billing.installments_br
    FOR ALL USING (region_code = current_setting('app.current_region', true));
CREATE POLICY regional_isolation ON billing.installments_us
    FOR ALL USING (region_code = current_setting('app.current_region', true));
CREATE POLICY regional_isolation ON billing.installments_eu
    FOR ALL USING (region_code = current_setting('app.current_region', true));

-- Policies for Claims
CREATE POLICY regional_isolation ON core.claims
    FOR ALL USING (region_code = current_setting('app.current_region', true));
CREATE POLICY regional_isolation ON core.claims_br
    FOR ALL USING (region_code = current_setting('app.current_region', true));
CREATE POLICY regional_isolation ON core.claims_us
    FOR ALL USING (region_code = current_setting('app.current_region', true));
CREATE POLICY regional_isolation ON core.claims_eu
    FOR ALL USING (region_code = current_setting('app.current_region', true));

-- Policies for Policy Versions
CREATE POLICY regional_isolation ON core.policy_versions
    FOR ALL USING (region_code = current_setting('app.current_region', true));
CREATE POLICY regional_isolation ON core.policy_versions_br
    FOR ALL USING (region_code = current_setting('app.current_region', true));
CREATE POLICY regional_isolation ON core.policy_versions_us
    FOR ALL USING (region_code = current_setting('app.current_region', true));
CREATE POLICY regional_isolation ON core.policy_versions_eu
    FOR ALL USING (region_code = current_setting('app.current_region', true));


-- 4. CDC CONFIGURATION (DEBEZIUM)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'debezium_user') THEN
        CREATE ROLE debezium_user WITH LOGIN PASSWORD 'secret_insurance_pass' REPLICATION IN ROLE pg_read_all_data;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA sys TO debezium_user;
GRANT SELECT ON sys.transactional_outbox TO debezium_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA sys TO debezium_user;

-- Allow Debezium to bypass RLS on the Outbox table
ALTER TABLE sys.transactional_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE sys.transactional_outbox FORCE ROW LEVEL SECURITY;

CREATE POLICY debezium_bypass_outbox ON sys.transactional_outbox
FOR SELECT TO debezium_user USING (true);

-- Replica identity
ALTER TABLE sys.transactional_outbox REPLICA IDENTITY FULL;

-- Publication (check for existence to avoid errors)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'debezium_pub') THEN
        CREATE PUBLICATION debezium_pub FOR TABLE sys.transactional_outbox;
    END IF;
END
$$;

-- Trigger for automatic update (Optional, depends on ACK strategy)
CREATE OR REPLACE FUNCTION mark_outbox_processed()
RETURNS TRIGGER AS $$
BEGIN
  NEW.processed_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_mark_outbox_processed
BEFORE UPDATE ON sys.transactional_outbox
FOR EACH ROW
EXECUTE FUNCTION mark_outbox_processed();

-- 5. FINAL SYSTEM ADJUSTMENTS
-- =======================================================================================
-- NOTE: In production, setting 'synchronous_commit = off' improves performance but risks
-- data loss on an OS crash. For the Zero Data Loss objective, 'on' or 'local' is preferable.
-- Keeping 'off' as in the original script for load-testing purposes only.
ALTER SYSTEM SET synchronous_commit = off;
SELECT pg_reload_conf();
-- hi git hub.