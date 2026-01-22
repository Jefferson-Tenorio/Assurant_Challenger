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
    
    -- PK Composta obrigatória para particionamento
    PRIMARY KEY (claim_id, created_at),
    
    -- Constraint "Soft": A garantia real de idempotência será via Redis (conforme sua decisão)
    CONSTRAINT uq_claims_idempotency UNIQUE (idempotency_key, created_at)
) PARTITION BY RANGE (created_at);

-- Índices nas tabelas particionadas
CREATE INDEX idx_claims_incident_date ON finance.claims (incident_date);

-- Partição Inicial
CREATE TABLE finance.claims_y2024m01 PARTITION OF finance.claims
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');