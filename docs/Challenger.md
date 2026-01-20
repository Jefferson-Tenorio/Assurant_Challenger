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

-   Saga orchestration vs choreography 3º
-   Idempotency strategies 1º
-   Compensating transactions 2º
-   Failure recovery paths 4º

Demonstrate at least one full transactional lifecycle.

5. Event-Driven Data Architecture

Implement a streaming-first architecture using tools such as:

-   Apache Kafka / Redpanda 2º
-   Schema Registry 1º passo, criar esquemas.
-   CDC tools (e.g., Debezium) 3º

Demonstrate how events propagate through the system and drive downstream data stores.

6. Data Modeling at Scale

Provide detailed logical /"1º primeiro passo"\ and physical /"2º habilite o System-Versioning no Azure SQL"\ data models for:

-   Policy lifecycle /"Ciclo de vida de uma apolice, ela muda, ela é cancelada, ela volta. precisa de um modelo que guarde versões"\
-   Claims processing /"é processo complexo, aberto, analise, pericia e aprovado ou negado.Não pode haber erros por causa da consistencia financeira"\ 3º Modele a tabela de sinistros conectada à versão histórica da apólice, não à apólice atual.
-   Audit and compliance records /"tabelas de auditogs imutáveis registram, quem, quando  e o que?"\
-   Historical snapshots /"(SCD Type 2 / Temporal Tables), O cliente bateu o carro dia 01/Jan. A apólice cobria vidros. Dia 02/Jan ele removeu a cobertura de vidros. Dia 03/Jan ele abriu o sinistro. O sistema tem que saber que no dia 01 a cobertura existia."\

Include strategies for schema evolution and backward compatibility.
/" O Conceito: Como adicionar uma coluna ou mudar uma tabela sem derrubar a aplicação que está rodando?
A Estratégia: Expand and Contract. Nunca renomeie uma coluna. Você cria a nova, sincroniza, muda a app, e depois apaga a velha "\
Defina a regra: "Ninguém roda ALTER TABLE direto em produção". Configure a ferramenta de migração (Flyway/Liquibase).

7. Data Lifecycle, Retention & Compliance

Design a complete data governance framework covering:

-   Data retention policies /"Política de retenção de dados, quanto tempo guardar?"\ 3º crie jobs que trabalham de madrugada,ex apagar logs com mais de um ano.
-   Soft delete vs hard delete /"um pode voltar atrás outro já era. um não cumpre LGPD outro sim"\ 1º na modelagem, vai ter delete_at ou não, usar temporal tables(ia recomendation)
-   Anonymization and pseudonymization /"(mascara)um não cumpre LGPD outro(tritura) sim"\ 
-   “Right to be forgotten” enforcement /"se eu quero excluir minha conta, precisa deletar tudo dela(LGPD), tem que saber orquestrar todo esse delete."\ 4º crie uma store procedure, será complexo mas tenha fé.
-   Immutable audit trails /"tudo é rastreado, nem um dba mal pode apagar dados sem deixar rastros."\ 2º ligue a auditoria antes de entrar o primeiro dado.

% more comments go to: Comments\Challenger-Comments     


8. Performance Engineering & Hotspot Mitigation

Demonstrate strategies for:

-   Hot partition avoidance /"escolher a chave certa"\ 1º design inteligente, antes de construir criar tabela.
-   Query plan optimization/"tunar as querys ao máx"\ 2º enquanto escreve, observia via EXPLAIN do postgre, simples. e analisar.
-   Adaptive indexing /"criar indecis adaptáveis ao uso, automatico."\ 3º dia 1 de prod, só clickar no checkbox na nuvem.(automatic tunning em modo notify).
-   Write amplification control 4º quando ouver escala massiva
-   Load shedding under extreme pressure 4º quando ouver escala massiva

Include benchmarking assumptions.

% more comments go to: Comments\Challenger-Comments     


9. Observability & Data Reliability

Design deep observability using tools such as:

-   Prometheus / Grafana /"Metricás, prometheus coleta e o grafana visualiza."\ 1º imediato, apenas configurar as métricas vitais do prometheus e ver no grafana.
-   Query-level monitoring /"Ferramentas como pg_stat_stataments verificam quais querys consumiram mais cpu"\ 1º imediato, o obrigação.
-   Distributed tracing (OpenTelemetry) /" a requisição passa pela api-rede-banco-authservice. quantos segundos passou em cada uma."\ 4º quando tudo tiver implementado da pra ver.
-   Replication lag detection /"quanto tempo o banco de leitura está atrasado?" 3º assim que fizer o primeiro banco de leitura.
-   Automated anomaly detection /"o sistema aprende quando será os picos de uso"\ 4 º exigi dados históricos, deixe por último.

% more comments go to: Comments\Challenger-Comments     


10. Security & Fine-Grained Access Control

Implement and document:

-   Encryption at rest and in transit /" at rest is database criptografádo [Transparent Data Encryption] in transit [ TLS/SSL ] is database criptografádo in web or api-database."\ 1º configurar isso na nuvem, só checkbox simpes.
-   Key management (KMS / Vault) /"Onde guarda a chave mestra?"\ 2º junto do secure rotation.
-   Secure secrets rotation /"Atualizar a senha a cada trinta dias, não só depender de um env."\ 2º Implentar o azure key vault para a aplicação buscar a senha por lá.
-   Row-level and column-level security /"Criar pólitcas de segurança direto no motor do banco."\ 3º(row) a lógica de négocio, isso é prioridade.
-   Attribute-based access control (ABAC) /"Gerenciar o acesso ao própio banco de dados com base nos perfis, gerente, rh etc"\ 4º complexo, mas nescessário.

% more comments go to: Comments\Challenger-Comments     

11. Disaster Recovery & Chaos Engineering

Design and validate:

-   Recovery Point Objective (RPO) / Recovery Time Objective(RTO) targets /" 0s  - seconds "\ 1º Alinhar com o négocio o desejo dele.
-   Automated disaster recovery plans /"Botão de panico via Terraform ou scripts"\ 3º Configure réplicas de leitura ou cluster em outra zona/região para atender o RTO. Automatize a virada de chave (failover).
-   Backup and restore strategies /" Cópia de segurança e estrátegias para torna-la funcional. "\ 2º Baseado no rpo e rto, testar e validar.
-   Chaos testing scenarios for data failure modes /"quebrar o sistema e ver como ele reage"\ 4º

% more comments go to: Comments\Challenger-Comments 

12. Infrastructure & Automation 

Use infrastructure-as-code and containerization, such as:

-   Docker /" tech de empacotamento, container de carga."\ 1º code + database + docker-file 
-   Automated migrations and rollbacks /" máquina do tempo de evolução."\ 2º scripts de migração running dentro do docker
-   Terraform /" Infra as code, é a planta da construção."\ 3º Terraform cria o ambiente Azure
-   Kubernetes /" orquestrador, gerencia clusters."\ 4º pega o docker rodando no registro do terraform e joga na infra
 
% more comments go to: Comments\Challenger-Comments

[ ] See LiquidBase as migration tools

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
