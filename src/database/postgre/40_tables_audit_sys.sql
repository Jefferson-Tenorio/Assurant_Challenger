-- =============================================================================
-- 1. INFRAESTRUTURA DE SISTEMA
-- =============================================================================

-- Tabela de Heartbeat (Usada para manter o slot de replicação ativo e saudável)
CREATE TABLE IF NOT EXISTS sys.heartbeat (
    id int PRIMARY KEY,
    ts timestamptz
);

-- =============================================================================
-- 2. AUDITORIA (LOGS DE MUDANÇA)
-- =============================================================================

CREATE TABLE audit.change_logs (
    log_id UUID DEFAULT uuid_generate_v7(),
    table_name VARCHAR(50) NOT NULL,
    record_id UUID NOT NULL,
    operation VARCHAR(10) NOT NULL,
    changed_by VARCHAR(100) NOT NULL DEFAULT 'system',
    changed_at TIMESTAMPTZ DEFAULT NOW(),
    changes JSONB, -- Armazena apenas o DIFF
    
    PRIMARY KEY (log_id, changed_at)
) PARTITION BY RANGE (changed_at);

-- Partição Inicial de Auditoria
CREATE TABLE audit.change_logs_y2026m01 PARTITION OF audit.change_logs
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

CREATE INDEX idx_audit_changes_gin ON audit.change_logs USING GIN (changes);

-- =============================================================================
-- 3. TRANSACTIONAL OUTBOX (O Coração do Event-Driven)
-- =============================================================================

-- TODO: retirei  a partição, mas deveria colocar ela no futuro?
-- .. (Criação da tabela pai sys.transactional_outbox continua igual) ...
CREATE TABLE sys.transactional_outbox (
    id uuid DEFAULT uuid_generate_v7() PRIMARY KEY,
    aggregate_type varchar(255) NOT NULL,
    aggregate_id varchar(255) NOT NULL,
    type varchar(255) NOT NULL,
    payload jsonb NOT NULL,
    created_at timestamptz DEFAULT NOW()
);
-- 1. CRIAR AS PARTIÇÕES PRIMEIRO
-- CREATE TABLE sys.transactional_outbox_default 
--    PARTITION OF sys.transactional_outbox DEFAULT;

-- CREATE TABLE sys.transactional_outbox_y2026 
--    PARTITION OF sys.transactional_outbox 
--    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');

-- 2. APLICAR O TUNING NAS PARTIÇÕES FÍSICAS
-- Agora sim: estamos configurando o arquivo físico no disco.

-- ALTER TABLE sys.transactional_outbox_default SET (
--     autovacuum_vacuum_scale_factor = 0.01,
--     autovacuum_vacuum_cost_limit = 1000
-- );

-- ALTER TABLE sys.transactional_outbox_y2026 SET (
--     autovacuum_vacuum_scale_factor = 0.01,
--     autovacuum_vacuum_cost_limit = 1000
--);

-- 3. PUBLICAR A TABELA PAI
-- O Debezium é inteligente o suficiente para ler a pai e descobrir as filhas.
-- CREATE PUBLICATION dbz_outbox_pub FOR TABLE sys.transactional_outbox;