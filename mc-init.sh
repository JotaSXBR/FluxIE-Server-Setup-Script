#!/bin/bash

# === CONFIGURAÇÕES DO USUÁRIO MINIO ===
MINIO_ALIAS="myminio"
MINIO_ENDPOINT="https://s3api.backend.fluxie.com.br"
MINIO_ROOT_USER="dimetal"
MINIO_ROOT_PASSWORD="SuIvvrIUvCqn3bF0FmTrsw"

# === CREDENCIAIS DO USUÁRIO A SER CRIADO ===
S3_ACCESS_KEY="evolution"
S3_SECRET_KEY="sm0DK7K1J8NkB6xUvCM5wPoE9GH9flKrReLaTKVw"
S3_POLICY="readwrite"

# === VALIDAÇÕES ===
set -e

echo "🔐 Conectando ao MinIO com o usuário root..."

mc alias set "$MINIO_ALIAS" "$MINIO_ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" --api S3v4

echo "👤 Verificando se o usuário '$S3_ACCESS_KEY' já existe..."

if mc admin user info "$MINIO_ALIAS" "$S3_ACCESS_KEY" >/dev/null 2>&1; then
    echo "⚠️  Usuário '$S3_ACCESS_KEY' já existe. Pulando criação..."
else
    echo "✅ Criando usuário '$S3_ACCESS_KEY'..."
    mc admin user add "$MINIO_ALIAS" "$S3_ACCESS_KEY" "$S3_SECRET_KEY"
fi

echo "🔑 Aplicando política '$S3_POLICY' ao usuário '$S3_ACCESS_KEY'..."
mc admin policy attach "$MINIO_ALIAS" "$S3_POLICY" --user "$S3_ACCESS_KEY"

echo "✅ Finalizado! Usuário '$S3_ACCESS_KEY' configurado com sucesso."
