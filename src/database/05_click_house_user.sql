-- Criar usuário administrativo
CREATE DATABASE IF NOT EXISTS insurance;

CREATE USER IF NOT EXISTS analytics_user
IDENTIFIED WITH plaintext_password BY 'analytics123';

GRANT ALL ON *.* TO analytics_user WITH GRANT OPTION;
