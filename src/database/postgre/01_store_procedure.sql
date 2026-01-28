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
    v_region_code VARCHAR(5);
    v_current_claim_id UUID;
    -- Capturamos o tempo fixo da operação para consistência em todas as tabelas
    v_op_timestamp TIMESTAMPTZ := now(); 
BEGIN
    -- 1. Verificação de Idempotência (Busca na tabela particionada)
    SELECT claim_id, status INTO v_current_claim_id, o_status
    FROM finance.claims 
    WHERE idempotency_key = p_idempotency_key
      -- Dica Sênior: Se soubermos que o retry vem em até 24h, 
      -- podemos filtrar o tempo aqui para acelerar a busca no índice.
    LIMIT 1;

    IF v_current_claim_id IS NOT NULL THEN
        RETURN QUERY SELECT v_current_claim_id, o_status::TEXT, 'Idempotent replay'::TEXT;
        RETURN;
    END IF;

    -- 2. Validação Bi-temporal
    SELECT policy_version_id, customer_id
    INTO v_policy_version_id, v_customer_id
    FROM core.policies
    WHERE policy_id = p_policy_id
      AND p_incident_date <@ validity_period
      AND status = 'ACTIVE'
    LIMIT 1; -- Removi o ORDER BY para satisfazer os puristas, já que o GIST garante 1 linha.

    IF v_policy_version_id IS NULL THEN
        RETURN QUERY SELECT NULL::UUID, 'REJECTED'::TEXT, 'No active coverage found.'::TEXT;
        RETURN;
    END IF;

    -- 3. Inserção com Timestamp Controlado
    v_current_claim_id := uuid_generate_v7(); 
    v_region_code := 'BR'; -- Em produção, isso viria de uma config global

    INSERT INTO finance.claims (
        claim_id, policy_id, policy_version_id, incident_date, 
        created_at, -- Usando o tempo fixo da variável
        estimated_loss_amount, estimated_loss_currency, status, idempotency_key
    ) VALUES (
        v_current_claim_id, p_policy_id, v_policy_version_id, p_incident_date, 
        v_op_timestamp, 
        p_estimated_loss_amount, p_estimated_loss_currency, 'OPEN', p_idempotency_key
    );

    -- 4. Outbox com o MESMO timestamp do sinistro
    INSERT INTO sys.transactional_outbox (
        correlation_id, aggregate_type, aggregate_id, event_type, 
        payload, region_code, occurred_at
    ) VALUES (
        gen_random_uuid(), 'CLAIM', v_current_claim_id, 'CLAIM_CREATED',
        jsonb_build_object(
            'claim_id', v_current_claim_id,
            'policy_id', p_policy_id,
            'occurred_at', v_op_timestamp -- Consistência total para o analítico
        ),
        v_region_code, v_op_timestamp
    );

    RETURN QUERY SELECT v_current_claim_id, 'CREATED'::TEXT, 'Success.'::TEXT;

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
    v_customer_id UUID := gen_random_uuid();
    v_policy_id UUID := gen_random_uuid();
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
        'POL-' || upper(left(gen_random_uuid()::text, 8)),
        v_customer_id,
        'SEED-' || gen_random_uuid(),
        tstzrange(NOW() - INTERVAL '1 month', NOW() + INTERVAL '11 months'),
        'ACTIVE',
        'AUTO-GOLD-001',
        '{"vehicle": "Tesla Model 3", "year": 2024}'::jsonb
    );
    
    RAISE NOTICE 'Seed Complete: Policy Version % created.', v_policy_version_id;
END;
$$;
