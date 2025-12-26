  # AssurantChallenger — Professional Project Documentation

  Version: 1.0 — last updated: 2025-12-26

  This README is the authoritative, developer- and stakeholder-facing documentation for the AssurantChallenger prototype. It merges the implemented artifacts under `src/` with the challenge specification in `docs/Challenger.md`.

  Purpose: provide a clear, self-contained reference that explains what exists, why decisions were made, how to run and validate the prototype locally, and what remains to be implemented for production readiness.

  Table of Contents
  -----------------
- [AssurantChallenger — Professional Project Documentation](#assurantchallenger--professional-project-documentation)
  - [Table of Contents](#table-of-contents)
  - [Quick Summary](#quick-summary)
  - [Status \& Scope](#status--scope)
  - [Architecture Overview](#architecture-overview)
  - [Data Model \& Patterns](#data-model--patterns)
  - [Eventing — Outbox \& CDC Flow](#eventing--outbox--cdc-flow)
  - [Security \& Compliance](#security--compliance)
  - [Operational Runbook (Local \& CI)](#operational-runbook-local--ci)
  - [Testing, Validation \& Observability](#testing-validation--observability)
  - [Disaster Recovery \& Chaos Testing](#disaster-recovery--chaos-testing)
  - [Roadmap \& Future Work](#roadmap--future-work)
  - [Files of Interest \& Quick Links](#files-of-interest--quick-links)
  - [Contributing \& Contact](#contributing--contact)

  Quick Summary
  -------------

  - Goal: prototype a global, resilient insurance data platform that supports ACID transactional workloads and high-throughput analytics with data sovereignty, strong security, and near-zero data loss.
  - Implementation highlights (prototype): partitioned PostgreSQL schema with RLS, transactional outbox, Debezium publication, seed and stress scripts, and infrastructure scaffolding for local orchestration.

  Status & Scope
  ----------------

  Implemented (prototype):
  - Partitioned Postgres DDL with schemas: `vault`, `core`, `billing`, `sys`.
  - Enumerated domain types (`policy_status`, `claim_status`, `payment_status`).
  - Row-Level Security (RLS) policy definitions and explicit partition-level enabling.
  - `vault.customer_pii` with encrypted PII columns and tokenization via `pii_token`.
  - Core domain tables: `core.policies`, `core.policy_versions`, `core.claims` (partitioned by `region_code`).
  - Billing: `billing.installments` partitioned by `region_code`.
  - `sys.transactional_outbox` with unprocessed index, `REPLICA IDENTITY FULL`, Debezium publication and a `debezium_user` role with bypass SELECT policy.

  Documented / scaffolded (not fully wired in code):
  - ClickHouse ingestion DDL and Redpanda/Kafka integration notes (`src/database/04_setup_click_house.sql`.
  - Cassandra global index design (documented in `docs/Challenger.md`).
  - Vault/KMS integration described but not automated in `infrastructure/`.

  Architecture Overview
  ---------------------

  High level:

  - Polyglot persistence model:
    - PostgreSQL: transactional core and bi-temporal modeling (regional, ACID, RLS).
    - Cassandra (global index): masterless, quick lookups for home-region routing.
    - ClickHouse: columnar analytics engine for fraud and audit queries.
    - Redis: speed layer for hot data and caches.

  - Eventing pipeline:
    - Transactional outbox writes in Postgres → Debezium streams outbox changes → Redpanda/Kafka topics → downstream consumers (ClickHouse, services).

  - Multi-region model (design intent in docs):
    - Regions hold local Postgres instances with partitioned data by `region_code`.
    - Cassandra serves a global routing index to avoid broadcast searches.
    - Write routing: local writes preferred; cross-region writes handled via asynchronous replication and application-level conflict resolution for non-financial flows.

  Data Model & Patterns
  ---------------------

  Key modeling choices:

  - Bi-temporal modeling for policies: `valid_from`/`valid_to` (business time) and `system_at` (system time) for auditability and retroactive validation.
  - Partitioning by `region_code` to enforce data residency and optimize regional queries.
  - `vault.customer_pii` design: PII stored encrypted (BYTEA) with `pii_token` used by core tables; minimizes surface area of plaintext PII.
  - Composite keys and composite foreign keys include `region_code` to ensure region-scoped referential integrity and partition pruning.

  Patterns used:
  - Transactional Outbox: write event payloads in the same DB transaction as state changes to guarantee atomicity between DB state and events.
  - Idempotency keys: stored in claims (and in event payloads) to permit retry-safe operations and prevent duplicate payouts.

  Eventing — Outbox & CDC Flow
  ---------------------------

  Flow summary:

  1. Business operation (e.g., register claim) writes domain rows and an outbox row in a single transaction.
  2. Transaction commits to Postgres.
  3. Debezium, subscribed to the `debezium_pub` publication, captures the outbox change and produces an event to Redpanda/Kafka.
  4. Consumers (fraud, analytics, downstream systems) consume events and take action; consumers must be idempotent.

  Important implementation notes:
  - Outbox table is configured with `REPLICA IDENTITY FULL` to give CDC tools full row images.
  - A dedicated `debezium_user` with a `USING (true)` SELECT policy ensures CDC can read outbox rows despite RLS.
  - Consumers should use event schema versioning and Schema Registry for safe evolution.

  Security & Compliance
  ---------------------

  PII protection:
  - PII is only stored in `vault.customer_pii` encrypted at rest; application holds tokens.
  - Enforce strict access control to `vault` schema and use separate tablespaces for encrypted data in production.

  Row & Column level controls:
  - RLS enforces region isolation using `app.current_region` session setting.
  - Consider adding column-level masking or Postgres `pgcrypto` functions where needed.

  Secrets & Keys:
  - Integrate HashiCorp Vault or cloud KMS for encryption keys and connector secrets; do not store secrets in repo.

  Audit & Retention:
  - Use outbox events as the primary source for immutable audit trails; replicate events into ClickHouse/archival lake for compliance retention.

  Operational Runbook (Local & CI)
  -------------------------------

  Local quick start (developer):

  1. Start Docker services:

  ```powershell
  # from repo root
  docker compose -f infrastructure/docker-compose.yml up --build -d
  ```

  2. Initialize DB and seed data (Windows example or linux):

  ```powershell
  powershell -File infrastructure\run_db_setup.ps1
  ```
  ```bash
  bash -File infrastructure\run_db_setup.sh
  ```

  3. Set session region before RLS-protected queries:

  ```sql
  SET app.current_region = 'US';
  ```

  4. After run the script (part 3) you can see the redpanda on [localhost:8080](http://localhost:8080/overview)


  Testing, Validation & Observability
  ----------------------------------

  Testing:
  - Unit test DB logic with pgTAP for stored procedures and constraint checks.
  - Integration tests should validate the end-to-end outbox → Debezium → Kafka → ClickHouse flow.
  - Add load/stress tests using `src/database/03_setup_data_stress.sql` and capture metrics.

  Observability:
  - Export Postgres metrics to Prometheus (example `infrastructure/prometheus.yml`).
  - Instrument services and connectors with OpenTelemetry; correlate traces with events.
  - Add monitors for: Debezium connector lag, Kafka consumer lag, ClickHouse ingestion errors, and RLS misconfigurations.

  Disaster Recovery & Chaos Testing
  --------------------------------

  DR goals (example targets to adopt):
  - RPO: near 0 for financial transactions (use synchronous replication or appropriate durability settings).
  - RTO: minutes for key transactional services, hours for full analytical recovery.

  I will do:
  - Backup: regular base backups + WAL archiving; test restores per region.
  - Cross-region failover: maintain Cassandra global index to route requests to surviving regions; for critical financial flows, prefer rerouting writes to the home region when possible.
  - Chaos tests: simulate region outage, network partition, and connector failure; verify idempotency and replay behavior.

  Roadmap & Future Work
  ---------------------

  Short term (next 1–3 weeks):
  - Add an example outbox worker and idempotent consumer with end-to-end test.
  - Automate Vault integration for dev (fetch keys during `run_db_setup.ps1`).
  - Implement RLS-aware migrations and CI validation.
  - Provide a minimal sample service demonstrating `app.current_region` usage and PII token resolution.
  - Add production-grade observability dashboards and alerts (Prometheus + Grafana + tracing).
  - Multi-region deployment automation (Terraform + Kubernetes), including Cassandra and ClickHouse replication topology.
  - Full DR runbook, runbook automation, and documented SRE procedures.

  Files of Interest & Quick Links
  ------------------------------

  - `src/database/00_init_schema.sql` — core DDL, partitions, RLS, outbox, Debezium publication.
  - `src/database/01_store_procedure.sql` — stored procedures and business transaction patterns.
  - `src/database/02_seed_data.sql` — sample data.
  - `src/database/03_setup_data_stress.sql` — load/stress helpers.
  - `src/database/04_setup_click_house.sql` — ClickHouse ingestion guidance.
  - `infrastructure/docker-compose.yml` — local dev orchestration.
  - `infrastructure/insurance-outbox-connector.json` — Debezium connector example.
  - `docs/Challenger.md` — original challenge brief and detailed HLD.
  ----------------------
