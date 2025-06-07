#!/bin/sh
set -e

# --- LEITURA DOS SECRETS ---
# Lê o conteúdo de cada arquivo de secret e armazena em uma variável shell.
PG_DB=$(cat /run/secrets/postgres_db)
PG_USER=$(cat /run/secrets/postgres_user)
PG_PASS=$(cat /run/secrets/postgres_password)
REDIS_PASS=$(cat /run/secrets/redis_password)
MINIO_USER=$(cat /run/secrets/minio_root_user)
MINIO_PASS=$(cat /run/secrets/minio_root_password)
EVO_API_KEY=$(cat /run/secrets/evolution_api_key)

# --- CONSTRUÇÃO DAS VARIÁVEIS DE AMBIENTE ---
# Usa os valores lidos dos secrets para montar as variáveis de ambiente complexas
# que a aplicação Evolution espera.
export DATABASE_CONNECTION_URI="postgresql://${PG_USER}:${PG_PASS}@postgres:5432/${PG_DB}"
export CACHE_REDIS_URI="redis://:${REDIS_PASS}@redis:6379/0"
export S3_ACCESS_KEY="${MINIO_USER}"
export S3_SECRET_KEY="${MINIO_PASS}"
export AUTHENTICATION_API_KEY="${EVO_API_KEY}"

echo "Entrypoint: Variáveis de ambiente com secrets configuradas."

# --- EXECUÇÃO DO COMANDO ORIGINAL ---
# 'exec "$@"' executa o comando original do Dockerfile da imagem.
# Isso garante que estamos apenas "preparando o ambiente" antes de rodar
# a aplicação principal.
exec "$@"