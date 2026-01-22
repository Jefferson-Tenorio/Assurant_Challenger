CREATE TABLE core.policies (
    policy_version_id UUID PRIMARY KEY, -- UUIDv7 vindo da App
    policy_number VARCHAR(50) NOT NULL,
    customer_id UUID NOT NULL REFERENCES access.customers_pii(customer_id),
    idempotency_key VARCHAR(100),
    validity_period tstzrange NOT NULL,
    status VARCHAR(20) CHECK (status IN ('ACTIVE', 'SUSPENDED', 'CANCELLED')),
    product_code VARCHAR(50) NOT NULL,
    risk_attributes JSONB NOT NULL,
    version_id BIGINT DEFAULT 1,

    -- PERFORMANCE: Fillfactor 90 deixa 10% da página vazia para updates futuros
    -- evitando page splits imediatos em inserções concorrentes.
    EXCLUDE USING GIST (
        policy_number WITH =, 
        validity_period WITH &&
    ) WITH (fillfactor = 90)
);

CREATE TABLE core.policy_coverages (
    coverage_id UUID DEFAULT gen_random_uuid(),
    policy_id UUID NOT NULL, -- FK Lógica (Não enforcei FK física para performance em batch, mas cuidado)
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
