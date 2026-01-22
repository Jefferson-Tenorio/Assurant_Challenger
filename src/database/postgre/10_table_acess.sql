CREATE TABLE access.customers_pii (
    customer_id UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- App deve enviar UUIDv7
    full_name_encrypted BYTEA NOT NULL, 
    tax_id_encrypted BYTEA NOT NULL, 
    email VARCHAR(255) NOT NULL,
    phone_encrypted TEXT NOT NULL, 
    
    key_version_id INT NOT NULL, 

    -- Blind Indexing
    tax_id_blind_index VARCHAR(64) NOT NULL,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ NULL, 
    
    -- Constraint PG 15+: Permite apenas um cadastro ativo por CPF Blindado.
    -- Se deleted_at for NULL, ele checa a unicidade. Se tiver data, ignora.
    CONSTRAINT uq_customer_tax_id_active UNIQUE NULLS NOT DISTINCT (tax_id_blind_index, deleted_at)
);

CREATE INDEX idx_customers_email ON access.customers_pii(email) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_tax_blind ON access.customers_pii(tax_id_blind_index) WHERE deleted_at IS NULL;