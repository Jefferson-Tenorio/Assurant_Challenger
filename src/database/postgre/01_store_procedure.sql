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
    v_region_code VARCHAR(5) := 'BR'; -- Configuração regional
BEGIN
    -- 1. GATEKEEPER (IDEMPOTÊNCIA GLOBAL)
    BEGIN
        INSERT INTO sys.idempotency_registry (idempotency_key, stored_result)
        VALUES (p_idempotency_key, jsonb_build_object('status', 'PROCESSING'))
        RETURNING stored_result INTO v_stored_json;
        
    EXCEPTION WHEN unique_violation THEN
        SELECT stored_result INTO v_stored_json 
        FROM sys.idempotency_registry 
        WHERE idempotency_key = p_idempotency_key;
        
        RETURN QUERY SELECT 
            (v_stored_json->>'claim_id')::UUID, 
            (v_stored_json->>'status')::TEXT, 
            'Idempotent replay: Result from registry'::TEXT;
        RETURN;
    END;

    -- 2. VALIDAÇÃO BI-TEMPORAL
    SELECT policy_version_id, customer_id
    INTO v_policy_version_id, v_customer_id
    FROM core.policies
    WHERE policy_id = p_policy_id
      AND p_incident_date <@ validity_period
      AND status = 'ACTIVE'
    LIMIT 1;

    IF v_policy_version_id IS NULL THEN
        DELETE FROM sys.idempotency_registry WHERE idempotency_key = p_idempotency_key;
        RETURN QUERY SELECT NULL::UUID, 'REJECTED'::TEXT, 'No active coverage found.'::TEXT;
        RETURN;
    END IF;

    -- 3. GERAÇÃO DE ID E PERSISTÊNCIA DO SINISTRO
    v_current_claim_id := uuid_generate_v7();

    INSERT INTO finance.claims (
        claim_id, 
        policy_id, 
        policy_version_id, 
        incident_date, 
        created_at, 
        estimated_loss_amount, 
        estimated_loss_currency, 
        status, 
        idempotency_key
    ) VALUES (
        v_current_claim_id, 
        p_policy_id, 
        v_policy_version_id, 
        p_incident_date, 
        v_op_timestamp, 
        p_estimated_loss_amount, 
        p_estimated_loss_currency, 
        'OPEN', 
        p_idempotency_key
    );

    -- 4. INSERÇÃO NO TRANSACTIONAL OUTBOX (SUBSTITUÍDOS OS '...')
    INSERT INTO sys.transactional_outbox (
        correlation_id,
        aggregate_type,
        aggregate_id,
        event_type,
        payload,
        region_code,
        occurred_at
    ) VALUES (
        gen_random_uuid(), -- Correlation ID para tracing
        'CLAIM',
        v_current_claim_id,
        'CLAIM_CREATED',
        jsonb_build_object(
            'claim_id', v_current_claim_id,
            'policy_id', p_policy_id,
            'customer_id', v_customer_id,
            'amount', p_estimated_loss_amount,
            'currency', p_estimated_loss_currency,
            'incident_date', p_incident_date,
            'metadata', p_metadata,
            'trace_parent', p_trace_parent
        ),
        v_region_code,
        v_op_timestamp
    );

    -- 5. ATUALIZAR REGISTRO DE IDEMPOTÊNCIA COM RESULTADO FINAL
    UPDATE sys.idempotency_registry 
    SET stored_result = jsonb_build_object(
        'claim_id', v_current_claim_id,
        'status', 'OPEN'
    )
    WHERE idempotency_key = p_idempotency_key;

    RETURN QUERY SELECT v_current_claim_id, 'CREATED'::TEXT, 'Claim successfully registered.'::TEXT;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE core.sp_seed_mock_policy(
    p_customer_name TEXT,
    p_tax_id TEXT,
    p_tax_id_blind VARCHAR(64)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_id UUID := uuid_generate_v7();
    v_policy_id UUID := uuid_generate_v7();
    v_policy_version_id UUID := uuid_generate_v7();
BEGIN
    -- 1. Inserir no Schema de Acesso (PII)
    INSERT INTO access.customers_pii (
        customer_id, full_name_encrypted, tax_id_encrypted, 
        email, phone_encrypted, key_version_id, tax_id_blind_index
    ) VALUES (
        v_customer_id, 
        p_customer_name::bytea, -- Em prod, use pgp_sym_encrypt
        p_tax_id::bytea, 
        'test@assurant.com', 
        '123456789'::text, 
        1, 
        p_tax_id_blind
    );

    -- 2. Criar a Apólice (Versão Inicial)
    -- Note: policy_id é o ID lógico, policy_version_id é a PK física da linha
    INSERT INTO core.policies (
        policy_version_id, policy_id, policy_number, customer_id, 
        idempotency_key, validity_period, status, product_code, risk_attributes
    ) VALUES (
        v_policy_version_id,
        v_policy_id,
        -- Usa 4 caracteres do tempo e 4 da parte aleatória
        'POL-' || upper(left(uuid_generate_v7()::text, 4) || right(uuid_generate_v7()::text, 4)),
        v_customer_id,
        'SEED-' || uuid_generate_v7(),
        tstzrange(NOW() - INTERVAL '1 month', NOW() + INTERVAL '11 months'),
        'ACTIVE',
        'AUTO-GOLD-001',
        '{"vehicle": "Tesla Model 3", "year": 2024}'::jsonb
    );
    
        RAISE NOTICE '---------------------------------------------------';
    RAISE NOTICE 'SEED COMPLETED SUCCESSFULLY';
    RAISE NOTICE 'Customer ID: %', v_customer_id;
    RAISE NOTICE 'POLICY ID (Use this for Claims): %', v_policy_id; -- O ID QUE IMPORTA
    RAISE NOTICE 'Version ID (Physical): %', v_policy_version_id;
    RAISE NOTICE '---------------------------------------------------';
END;
$$;
