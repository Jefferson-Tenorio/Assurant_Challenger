-- Polyfill for UUID v7 (Postgres 16 has no native UUID v7 yet)
CREATE OR REPLACE FUNCTION uuid_generate_v7()
RETURNS uuid
AS $$
BEGIN
    RETURN encode(
        set_bit(
            set_bit(
                overlay(
                    uuid_send(gen_random_uuid())
                    placing substring(int8send(floor(extract(epoch from clock_timestamp()) * 1000)::bigint) from 3)
                    from 1 for 6
                ),
                50, 1
            ),
            51, 1
        ),
        'hex')::uuid;
END
$$ LANGUAGE plpgsql;
-- FILE: 01_stored_procedure.sql
-- DESCRIPTION: Business logic encapsulated as DB functions/procedures
--              (Idempotency, bi-temporal validation and transactional outbox)
-- 1. FUNCTION: REGISTER CLAIM (SAFE)
-- Purpose: validate historical coverage (bi-temporal), enforce idempotency,
-- and persist both the domain object and a transactional outbox event atomically.
CREATE OR REPLACE FUNCTION core.fn_register_claim(
    p_idempotency_key TEXT,
    p_policy_id UUID,
    p_incident_date TIMESTAMP WITH TIME ZONE,
    p_estimated_payout DECIMAL(18, 2),
    p_metadata JSONB,
    p_trace_parent TEXT -- Para OpenTelemetry
) RETURNS TABLE (
    o_claim_id UUID, 
    o_status TEXT, 
    o_message TEXT
) AS $$
DECLARE
    v_policy_version_id UUID;
    v_region_code VARCHAR(5);
    v_current_claim_id UUID;
    v_customer_token UUID;
BEGIN
    -- ---------------------------------------------------------------------------
    -- STEP 1: IDEMPOTENCY CHECK
    -- If the same idempotency key was already processed, return the existing claim.
    -- This allows clients to safely retry without creating duplicates.
    -- NOTE: we intentionally do not filter by region here because idempotency keys
    -- must be globally unique and we must search across partitions.
    -- ---------------------------------------------------------------------------
    SELECT claim_id, status INTO v_current_claim_id, o_status
    FROM core.claims 
    WHERE idempotency_key = p_idempotency_key
    LIMIT 1;

    IF v_current_claim_id IS NOT NULL THEN
        RETURN QUERY SELECT v_current_claim_id, o_status::TEXT, 'Idempotent replay: Claim already exists.'::TEXT;
        RETURN;
    END IF;

    -- ---------------------------------------------------------------------------
    -- STEP 2: BI-TEMPORAL VALIDATION (Time-travel logic)
    -- The claim is valid only if the policy was ACTIVE at the incident timestamp.
    -- This validates business time (effective coverage) regardless of current state.
    -- We also read the policy's region_code and the pii token to route inserts and
    -- to include a pseudonymous token in the outbox payload for analytics use.
    -- ---------------------------------------------------------------------------
    SELECT 
        pv.version_id, 
        pv.region_code,
        p.pii_token
    INTO 
        v_policy_version_id, 
        v_region_code,
        v_customer_token
    FROM core.policy_versions pv
    JOIN core.policies p ON p.policy_id = pv.policy_id AND p.region_code = pv.region_code
    WHERE pv.policy_id = p_policy_id
      AND p_incident_date >= pv.valid_from 
      AND p_incident_date < pv.valid_to
      AND pv.status = 'ACTIVE'
      AND pv.superseded_at IS NULL 
    LIMIT 1;

    -- If no matching active version, reject the claim with a clear message.
    IF v_policy_version_id IS NULL THEN
        RETURN QUERY SELECT NULL::UUID, 'REJECTED'::TEXT, 'No active coverage found for the incident date.'::TEXT;
        RETURN;
    END IF;

    -- ---------------------------------------------------------------------------
    -- STEP 3: ATOMIC PERSISTENCE (domain object + transactional outbox)
    -- We insert the claim into the appropriate regional partition, then insert
    -- the outbox event in the same transaction. Debezium will pick up the outbox
    -- row and publish to the event backbone (Redpanda/Kafka).
    -- ---------------------------------------------------------------------------
    v_current_claim_id := uuid_generate_v7(); -- time-ordered UUID (better insert locality)

    -- 3.1 Insert the claim into the region partition determined above
    INSERT INTO core.claims (
        claim_id, 
        policy_id, 
        region_code,
        incident_date, 
        estimated_payout, 
        status, 
        idempotency_key,
        metadata
    ) VALUES (
        v_current_claim_id, 
        p_policy_id, 
        v_region_code,
        p_incident_date, 
        p_estimated_payout, 
        'OPEN', 
        p_idempotency_key,
        p_metadata
    );

    -- 3.2 Transactional Outbox: guarantees the event exists only if the insert succeeded.
    -- Debezium reads the outbox table (logical decoding) and publishes a "CLAIM_CREATED" event.
    INSERT INTO sys.transactional_outbox (
        correlation_id,
        aggregate_type,
        aggregate_id,
        event_type,
        payload,
        region_code,
        trace_parent
    ) VALUES (
        uuid_generate_v4(), -- correlation id for tracing across services
        'CLAIM',
        v_current_claim_id,
        'CLAIM_CREATED',
        jsonb_build_object(
            'claim_id', v_current_claim_id,
            'policy_id', p_policy_id,
            'pii_token', v_customer_token, -- pseudonym used for analytics (no direct PII)
            'amount', p_estimated_payout,
            'incident_date', p_incident_date,
            'region_code', v_region_code,
            'risk_context', p_metadata
        ),
        v_region_code,
        p_trace_parent
    );

    -- ---------------------------------------------------------------------------
    -- STEP 4: SUCCESS RETURN
    -- Return the created claim id and status to the caller.
    -- ---------------------------------------------------------------------------
    RETURN QUERY SELECT v_current_claim_id, 'CREATED'::TEXT, 'Claim successfully registered.'::TEXT;

EXCEPTION WHEN OTHERS THEN
    -- Rollback is automatic on exception; surface the error for diagnostics.
    RAISE EXCEPTION 'Error processing claim: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;


-- 2. HELPER PROCEDURE: SEED MOCK POLICY
-- Convenience procedure to create a policy with the required PII entry in the vault
-- and an initial active policy_version. Useful for local testing/demos.
CREATE OR REPLACE PROCEDURE core.sp_seed_mock_policy(
    p_region VARCHAR,
    p_customer_name TEXT,
    p_tax_id TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_pii_token UUID := uuid_generate_v4();
    v_policy_id UUID := uuid_generate_v7();
BEGIN
    -- 1. Insert sensitive data into the Vault schema (should be encrypted and access-controlled)
    INSERT INTO vault.customer_pii (pii_token, full_name_enc, tax_id_enc, region_code)
    VALUES (
        v_pii_token, 
        pgp_sym_encrypt(p_customer_name, 'chave_segura_regional'), 
        pgp_sym_encrypt(p_tax_id, 'chave_segura_regional'),
        p_region
    );

    -- 2. Create the policy header record
    INSERT INTO core.policies (policy_id, pii_token, region_code, product_code)
    VALUES (v_policy_id, v_pii_token, p_region, 'GLOBAL_LIFE_V1');

    -- 3. Create an initial policy version valid for one year (business effective time)
    INSERT INTO core.policy_versions (
        policy_id, region_code, status, premium_amount, coverage_limit,
        valid_from, valid_to, version_number
    ) VALUES (
        v_policy_id, p_region, 'ACTIVE', 100.00, 50000.00,
        NOW() - INTERVAL '1 month', -- started one month ago
        NOW() + INTERVAL '11 months',
        1
    );
    
    RAISE NOTICE 'Mock Data Created: Policy % in Region %', v_policy_id, p_region;
END;
$$;