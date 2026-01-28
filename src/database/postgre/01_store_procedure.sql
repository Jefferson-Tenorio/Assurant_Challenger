CREATE OR REPLACE FUNCTION core.fn_register_claim(
    p_idempotency_key UUID, -- Alterado para UUID para dar match com a tabela finance.claims
    p_policy_id UUID,
    p_incident_date TIMESTAMP WITH TIME ZONE,
    p_estimated_loss_amount DECIMAL(18, 2),
    p_estimated_loss_currency currency_code_enum, -- Usando o ENUM definido no seu schema
    p_metadata JSONB,
    p_trace_parent TEXT 
) RETURNS TABLE (
    o_claim_id UUID, 
    o_status TEXT, 
    o_message TEXT
) AS $$
DECLARE
    v_policy_version_id UUID;
    v_region_code VARCHAR(5);
    v_current_claim_id UUID;
    v_customer_id UUID;
BEGIN
    -- ---------------------------------------------------------------------------
    -- PASSO 1: VERIFICAÇÃO DE IDEMPOTÊNCIA
    -- Buscamos na tabela correta: finance.claims
    -- ---------------------------------------------------------------------------
    SELECT claim_id, status INTO v_current_claim_id, o_status
    FROM finance.claims 
    WHERE idempotency_key = p_idempotency_key
    LIMIT 1;

    IF v_current_claim_id IS NOT NULL THEN
        RETURN QUERY SELECT v_current_claim_id, o_status::TEXT, 'Idempotent replay: Claim already exists.'::TEXT;
        RETURN;
    END IF;

    -- ---------------------------------------------------------------------------
    -- PASSO 2: VALIDAÇÃO BI-TEMPORAL (Time-travel)
    -- Verificamos se o p_incident_date está DENTRO do validity_period (tstzrange)
    -- ---------------------------------------------------------------------------
    SELECT 
        policy_version_id, 
        customer_id
    INTO 
        v_policy_version_id, 
        v_customer_id
    FROM core.policies
    WHERE policy_id = p_policy_id
      AND p_incident_date <@ validity_period -- Operador "está contido no range"
      AND status = 'ACTIVE'
    ORDER BY version_id DESC -- Pega a versão mais recente caso haja overlap (segurança)
    LIMIT 1;

    -- Se não encontrar apólice ativa para essa data, rejeita.
    IF v_policy_version_id IS NULL THEN
        RETURN QUERY SELECT NULL::UUID, 'REJECTED'::TEXT, 'No active coverage found for the incident date.'::TEXT;
        RETURN;
    END IF;

    -- ---------------------------------------------------------------------------
    -- PASSO 3: PERSISTÊNCIA ATÔMICA (Domain + Outbox)
    -- ---------------------------------------------------------------------------
    v_current_claim_id := uuid_generate_v7(); 
    
    -- Aqui definimos a região com base em uma variável de ambiente ou lógica de negócio
    -- No exemplo, vou extrair do contexto ou parâmetro. Se não tiver, definimos 'BR' como default.
    v_region_code := 'BR'; 

    -- 3.1 Inserir Sinistro (finance.claims)
    INSERT INTO finance.claims (
        claim_id, 
        policy_id, 
        policy_version_id,
        incident_date, 
        estimated_loss_amount, 
        estimated_loss_currency,
        status, 
        idempotency_key,
        rejection_reason
    ) VALUES (
        v_current_claim_id, 
        p_policy_id, 
        v_policy_version_id,
        p_incident_date, 
        p_estimated_loss_amount, 
        p_estimated_loss_currency,
        'OPEN', 
        p_idempotency_key,
        NULL
    );

    -- 3.2 Transactional Outbox (sys.transactional_outbox)
    INSERT INTO sys.transactional_outbox (
        correlation_id,
        aggregate_type,
        aggregate_id,
        event_type,
        payload,
        region_code
    ) VALUES (
        gen_random_uuid(), -- correlation id
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
            'trace_parent', p_trace_parent,
            'metadata', p_metadata
        ),
        v_region_code
    );

    RETURN QUERY SELECT v_current_claim_id, 'CREATED'::TEXT, 'Claim successfully registered.'::TEXT;

EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Error processing claim: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;
