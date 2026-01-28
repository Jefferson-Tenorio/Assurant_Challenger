CREATE OR REPLACE FUNCTION core.fn_register_claim(
    p_idempotency_key UUID,
    p_policy_id UUID,
    p_incident_date TIMESTAMP WITH TIME ZONE,
    p_estimated_loss_amount DECIMAL(18, 2),
    p_estimated_loss_currency currency_code_enum,
    p_metadata JSONB,
    p_trace_parent TEXT 
) RETURNS TABLE (
    o_claim_id UUID, 
    o_status TEXT, 
    o_message TEXT
) AS $$
DECLARE
    v_policy_version_id UUID;
    v_customer_id UUID;
    v_current_claim_id UUID;
    v_op_timestamp TIMESTAMPTZ := now();
    v_stored_json JSONB;
BEGIN
    -- ---------------------------------------------------------------------------
    -- PASSO 1: O GATEKEEPER (IDEMPOTÊNCIA REAL)
    -- Tentamos inserir a chave. Se já existir, capturamos o resultado anterior.
    -- ---------------------------------------------------------------------------
    BEGIN
        -- Usamos um placeholder inicial. O resultado real será atualizado no fim.
        INSERT INTO sys.idempotency_registry (idempotency_key, stored_result)
        VALUES (p_idempotency_key, jsonb_build_object('status', 'PROCESSING'))
        RETURNING stored_result INTO v_stored_json;
        
    EXCEPTION WHEN unique_violation THEN
        -- Se caiu aqui, é um replay. Buscamos o ID e Status que foram gerados na primeira vez.
        SELECT stored_result INTO v_stored_json 
        FROM sys.idempotency_registry 
        WHERE idempotency_key = p_idempotency_key;
        
        RETURN QUERY SELECT 
            (v_stored_json->>'claim_id')::UUID, 
            (v_stored_json->>'status')::TEXT, 
            'Idempotent replay: Result from registry'::TEXT;
        RETURN;
    END;

    -- ---------------------------------------------------------------------------
    -- PASSO 2: VALIDAÇÃO BI-TEMPORAL
    -- ---------------------------------------------------------------------------
    SELECT policy_version_id, customer_id
    INTO v_policy_version_id, v_customer_id
    FROM core.policies
    WHERE policy_id = p_policy_id
      AND p_incident_date <@ validity_period
      AND status = 'ACTIVE'
    LIMIT 1;

    IF v_policy_version_id IS NULL THEN
        -- Se falhar a validação, removemos do registro para permitir tentar de novo com outra apólice
        DELETE FROM sys.idempotency_registry WHERE idempotency_key = p_idempotency_key;
        RETURN QUERY SELECT NULL::UUID, 'REJECTED'::TEXT, 'No active coverage.'::TEXT;
        RETURN;
    END IF;

    -- ---------------------------------------------------------------------------
    -- PASSO 3: INSERÇÃO NO SINISTRO (PARTICIONADO) E OUTBOX
    -- ---------------------------------------------------------------------------
    v_current_claim_id := uuid_generate_v7();

    INSERT INTO finance.claims (
        claim_id, policy_id, policy_version_id, incident_date, 
        created_at, estimated_loss_amount, estimated_loss_currency, status, idempotency_key
    ) VALUES (
        v_current_claim_id, p_policy_id, v_policy_version_id, p_incident_date, 
        v_op_timestamp, p_estimated_loss_amount, p_estimated_loss_currency, 'OPEN', p_idempotency_key
    );

    -- ---------------------------------------------------------------------------
    -- PASSO 4: ATUALIZAR O REGISTRO DE IDEMPOTÊNCIA COM O RESULTADO FINAL
    -- ---------------------------------------------------------------------------
    UPDATE sys.idempotency_registry 
    SET stored_result = jsonb_build_object(
        'claim_id', v_current_claim_id,
        'status', 'OPEN'
    )
    WHERE idempotency_key = p_idempotency_key;

    -- Outbox e Sucesso...
    INSERT INTO sys.transactional_outbox (...) VALUES (...);

    RETURN QUERY SELECT v_current_claim_id, 'CREATED'::TEXT, 'Success.'::TEXT;

END;
$$ LANGUAGE plpgsql;
