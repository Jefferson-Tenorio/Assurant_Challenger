-- Função de Diff JSONB (Otimizada)
-- TODO: A função utils.jsonb_diff_val usa CPU. Se você fizer um batch update de 1 milhão de linhas, a CPU do banco vai subir por causa do cálculo do diff JSON em cada linha. Fique de olho no métrica de CPU durante migrações de dados massivas.
CREATE OR REPLACE FUNCTION utils.jsonb_diff_val(val1 JSONB, val2 JSONB)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
    v RECORD;
BEGIN
    result = val2;
    FOR v IN SELECT * FROM jsonb_each(val1) LOOP
        IF result @> jsonb_build_object(v.key, v.value) THEN
            result = result - v.key;
        ELSIF result ? v.key THEN
            CONTINUE;
        END IF;
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql PARALLEL SAFE IMMUTABLE;

CREATE OR REPLACE FUNCTION audit.log_changes_trigger()
RETURNS TRIGGER AS $$
DECLARE
    json_old JSONB;
    json_new JSONB;
    json_diff JSONB;
    rec_id UUID;
BEGIN
    -- LÓGICA DE DETECÇÃO DE PK MANUAL (Segura para este Schema)
    -- Ajuste aqui se adicionar novas tabelas com nomes de PK diferentes
    IF (TG_TABLE_NAME = 'policies') THEN
        IF TG_OP = 'DELETE' THEN rec_id := OLD.policy_version_id;
        ELSE rec_id := NEW.policy_version_id; END IF;
    ELSIF (TG_TABLE_NAME = 'customers_pii') THEN
         IF TG_OP = 'DELETE' THEN rec_id := OLD.customer_id;
         ELSE rec_id := NEW.customer_id; END IF;
    ELSE
        -- Fallback genérico (pode falhar se não existir coluna 'id')
        -- Idealmente usar introspecção dinâmica, mas custa performance.
        BEGIN
            IF TG_OP = 'DELETE' THEN rec_id := OLD.id;
            ELSE rec_id := NEW.id; END IF;
        EXCEPTION WHEN OTHERS THEN
            rec_id := '00000000-0000-0000-0000-000000000000'::uuid; -- Placeholder para não abortar transação
        END;
    END IF;

    IF (TG_OP = 'DELETE') THEN
        json_diff := to_jsonb(OLD);
    ELSE
        IF (TG_OP = 'INSERT') THEN
            json_diff := to_jsonb(NEW);
        ELSIF (TG_OP = 'UPDATE') THEN
            json_old := to_jsonb(OLD);
            json_new := to_jsonb(NEW);
            json_diff := utils.jsonb_diff_val(json_old, json_new);
            
            IF json_diff = '{}'::jsonb THEN
                RETURN NEW;
            END IF;
        END IF;
    END IF;

    INSERT INTO audit.change_logs (
        table_name, record_id, operation, changed_by, changes
    ) VALUES (
        TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
        rec_id,
        TG_OP,
        COALESCE(current_setting('app.current_user', true), 'system'),
        json_diff
    );

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;