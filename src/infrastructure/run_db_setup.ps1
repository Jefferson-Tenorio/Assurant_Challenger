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
# 3. DEBEZIUM (KAFKA CONNECT) SETUP
# ------------------------------------------------------------------------------
Write-Host "3. Configurando Conector Debezium..." -ForegroundColor Yellow

# URL do Kafka Connect
$ConnectUrl = "http://localhost:8083"

# Loop simples para esperar o Kafka Connect estar pronto (ele demora a subir)
Write-Host "   Aguardando Kafka Connect estar online em $ConnectUrl..."
$RetryCount = 0
while ($RetryCount -lt 30) {
    try {
        $null = Invoke-RestMethod -Uri "$ConnectUrl" -ErrorAction Stop
        Write-Host "   Kafka Connect está ONLINE!" -ForegroundColor Green
        break
    } catch {
        Start-Sleep -Seconds 2
        Write-Host -NoNewline "."
        $RetryCount++
    }
}

# Ler o JSON template e substituir as variáveis
$JsonPath = "insurance-outbox-connector.json" # Caminho relativo dentro de infrastructure/
if (Test-Path $JsonPath) {
    $JsonContent = Get-Content -Path $JsonPath -Raw
    
    # Substituição das variáveis de ambiente no JSON em memória
    $JsonContent = $JsonContent.Replace('${DB_USER}', $DB_USER)
    $JsonContent = $JsonContent.Replace('${DB_PASSWORD}', $DB_PASSWORD)

    # Enviar para a API
    try {
        $response = Invoke-RestMethod -Uri "$ConnectUrl/connectors" `
                                      -Method Post `
                                      -ContentType "application/json" `
                                      -Body $JsonContent
        Write-Host "   Conector registrado com sucesso!" -ForegroundColor Green
    } catch {
        # Erro 409 significa que já existe, não é um problema real
        if ($_.Exception.Response.StatusCode.value__ -eq 409) {
            Write-Host "   Conector já existia (ignorado)." -ForegroundColor Gray
        } else {
            Write-Error "   Falha ao criar conector: $_"
        }
    }
} else {
    Write-Warning "   Arquivo $JsonPath não encontrado. Pulei a etapa do Debezium."
}

# ------------------------------------------------------------------------------
# 4. STRESS TEST (Opcional)
# ------------------------------------------------------------------------------
Write-Host "4. Gerando Carga de Teste (Stress Load)..." -ForegroundColor Yellow

# Gera 10 transações para popular o Outbox -> Kafka -> ClickHouse
docker exec -i insurance-core-postgres sh -c "psql -U $DB_USER -d insurance_core_db -c 'CALL sys.sp_generate_stress_load(10, NULL);'"

Write-Host "--- SETUP CONCLUÍDO ---" -ForegroundColor Cyan