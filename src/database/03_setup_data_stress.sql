-- =======================================================================================
-- PROCEDURE: sp_generate_stress_load
-- DESCRIPTION: Generate high-fidelity synthetic traffic for stress testing and chaos engineering.
-- USAGE: CALL sys.sp_generate_stress_load(1000, NULL); -- generates 1000 distributed policies
-- =======================================================================================

CREATE OR REPLACE PROCEDURE sys.sp_generate_stress_load(
    p_iterations INT DEFAULT 100,
    p_force_region TEXT DEFAULT NULL -- Se NULL, distribui aleatoriamente
)
LANGUAGE plpgsql
AS $$
DECLARE
    -- Constants & configuration
    v_regions TEXT[] := ARRAY['BR','US','EU'];
    v_products TEXT[] := ARRAY['AUTO_GLOBAL_V1', 'LIFE_PREMIUM_X', 'CYBER_RISK_2025', 'HOME_SMART'];

    -- Loop control variables
    v_start_time TIMESTAMP;
    v_region TEXT;
    v_pii_token UUID;
    v_policy_id UUID;
    v_version_id UUID;
    v_correlation_id UUID;
    v_premium NUMERIC(10,2);

    -- Generic mock data
    v_random_name TEXT;
    v_encryption_key TEXT := 'stress_test_key_2025'; -- Demo key; in prod use Vault/KMS
    i INT;
BEGIN
    v_start_time := clock_timestamp();
    RAISE NOTICE 'Starting stress test: % iterations...', p_iterations;

    FOR i IN 1..p_iterations LOOP
        
        -- 1. Definição de Contexto (Simula Roteamento Global)
        -- 1. Context setup (simulate global routing)
        -- Choose region either forced by parameter or random from the regions list.
        IF p_force_region IS NOT NULL THEN
            v_region := p_force_region;
        ELSE
            v_region := v_regions[FLOOR(random() * ARRAY_LENGTH(v_regions,1) + 1)];
        END IF;

        -- Simulate application context: set the session region for RLS usage
        PERFORM set_config('app.current_region', v_region, false);
        
        -- Generate IDs up-front to avoid extra round-trips
        v_pii_token := uuid_generate_v4(); -- new customer token
        v_policy_id := uuid_generate_v7(); -- time-ordered UUID for better insert locality
        v_correlation_id := uuid_generate_v4();
        
        -- Generate random payload variation
        v_premium := (random() * 1000 + 50)::NUMERIC(10,2);
        v_random_name := 'Customer_' || md5(random()::text); -- unique pseudo name

        -- 2. Inserção no Vault (Custo de CPU: Criptografia)
        -- 2. Vault insertion (CPU cost: encryption)
        -- Store PII encrypted; this is intentionally CPU-bound to simulate real workloads.
        INSERT INTO vault.customer_pii (
            pii_token, region_code, full_name_enc, tax_id_enc, email_enc, created_at
        ) VALUES (
            v_pii_token, 
            v_region,
            pgp_sym_encrypt(v_random_name, v_encryption_key), -- CPU intensive
            pgp_sym_encrypt('000.000.000-00', v_encryption_key),
            pgp_sym_encrypt(v_random_name || '@test.com', v_encryption_key),
            clock_timestamp()
        );

        -- 3. Inserção no Core (Custo de I/O e Índices)
        -- 3. Core insertion (I/O and index cost)
        -- Insert policy header; indexes and WAL volume are exercised here.
        INSERT INTO core.policies (
            policy_id, pii_token, region_code, product_code, fraud_risk_score
        ) VALUES (
            v_policy_id, 
            v_pii_token, 
            v_region, 
            v_products[FLOOR(random() * ARRAY_LENGTH(v_products,1) + 1)],
            random() -- initial random fraud score
        );

        -- 4. Inserção da Versão (Modelo Bi-temporal)
        -- 4. Insert version (bi-temporal model)
        -- A policy header without a version is not valid for claims; insert a version
        INSERT INTO core.policy_versions (
            policy_id, region_code, status, premium_amount, coverage_limit,
            valid_from, valid_to, version_number, metadata
        ) VALUES (
            v_policy_id, 
            v_region, 
            'ISSUED', 
            v_premium, 
            v_premium * 100,
            clock_timestamp(), -- valid from now
            clock_timestamp() + INTERVAL '1 year',
            1,
            '{"source": "stress_test_bot"}'::jsonb
        ) RETURNING version_id INTO v_version_id;

        -- 5. Inserção Financeira (Billing)
        -- 5. Billing insertion
        INSERT INTO billing.installments (
            policy_id, region_code, amount, due_date, status
        ) VALUES (
            v_policy_id,
            v_region,
            v_premium / 12, -- monthly installment
            CURRENT_DATE + 5,
            'PENDING'
        );

        -- 6. Transactional Outbox (Gatilho CDC)
        -- 6. Transactional outbox (CDC trigger)
        -- Build a JSONB payload to exercise the event pipeline (Debezium -> Redpanda).
        INSERT INTO sys.transactional_outbox (
            correlation_id,
            aggregate_type,
            aggregate_id,
            event_type,
            payload,
            region_code,
            trace_parent
        ) VALUES (
            v_correlation_id,
            'POLICY',
            v_policy_id,
            'POLICY_ISSUED',
            jsonb_build_object(
                'policy_id', v_policy_id,
                'customer_token', v_pii_token,
                'premium', v_premium,
                'timestamp', clock_timestamp(),
                'region', v_region,
                'simulation_metadata', jsonb_build_object('load_test', true, 'batch_id', v_start_time)
            ),
            v_region,
            '00-' || replace(uuid_generate_v4()::text, '-', '') || '-01' -- synthetic OpenTelemetry trace id
        );

        -- Commit a cada X registros para não estourar memória do WAL em testes massivos
        -- Commit every X records to avoid excessive WAL growth during heavy load tests
        -- (Optional: remove for full atomicity of the entire batch)
        IF MOD(i, 500) = 0 THEN
            COMMIT;
            RAISE NOTICE 'Processed: % records...', i;
        END IF;

    END LOOP;
    RAISE NOTICE 'Stress test finished. Total inserted: % in %', p_iterations, age(clock_timestamp(), v_start_time);
END;
$$;