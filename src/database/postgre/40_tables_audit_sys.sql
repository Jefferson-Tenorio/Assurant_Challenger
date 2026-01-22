
CREATE TABLE audit.change_logs (
    log_id UUID DEFAULT gen_random_uuid(),
    table_name VARCHAR(50) NOT NULL,
    record_id UUID NOT NULL,
    operation VARCHAR(10) NOT NULL,
    changed_by VARCHAR(100) NOT NULL DEFAULT 'system',
    changed_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Armazena apenas o DIFF (Economia de TOAST)
    changes JSONB, 
    
    PRIMARY KEY (log_id, changed_at)
) PARTITION BY RANGE (changed_at);

CREATE TABLE audit.change_logs_y2024m01 PARTITION OF audit.change_logs
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Indexação correta no JSONB 'changes'
CREATE INDEX idx_audit_changes_gin ON audit.change_logs USING GIN (changes);

-- TODO:     Mesmo particionada, a tabela transactional_outbox terá altíssima rotatividade (INSERT + UPDATE processed_at). Configure o Autovacuum para ser agressivo especificamente nela code SQL LTER TABLE sys.transactional_outbox SET ( autovacuum_vacuum_scale_factor = 0.01, -- Vacuum a cada 1% de mudanç     autovacuum_vacuum_cost_limit = 1000 );
CREATE TABLE sys.transactional_outbox (
    event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    correlation_id UUID NOT NULL, 
    aggregate_type VARCHAR(50) NOT NULL,
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    payload JSONB NOT NULL,
    region_code VARCHAR(5) NOT NULL,
    occurred_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    
    -- CORREÇÃO: Adicionada coluna processed_at para o Debezium/Worker atualizar
    processed_at TIMESTAMPTZ NULL 
) PARTITION BY RANGE (occurred_at);

-- Índice parcial para o Debezium pegar o que falta processar rápido
CREATE INDEX idx_outbox_unprocessed ON sys.transactional_outbox (occurred_at) 
WHERE processed_at IS NULL;

CREATE TABLE sys.transactional_outbox_default PARTITION OF sys.transactional_outbox DEFAULT;