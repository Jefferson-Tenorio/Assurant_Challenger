```mermaid
sequenceDiagram
    %% Configuração de Tema para ficar mais "Professional Clean"
    %%{init: { 
      'theme': 'base', 
      'themeVariables': { 
        'primaryColor': '#e1f5fe',
        'primaryBorderColor': '#0277bd', 
        'actorBorder': '#0277bd',
        'signalColor': '#0277bd',
        'noteBkgColor': '#fff9c4',
        'noteBorderColor': '#fbc02d'
      } 
    }}%%

    autonumber

    %% Definição dos Participantes com Ícones
    actor App as 📱 Client App
    participant API as ⚙️ Backend API
    
    box "Persistence Layer (ACID)" #f3f4f6
        participant PG as 🐘 Postgres (Primary)
        participant Outbox as 📦 Outbox Table
    end

    box "Integration & Streaming" #e8f5e9
        participant DBZ as 🦎 Debezium
        participant RP as 🚀 Redpanda
    end

    Note over App, RP: 🛡️ Claim Creation Flow (Transactional Outbox Pattern)

    App->>API: ⚡ POST /claims<br/>(Payload + IdempotencyKey)
    
    activate API
    
    rect rgba(200, 200, 200, 0.2)
        Note right of API: 🔒 Critical Transaction Scope
        API->>PG: BEGIN TRANSACTION
        activate PG
        
        PG->>PG: Check Idempotency (Row Lock)
        PG->>PG: Validate Coverage (Bi-temporal)
        PG->>PG: 📝 INSERT INTO claims
        PG->>Outbox: 📝 INSERT INTO outbox (Event)
        Note right of Outbox: Event is committed atomically<br/>with the business data
        
        PG-->>API: COMMIT
        deactivate PG
    end

    par 🚀 Async Propagation
        API-->>App: ✅ 201 Created (Claim ID)
        deactivate API
    and
        Note right of PG: Data is safely on Disk (WAL)
        DBZ->>Outbox: 🕵️ Read WAL / Log
        activate DBZ
        DBZ->>RP: 📨 Publish 'claims.events'
        activate RP
        RP-->>DBZ: Ack (Offset Committed)
        deactivate RP
        DBZ->>Outbox: ✅ Update processed_at
        deactivate DBZ
    end
```


### Diagram B — Documentation & mapping

- Purpose: sequence diagram proving the "zero data loss" flow for a transactional operation, showing the outbox pattern and CDC propagation.
- What it represents: single request lifecycle from client → API → Postgres (writes state + outbox) → commit → Debezium reads WAL → publishes to Redpanda → outbox marked processed.
- Mapping to repo:
    - API behavior and transactional patterns are implied by `src/database/01_store_procedure.sql` (idempotency and business checks) and `00_init_schema.sql` (outbox table).
    - Debezium behavior is captured by the publication created in `00_init_schema.sql` and the connector payload in `infrastructure/insurance-outbox-connector.json`.

- Important clarifications / suggestions:
    - Debezium reads the WAL and publishes events, but Debezium itself does not typically update a `processed_at` column. In this repo there is a trigger `mark_outbox_processed()` that sets `processed_at` on update, but some outbox patterns rely on an external outbox poller to mark rows processed. Clarify which component updates `processed_at` (recommended: an outbox-ack service or consumer that acknowledges delivery).
    - Consider documenting idempotency semantics in the diagram: who holds the idempotency key (client) and where it's stored (claims table and event payload).
