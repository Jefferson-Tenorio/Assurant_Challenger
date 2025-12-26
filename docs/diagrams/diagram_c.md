```mermaid
graph TD
    %%{init: {'theme': 'base', 'themeVariables': { 'primaryColor': '#fff', 'edgeLabelBackground':'#fff', 'tertiaryColor': '#f3f4f6'}}}%%

    classDef db fill:#e3f2fd,stroke:#1565c0,stroke-width:2px,color:#0d47a1;
    classDef vault fill:#ffebee,stroke:#c62828,stroke-width:2px,stroke-dasharray: 5 5,color:#b71c1c;
    classDef queue fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,color:#1b5e20;
    classDef note fill:#fff9c4,stroke:#fbc02d,stroke-width:1px,stroke-dasharray: 2 2,color:#333;

    subgraph BR_Region ["🇧🇷 BR Region (São Paulo)"]
        direction TB
        PG_BR[("🐘 Postgres BR<br/>(Partition: BR)")]:::db
        Vault_BR["🔒 PII Vault BR<br/>(CPF & Names)"]:::vault
        
        PG_BR <--> Vault_BR
        
        NoteBR>⚠️ Sensitive data NEVER<br/>leaves this boundary]:::note
        Vault_BR -.- NoteBR
    end

    subgraph EU_Region ["🇪🇺 EU Region (Frankfurt)"]
        direction TB
        PG_EU[("🐘 Postgres EU<br/>(Partition: EU)")]:::db
        Vault_EU["🔒 PII Vault EU<br/>(GDPR Data)"]:::vault
        
        PG_EU <--> Vault_EU
    end

    subgraph Global_Plane ["🌍 Global Plane (Shared)"]
        direction TB
        Redpanda[["🚀 Redpanda Cluster<br/>(Replicated Events)"]]:::queue
        Cassandra[("🗂️ Cassandra<br/>Global Index")]:::db
        
        Redpanda -- "Metadata Only" --> Cassandra
    end

    PG_BR -- "CDC Stream<br/>(Anonymized)" --> Redpanda
    PG_EU -- "CDC Stream<br/>(Anonymized)" --> Redpanda

    %% BR_Region ~~~ EU_Region
```


### Diagram C — Documentation & mapping (Data Sovereignty)

- Purpose: show regional sovereignty and that PII never leaves the home region.
- What it represents: per-region Postgres + local PII Vault and a global plane that carries non-sensitive metadata (events and indexes) into Redpanda and Cassandra.
- Mapping to repo:
    - `vault.customer_pii` and per-region partitions → `src/database/00_init_schema.sql`.
    - The "Metadata Only → Cassandra" arrow corresponds to the global index design in `docs/Challenger.md` (Cassandra `global_registry.policy_index`). Ensure only non-PII fields (policy_id, home_region, status) are propagated.
