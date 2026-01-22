#!/bin/bash

# ==============================================================================
# SETUP SCRIPT - ASSURANT CHALLENGER (LINUX VERSION)
# Contexto: Executar dentro de src/infrastructure
# ==============================================================================

# Definição de Cores para o Terminal
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color (Reset)

# Definição de Credenciais
# Dica: Em produção, estas variáveis viriam de um arquivo .env ou Vault
DB_USER="admin_user"
DB_PASSWORD="secure_pass_123"

echo -e "${CYAN}--- INICIANDO CONFIGURAÇÃO DO AMBIENTE (LINUX) ---${NC}"

# ------------------------------------------------------------------------------
# 1. POSTGRESQL SETUP
# ------------------------------------------------------------------------------
echo -e "${YELLOW}1. Configurando PostgreSQL (Core)...${NC}"

# Copiando arquivos SQL para dentro do container
# O comando 'docker cp' funciona igual ao Windows
docker cp ../database/01_store_procedure.sql insurance-core-postgres:/tmp/01_store_procedure.sql
docker cp ../database/02_seed_data.sql insurance-core-postgres:/tmp/02_seed_data.sql
docker cp ../database/03_setup_data_stress.sql insurance-core-postgres:/tmp/03_setup_data_stress.sql

# Executando os scripts via psql
# Usamos -i (interactive) e passamos o comando. 
# O comando psql precisa do usuário e banco.
docker exec -i insurance-core-postgres sh -c "psql -U $DB_USER -d insurance_core_db -f /tmp/01_store_procedure.sql"
docker exec -i insurance-core-postgres sh -c "psql -U $DB_USER -d insurance_core_db -f /tmp/02_seed_data.sql"
docker exec -i insurance-core-postgres sh -c "psql -U $DB_USER -d insurance_core_db -f /tmp/03_setup_data_stress.sql"

# ------------------------------------------------------------------------------
# 2. CLICKHOUSE SETUP
# ------------------------------------------------------------------------------
echo -e "${YELLOW}2. Configurando ClickHouse (Analytics)...${NC}"

docker cp ../database/04_init_clickhouse_table.sql insurance-clickhouse:/var/lib/clickhouse/04_clickhouse_table_gemini.sql

# Execução no Clickhouse
docker exec -i insurance-clickhouse sh -c "clickhouse-client --multiquery --queries-file /var/lib/clickhouse/04_clickhouse_table_gemini.sql"

# Verificando se o último comando (ClickHouse) deu erro
if [ $? -eq 0 ]; then
    echo -e "${GREEN}   ClickHouse configurado com sucesso.${NC}"
else
    echo -e "${RED}   Erro ao configurar Clickhouse.${NC}"
    exit 1
fi

# -----------------------------------------------------------------------------
# 3. STRESS TEST
# ------------------------------------------------------------------------------
echo -e "${YELLOW}3. Gerando Carga de Teste (Stress Load)...${NC}"

# Chamada de Procedure no Postgres
docker exec -i insurance-core-postgres sh -c "psql -U $DB_USER -d insurance_core_db -c \"CALL sys.sp_generate_stress_load(10, NULL);\""

echo -e "${CYAN}--- SETUP CONCLUÍDO ---${NC}"