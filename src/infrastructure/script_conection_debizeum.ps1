$url = "http://localhost:8083/connectors"
$name = "insurance-outbox-connector"

# 1. Remove previous connector if it exists (idempotent reset)
try { 
    Invoke-RestMethod -Uri "$url/$name" -Method Delete -ErrorAction SilentlyContinue 
    Start-Sleep -Seconds 2
} catch {}

# 2. Connector configuration (JSON)
# NOTE: credentials here are sample values for local dev; use environment variables or Vault in production
$body = @{
    name = $name
    config = @{
        "connector.class"      = "io.debezium.connector.postgresql.PostgresConnector"
        "database.hostname"    = "transactional-db"
        "database.port"        = "5432"
        "database.user"        = "admin_user"
        "database.password"    = "secure_pass_123"
        "database.dbname"      = "insurance_core_db"
        "database.server.name" = "insurance_server"
        "plugin.name"          = "pgoutput"
        "publication.name"     = "debezium_pub"
        "table.include.list"   = "sys.transactional_outbox"
        "topic.prefix"         = "insurance"
        "slot.name"            = "insurance_outbox_slot"
        "tombstones.on.delete" = "false"
        "snapshot.mode"        = "never"
    }
} | ConvertTo-Json -Depth 5

# 3. Create the connector via Kafka Connect REST API
Write-Host "Creating Debezium connector..."
Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json" | Out-Null

# 4. Wait briefly and show connector status (connector + task state).
Start-Sleep -Seconds 2
Write-Host "Connector status:"
$status = Invoke-RestMethod -Uri "$url/$name/status"

# Show key status fields only: connector state and first task state.
@{
    Connector = $status.connector.state
    Task      = $status.tasks[0].state
    Trace     = $status.tasks[0].trace # Present only if there is an error
} | Format-List