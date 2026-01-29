-- Extensões e Tipos Globais
CREATE EXTENSION IF NOT EXISTS "btree_gist"; 
CREATE TYPE currency_code_enum AS ENUM ('USD', 'BRL', 'EUR', 'GBP');

CREATE OR REPLACE FUNCTION uuid_generate_v7()
RETURNS uuid AS $$
DECLARE
  v_time timestamp with time zone:= clock_timestamp();
  v_secs bigint := extract(epoch from v_time);
  v_msec bigint := (v_secs * 1000) + extract(milliseconds from v_time)::bigint % 1000;
  v_msec_hex text;
BEGIN
  -- 48 bits de timestamp em hexadecimal (12 caracteres)
  v_msec_hex := lpad(to_hex(v_msec), 12, '0');
  
  -- Montagem do UUIDv7: 
  -- timestamp (48 bits) + '4' (versão) + random (12 bits) + '8' (variante) + random (62 bits)
  RETURN (
    v_msec_hex || 
    '-7' || -- Versão 7
    substr(to_hex(floor(random() * 4096)::int), 1, 3) || 
    '-' || 
    substr('89ab', (floor(random() * 4)::int + 1), 1) || 
    substr(to_hex(floor(random() * 4096)::int), 1, 3) || 
    '-' || 
    lpad(to_hex(floor(random() * 281474976710656)::bigint), 12, '0')
  )::uuid;
END;
$$ LANGUAGE plpgsql VOLATILE;