Advanced Database Engineering Challenge
Global Insurance Distributed Data & Intelligence Platform

[context]

Assurant operates a global insurance ecosystem handling:

-   Tens of millions of active policies
-   Real-time claims, billing, fraud detection, and risk analytics
-   Multi-jurisdiction regulatory compliance (LGPD, GDPR, HIPAA-like constraints)
-   Near-zero tolerance for data loss
-   Strict SLAs for latency, availability, and consistency
    
You are required to 
1.design, 
2.implement
3.document 
    a **highly resilient, globally distributed insurance data platform** capable of supporting both **transactional** and **analytical** workloads at **extreme scale.**

Core Requirements (12 Topics)

1. Polyglot Persistence Strategy

Design and justify a polyglot data architecture, explicitly using:

-   PostgreSQL (transactional core)
-   A distributed NoSQL database (e.g., Cassandra / DynamoDB)
-   A columnar analytical engine (e.g., ClickHouse / BigQuery / Snowflake)
-   An in-memory layer (e.g., Redis / KeyDB)
    
Explain clear ownership boundaries, data flow, and consistency guarantees between systems.

2. Global Multi-Region Replication Architecture

Design a multi-region, active-active architecture across at least three geographic regions, covering:

-   Write routing strategies
-   Read locality optimization
-   Cross-region replication
-   Failover and failback mechanisms
-   Data sovereignty constraints

Include replication topology diagrams.

3. Advanced Consistency Models

Define and implement hybrid consistency models, including:

-   Strong consistency for financial transactions
-   Eventual consistency for analytical and reporting pipelines
-   Bounded staleness guarantees

Explicitly explain trade-offs and enforcement mechanisms.

4. Transaction Coordination Without Global Locks

Design a solution for cross-service transactional workflows without distributed locks, covering:

-   Saga orchestration vs choreography
-   Idempotency strategies
-   Compensating transactions
-   Failure recovery paths

Demonstrate at least one full transactional lifecycle.

5. Event-Driven Data Architecture

Implement a streaming-first architecture using tools such as:

-   Apache Kafka / Redpanda
-   Schema Registry
-   CDC tools (e.g., Debezium)

Demonstrate how events propagate through the system and drive downstream data stores.

6. Data Modeling at Scale

Provide detailed logical and physical data models for:

-   Policy lifecycle
-   Claims processing
-   Audit and compliance records
-   Historical snapshots

Include strategies for schema evolution and backward compatibility.

7. Data Lifecycle, Retention & Compliance

Design a complete data governance framework covering:

-   Data retention policies
-   Soft delete vs hard delete
-   Anonymization and pseudonymization
-   “Right to be forgotten” enforcement
-   Immutable audit trails

1. Performance Engineering & Hotspot Mitigation

Demonstrate strategies for:

-   Hot partition avoidance
-   Adaptive indexing
-   Query plan optimization
-   Write amplification control
-   Load shedding under extreme pressure

Include benchmarking assumptions.

9. Observability & Data Reliability

Design deep observability using tools such as:

-   Prometheus / Grafana
-   Distributed tracing (OpenTelemetry)
-   Query-level monitoring
-   Replication lag detection
-   Automated anomaly detection
    

10. Security & Fine-Grained Access Control

Implement and document:

-   Row-level and column-level security
-   Attribute-based access control (ABAC)
-   Encryption at rest and in transit
-   Key management (KMS / Vault)
-   Secure secrets rotation
    

11. Disaster Recovery & Chaos Engineering

Design and validate:

-   RPO / RTO targets
-   Automated disaster recovery plans
-   Backup and restore strategies
-   Chaos testing scenarios for data failure modes

12. Infrastructure & Automation

Use infrastructure-as-code and containerization, such as:

-   Docker
-   Kubernetes
-   Terraform
-   Automated migrations and rollbacks

Demonstrate how the system is provisioned, scaled, and recovered.

Deliverables & Expectations

[ end ] By the Technical Meeting (February 3rd)

The solution should be practically complete, including:

-   Architecture diagrams
-   Data models
-   Tooling choices and justifications
-   Partial or full implementation where applicable
-   Clear documentation of all decisions and trade-offs

During the Meeting

You will be asked in depth about:

-   Every architectural choice
-   Failure scenarios
-   Trade-offs you consciously accepted
-   Alternative designs you rejected and why

There is no single correct solution.
We are evaluating architectural depth, technical rigor, and decision-making under extreme complexity.

