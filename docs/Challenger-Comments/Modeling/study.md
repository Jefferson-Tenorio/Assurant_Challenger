CREATE SCHEMA workflow;

CREATE TABLE workflow.saga_instances (
    saga_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    correlation_id UUID NOT NULL, -- ID da apólice ou cliente
    saga_type VARCHAR(50) NOT NULL, -- 'POLICY_ISSUANCE'
    current_state VARCHAR(50) NOT NULL, -- 'CREATED', 'PAYMENT_PENDING', 'COMPLETED'
    payload JSONB, -- Dados temporários (token do cartão, valores)
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    error_log TEXT
);

-- Isso permite que se o servidor cair no meio do pagamento, 
-- quando voltar, ele consulta essa tabela e vê: "Opa, parei no pagamento, vou tentar de novo".

Isso é exatamente o que define a linha entre um **Desenvolvedor Sênior** (que sabe codar) e um **Arquiteto** (que sabe defender decisões).

O entrevistador vai procurar **"Pontos de Ruptura"**. Ele vai pegar o seu desenho e perguntar: "E se eu puxar esse cabo?".

Para o dia 03/Fev, montei seu **Guia de Sobrevivência**. Foque 80% do seu estudo nestes 5 tópicos, pois eles cobrem as decisões arriscadas que tomamos na arquitetura.

---

### 1. Consistência em Sistemas Distribuídos (O "Calcanhar de Aquiles")
**A Pergunta da Morte:** *"Você gravou o pagamento no Postgres e depois mandou o evento pro Kafka. E se a luz acabar no milissegundo exato entre gravar e enviar? O cliente pagou mas o sistema não sabe?"*

**O que estudar:**
*   **O Problema do Dual-Write:** Por que você não pode simplesmente fazer `db.save()` e `kafka.send()` na mesma função.
*   **A Solução (Sua Defesa):** O padrão **Transactional Outbox**.
    *   *Explicação:* "Eu não escrevo no Kafka direto. Eu escrevo o evento numa tabela `outbox` no Postgres DENTRO da mesma transação do pagamento (ACID). O Debezium lê o log do banco e põe no Kafka. É impossível perder o evento."
*   **Teorema CAP:** Saiba explicar que seu financeiro prioriza **Consistência** (CP) e seu Analytics prioriza **Disponibilidade** (AP).

### 2. Internals do PostgreSQL (Aprofundamento Obrigatório)
**A Pergunta da Morte:** *"Você usou `tstzrange` e índices `GiST`. Isso é bonito na teoria, mas performa com 500 milhões de linhas? Por que não usou B-Tree normal?"*

**O que estudar:**
*   **B-Tree vs GiST:**
    *   *B-Tree:* Ótimo para igualdade (`id = 5`) ou range simples (`data > hoje`). Péssimo para "intervalos que se sobrepõem".
    *   *GiST (Generalized Search Tree):* Trata o dado como geometria. Ele entende "interseção". É por isso que você escolheu.
*   **MVCC (Multi-Version Concurrency Control):** Entenda como o Postgres permite que alguém leia a tabela de apólices enquanto outro alguém está atualizando, sem ninguém travar ninguém (Readers don't block Writers).

### 3. Kafka & Estratégia de Particionamento (Escalabilidade)
**A Pergunta da Morte:** *"O sistema cresceu. Temos 10 milhões de eventos por minuto. O consumidor do ClickHouse não está aguentando processar. O que você faz?"*

**O que estudar:**
*   **Particionamento:** A unidade de paralelismo do Kafka.
    *   *Defesa:* "Se o consumidor está lento, eu aumento o número de partições do tópico e subo mais instâncias do consumidor (Consumer Group). O Kafka distribui a carga automaticamente."
*   **Ordering Guarantee:** O Kafka só garante ordem **dentro da partição**.
    *   *Defesa:* "Por isso usei o `policy_id` como Partition Key. Todos os eventos da apólice 123 vão para a mesma partição e são processados na ordem certa. Não importa se a apólice 456 for processada antes ou depois."

### 4. Idempotência e Retries (Confiabilidade)
**A Pergunta da Morte:** *"A rede oscilou. O gateway de pagamento não respondeu. Seu sistema tenta de novo (retry). Como você garante que não vai cobrar o cliente duas vezes?"*

**O que estudar:**
*   **Idempotency Keys:** O conceito de enviar um ID único junto com a requisição.
    *   *Defesa:* "Na minha tabela `finance.payments`, tenho uma constraint `UNIQUE(idempotency_key)`. Se o retry tentar inserir a mesma chave, o banco rejeita (Do Nothing). O sistema é à prova de rede ruim."

### 5. Modelagem OLTP vs OLAP (Polyglot Persistence)
**A Pergunta da Morte:** *"Por que diabos você precisa de Postgres, ClickHouse E Redis? Não dava pra fazer tudo no Postgres?"*

**O que estudar:**
*   **Row-Store (Postgres) vs Column-Store (ClickHouse):**
    *   *Defesa:* "O Postgres grava linha a linha. Para somar o faturamento de 10 anos, ele tem que ler milhões de linhas inteiras no disco (IO pesado). O ClickHouse guarda colunas separadas. Para somar, ele lê só a coluna de valor. É 100x mais rápido para Analytics."
*   **Custo de Join:** NoSQL (Cassandra) e Analytics (ClickHouse) odeiam JOINs. Por isso desnormalizamos (repetimos dados) lá.

---

### O "Cheat Sheet" Teórico (Seus Argumentos Prontos)

Se o entrevistador perguntar... | Você responde com este conceito...
--- | ---
"E se o banco cair?" | "Failover Automático (RTO) e Replicação Assíncrona (RPO)."
"Como garante auditoria?" | "Imutabilidade no Log (Kafka) e nas tabelas de Auditoria."
"Como evolui o schema?" | "Padrão Expand & Contract e Schema Registry (Avro)."
"Como lida com LGPD?" | "Crypto-shredding e Tabela PII isolada."
"Por que não usou Locks?" | "Optimistic Concurrency Control (`version_id`)."

### Recomendação de Leitura "Express" (Para ler hoje à noite)

Não tente ler livros inteiros. Procure artigos no Medium ou documentação oficial sobre estes termos exatos:
1.  **"Postgres transactional outbox pattern with Debezium"** (Isso é o coração da sua integração).
2.  **"Postgres exclusion constraint tstzrange example"** (Para defender a modelagem temporal).
3.  **"Kafka partition key strategy ordering"** (Para defender a fila).
4.  **"Cassandra wide column data modeling guide"** (Para entender a tabela de telemetria).

Você tem a prática (o código que vamos fazer). Com esses conceitos teóricos, a defesa fica blindada.

Ainda não. No desenho que fizemos até agora, garantimos o **Outbox** (garantia de envio), mas não desenhamos explicitamente o **Inbox** (garantia de recebimento único).

Para o nível de **Senior Architect** e para cobrir o **Tópico 4 (Idempotency strategies)**, você **precisa** adicionar isso, ou pelo menos saber explicar como faria.

Aqui está a diferença e como implementar:

---

### O Conceito: O Par Perfeito
*   **Outbox Pattern (Quem Envia):** Garante que o evento **saiu** do banco de origem (ex: Core) e foi pro Kafka. "Não perdi a mensagem".
*   **Inbox Pattern (Quem Recebe):** Garante que o destino (ex: Financeiro) processou a mensagem **apenas uma vez**. "Não processei duplicado".

### Por que você precisa disso? (O Problema do Kafka)
O Kafka garante entrega **"At-Least-Once"** (Pelo menos uma vez).
Isso significa que, em caso de falha de rede ou estouro de timeout, o Kafka pode entregar a **mesma mensagem duas vezes** para o consumidor.

**Cenário de Desastre sem Inbox:**
1.  Serviço de Cobrança recebe evento `POLICY_CREATED`.
2.  Serviço debita o cartão do cliente.
3.  Serviço tenta avisar o Kafka "Já processei", mas a rede cai.
4.  O Kafka pensa "Ele não processou" e manda a mensagem de novo.
5.  Serviço recebe de novo e **debita o cartão de novo**.

### A Solução: Implementando o Inbox Pattern

Você cria uma tabela de controle no banco de dados do **Consumidor** (no caso, o Schema `finance`).

#### 1. O SQL (Adicione ao seu script)

```sql
CREATE SCHEMA integration;

-- Tabela genérica para controlar mensagens processadas
CREATE TABLE integration.inbox_processed_messages (
    message_id UUID PRIMARY KEY, -- O ID único do evento que veio do Kafka
    consumer_group VARCHAR(50) NOT NULL, -- Quem processou
    processed_at TIMESTAMPTZ DEFAULT NOW()
);

-- Dica de performance: Limpar essa tabela periodicamente (mensagens velhas não voltam)
```

#### 2. A Lógica da Transação (No código do Consumidor)

Quando o seu microsserviço (Worker) pega uma mensagem do Kafka, ele deve fazer isso dentro de uma transação do banco:

```sql
BEGIN; -- Inicia Transação

    -- Passo 1: Verifica se já processou essa mensagem
    -- Se retornar alguma linha, ABORTA. É duplicata.
    SELECT 1 FROM integration.inbox_processed_messages 
    WHERE message_id = 'uuid-do-evento-kafka';

    -- Passo 2: Executa a Lógica de Negócio (Ex: Gerar Boleto)
    INSERT INTO finance.invoices (...) VALUES (...);

    -- Passo 3: Marca como processado
    INSERT INTO integration.inbox_processed_messages (message_id, consumer_group)
    VALUES ('uuid-do-evento-kafka', 'finance-service');

COMMIT; -- Se der erro em qualquer passo, nada acontece.
```

---

### A Alternativa "Business Idempotency" (O jeito Senior de economizar Storage)
a
Existe um jeito de não precisar criar essa tabela `inbox`, se a sua modelagem de negócio for inteligente. Isso se chama **Idempotência de Negócio**.

Se o evento do Kafka traz o `policy_id`, e a sua tabela de faturas (`invoices`) tem uma constraint de unicidade:

```sql
CREATE TABLE finance.invoices (
    invoice_id UUID PRIMARY KEY,
    policy_id UUID NOT NULL UNIQUE, -- <--- O PULO DO GATO
    amount DECIMAL(10,2)
);
```

Se o Kafka mandar a mensagem duas vezes:
1.  Primeira vez: `INSERT` funciona.
2.  Segunda vez: `INSERT` falha com violação de chave única (`policy_id`).
3.  O código captura o erro, vê que é duplicação, ignora e segue a vida.

**Qual escolher para a entrevista?**

*   **Opção A (Tabela Inbox dedicada):** É mais "escolar" e tecnicamente pura. Funciona para qualquer cenário (mesmo enviar emails, onde não tem constraint de banco). Use se quiser mostrar domínio do padrão de integração.
*   **Opção B (Idempotência na Regra de Negócio):** É mais performática e pragmática. Use se quiser mostrar que sabe otimizar banco de dados.

**Minha recomendação:**
Diga na entrevista:
*"Para garantir idempotência (Tópico 4), eu utilizo chaves de unicidade de negócio no banco sempre que possível (Business Idempotency). Onde isso não é possível (ex: disparar um e-mail), eu implemento o **Inbox Pattern** com uma tabela de deduplicação para garantir que o efeito colateral só aconteça uma vez."*

Isso cobre todas as bases. Você mostra que conhece a técnica complexa (Inbox) mas prefere a simples (Constraint) quando dá.