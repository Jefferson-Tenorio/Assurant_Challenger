-- =======================================================================================
-- FILE: 02_seed_data.sql
-- DESCRIPTION: Initial seed data (golden records) for demos and local testing.
-- NOTE: Run as a superuser if you need to bypass RLS during initial load.
-- =======================================================================================

BEGIN;

-- 1. PRECAUTIONARY CLEANUP (truncate in FK-safe order)
-- Truncate tables to start from a known state for local demos/tests.
TRUNCATE TABLE sys.transactional_outbox CASCADE;
TRUNCATE TABLE core.claims CASCADE;
TRUNCATE TABLE billing.installments CASCADE;
TRUNCATE TABLE core.policy_versions CASCADE;
TRUNCATE TABLE core.policies CASCADE;
TRUNCATE TABLE vault.customer_pii CASCADE;

-- 2. ANONYMOUS BLOCK TO GENERATE RELATED DATA (consistent UUIDs)
-- We generate PII tokens and policy IDs per region, then insert related rows.
-- For demos we use a local symmetric key; in production this should be managed
-- by Vault/KMS and never hard-coded.
DO $$
DECLARE
    -- Variables for BR
    v_pii_br UUID := uuid_generate_v4();
    v_pol_br UUID := uuid_generate_v7();
    
    -- Variables for US
    v_pii_us UUID := uuid_generate_v4();
    v_pol_us UUID := uuid_generate_v7();
    
    -- Variables for EU
    v_pii_eu UUID := uuid_generate_v4();
    v_pol_eu UUID := uuid_generate_v7();
    
    -- Demo encryption key (use Vault in real deployments)
    v_key TEXT := 'segredo_regional_2025';
BEGIN

    -- ========================================================================
    -- SCENARIO 1: BRAZIL - CUSTOMER "JOÃO SILVA" (Active policy, one installment paid)
    -- ========================================================================
    RAISE NOTICE 'Seeding BR Data...';
    
    -- A. Vault entry (encrypted PII)
    INSERT INTO vault.customer_pii (pii_token, region_code, full_name_enc, tax_id_enc, email_enc, date_of_birth)
    VALUES (
        v_pii_br, 'BR',
        pgp_sym_encrypt('João da Silva', v_key), -- encrypted full name
        pgp_sym_encrypt('123.456.789-00', v_key), -- encrypted tax id (CPF)
        pgp_sym_encrypt('joao.silva@email.com.br', v_key),
        '1985-05-20'
    );

    -- B. Core policy header
    INSERT INTO core.policies (policy_id, pii_token, region_code, product_code, fraud_risk_score)
    VALUES (v_pol_br, v_pii_br, 'BR', 'AUTO_PREMIUM_V2', 0.05);

    -- C. Policy version (business effective dates)
    INSERT INTO core.policy_versions (
        policy_id, region_code, status, premium_amount, coverage_limit,
        valid_from, valid_to, version_number
    ) VALUES (
        v_pol_br, 'BR', 'ACTIVE', 2500.00, 150000.00,
        NOW() - INTERVAL '6 months', -- started 6 months ago
        NOW() + INTERVAL '6 months', -- expires in 6 months
        1
    );

    -- D. Billing: one installment already paid (demonstrates billing joins)
    INSERT INTO billing.installments (policy_id, region_code, amount, due_date, status)
    VALUES (v_pol_br, 'BR', 2500.00, CURRENT_DATE - 10, 'PAID');


    -- ========================================================================
    -- SCENARIO 2: USA - CUSTOMER "JOHN SMITH" (Used for CLAIM testing)
    -- ========================================================================
    RAISE NOTICE 'Seeding US Data...';

    -- Store PII in vault (SSN encrypted)
    INSERT INTO vault.customer_pii (pii_token, region_code, full_name_enc, tax_id_enc, date_of_birth)
    VALUES (
        v_pii_us, 'US',
        pgp_sym_encrypt('John Smith', v_key),
        pgp_sym_encrypt('987-65-4321', v_key), -- SSN
        '1990-11-15'
    );

    -- Policy header
    INSERT INTO core.policies (policy_id, pii_token, region_code, product_code)
    VALUES (v_pol_us, v_pii_us, 'US', 'HOME_INSURANCE_NY');

    -- Active policy version (used by claim validation tests)
    INSERT INTO core.policy_versions (
        policy_id, region_code, status, premium_amount, coverage_limit,
        valid_from, valid_to, version_number
    ) VALUES (
        v_pol_us, 'US', 'ACTIVE', 120.00, 500000.00,
        NOW() - INTERVAL '1 month', 
        NOW() + INTERVAL '11 months', 
        1
    );


    -- ========================================================================
    -- SCENARIO 3: EUROPE - CUSTOMER "HANS MUELLER" (Expired policy - used to test rejection)
    -- ========================================================================
    RAISE NOTICE 'Seeding EU Data...';

    INSERT INTO vault.customer_pii (pii_token, region_code, full_name_enc, tax_id_enc, date_of_birth)
    VALUES (
        v_pii_eu, 'EU',
        pgp_sym_encrypt('Hans Mueller', v_key),
        pgp_sym_encrypt('DE123456789', v_key), 
        '1975-03-30'
    );

    INSERT INTO core.policies (policy_id, pii_token, region_code, product_code)
    VALUES (v_pol_eu, v_pii_eu, 'EU', 'TRAVEL_SAFE_EU');

    -- Older version that already expired (should be rejected by bi-temporal checks)
    INSERT INTO core.policy_versions (
        policy_id, region_code, status, premium_amount, coverage_limit,
        valid_from, valid_to, version_number
    ) VALUES (
        v_pol_eu, 'EU', 'EXPIRED', 50.00, 10000.00,
        NOW() - INTERVAL '2 years', 
        NOW() - INTERVAL '1 year', -- already expired
        1
    );

END $$;

COMMIT;

-- 3. FINAL CHECK (for logs)
-- Read back inserted rows and decrypt the demo name to validate the seed.
SELECT 
    p.region_code, 
    p.product_code, 
    pgp_sym_decrypt(v.full_name_enc, 'segredo_regional_2025') as decrypted_name,
    pv.status,
    pv.valid_from,
    pv.valid_to
FROM core.policies p
JOIN vault.customer_pii v ON p.pii_token = v.pii_token AND p.region_code = v.region_code
JOIN core.policy_versions pv ON p.policy_id = pv.policy_id AND p.region_code = pv.region_code;