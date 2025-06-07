#!/bin/bash
set -e

# Lê os valores dos secrets que foram montados dentro do container
DB_NAME=$(cat "$POSTGRES_DB_FILE")
DB_USER=$(cat "$POSTGRES_USER_FILE")
DB_PASSWORD=$(cat "$POSTGRES_PASSWORD_FILE")

# Conecta-se ao banco como o superusuário padrão 'postgres' para executar os comandos de configuração.
# O entrypoint do PostgreSQL já cria o banco de dados ($DB_NAME), então aqui nós criamos
# o usuário e garantimos que ele seja o dono do banco.
psql -v ON_ERROR_STOP=1 --username "postgres" --dbname "$DB_NAME" <<-EOSQL
    -- Cria um novo usuário com a senha do secret, somente se o usuário não existir.
    DO
    \$do\$
    BEGIN
       IF NOT EXISTS (
          SELECT FROM pg_catalog.pg_roles
          WHERE  rolname = '$DB_USER') THEN
    
          CREATE ROLE "$DB_USER" WITH LOGIN PASSWORD '$DB_PASSWORD';
       END IF;
    END
    \$do\$;

    -- Concede todos os privilégios no banco de dados especificado para o novo usuário.
    GRANT ALL PRIVILEGES ON DATABASE "$DB_NAME" TO "$DB_USER";

    -- Conecta-se ao banco de dados específico do usuário para instalar extensões.
    \c "$DB_NAME" "$DB_USER"

    -- Concede permissão para o usuário criar objetos (tabelas, etc.) no schema público.
    GRANT ALL ON SCHEMA public TO "$DB_USER";

    -- Habilita a extensão pgvector, um dos motivos para usar esta imagem específica.
    CREATE EXTENSION IF NOT EXISTS vector;
EOSQL