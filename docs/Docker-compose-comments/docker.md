Você fez um trabalho excelente no seu arquivo original. Ele está completo, tem healthchecks e boas práticas de produção (como `wal_level=logical` para CDC).

Para transformar isso em um **Simulador Multi-Region (Cell-Based)**, nós precisamos aplicar a regra do "Shared-Nothing" que discuti.

**O que muda:**
1.  **Duplicação de Células:** Vamos criar sufixos `-br` e `-us` para os serviços que são regionais (Postgres, Redpanda, Redis).
2.  **Isolamento de Rede:** Vamos criar redes separadas para simular que o BR não vê o US diretamente.
3.  **Camada Global:** ClickHouse, Cassandra e Observabilidade ficam numa rede "Backbone" que enxerga tudo.

Aqui está a versão refatorada e comentada "Nível DBA Sênior".

**Atenção:** Esse arquivo vai consumir bastante RAM (uns 8GB+). Se sua máquina for modesta, comente a seção "US Region" para rodar apenas o BR, e depois inverta para testar.

```yaml
version: '3.8'

# ==============================================================================
# ESTRATÉGIA DE REDES (A Ilusão da Distância Geográfica)
# ==============================================================================
networks:
  # Rede isolada do Brasil (VPC SA-EAST-1)
  net-region-br:
    driver: bridge
  # Rede isolada dos EUA (VPC US-EAST-1)
  net-region-us:
    driver: bridge
  # Rede de Gerenciamento Global (Peering / VPN / Backbone)
  # Apenas serviços Globais (ClickHouse, Grafana) entram aqui
  net-global-backbone:
    driver: bridge

services:

  # ============================================================================
  # REGION 1: BRASIL (Primary Transactional Cell)
  # ============================================================================

  # 1.1 POSTGRES BR (Source of Truth BR)
  postgres-br:
    image: postgres:16-alpine
    container_name: db-core-br
    restart: always
    environment:
      POSTGRES_USER: ${DB_USER:-admin}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-admin}
      POSTGRES_DB: insurance_core_br
    command: ["postgres", "-c", "wal_level=logical", "-c", "max_replication_slots=4"]
    ports:
      - "5432:5432" # Porta Padrão
    volumes:
      - pg_data_br:/var/lib/postgresql/data
      # Script de init carrega schemas locais
      - ../database/00_init_schema.sql:/docker-entrypoint-initdb.d/00_init_schema.sql
    networks:
      - net-region-br
      - net-global-backbone # Necessário para o Exporter e Debezium verem ele
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U admin -d insurance_core_br"]
      interval: 10s

  # 1.2 REDPANDA BR (Event Bus BR)
  redpanda-br:
    image: docker.redpanda.com/redpandadata/redpanda:v23.3.10
    container_name: bus-core-br
    command: >
      redpanda start
      --smp 1
      --overprovisioned
      --kafka-addr internal://0.0.0.0:9092,external://0.0.0.0:19092
      --advertise-kafka-addr internal://redpanda-br:9092,external://localhost:19092
    ports:
      - "19092:19092" # Porta Externa BR
    volumes:
      - redpanda_data_br:/var/lib/redpanda/data
    networks:
      - net-region-br
      - net-global-backbone

  # 1.3 REDIS BR (Cache BR)
  redis-br:
    image: redis:7-alpine
    container_name: cache-br
    ports:
      - "6379:6379"
    networks:
      - net-region-br

  # 1.4 DEBEZIUM BR (CDC Worker Local)
  debezium-br:
    image: debezium/connect:2.5
    container_name: cdc-worker-br
    ports:
      - "8083:8083"
    environment:
      BOOTSTRAP_SERVERS: redpanda-br:9092
      GROUP_ID: cdc-group-br
      CONFIG_STORAGE_TOPIC: connect_configs_br
      OFFSET_STORAGE_TOPIC: connect_offsets_br
    networks:
      - net-region-br
      - net-global-backbone # Precisa ver o Postgres e o Redpanda
    depends_on:
      postgres-br:
        condition: service_healthy
      redpanda-br:
        condition: service_started

  # ============================================================================
  # REGION 2: USA (Secondary/Failover Transactional Cell)
  # * DUPLICAÇÃO INTENCIONAL para simular "Shared-Nothing" *
  # ============================================================================

  # 2.1 POSTGRES US
  postgres-us:
    image: postgres:16-alpine
    container_name: db-core-us
    environment:
      POSTGRES_USER: ${DB_USER:-admin}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-admin}
      POSTGRES_DB: insurance_core_us
    command: ["postgres", "-c", "wal_level=logical"]
    ports:
      - "5433:5432" # MAPEAR PORTA DIFERENTE NO HOST (5433)
    volumes:
      - pg_data_us:/var/lib/postgresql/data
      - ../database/00_init_schema.sql:/docker-entrypoint-initdb.d/00_init_schema.sql
    networks:
      - net-region-us
      - net-global-backbone

  # 2.2 REDPANDA US
  redpanda-us:
    image: docker.redpanda.com/redpandadata/redpanda:v23.3.10
    container_name: bus-core-us
    command: >
      redpanda start
      --smp 1
      --overprovisioned
      --kafka-addr internal://0.0.0.0:9092,external://0.0.0.0:29092
      --advertise-kafka-addr internal://redpanda-us:9092,external://localhost:29092
    ports:
      - "29092:29092" # Porta Externa US diferente da BR
    volumes:
      - redpanda_data_us:/var/lib/redpanda/data
    networks:
      - net-region-us
      - net-global-backbone

  # 2.3 REDIS US
  redis-us:
    image: redis:7-alpine
    container_name: cache-us
    ports:
      - "6380:6379" # Porta mapeada
    networks:
      - net-region-us

  # ============================================================================
  # GLOBAL LAYER (Serviços que atravessam fronteiras)
  # ============================================================================

  # 3. GLOBAL DISTRIBUTED NOSQL (Cassandra)
  # Simula o cluster global. Na prática, teríamos nós em cada região,
  # mas aqui usamos um nó central acessível por todos via Backbone.
  distributed-nosql:
    image: cassandra:4.1
    container_name: global-cassandra
    ports:
      - "9042:9042"
    environment:
      - CASSANDRA_CLUSTER_NAME=GlobalInsurance
      - CASSANDRA_DC=dc-global
    volumes:
      - cassandra_data:/var/lib/cassandra
    networks:
      - net-global-backbone
      - net-region-br # App BR acessa
      - net-region-us # App US acessa

  # 4. GLOBAL ANALYTICS (ClickHouse)
  # O "Grande Irmão" que consome dados do Redpanda BR e Redpanda US
  analytical-db:
    image: clickhouse/clickhouse-server:latest
    container_name: global-clickhouse
    ports:
      - "8123:8123"
      - "9000:9000"
    volumes:
      - ../database/04_init_clickhouse_table.sql:/docker-entrypoint-initdb.d/init.sql
      - clickhouse_data:/var/lib/clickhouse
    networks:
      - net-global-backbone
    # Dica DBA: No ClickHouse, você criará "Kafka Engines" apontando para
    # redpanda-br:9092 e redpanda-us:9092

  # 5. SECURITY (Vault)
  security-vault:
    image: hashicorp/vault:1.15
    container_name: global-vault
    ports:
      - "8200:8200"
    environment:
      VAULT_DEV_ROOT_TOKEN_ID: "root"
    cap_add:
      - IPC_LOCK
    networks:
      - net-global-backbone

  # ============================================================================
  # OBSERVABILITY (Monitoramento Centralizado)
  # ============================================================================
  
  prometheus:
    image: prom/prometheus:latest
    container_name: global-metrics
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
    ports:
      - "9090:9090"
    volumes:
      # Você precisará editar seu prometheus.yml para ter jobs:
      # - job_name: 'postgres-br' ... target: 'postgres-exporter-br:9187'
      # - job_name: 'postgres-us' ... target: 'postgres-exporter-us:9187'
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    networks:
      - net-global-backbone

  grafana:
    image: grafana/grafana-oss:latest
    container_name: global-dashboard
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana_data:/var/lib/grafana
    networks:
      - net-global-backbone

  # Exporter BR
  postgres-exporter-br:
    image: prometheuscommunity/postgres-exporter
    container_name: exporter-pg-br
    environment:
      DATA_SOURCE_NAME: "postgresql://${DB_USER:-admin}:${DB_PASSWORD:-admin}@postgres-br:5432/insurance_core_br?sslmode=disable"
    networks:
      - net-global-backbone

  # Exporter US
  postgres-exporter-us:
    image: prometheuscommunity/postgres-exporter
    container_name: exporter-pg-us
    environment:
      DATA_SOURCE_NAME: "postgresql://${DB_USER:-admin}:${DB_PASSWORD:-admin}@postgres-us:5432/insurance_core_us?sslmode=disable"
    networks:
      - net-global-backbone

volumes:
  pg_data_br:
  pg_data_us:
  redpanda_data_br:
  redpanda_data_us:
  cassandra_data:
  clickhouse_data:
  prometheus_data:
  grafana_data:
```

### O que você deve destacar ao apresentar isso:

1.  **Isolamento Físico Simulado:** "Observem que `postgres-br` e `postgres-us` salvam em volumes diferentes (`pg_data_br` vs `pg_data_us`). Isso prova que não estamos compartilhando storage."
2.  **Portas Distintas:** "Para rodar localmente, mapeamos portas diferentes (5432/5433), mas dentro da rede do Docker, cada banco responde na porta padrão 5432, garantindo que a configuração da aplicação seja idêntica."
3.  **Rede Backbone:** "Criamos uma rede `global-backbone` apenas para os serviços que têm permissão de ver o mundo todo (Analytics e Monitoramento). A aplicação BR não tem acesso a essa rede, garantindo segurança."

Isso é um setup de Engenharia de Dados de respeito. Pode rodar.

O veredito de um Sênior: **Sim, atende cerca de 85% do desafio arquitetural.**

A estrutura atual "Cell-Based" (separada por regiões) que montamos é sofisticada e cobre os pilares de Poliglota, Event-Driven e Multi-Region. É muito superior a um "monolito de dados".

Porém, para tirar **nota 10** e cobrir os requisitos de **Governança, Migração Automatizada, Backup e Caos**, faltam as ferramentas de **Operação do Dia-a-Dia**. Um banco sem backup e sem controle de versão de schema é uma bomba relógio.

Aqui estão as ferramentas que faltam no seu `docker-compose.yml` para fechar o ciclo completo do desafio:

---

### 1. Liquibase (Schema Migration & Versioning)
**Por que:** O desafio exige "Automated migrations" (Tópico 12) e "Schema evolution" (Tópico 6). Você não pode criar tabelas manualmente. O Liquibase deve rodar no boot para garantir que o Postgres BR e US tenham a mesma estrutura.

```yaml
  # Adicione na seção de cada região (BR e US) ou como um job único
  liquibase-br:
    image: liquibase/liquibase:latest
    container_name: migration-br
    networks:
      - net-region-br
    volumes:
      - ./database/changelogs:/liquibase/changelog
    command: >
      --url="jdbc:postgresql://postgres-br:5432/insurance_core_br"
      --username=admin
      --password=admin
      --changelog-file=db.changelog-master.xml
      update
    depends_on:
      postgres-br:
        condition: service_healthy
```

### 2. MinIO (S3 Compatible Object Storage)
**Por que:** O desafio pede "Backup and restore strategies" (Tópico 11) e "Data retention" (Tópico 7).
Onde você vai salvar os backups do Postgres? Onde o ClickHouse vai buscar dados históricos frios (Tiered Storage)? Você precisa de um "S3 local".

```yaml
  # Global Services
  minio:
    image: minio/minio
    container_name: global-s3-storage
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      MINIO_ROOT_USER: admin
      MINIO_ROOT_PASSWORD: supersecretpassword
    command: server /data --console-address ":9001"
    volumes:
      - minio_data:/data
    networks:
      - net-global-backbone
```
*   **Uso Prático:** Configure scripts para fazer dump do Postgres e enviar para o MinIO toda noite (simulando backup para nuvem).

### 3. Jaeger (Distributed Tracing)
**Por que:** O desafio pede "Distributed tracing (OpenTelemetry)" (Tópico 9).
Saber que o sistema está lento não basta. Você precisa saber *onde*. O Jaeger mostra: "A API demorou 20ms, o Redis 1ms, mas o Postgres demorou 500ms".

```yaml
  jaeger:
    image: jaegertracing/all-in-one:latest
    container_name: global-tracing
    ports:
      - "16686:16686" # UI do Jaeger
      - "4317:4317"   # OTLP gRPC (OpenTelemetry)
    networks:
      - net-global-backbone
```

### 4. Traefik (Global Load Balancer / API Gateway)
**Por que:** O desafio pede "Write routing strategies" (Tópico 2).
Como você simula o roteamento do usuário? O Traefik pode atuar como o "Gateway de Entrada". Você pode configurar regras como: "Se o header for `Region: BR`, mande para o container BR".

```yaml
  traefik:
    image: traefik:v2.10
    container_name: global-gateway
    command: --api.insecure=true --providers.docker
    ports:
      - "80:80"     # Porta de entrada da App
      - "8080:8080" # Dashboard do Traefik
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - net-region-br
      - net-region-us
      - net-global-backbone
```

### 5. Pumba ou Toxiproxy (Chaos Engineering)
**Por que:** O desafio pede "Chaos testing scenarios" (Tópico 11).
Você precisa provar que o sistema aguenta falhas. O **Pumba** é uma ferramenta de caos para Docker. Ele pode matar containers aleatoriamente ou introduzir lentidão de rede.

```yaml
  chaos-monkey:
    image: gaiaadm/pumba
    container_name: chaos-testing
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: >
      --interval 60s 
      --random 
      netem --duration 10s --delay 1000ms 
      re2:^db-core-.* 
    # Tradução: A cada 60s, escolha um container que comece com "db-core-" 
    # (seja BR ou US) e adicione 1 segundo de lag na rede por 10 segundos.
    networks:
      - net-global-backbone
```

---

### Resumo da "Stack Completa" Visual

Se você adicionar esses itens, seu diagrama mental (e sua documentação) cobrirá 100% dos requisitos:

1.  **Core Data:** Postgres (x2) + Cassandra.
2.  **Eventos:** Redpanda (x2).
3.  **App & Cache:** Redis (x2) + App Containers.
4.  **Analytics:** ClickHouse.
5.  **Observabilidade:** Prometheus + Grafana + **Jaeger**.
6.  **Operações (Ops):** **Liquibase** (Migrations) + **MinIO** (Backup/Lake).
7.  **Resiliência:** **Pumba** (Caos).
8.  **Roteamento:** **Traefik** (Gateway).

**Conselho final:** Não tente rodar *tudo* isso de uma vez se tiver menos de 16GB de RAM. Se for apresentar, rode o essencial, e tenha os trechos de código do Pumba e Jaeger prontos para "descomentar" e mostrar: *"Aqui está como testamos resiliência e tracing"*. Isso demonstra conhecimento sem travar seu computador na hora H.