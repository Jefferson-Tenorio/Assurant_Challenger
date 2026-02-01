CREATE TABLE finance.claims (
    claim_id UUID NOT NULL DEFAULT uuid_generate_v7(),
    
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

CREATE TABLE finance.claims_y2026m01 PARTITION OF finance.claims
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

CREATE TABLE finance.claims_default PARTITION OF finance.claims DEFAULT;


-- Criando um índice de exclusão para evitar dois sinistros 
-- da mesma apólice no mesmo dia (usando a data truncada)
--CREATE UNIQUE INDEX uq_one_claim_per_day 
--ON finance.claims (policy_id, date_trunc('day', incident_date));

-- TODO: "Nossa arquitetura lida com isso em duas camadas. Primeiro, a Idempotência Técnica (Portão 1) garante que falhas de rede não gerem duplicidade de um mesmo request. Segundo, a Integridade de Negócio (Portão 2) pode ser configurada via Constraints no banco para impedir sinistros sobrepostos no tempo para a mesma apólice, utilizando índices únicos sobre o truncamento da data do incidente. Isso protege o caixa da Assurant contra erros de aplicação ou tentativas de fraude."