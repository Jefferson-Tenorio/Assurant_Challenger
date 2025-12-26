```mermaid
graph TD
    %% Estilos
    classDef person fill:#08427b,stroke:#052e56,color:#fff;
    classDef container fill:#23a2d9,stroke:#1f8ebf,color:#fff;
    classDef db fill:#1168bd,stroke:#0b4884,color:#fff;
    classDef queue fill:#999,stroke:#666,color:#fff;
    classDef external fill:#999,stroke:#666,color:#fff,stroke-dasharray: 5 5;

    %% Atores
    Customer(Segurado<br/>App Mobile/Web):::person

    %% Sistema
    subgraph "Insurance Platform Ecosystem"
        API(API Gateway<br/>Go/Java):::container
        
        PG[(Core Transactional<br/>PostgreSQL 16)]:::db
        Redis[(Hot Cache<br/>Redis)]:::db
        
        CDC(CDC Connector<br/>Debezium):::container
        Kafka(Event Backbone<br/>Redpanda):::queue
        
        Cass[(Global Index<br/>Cassandra)]:::db
        CH[(Analytics Engine<br/>ClickHouse)]:::db
    end

    %% Relações
    Customer -- "HTTPS/JSON" --> API
    API -- "Writes (JDBC)" --> PG
    API -- "Reads (RESP)" --> Redis
    
    PG -. "Logical Decoding" .-> CDC
    CDC -- "Avro/JSON" --> Kafka
    
    Kafka -- "Sink Connector" --> Cass
    Kafka -- "Kafka Engine" --> CH
```
### Diagram A — Documentation & mapping


- Purpose: container-level view (C4 container) that shows runtime components and how they connect. Good for stakeholders and ops.
- What it represents: API (ingress), PostgreSQL as transactional core, Redis cache, Debezium CDC connector, Redpanda (Kafka API), Cassandra global index, and ClickHouse analytics.
- Mapping to repo:
    - `Postgres` → `src/database/00_init_schema.sql` (schemas, outbox, RLS)
    - `Debezium` → `infrastructure/insurance-outbox-connector.json` and the publication created in the SQL DDL
    - `Redpanda` / `Kafka` → referenced by `src/database/04_setup_click_house.sql` (ClickHouse Kafka engine) and connectors
    - `ClickHouse` → `src/database/04_setup_click_house.sql` (analytics DDL)
    - `Cassandra` global index → conceptual design in `docs/Challenger.md` (not implemented in `src/`)

