#!/bin/bash

set -e

STACK_NAME="minio"
COMPOSE_FILE="docker-compose.minio.yml"
ENV_FILE=".env.minio"
NETWORK_NAME="traefik-public"
VOLUME_NAME="minio_data"

echo "🔍 Verificando se a rede '$NETWORK_NAME' existe..."
if ! docker network ls --format '{{.Name}}' | grep -qw "$NETWORK_NAME"; then
  echo "🌐 Criando rede externa '$NETWORK_NAME'..."
  docker network create --driver overlay "$NETWORK_NAME"
else
  echo "✅ Rede '$NETWORK_NAME' já existe."
fi

echo "🔍 Verificando se o volume '$VOLUME_NAME' existe..."
if ! docker volume ls --format '{{.Name}}' | grep -qw "$VOLUME_NAME"; then
  echo "💾 Criando volume '$VOLUME_NAME'..."
  docker volume create --name "$VOLUME_NAME"
else
  echo "✅ Volume '$VOLUME_NAME' já existe."
fi

echo "🚀 Subindo stack '$STACK_NAME'..."
docker stack deploy -c "$COMPOSE_FILE" --with-registry-auth "$STACK_NAME"

echo "⏳ Aguardando MinIO iniciar..."
sleep 20  # tempo para o container estar pronto — ajuste se necessário

echo "🔐 Executando inicialização via MinIO Client..."
./mc-init.sh

echo "🎉 Instalação do MinIO finalizada com sucesso."
