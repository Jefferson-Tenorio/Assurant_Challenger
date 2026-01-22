-- Extensões e Tipos Globais
CREATE EXTENSION IF NOT EXISTS "btree_gist"; 
CREATE TYPE currency_code_enum AS ENUM ('USD', 'BRL', 'EUR', 'GBP');