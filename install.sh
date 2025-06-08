#!/bin/bash

# Sair em caso de erro
set -e

# Função para tratamento de erros
handle_error() {
    echo "Erro na linha $1: comando '$2' falhou"
    echo "⚠️ Verifique o log em $LOG_FILE para mais detalhes"
    exit 1
}

trap 'handle_error $LINENO $BASH_COMMAND' ERR

echo "
███████╗██╗     ██╗   ██╗██╗  ██╗██╗███████╗
██╔════╝██║     ██║   ██║╚██╗██╔╝██║██╔════╝
█████╗  ██║     ██║   ██║ ╚███╔╝ ██║█████╗  
██╔══╝  ██║     ██║   ██║ ██╔██╗ ██║██╔══╝  
██║     ███████╗╚██████╔╝██╔╝ ██╗██║███████╗
╚═╝     ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝╚════════╝
                                             
Script de Instalação e Configuração do Servidor
"

# =============================================================================
# SEÇÃO 1: COLETA DE TODOS OS DADOS NECESSÁRIOS NO INÍCIO
# =============================================================================

echo "Coletando todas as informações necessárias para a instalação..."
echo "=================================================================="

# Domínio principal
read -p "Digite seu domínio (ex: exemplo.com.br): " DOMAIN_NAME
export DOMAIN_NAME

# Email para Let's Encrypt
read -p "Digite seu e-mail para notificações do Let's Encrypt: " LETSENCRYPT_EMAIL
export LETSENCRYPT_EMAIL

# Configurar senha do usuário deploy
echo "Configure a senha para o usuário deploy (você precisará desta senha depois):"
read -s -p "Digite a senha para o usuário deploy: " DEPLOY_PASSWORD
echo
read -s -p "Confirme a senha para o usuário deploy: " DEPLOY_PASSWORD_CONFIRM
echo

# Verificar se as senhas coincidem
if [ "$DEPLOY_PASSWORD" != "$DEPLOY_PASSWORD_CONFIRM" ]; then
    echo "As senhas não coincidem. Por favor, execute o script novamente."
    exit 1
fi

# Solicitar chave SSH pública
read -p "Cole sua chave SSH pública (ou pressione Enter para pular): " SSH_KEY

# PostgreSQL
read -p "Digite o nome do banco de dados principal para PostgreSQL (padrão: 'main_db'): " PG_DATABASE
[ -z "$PG_DATABASE" ] && PG_DATABASE="main_db"
read -p "Digite o nome do usuário para este banco (padrão: 'main_user'): " PG_USER
[ -z "$PG_USER" ] && PG_USER="main_user"
read -s -p "Digite a senha para o usuário '$PG_USER' (Enter para gerar automaticamente): " PG_PASSWORD
echo

# Redis
read -s -p "Digite a senha para o Redis (Enter para gerar automaticamente): " REDIS_PASSWORD
echo

# MinIO
read -p "Digite o usuário ROOT do MinIO (padrão: 'admin'): " MINIO_ROOT_USER
[ -z "$MINIO_ROOT_USER" ] && MINIO_ROOT_USER="admin"
read -s -p "Digite a senha ROOT do MinIO (Enter para gerar automaticamente): " MINIO_ROOT_PASSWORD
echo

# Evolution API
read -s -p "Digite a chave de API da Evolution (Enter para gerar automaticamente): " EVOLUTION_API_KEY
echo

# n8n
read -s -p "Digite a chave de criptografia do n8n (Enter para gerar automaticamente): " N8N_ENCRYPTION_KEY
echo

# Desativação do root
read -p "Desativar acesso root via SSH após instalação? (S/n): " DISABLE_ROOT_INPUT
DISABLE_ROOT_INPUT=${DISABLE_ROOT_INPUT:-S}

echo ""
echo "✅ Todas as informações coletadas!"
echo "🚀 Iniciando instalação automatizada..."
echo ""

# Gerar senhas automaticamente se não fornecidas
[ -z "$PG_PASSWORD" ] && PG_PASSWORD=$(openssl rand -base64 20)
[ -z "$REDIS_PASSWORD" ] && REDIS_PASSWORD=$(openssl rand -base64 20)
[ -z "$MINIO_ROOT_PASSWORD" ] && MINIO_ROOT_PASSWORD=$(openssl rand -base64 20)
[ -z "$EVOLUTION_API_KEY" ] && EVOLUTION_API_KEY=$(openssl rand -hex 16)
[ -z "$N8N_ENCRYPTION_KEY" ] && N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)

# Gerar senha do Traefik
TRAEFIK_ADMIN_PASSWORD_RAW=$(openssl rand -base64 16)

# =============================================================================
# SEÇÃO 2: CONFIGURAÇÃO DO SISTEMA
# =============================================================================

echo "Atualizando pacotes do sistema..."
apt-get update
apt-get upgrade -y

echo "Criando usuário deploy..."
useradd -m -s /bin/bash deploy
echo "deploy:$DEPLOY_PASSWORD" | chpasswd
usermod -aG sudo deploy

# Configurando SSH para o usuário deploy
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh

if [ ! -z "$SSH_KEY" ]; then
    echo "$SSH_KEY" > /home/deploy/.ssh/authorized_keys
    chmod 600 /home/deploy/.ssh/authorized_keys
elif [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys /home/deploy/.ssh/
    chmod 600 /home/deploy/.ssh/authorized_keys
fi

chown -R deploy:deploy /home/deploy/.ssh

# =============================================================================
# SEÇÃO 3: INSTALAÇÃO DO DOCKER
# =============================================================================

echo "Instalando Docker..."
apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg apache2-utils
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

usermod -aG docker deploy
systemctl start docker
systemctl enable docker

# =============================================================================
# SEÇÃO 4: CONFIGURAÇÃO DO DOCKER SWARM
# =============================================================================

echo "Configurando Docker Swarm..."
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    IP_ADDRESSES=$(hostname -I)
    NUM_IPS=$(echo $IP_ADDRESSES | wc -w)
    SWARM_ADVERTISE_IP=""
    
    if [ "$NUM_IPS" -eq 1 ]; then
        SWARM_ADVERTISE_IP=$(echo $IP_ADDRESSES | awk '{print $1}')
        echo "Usando IP: $SWARM_ADVERTISE_IP para Docker Swarm"
    elif [ "$NUM_IPS" -gt 1 ]; then
        PS3="Escolha o IP para Docker Swarm: "
        echo "Múltiplos IPs encontrados:"
        select selected_ip in $IP_ADDRESSES; do
            if [ -n "$selected_ip" ]; then
                SWARM_ADVERTISE_IP="$selected_ip"
                echo "IP selecionado: $SWARM_ADVERTISE_IP"
                break
            fi
        done
    else
        echo "Erro: Nenhum IP encontrado"
        exit 1
    fi
    
    docker swarm init --advertise-addr $SWARM_ADVERTISE_IP
else
    echo "Docker Swarm já está ativo"
fi

# Criando redes
if ! docker network ls | grep -q "traefik-public"; then
    docker network create --driver=overlay traefik-public
fi
if ! docker network ls | grep -q "backend-network"; then
    docker network create --driver=overlay --attachable backend-network
fi

# =============================================================================
# SEÇÃO 5: CRIAÇÃO DOS SECRETS
# =============================================================================

echo "Criando secrets do Docker..."

create_or_update_secret() {
    local secret_name=$1
    local secret_value=$2
    if docker secret inspect "$secret_name" &>/dev/null; then
        SECRET_ID=$(docker secret ls --filter name="$secret_name" -q)
        docker secret rm "$SECRET_ID"
    fi
    echo "$secret_value" | docker secret create "$secret_name" -
}

# Traefik
TRAEFIK_ADMIN_PASSWORD_HASHED=$(htpasswd -nbB admin "$TRAEFIK_ADMIN_PASSWORD_RAW")
create_or_update_secret "traefik_dashboard_users" "$TRAEFIK_ADMIN_PASSWORD_HASHED"

# PostgreSQL
create_or_update_secret "postgres_db" "$PG_DATABASE"
create_or_update_secret "postgres_user" "$PG_USER"
create_or_update_secret "postgres_password" "$PG_PASSWORD"

# Redis
create_or_update_secret "redis_password" "$REDIS_PASSWORD"

# MinIO
create_or_update_secret "minio_root_user" "$MINIO_ROOT_USER"
create_or_update_secret "minio_root_password" "$MINIO_ROOT_PASSWORD"

# Evolution API
create_or_update_secret "evolution_api_key" "$EVOLUTION_API_KEY"

# n8n
create_or_update_secret "n8n_encryption_key" "$N8N_ENCRYPTION_KEY"

# =============================================================================
# SEÇÃO 6: CRIAÇÃO DOS ARQUIVOS DE CONFIGURAÇÃO
# =============================================================================

echo "Criando arquivos de configuração..."

# PostgreSQL init script
cat > init-db.sh <<'EOF'
#!/bin/bash
set -e
DB_NAME=$(cat "$POSTGRES_DB_FILE")
DB_USER=$(cat "$POSTGRES_USER_FILE")
DB_PASSWORD=$(cat "$POSTGRES_PASSWORD_FILE")
psql -v ON_ERROR_STOP=1 --username "postgres" --dbname "$DB_NAME" <<-EOSQL
    DO \$do\$ BEGIN
       IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$DB_USER') THEN
          CREATE ROLE "$DB_USER" WITH LOGIN PASSWORD '$DB_PASSWORD';
       END IF;
    END \$do\$;
    GRANT ALL PRIVILEGES ON DATABASE "$DB_NAME" TO "$DB_USER";
    \c "$DB_NAME" "$DB_USER";
    GRANT ALL ON SCHEMA public TO "$DB_USER";
    CREATE EXTENSION IF NOT EXISTS vector;
EOSQL
EOF
chmod +x init-db.sh

# Evolution env
cat > evolution.env <<EOF
SERVER_URL=https://api.${DOMAIN_NAME}
DEL_INSTANCE=false
LANGUAGE=pt-BR
DATABASE_ENABLED=true
DATABASE_PROVIDER=postgresql
DATABASE_SAVE_DATA_INSTANCE=true
DATABASE_SAVE_DATA_NEW_MESSAGE=true
DATABASE_SAVE_MESSAGE_UPDATE=true
DATABASE_SAVE_DATA_CONTACTS=true
DATABASE_SAVE_DATA_CHATS=true
CACHE_REDIS_ENABLED=true
CACHE_REDIS_PREFIX_KEY=evolution_api
S3_ENABLED=true
S3_PORT=443
S3_ENDPOINT=s3api.${DOMAIN_NAME}
S3_USE_SSL=true
S3_BUCKET=evolution
AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=true
PROVIDER_ENABLED=false
RABBITMQ_ENABLED=false
SQS_ENABLED=false
WEBSOCKET_ENABLED=false
EOF

# Evolution entrypoint
cat > entrypoint.sh <<'EOF'
#!/bin/sh
set -e
PG_DB=$(cat /run/secrets/postgres_db)
PG_USER=$(cat /run/secrets/postgres_user)
PG_PASS=$(cat /run/secrets/postgres_password)
REDIS_PASS=$(cat /run/secrets/redis_password)
MINIO_USER=$(cat /run/secrets/minio_root_user)
MINIO_PASS=$(cat /run/secrets/minio_root_password)
EVO_API_KEY=$(cat /run/secrets/evolution_api_key)
export DATABASE_CONNECTION_URI="postgresql://${PG_USER}:${PG_PASS}@postgres:5432/${PG_DB}"
export CACHE_REDIS_URI="redis://:${REDIS_PASS}@redis:6379/0"
export S3_ACCESS_KEY="${MINIO_USER}"
export S3_SECRET_KEY="${MINIO_PASS}"
export AUTHENTICATION_API_KEY="${EVO_API_KEY}"
exec "$@"
EOF
chmod +x entrypoint.sh

# n8n env
cat > n8n.env <<EOF
N8N_HOST=n8n.${DOMAIN_NAME}
N8N_PROTOCOL=https
N8N_EDITOR_BASE_URL=https://n8n.${DOMAIN_NAME}
WEBHOOK_URL=https://webhook-n8n.${DOMAIN_NAME}
NODE_ENV=production
GENERIC_TIMEZONE=America/Sao_Paulo
TZ=America/Sao_Paulo
EXECUTIONS_MODE=queue
QUEUE_CONCURRENCY=10
N8N_REINSTALL_MISSING_PACKAGES=true
N8N_COMMUNITY_PACKAGES_ENABLED=true
N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true
DB_TYPE=postgresdb
N8N_DATABASE_TYPE=postgresdb
EOF

# n8n entrypoint
cat > entrypoint-n8n.sh <<'EOF'
#!/bin/sh
set -e
PG_DB=$(cat /run/secrets/postgres_db)
PG_USER=$(cat /run/secrets/postgres_user)
PG_PASS=$(cat /run/secrets/postgres_password)
export QUEUE_BULL_REDIS_PASSWORD=$(cat /run/secrets/redis_password)
export N8N_ENCRYPTION_KEY=$(cat /run/secrets/n8n_encryption_key)
export QUEUE_BULL_REDIS_HOST=redis
export QUEUE_BULL_REDIS_PORT=6379
export QUEUE_BULL_REDIS_DB=2
export DB_POSTGRESDB_HOST=postgres
export DB_POSTGRESDB_PORT=5432
export DB_POSTGRESDB_DATABASE=$PG_DB
export DB_POSTGRESDB_USER=$PG_USER
export DB_POSTGRESDB_PASSWORD=$PG_PASS
exec /usr/local/bin/docker-entrypoint.sh "$@"
EOF
chmod +x entrypoint-n8n.sh

# Função para verificar se o serviço está saudável
wait_for_service() {
    local service_name=$1
    local max_attempts=30
    local attempt=1
    
    echo "⏳ Aguardando serviço $service_name ficar online..."
    while [ $attempt -le $max_attempts ]; do
        if docker service ls --filter "name=$service_name" --format "{{.Replicas}}" | grep -q "[0-9]/[0-9]"; then
            if docker service ls --filter "name=$service_name" --format "{{.Replicas}}" | grep -q "[0-9]/[0-9]$"; then
                echo "✅ Serviço $service_name está online!"
                return 0
            fi
        fi
        echo "⏳ Tentativa $attempt/$max_attempts - Aguardando $service_name..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    echo "❌ Timeout aguardando $service_name"
    return 1
}

# =============================================================================
# SEÇÃO 7: DEPLOY DOS SERVIÇOS
# =============================================================================

echo "Fazendo deploy dos serviços..."

# Deploy e aguarda Traefik
echo "📡 Deployando Traefik..."
envsubst '\$DOMAIN_NAME \$LETSENCRYPT_EMAIL' < traefik.yml | docker stack deploy -c - traefik
wait_for_service "traefik_traefik" || exit 1

# Deploy e aguarda Portainer
echo "🐳 Deployando Portainer..."
envsubst '\$DOMAIN_NAME' < portainer.yml | docker stack deploy -c - portainer
wait_for_service "portainer_portainer" || exit 1

# Deploy e aguarda PostgreSQL
echo "🗄️ Deployando PostgreSQL..."
docker stack deploy -c postgres.yml postgres
wait_for_service "postgres_postgres" || exit 1

# Deploy e aguarda Redis
echo "⚡ Deployando Redis..."
envsubst '\$DOMAIN_NAME' < redis.yml | docker stack deploy -c - redis
wait_for_service "redis_redis" || exit 1

# Deploy e aguarda MinIO
echo "📦 Deployando MinIO..."
envsubst '\$DOMAIN_NAME' < minio.yml | docker stack deploy -c - minio
wait_for_service "minio_minio" || exit 1

# Deploy e aguarda Evolution API
echo "📱 Deployando Evolution API..."
envsubst '\$DOMAIN_NAME' < evolution.yml | docker stack deploy -c - evolution
wait_for_service "evolution_evolution" || exit 1

# Deploy e aguarda n8n
echo "🔄 Deployando n8n..."
envsubst '\$DOMAIN_NAME' < n8n.yml | docker stack deploy -c - n8n
wait_for_service "n8n_n8n" || exit 1

# =============================================================================
# SEÇÃO 8: FINALIZAÇÃO
# =============================================================================

echo "Copiando arquivos de configuração..."
BACKUP_SUFFIX=$(date +%Y%m%d_%H%M%S)
if [ -d "/home/deploy/FluxIE-Server-Setup-Script" ]; then
    mv /home/deploy/FluxIE-Server-Setup-Script "/home/deploy/FluxIE-Server-Setup-Script_backup_$BACKUP_SUFFIX"
fi
mkdir -p /home/deploy/FluxIE-Server-Setup-Script
cp *.yml *.env *.sh README.md /home/deploy/FluxIE-Server-Setup-Script/
chown -R deploy:deploy /home/deploy/FluxIE-Server-Setup-Script

# Limpeza
apt-get autoremove -y
apt-get clean

# =============================================================================
# SEÇÃO 9: EXIBIR INFORMAÇÕES FINAIS
# =============================================================================

echo "
╔═══════════════════════════════════════════════╗
║        Instalação Concluída com Sucesso!      ║
║             Powered by FluxIE                 ║
╚═══════════════════════════════════════════════╝
"

echo "🔐 CREDENCIAIS GERADAS (ANOTE EM LOCAL SEGURO!):"
echo "=================================================="
echo "👤 Usuário deploy: deploy"
echo "🌐 Traefik Dashboard - Usuário: admin | Senha: $TRAEFIK_ADMIN_PASSWORD_RAW"
echo "🗄️ PostgreSQL - Banco: $PG_DATABASE | Usuário: $PG_USER | Senha: $PG_PASSWORD"
echo "⚡ Redis - Senha: $REDIS_PASSWORD"
echo "📦 MinIO - Usuário: $MINIO_ROOT_USER | Senha: $MINIO_ROOT_PASSWORD"
echo "📱 Evolution API - Chave: $EVOLUTION_API_KEY"
echo "🔄 n8n - Chave de Criptografia: $N8N_ENCRYPTION_KEY"
echo ""

echo "🌍 SERVIÇOS DISPONÍVEIS:"
echo "========================"
echo "📡 Traefik Dashboard: https://traefik.$DOMAIN_NAME"
echo "🐳 Portainer: https://portainer.$DOMAIN_NAME"
echo "📦 MinIO Console: https://s3.$DOMAIN_NAME"
echo "📦 MinIO API: https://s3api.$DOMAIN_NAME"
echo "🔍 Redis Insight: https://redis-insight.$DOMAIN_NAME"
echo "📱 Evolution API: https://api.$DOMAIN_NAME"
echo "🔄 n8n Editor: https://n8n.$DOMAIN_NAME"
echo "🔗 n8n Webhooks: https://webhook-n8n.$DOMAIN_NAME"
echo ""

echo "📋 PRÓXIMOS PASSOS:"
echo "==================="
echo "1. Configure os DNS dos subdomínios para apontar para este servidor"
echo "2. Aguarde ~5 minutos para todos os serviços ficarem online"
echo "3. Acesse o Portainer para configurar a senha de administrador"
echo "4. Use o usuário 'deploy' para acessar o servidor"
echo ""

# Desativação do root
if [ "${DISABLE_ROOT_INPUT,,}" = "s" ]; then
    echo "🔒 Desativando acesso root via SSH..."
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    passwd -l root
    systemctl restart sshd
    echo "✅ Acesso root via SSH desativado com sucesso!"
    echo "⚠️ Use o usuário 'deploy' para futuras conexões"
else
    echo "⚠️ Acesso root via SSH mantido ativo (não recomendado para produção)"
fi

echo ""
echo "🎉 Instalação finalizada! Todos os serviços estão sendo inicializados."

# Verificar versão do sistema
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "ubuntu" ] || [ "${VERSION_ID%%.*}" -lt 20 ]; then
        echo "❌ Este script requer Ubuntu 20.04 ou superior"
        exit 1
    fi
fi

# Verificar espaço em disco
MIN_SPACE_GB=20
AVAILABLE_SPACE_GB=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
if [ "$AVAILABLE_SPACE_GB" -lt "$MIN_SPACE_GB" ]; then
    echo "❌ Espaço insuficiente. Mínimo necessário: ${MIN_SPACE_GB}GB"
    exit 1
fi

# Verificar conectividade
echo "🌐 Verificando conectividade..."
if ! ping -c 1 google.com &> /dev/null; then
    echo "❌ Sem conexão com a internet"
    exit 1
fi

# Configurar logging
LOG_FILE="/var/log/fluxie_install.log"
exec 1> >(tee -a "$LOG_FILE") 2>&1
echo "📝 Log da instalação disponível em: $LOG_FILE"

# Backup automático
setup_backup() {
    echo "📦 Configurando backup automático..."
    mkdir -p /home/deploy/backups
    cat > /home/deploy/backup.sh <<'EOFBACKUP'
#!/bin/bash
BACKUP_DIR="/home/deploy/backups"
DATE=$(date +%Y%m%d_%H%M%S)
# Backup PostgreSQL
docker exec $(docker ps -qf name=postgres) pg_dumpall -U postgres > "$BACKUP_DIR/postgres_$DATE.sql"
# Backup Redis
docker exec $(docker ps -qf name=redis) redis-cli SAVE
cp /var/lib/docker/volumes/redis_data/_data/dump.rdb "$BACKUP_DIR/redis_$DATE.rdb"
# Manter apenas últimos 7 backups
find "$BACKUP_DIR" -type f -mtime +7 -delete
EOFBACKUP
    chmod +x /home/deploy/backup.sh
    chown deploy:deploy /home/deploy/backup.sh

    # Adicionar ao crontab
    (crontab -l 2>/dev/null; echo "0 3 * * * /home/deploy/backup.sh") | crontab -
}

# Adicionar backup antes da seção de finalização
setup_backup

echo "💾 Backup automático configurado (diariamente às 3h)"
echo "📁 Backups serão salvos em: /home/deploy/backups"

# Adicionar verificação de arquivos necessários
check_required_files() {
    local required_files=(
        "traefik.yml"
        "traefik-dynamic.yml"
        "portainer.yml"
        "postgres.yml"
        "redis.yml"
        "minio.yml"
        "evolution.yml"
        "n8n.yml"
        "init-db.sh"
        "entrypoint.sh"
        "entrypoint-n8n.sh"
    )

    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            echo "❌ Arquivo necessário não encontrado: $file"
            exit 1
        fi
    done
    echo "✅ Todos os arquivos necessários encontrados"
}

# Adicionar verificação antes do deploy
echo "🔍 Verificando arquivos necessários..."
check_required_files

# Adicionar verificação de permissões dos scripts
echo "🔒 Verificando permissões dos scripts..."
chmod +x init-db.sh entrypoint.sh entrypoint-n8n.sh