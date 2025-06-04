#!/bin/bash

set -e

### CONFIGURAÇÕES PERSONALIZÁVEIS
EMAIL_LETSENCRYPT="ceo@fluxie.com.br"
DOMAIN_TRAEFIK="traefik.backend.fluxie.com.br"
DOMAIN_PORTAINER="portainer.backend.fluxie.com.br"

echo "🔧 Atualizando sistema..."
sudo apt update && sudo apt upgrade -y && sudo apt install -y curl apache2-utils

echo "🐳 Instalando Docker..."
curl -fsSL https://get.docker.com | sudo bash
sudo usermod -aG docker $USER

echo "🚀 Inicializando Docker Swarm..."
sudo docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')

echo "🌐 Criando rede traefik-public..."
sudo docker network create --driver=overlay traefik-public || true

echo "📁 Preparando diretórios..."
sudo mkdir -p /opt/traefik/config /opt/traefik/certs
sudo mkdir -p /opt/portainer

echo "🔐 Criando acme.json com permissões seguras..."
sudo touch /opt/traefik/certs/acme.json
sudo chmod 600 /opt/traefik/certs/acme.json

echo "📝 Escrevendo traefik.yml..."
sudo tee /opt/traefik/config/traefik.yml > /dev/null <<EOF
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  docker:
    swarmMode: true
    exposedByDefault: false
    network: traefik-public

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${EMAIL_LETSENCRYPT}
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

api:
  dashboard: true
  insecure: false

accessLog:
  disabled: true
EOF

echo "🧱 Gerando docker-compose do Traefik..."
sudo tee /opt/traefik/docker-compose.yml > /dev/null <<EOF
version: '3.8'

services:
  traefik:
    image: traefik:v2.11
    command:
      - --configFile=/etc/traefik/traefik.yml
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /opt/traefik/config/traefik.yml:/etc/traefik/traefik.yml:ro
      - /opt/traefik/certs/acme.json:/letsencrypt/acme.json
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - traefik-public
    deploy:
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.api.rule=Host(\`${DOMAIN_TRAEFIK}\`)"
        - "traefik.http.routers.api.entrypoints=websecure"
        - "traefik.http.routers.api.tls.certresolver=letsencrypt"
        - "traefik.http.routers.api.service=api@internal"
        - "traefik.http.services.api.loadbalancer.server.port=8080"

networks:
  traefik-public:
    external: true
EOF

echo "🚢 Deploy da stack Traefik..."
sudo docker stack deploy -c /opt/traefik/docker-compose.yml traefik

echo "🧱 Gerando docker-compose do Portainer..."
sudo tee /opt/portainer/portainer.yml > /dev/null <<EOF
version: '3.8'

services:
  portainer:
    image: portainer/portainer-ce:latest
    command: -H unix:///var/run/docker.sock
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - traefik-public
    deploy:
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.portainer.rule=Host(\`${DOMAIN_PORTAINER}\`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"

volumes:
  portainer_data:

networks:
  traefik-public:
    external: true
EOF

echo "🚢 Deploy da stack Portainer..."
sudo docker stack deploy -c /opt/portainer/portainer.yml portainer

echo "✅ Instalação completa!"
echo "➡ Acesse o Traefik:   https://${DOMAIN_TRAEFIK}"
echo "➡ Acesse o Portainer: https://${DOMAIN_PORTAINER}"
echo "🔁 ⚠️ Faça logout/login para aplicar permissões do grupo docker ao seu usuário."
