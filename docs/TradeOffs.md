# Trade-offs — Global Resilience Project

Concise list of the main trade-offs for this project.

- Consistency vs. Latency: strong consistency for financial transactions (Postgres) and eventual consistency for analytics/index (Redpanda → ClickHouse/Cassandra). This reduces write latency but introduces windows of eventuality.

- Operational Complexity vs. Specialization: a polyglot stack (Postgres, Cassandra, ClickHouse, Redpanda, Redis, Vault) gives best-tool-for-purpose at the cost of higher operational overhead and specialized skills.

- Data Sovereignty vs. Integration Ease: tokenization/Vault and regional partitioning protect PII (LGPD/GDPR) but complicate global reports and simple cross-region joins.

- DB Logic vs. Evolvability & Testing: stored procedures and DB-side rules ensure atomicity and idempotency but make versioning, unit testing, and continuous deployment harder.

- UUID v7 (global IDs) vs. Index/Storage Overhead: global time-ordered IDs avoid centralized coordinators and improve distributed inserts, but increase index size and memory usage.

- Transactional Outbox / CDC vs. Propagation Latency: Outbox + Debezium ensures no data loss and consistent event publishing, yet propagation is asynchronous and consumers may experience lag.

- Region Partitioning vs. Cross-region Query Complexity: partitioning by region improves local performance and compliance, but requires routing and merging logic for cross-region queries.

---
