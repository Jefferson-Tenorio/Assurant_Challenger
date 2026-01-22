-- ============================================================================
-- 7. CONFIGURAÇÃO CDC (DEBEZIUM) - SETUP DE REPLICAÇÃO
-- ============================================================================
-- TODO: Integrar tudo para depositar em analytcs, todas as tabelas.
-- TODO: admin e senha devem ser alterados em produção para algo seguro!
-- 7.1. Criação do Usuário de Replicação
-- Verificamos se existe para evitar erro em re-execução
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'debezium_user') THEN
        CREATE ROLE debezium_user WITH REPLICATION LOGIN PASSWORD 'admin';
    END IF;
END
$$;

-- 7.2. Permissões Granulares (Least Privilege)
-- O Debezium precisa ver o schema e ler a tabela para fazer o "Snapshot Inicial"
GRANT USAGE ON SCHEMA sys TO debezium_user;
GRANT SELECT ON sys.transactional_outbox TO debezium_user;

-- IMPORTANTE: Como a tabela é particionada, garantimos acesso nas filhas (boa prática)
GRANT SELECT ON ALL TABLES IN SCHEMA sys TO debezium_user;

-- 7.3. Configuração da Tabela para CDC
-- REPLICA IDENTITY DEFAULT: Grava apenas a PK no WAL em updates/deletes.
-- O 'FULL' que você usava grava a linha inteira antiga. Isso dobra o tamanho do seu WAL
-- e causa I/O desnecessário. Como temos PK (event_id), DEFAULT é o correto.
ALTER TABLE sys.transactional_outbox REPLICA IDENTITY DEFAULT;

-- 7.4. Criação da Publicação
-- O Postgres 13+ permite publicar a tabela particionada "Pai".
-- O parâmetro 'publish_via_partition_root' garante que o Debezium receba o evento
-- com o nome da tabela pai 'sys.transactional_outbox' e não 'sys.transactional_outbox_default'.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'dbz_outbox_pub') THEN
        CREATE PUBLICATION dbz_outbox_pub FOR TABLE sys.transactional_outbox
        WITH (publish_via_partition_root = true);
    END IF;
END
$$;