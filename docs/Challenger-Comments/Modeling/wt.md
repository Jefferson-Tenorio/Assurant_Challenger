Você está prestes a defender um projeto de arquitetura sênior. O entrevistador **não** vai pedir para você escrever um `SELECT`. Ele vai tentar achar **falhas na sua lógica**.

Para sobreviver e brilhar na entrevista técnica do dia 03/Fev, aqui estão os **5 Tópicos de Vida ou Morte** que você precisa revisar agora. Se você travar neles, o projeto desmorona.

---

### 1. Consistência de Dados (O Tópico Mais Perigoso)
**O que estudar:** Teorema CAP, ACID vs. BASE e Níveis de Isolamento.
**Por que é urgente:** Você tem dados financeiros no Postgres (ACID) e dados analíticos no ClickHouse (Eventual). Você precisa explicar como garante que o dinheiro não suma no meio do caminho.
a 
*   **Perguntas do Entrevistador:**
    *   "Se o Debezium cair, o meu dashboard no Grafana vai mostrar dados errados? Por quanto tempo?" (Resposta: Sim, consistência eventual. O RPO do analítico sobe, mas o transacional não para).
    *   "Por que você não usou Cassandra para o financeiro?" (Resposta: Cassandra não tem transações ACID multi-row, e para saldo/sinistro precisamos de consistência forte imediata).
    *   **O Conceito Chave:** *Transactional Outbox Pattern* (garantir que salvou no banco E enviou o evento).

### 2. Internals do PostgreSQL (Você é o DBA)
**O que estudar:** MVCC (Multi-Version Concurrency Control), WAL (Write-Ahead Log), Índices (B-Tree vs GiST) e Vacuum.
**Por que é urgente:** Você usou recursos avançados (`tstzrange`, `EXCLUDE`). Você tem que saber como funcionam por baixo do capô.

*   **Perguntas do Entrevistador:**
    *   "Essa tabela de apólices com `tstzrange`... isso não vai ficar lento com 100 milhões de linhas? Como o índice GiST ajuda?" (Resposta: O GiST trata o intervalo como uma forma geométrica, permitindo busca espacial rápida, diferente do B-Tree que é linear).
    *   "O que é esse `wal_level=logical` no seu Docker?" (Resposta: É o que permite o Debezium ler o log binário do banco para fazer o CDC sem onerar a CPU com queries de polling).

### 3. Kafka/Redpanda (O Sistema Nervoso)
**O que estudar:** Partições, Consumer Groups, Offsets e Semântica de Entrega (At-least-once vs Exactly-once).
**Por que é urgente:** É a cola do seu sistema. Se você não entender Partições, não entende escalabilidade.

*   **Perguntas do Entrevistador:**
    *   "Como você garante a ordem dos eventos? Se eu crio a apólice e depois cancelo, o sistema pode processar o cancelamento antes da criação?" (Resposta: Garantia de ordem é apenas **dentro da Partição**. Usamos o `policy_id` como Partition Key para garantir que eventos da mesma apólice caiam na mesma fila).
    *   "O que acontece se o consumidor (Consumer Group) cair?" (Resposta: O Redpanda guarda o *Offset*. Quando o consumidor voltar, ele lê de onde parou. Nada se perde).

### 4. Arquitetura Distribuída & Falhas (Chaos)
**O que estudar:** Cell-Based Architecture, Bulkheads, Circuit Breaker e Idempotência.
**Por que é urgente:** Seu diferencial é o Multi-Region.

*   **Perguntas do Entrevistador:**
    *   "Se a região BR cair, o que acontece com o usuário?" (Resposta: O DNS redireciona para US. O banco US vira Master. Mas... e os dados que não replicaram? Assumimos um RPO > 0 em troca de não travar o sistema (Availability over Consistency no CAP para DR)).
    *   "O que é Idempotência e por que você colocou isso na tabela?" (Resposta: Se a rede falhar e o cliente clicar 'Pagar' duas vezes, o `idempotency_key` impede que eu cobre duas vezes. Essencial em sistemas distribuídos onde *retries* são comuns).

### 5. Modelagem NoSQL (Cassandra)
**O que estudar:** Partition Key vs Clustering Key. Wide-Column Store.
**Por que é urgente:** É o ponto onde quem vem do SQL costuma errar feio.

*   **Perguntas do Entrevistador:**
    *   "Por que você modelou a tabela do Cassandra desse jeito?" (Resposta: No Cassandra, modelamos baseado na **query**, não na entidade. A Partition Key `policy_id` distribui os dados nos nós, e a Clustering Key `event_time` ordena eles no disco para leitura rápida de histórico).

---

### Resumo do Plano de Estudo "Crash Course"

Se você tiver apenas 4 horas para estudar:

1.  **Hora 1 (Postgres):** Entenda profundamente **Índices GiST** e como funciona o **CDC (Debezium/WAL)**.
2.  **Hora 2 (Arquitetura):** Desenhe num papel o fluxo de um **Failover**. O que acontece passo a passo se o servidor pegar fogo? (DNS muda -> Script sobe réplica -> App reconecta).
3.  **Hora 3 (Kafka/Redpanda):** Entenda **Partition Key**. Isso é a resposta para 90% das perguntas de "como escala?".
4.  **Hora 4 (Conceitos):** Leia sobre **Teorema CAP** e **ACID**. Tenha na ponta da língua por que você escolheu CP ou AP em cada parte.

**Dica de Ouro:** Não tente esconder o que você não sabe. Se perguntarem algo muito profundo (ex: "Como o algoritmo de compressão LZ4 do Cassandra funciona?"), diga: *"Não estudei o algoritmo de compressão a fundo, mas escolhi o Cassandra pela capacidade de escrita linear e replicação multi-DC."* Foque no "Porquê" arquitetural.

Para se tornar um Arquiteto de Dados de verdade (e não apenas um "empilhador de ferramentas"), você precisa dominar os conceitos que sobrevivem à mudança das tecnologias. O Spark pode ser substituído amanhã, mas a **Teoria CAP** e a **Modelagem Dimensional** continuam valendo.

Como seu mentor, divido a Arquitetura de Dados em **6 Grandes Pilares**. Se você dominar isso, você conversa de igual para igual com qualquer CTO.

---

### 1. Modelagem de Dados (A Arte Perdida)
Muitos "Engenheiros Modernos" ignoram isso e criam "Pântanos de Dados" (Data Swamps).
*   **OLTP vs OLAP:** Entender profundamente a diferença física de escrita e leitura entre um sistema transacional (Postgres) e um analítico (ClickHouse/Snowflake).
*   **Normalização (3NF) vs Desnormalização:** Quando dividir tabelas para evitar redundância (bancos operacionais) e quando juntar tudo para performance de leitura (Analytics).
*   **Modelagem Dimensional (Kimball):** **Vital para a vaga da Assurant.** Entender o que é Tabela Fato, Dimensão, Star Schema e Snowflake Schema.
*   **SCD (Slowly Changing Dimensions):** Como lidar com mudanças no histórico (Tipos 1, 2 e 3). Você já aplicou isso no seu desafio com o `validity_period`.

### 2. Paradigmas de Armazenamento (Storage Patterns)
Não existe "bala de prata".
*   **Data Warehouse (DWH):** Dados estruturados, limpos, SQL, "Schema-on-Write" (Define a tabela antes de gravar). Ex: SQL Server, Redshift.
*   **Data Lake:** Dados brutos, qualquer formato (JSON, CSV, Imagens), "Schema-on-Read" (Define a estrutura na hora de ler). Ex: S3, Azure Blob Storage.
*   **Data Lakehouse (A Tendência Atual):** A fusão dos dois. Formatos de arquivo abertos (Parquet/Avro) com uma camada de transação ACID em cima (Delta Lake, Apache Iceberg, Hudi). O Databricks é rei aqui.
*   **Polyglot Persistence:** Saber quando usar Relacional, Documento (Mongo), Chave-Valor (Redis), Colunar (Cassandra/ClickHouse) ou Grafo (Neo4j).

### 3. Padrões de Movimentação de Dados (Integration)
Como o sangue corre nas veias do sistema.
*   **ETL vs ELT:**
    *   *ETL (Extract, Transform, Load):* Transforma no meio do caminho (SSIS, Pentaho). Modelo antigo ou para segurança.
    *   *ELT (Extract, Load, Transform):* Joga tudo bruto no Lake e transforma lá dentro usando o poder da nuvem (dbt, Spark). Modelo moderno.
*   **Batch vs Streaming:**
    *   *Batch:* Processamento em lotes (D-1). "Como fechou o dia ontem?".
    *   *Streaming:* Tempo real. "O que está acontecendo agora?".
*   **CDC (Change Data Capture):** Ler o log do banco (WAL) para replicar dados sem fazer queries pesadas (`SELECT *`). É o que você fez com o Debezium.

### 4. Teoria de Sistemas Distribuídos (A Física da Coisa)
Para trabalhar com Big Data e Cloud, você tem que aceitar que as coisas falham.
*   **Teorema CAP:** Em um sistema distribuído, você só pode escolher 2 de 3: Consistência (Consistency), Disponibilidade (Availability) ou Tolerância a Partição (Partition Tolerance).
*   **Consistência Eventual vs Consistência Forte:** Entender que no Cassandra ou Kafka, o dado pode demorar uns milissegundos para aparecer (Eventual), e como lidar com isso na aplicação.
*   **Sharding e Partitioning:** Como dividir um banco de 100 Terabytes em 50 máquinas sem perder a sanidade.

### 5. Arquiteturas de Dados Modernas (Macro-Design)
Como organizar a empresa em torno dos dados.
*   **Lambda Architecture:** Ter duas camadas separadas: uma rápida (Speed Layer) e uma precisa (Batch Layer). Complexo de manter.
*   **Kappa Architecture:** Tudo é stream. Simplifica a stack (usa Kafka para tudo).
*   **Data Mesh (O Hype Corporativo):** Descentralizar os dados. Em vez de um time central de engenharia gargalo, cada time (Vendas, RH) cuida do seu próprio "Produto de Dados". Exige maturidade alta.
*   **Data Fabric:** Uma camada inteligente que conecta dados on-premise e cloud automaticamente.

### 6. Governança e Operações (DataOps)
O que torna o sistema profissional.
*   **Data Quality:** Testes automatizados (Great Expectations). O dado está nulo? Está negativo?
*   **Data Lineage:** O "Rastreio". Se o relatório do CEO está errado, de onde veio esse dado? Qual pipeline tocou nele?
*   **Catálogo de Dados:** Uma "Wikipédia" dos dados da empresa para os analistas saberem o que existe.
*   **FinOps:** Como arquitetar para não falir a empresa na nuvem (Partition Pruning, Compactação de arquivos Parquet/ORC).

---

### Por onde começar a estudar (Roadmap Prático)

Não tente abraçar o mundo. Para o seu momento (Foco na Assurant e Base Sênior):

1.  **Prioridade 0 (Já está fazendo):** Docker, Linux, Postgres, Kafka. (A Base Operacional).
2.  **Prioridade 1 (Para a Vaga):** **Modelagem Dimensional (Star Schema)** e **Data Warehousing**. Leia sobre "Kimball Group".
3.  **Prioridade 2 (O Futuro):** **Data Lakehouse** (Entender o formato Parquet e como o Spark processa isso).

**Livro de Cabeceira Recomendado:**
*   *"Designing Data-Intensive Applications"* (Martin Kleppmann). É a bíblia da engenharia de dados moderna. Se você ler esse livro, você vira Sênior automaticamente (na teoria).