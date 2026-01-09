# ==============================================================================
# SETUP SCRIPT - ASSURANT CHALLENGER
# Working directory context: src\infrastructure
# ==============================================================================

# Definição de Credenciais (Ajuste conforme seu docker-compose)
$DB_USER = "admin_user"
$DB_PASSWORD = "secure_pass_123"

Write-Host "--- INICIANDO CONFIGURAÇÃO DO AMBIENTE ---" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# 1. POSTGRESQL SETUP
# ------------------------------------------------------------------------------
Write-Host "1. Configurando PostgreSQL (Core)..." -ForegroundColor Yellow

# Copy SQL files into the running Postgres container
docker cp ../database/01_store_procedure.sql insurance-core-postgres:/tmp/01_store_procedure.sql
docker cp ../database/02_seed_data.sql insurance-core-postgres:/tmp/02_seed_data.sql
docker cp ../database/03_setup_data_stress.sql insurance-core-postgres:/tmp/03_setup_data_stress.sql

# Execute SQL scripts
docker exec -i insurance-core-postgres sh -c "psql -U $DB_USER -d insurance_core_db -f /tmp/01_store_procedure.sql"
docker exec -i insurance-core-postgres sh -c "psql -U $DB_USER -d insurance_core_db -f /tmp/02_seed_data.sql"
docker exec -i insurance-core-postgres sh -c "psql -U $DB_USER -d insurance_core_db -f /tmp/03_setup_data_stress.sql"

# ------------------------------------------------------------------------------
# 2. CLICKHOUSE SETUP
# ------------------------------------------------------------------------------
Write-Host "2. Configurando ClickHouse (Analytics)..." -ForegroundColor Yellow

# Copy ClickHouse setup SQL into the container
docker cp ../database/04_clickhouse_table_gemini.sql insurance-clickhouse:/var/lib/clickhouse/04_clickhouse_table_gemini.sql

# Execute the SQL using clickhouse-client inside the container
# Note: --multiquery allows running a file with multiple SQL statements
docker exec -i insurance-clickhouse sh -c "clickhouse-client --multiquery --queries-file /var/lib/clickhouse/04_clickhouse_table_gemini.sql"

if ($LASTEXITCODE -eq 0) {
    Write-Host "   ClickHouse configurado com sucesso." -ForegroundColor Green
} else {
    Write-Host "   Erro ao configurar ClickHouse." -ForegroundColor Red
}


# ------------------------------------------------------------------------------
# 4. STRESS TEST (Opcional)
# ------------------------------------------------------------------------------
Write-Host "4. Gerando Carga de Teste (Stress Load)..." -ForegroundColor Yellow

# Gera 10 transações para popular o Outbox -> Kafka -> ClickHouse
docker exec -i insurance-core-postgres sh -c "psql -U $DB_USER -d insurance_core_db -c 'CALL sys.sp_generate_stress_load(10, NULL);'"

Write-Host "--- SETUP CONCLUÍDO ---" -ForegroundColor Cyan