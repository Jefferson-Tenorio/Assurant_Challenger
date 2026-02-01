-- Extensões e Tipos Globais
CREATE EXTENSION IF NOT EXISTS "btree_gist"; 
CREATE TYPE currency_code_enum AS ENUM ('USD', 'BRL', 'EUR', 'GBP');

CREATE OR REPLACE FUNCTION uuid_generate_v7()
RETURNS uuid AS $$
DECLARE
  v_time timestamp with time zone := clock_timestamp();
  v_unix_t bigint := floor(extract(epoch from v_time) * 1000);
  v_bytea bytea;
BEGIN
  -- 1. Geramos 16 bytes aleatórios
  v_bytea := gen_random_bytes(16);

  -- 2. Colocamos os 48 bits do timestamp nos primeiros 6 bytes
  v_bytea := overlay(v_bytea placing substring(int8send(v_unix_t) from 3) from 1 for 6);

  -- 3. Definimos a Versão 7 (bits 4-7 do byte 7)
  -- 0x70 é 01110000 em binário
  v_bytea := set_byte(v_bytea, 6, (get_byte(v_bytea, 6) & 15) | 112);

  -- 4. Definimos a Variante RFC 4122 (bits 6-7 do byte 9)
  -- 0x80 é 10000000 em binário
  v_bytea := set_byte(v_bytea, 8, (get_byte(v_bytea, 8) & 63) | 128);

  RETURN encode(v_bytea, 'hex')::uuid;
END;
$$ LANGUAGE plpgsql VOLATILE;