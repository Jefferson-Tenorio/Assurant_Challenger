# Working directory: src\infrastructure
# SQL scripts live in ../database

# Copy SQL files into the running Postgres container so they can be executed there
docker cp ../database/01_store_procedure.sql insurance-core-postgres:/tmp/01_store_procedure.sql
docker cp ../database/02_seed_data.sql insurance-core-postgres:/tmp/02_seed_data.sql
docker cp ../database/03_setup_data_stress.sql insurance-core-postgres:/tmp/03_setup_data_stress.sql

Write-Host "Configuring ClickHouse analytics..."
# Copy ClickHouse setup SQL into the ClickHouse container
docker cp ../database/04_setup_click_house.sql insurance-clickhouse:/var/lib/clickhouse/04_setup_clickhouse.sql


# Execute stored procedures and seed data inside Postgres container
docker exec -i insurance-core-postgres sh -c `
  "psql -U `$POSTGRES_USER -d `$POSTGRES_DB -f /tmp/01_store_procedure.sql"

docker exec -i insurance-core-postgres sh -c `
  "psql -U `$POSTGRES_USER -d `$POSTGRES_DB -f /tmp/02_seed_data.sql"

docker exec -i insurance-core-postgres sh -c `
  "psql -U `$POSTGRES_USER -d `$POSTGRES_DB -f /tmp/03_setup_data_stress.sql"

# Optionally run a small stress load to generate test traffic (adjust params as needed)
docker exec -i insurance-core-postgres sh -c `
  "psql -U `$POSTGRES_USER -d `$POSTGRES_DB -c 'CALL sys.sp_generate_stress_load(10, NULL);'"

# Run ClickHouse client to apply analytics schema and materialized views
docker exec -i insurance-clickhouse clickhouse-client --multiquery --queries-file /var/lib/clickhouse/04_setup_clickhouse.sql
Write-Host "ClickHouse configured successfully!"