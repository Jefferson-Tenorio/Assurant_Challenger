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

DROP TABLE IF EXISTS sys.transactional_outbox CASCADE;

CREATE TABLE sys.transactional_outbox (
    -- ID Único do Evento
    event_id UUID NOT NULL DEFAULT uuid_generate_v7(),
    
    -- ID para rastreamento (OpenTelemetry/Tracing)
    correlation_id UUID NOT NULL,
    
    -- Dados do Evento
    aggregate_type VARCHAR(50) NOT NULL, -- ex: 'CLAIM'
    aggregate_id UUID NOT NULL,          -- ex: ID do Sinistro
    event_type VARCHAR(50) NOT NULL,     -- ex: 'CLAIM_CREATED'
    payload JSONB NOT NULL,
    
    -- Metadados de Infraestrutura Global
    region_code VARCHAR(5) NOT NULL,     -- ex: 'BR' ou 'US'
    occurred_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    
    -- PK composta necessária para o particionamento
    PRIMARY KEY (event_id, occurred_at)
) PARTITION BY RANGE (occurred_at);

-- Criar partição padrão para não dar erro no primeiro INSERT
CREATE TABLE sys.transactional_outbox_default PARTITION OF sys.transactional_outbox DEFAULT;