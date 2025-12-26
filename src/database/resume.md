
# Database Folder — Summary

This file summarizes the SQL scripts present in the `src/database/` folder, explains their purposes, and lists important notes for running them in a local or CI environment.

Files
- `00_init_schema.sql` — Core schema DDL: schemas, tables, partitions, RLS policies, `sys.transactional_outbox`, Debezium publication and necessary extensions. Comments translated into English. No behavior changes.
- `01_store_procedure.sql` — Stored procedures and functions: `uuid_generate_v7()` polyfill, `core.fn_register_claim` (idempotent claim registration with bi-temporal validation and transactional outbox), and `core.sp_seed_mock_policy` helper. Comments translated and clarified.
- `02_seed_data.sql` — Demo seed data for BR/US/EU scenarios (vaulted PII entries, policies, versions, billing). Includes cleanup and final validation query. Uses a demo symmetric key; in production use Vault.
- `03_setup_data_stress.sql` — Stress/chaos workload procedure `sys.sp_generate_stress_load(p_iterations, p_force_region)` that inserts synthetic policies, vault entries and outbox events to exercise CPU, I/O and the event pipeline.
- `04_setup_click_house.sql` — ClickHouse analytics setup: `analytics.events_history` target table, `analytics.kafka_stream` Kafka-engine table, and `analytics.mv_kafka_to_history` materialized view parsing Debezium "after" envelope into normalized columns.

Quick Notes & Running
- Run order (recommended):
	1. `00_init_schema.sql` — create schemas and extensions.
	2. `01_store_procedure.sql` — install functions/stored procedures.
	3. `02_seed_data.sql` — seed demo data.
	4. Optionally call `CALL sys.sp_generate_stress_load(...)` or run `03_setup_data_stress.sql` for load.
	5. `04_setup_click_house.sql` — apply ClickHouse schema and materialized views (after event-bus is available).

- Execution: scripts are copied into containers by `src/infrastructure/run_db_setup.ps1` and executed via `docker exec` (adjust for your environment). Debezium connector registration scripts are in `src/infrastructure/`.

Important Implementation Notes
- Transactional Outbox: the Postgres outbox table (`sys.transactional_outbox`) and the trigger/process guarantee atomic write + outbox row. Debezium reads the WAL and publishes events to Redpanda.
- Bi-temporal checks: `core.fn_register_claim` validates business-time (`valid_from`/`valid_to`) to ensure claims were within coverage at the incident time.
- RLS & `app.current_region`: several scripts set session config (`set_config('app.current_region', ...)`) to simulate Row-Level Security scoping. In production, ensure RLS policies and session propagation are correctly configured.
- UUID v7 polyfill: provided for better insert locality; replace with native UUID v7 when the database supports it.
- Secrets: seed and demo scripts use a local symmetric key for PGP encryption only for demos. Use HashiCorp Vault (service included in `docker-compose.yml`) for production secrets.

