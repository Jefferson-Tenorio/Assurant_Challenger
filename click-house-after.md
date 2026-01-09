Fico muito feliz que a infraestrutura esteja estável! 🚀

Agora que o "esqueleto" (Infra) está pronto, precisamos dar vida ao projeto e prepará-lo para o **Desafio de Código**. O objetivo agora deixa de ser "fazer funcionar" e passa a ser **"provar que aguenta o tranco"** e **"extrair valor dos dados"**.

Aqui estão os próximos passos estratégicos para você brilhar no desafio:

---

### 1. Preparar o Cenário de Stress (Load Testing) 💥

Você mencionou que o banco será estressado. Não espere o avaliador fazer isso; faça você mesmo para garantir que não vai quebrar na hora H.

**O que fazer:**
Crie um script (pode ser em Node.js, Python ou Go, ou use uma ferramenta como [k6](https://k6.io/)) que bombardeie a sua API/Redpanda.

*   **Meta:** Tente enviar, por exemplo, **10.000 eventos em 1 minuto**.
*   **O que observar:**
    1.  **Consumer Lag:** O ClickHouse consegue acompanhar ou ele fica muito atrasado?
    2.  **Erro de Memória:** Se o container do ClickHouse reiniciar (`Exited (137)`), aumente a RAM no Docker.
    3.  **Monitoramento:** Abra um segundo terminal e rode `docker stats` para ver CPU/RAM "fritando" em tempo real.

### 2. Criar Queries Analíticas de "Negócio" 📊

Ter os dados lá é legal, mas o avaliador quer ver *insights*. Crie um arquivo `queries.sql` no seu repo com consultas que mostram o poder do ClickHouse.

**Exemplos para você testar:**

*   **Volume por Minuto (Ótimo para provar a ingestão):**
    ```sql
    SELECT
        toStartOfMinute(occurred_at) as minuto,
        count() as total_eventos
    FROM insurance.outbox_analytics
    GROUP BY minuto
    ORDER BY minuto DESC
    LIMIT 20;
    ```

*   **Distribuição por Região (Agregação rápida):**
    ```sql
    SELECT
        region_code,
        count() as qtd,
        bar(qtd, 0, (SELECT max(count()) FROM insurance.outbox_analytics GROUP BY region_code), 20) as visual
    FROM insurance.outbox_analytics
    GROUP BY region_code
    ORDER BY qtd DESC;
    ```
    *(A função `bar` desenha um gráfico de barras no próprio terminal! Avaliadores adoram isso).*

---

### 3. Configurar um TTL (Time To Live) ⏳

Em desafios de Big Data, mostrar que você se preocupa com o custo de armazenamento é um diferencial de Senioridade. Dados velhos devem ser apagados automaticamente.

**Ação:** Adicione uma política de retenção na sua tabela.
Execute este comando (ou adicione no seu SQL de criação):

```sql
ALTER TABLE insurance.outbox_analytics
MODIFY TTL occurred_at + INTERVAL 30 DAY;
```
*Isso diz ao ClickHouse: "Dados com mais de 30 dias podem ser excluídos automaticamente para economizar disco".*

---

### 4. (Opcional) Visualização com Grafana 📈

Se sobrar tempo e você quiser o "Efeito Uau", suba um container do **Grafana**.

1.  Adicione o Grafana no `docker-compose.yml`.
2.  Instale o plugin do ClickHouse no Grafana.
3.  Crie um Dashboard simples mostrando:
    *   Taxa de ingestão (Eventos/segundo).
    *   Pizza de Tipos de Eventos.

*Se achar complexo agora, pule. As queries no terminal com a função `bar` já impressionam bastante.*

---

### 5. Documentar a Performance 📝

No seu `README.md`, adicione uma seção chamada **"Performance Benchmark"**.

Coloque algo como:
> "Durante os testes de stress, o sistema processou **X mil eventos/segundo** com consumo de memória estável em **Y GB**, mantendo a latência de ingestão (Redpanda -> Disponível para Query) abaixo de **Z segundos**."

---

### Resumo do Plano de Ação:

1.  **Script de Ataque:** Crie um loop que mande milhares de JSONs para o Redpanda.
2.  **Validação:** Rode o `docker stats` e veja o ClickHouse trabalhando.
3.  **Queries:** Teste as queries com a função `bar` que te passei acima.
4.  **Limpeza:** Aplique o `TTL`.

Precisa de ajuda para montar o script de stress test ou prefere focar nas queries primeiro?