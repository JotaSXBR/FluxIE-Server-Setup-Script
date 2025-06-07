#!/bin/bash

# Sair em caso de erro
set -e

# Função para tratamento de erros
handle_error() {
    echo "Erro na linha $1"
    exit 1
}

trap 'handle_error $LINENO' ERR

echo "
███████╗██╗     ██╗   ██╗██╗  ██╗██╗███████╗
██╔════╝██║     ██║   ██║╚██╗██╔╝██║██╔════╝
█████╗  ██║     ██║   ██║ ╚███╔╝ ██║█████╗  
██╔══╝  ██║     ██║   ██║ ██╔██╗ ██║██╔══╝  
██║     ███████╗╚██████╔╝██╔╝ ██╗██║███████╗
╚═╝     ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝╚════════╝
                                             
Script de Instalação e Configuração do Servidor
"

# Solicitar o domínio
read -p "Digite seu domínio (ex: exemplo.com.br): " DOMAIN_NAME
export DOMAIN_NAME

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

echo "Iniciando script de configuração do servidor..."

# Atualização dos pacotes do sistema
echo "Atualizando pacotes do sistema..."
apt-get update
apt-get upgrade -y

# Criação do usuário deploy e adição ao grupo sudo
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

# Instalação do Docker
echo "Instalando Docker..."
apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Adicionando usuário deploy ao grupo docker
echo "Configurando permissões do Docker..."
usermod -aG docker deploy

# Iniciando e habilitando serviço do Docker
systemctl start docker
systemctl enable docker

# Inicializando Docker Swarm
echo "Verificando status do Docker Swarm..."
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "Inicializando Docker Swarm..."
    IP_ADDRESSES=$(hostname -I)
    NUM_IPS=$(echo $IP_ADDRESSES | wc -w)
    SWARM_ADVERTISE_IP=""
    if [ "$NUM_IPS" -eq 1 ]; then
        SWARM_ADVERTISE_IP=$(echo $IP_ADDRESSES | awk '{print $1}')
        echo "Um único endereço IP encontrado: $SWARM_ADVERTISE_IP. Usando este para o Docker Swarm."
    elif [ "$NUM_IPS" -gt 1 ]; then
        PS3="Por favor, escolha o IP para o Docker Swarm advertise address: "
        echo "Múltiplos endereços IP encontrados:"
        select selected_ip in $IP_ADDRESSES; do
            if [ -n "$selected_ip" ]; then
                SWARM_ADVERTISE_IP="$selected_ip"
                echo "Você selecionou: $SWARM_ADVERTISE_IP"
                break
            else
                echo "Seleção inválida. Por favor, escolha um número da lista."
            fi
        done
    else
        echo "Nenhum endereço IP encontrado para configurar o Docker Swarm. Saindo."
        exit 1
    fi
    if [ -z "$SWARM_ADVERTISE_IP" ]; then
        echo "Não foi possível determinar o endereço IP para o Docker Swarm. Saindo."
        exit 1
    fi
    docker swarm init --advertise-addr $SWARM_ADVERTISE_IP || { echo "Erro ao inicializar Docker Swarm"; exit 1; }
else
    echo "Docker Swarm já está ativo"
fi

# Criando redes
echo "Verificando redes do Docker Swarm..."
if ! docker network ls | grep -q "traefik-public"; then
    echo "Criando rede externa 'traefik-public'..."
    docker network create --driver=overlay traefik-public
else
    echo "Rede 'traefik-public' já existe."
fi
if ! docker network ls | grep -q "backend-network"; then
    echo "Criando rede interna 'backend-network'..."
    docker network create --driver=overlay --attachable backend-network
else
    echo "Rede 'backend-network' já existe."
fi

# Instalação de ferramentas adicionais
echo "Instalando ferramentas adicionais (Docker Compose, apache2-utils)..."
apt-get update
apt-get install -y docker-compose-plugin apache2-utils

# --- Função para criar ou atualizar secrets (definida uma vez) ---
create_or_update_secret() {
    local secret_name=$1
    local secret_value=$2
    if docker secret inspect "$secret_name" &>/dev/null; then
        echo "Atualizando o secret '$secret_name'..."
        SECRET_ID=$(docker secret ls --filter name="$secret_name" -q)
        docker secret rm "$SECRET_ID"
    fi
    echo "$secret_value" | docker secret create "$secret_name" -
    echo "Secret '$secret_name' criado com sucesso."
}

# --- Configuração do Traefik ---
echo "-----------------------------------------------------"
echo "Configurando o Traefik..."
read -p "Digite seu e-mail para notificações do Let's Encrypt: " LETSENCRYPT_EMAIL
export LETSENCRYPT_EMAIL
TRAEFIK_ADMIN_PASSWORD_RAW=$(openssl rand -base64 16)
TRAEFIK_ADMIN_PASSWORD_HASHED=$(htpasswd -nbB admin "$TRAEFIK_ADMIN_PASSWORD_RAW")
echo "--- Senha do Traefik Dashboard ---"
echo "Usuário: admin | Senha: $TRAEFIK_ADMIN_PASSWORD_RAW"
echo "ANOTE esta senha!"
read -p "Pressione Enter para continuar..."
create_or_update_secret "traefik_dashboard_users" "$TRAEFIK_ADMIN_PASSWORD_HASHED"
envsubst '\$DOMAIN_NAME \$LETSENCRYPT_EMAIL' < traefik.yml | docker stack deploy -c - traefik
echo "Stack do Traefik deployada."
echo "-----------------------------------------------------"

# --- Configuração do Portainer ---
echo "-----------------------------------------------------"
echo "Configurando o Portainer..."
envsubst '\$DOMAIN_NAME' < portainer.yml | docker stack deploy -c - portainer
echo "Stack do Portainer deployada."
echo "-----------------------------------------------------"

# --- Configuração do PostgreSQL ---
echo "-----------------------------------------------------"
echo "Configurando o PostgreSQL..."
read -p "Digite o nome do banco de dados para o PostgreSQL (ex: 'main_db'): " PG_DATABASE
read -p "Digite o nome do usuário para este banco (ex: 'main_user'): " PG_USER
read -s -p "Digite a senha para o usuário '$PG_USER' (Enter para gerar uma): " PG_PASSWORD
echo
if [ -z "$PG_PASSWORD" ]; then
    PG_PASSWORD=$(openssl rand -base64 20)
    echo "Senha do PostgreSQL gerada: $PG_PASSWORD (ANOTE!)"
fi
create_or_update_secret "postgres_db" "$PG_DATABASE"
create_or_update_secret "postgres_user" "$PG_USER"
create_or_update_secret "postgres_password" "$PG_PASSWORD"
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
docker stack deploy -c postgres.yml postgres
echo "Stack do PostgreSQL deployada."
echo "-----------------------------------------------------"

# --- Configuração do Redis ---
echo "-----------------------------------------------------"
echo "Configurando o Redis..."
read -s -p "Digite a senha para o Redis (Enter para gerar uma): " REDIS_PASSWORD
echo
if [ -z "$REDIS_PASSWORD" ]; then
    REDIS_PASSWORD=$(openssl rand -base64 20)
    echo "Senha do Redis gerada: $REDIS_PASSWORD (ANOTE!)"
fi
create_or_update_secret "redis_password" "$REDIS_PASSWORD"
envsubst '\$DOMAIN_NAME' < redis.yml | docker stack deploy -c - redis
echo "Stack do Redis deployada."
echo "-----------------------------------------------------"

# --- Configuração do MinIO ---
echo "-----------------------------------------------------"
echo "Configurando o MinIO..."
read -p "Digite o usuário ROOT do MinIO (Enter para 'admin'): " MINIO_ROOT_USER
[ -z "$MINIO_ROOT_USER" ] && MINIO_ROOT_USER="admin"
read -s -p "Digite a senha ROOT do MinIO (Enter para gerar uma): " MINIO_ROOT_PASSWORD
echo
if [ -z "$MINIO_ROOT_PASSWORD" ]; then
    MINIO_ROOT_PASSWORD=$(openssl rand -base64 20)
    echo "Senha ROOT do MinIO gerada: $MINIO_ROOT_PASSWORD (ANOTE!)"
fi
create_or_update_secret "minio_root_user" "$MINIO_ROOT_USER"
create_or_update_secret "minio_root_password" "$MINIO_ROOT_PASSWORD"
envsubst '\$DOMAIN_NAME' < minio.yml | docker stack deploy -c - minio
echo "Stack do MinIO deployada."
echo "-----------------------------------------------------"

# --- Configuração da Evolution API ---
echo "-----------------------------------------------------"
echo "Configurando a Evolution API..."
read -s -p "Digite a chave de API da Evolution (Enter para gerar uma): " EVOLUTION_API_KEY
echo
if [ -z "$EVOLUTION_API_KEY" ]; then
    EVOLUTION_API_KEY=$(openssl rand -hex 16)
    echo "Chave de API da Evolution gerada: $EVOLUTION_API_KEY (ANOTE!)"
fi
create_or_update_secret "evolution_api_key" "$EVOLUTION_API_KEY"
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
envsubst '\$DOMAIN_NAME' < evolution.yml | docker stack deploy -c - evolution
echo "Stack da Evolution API deployada."
echo "-----------------------------------------------------"

      
# --- Configuração do n8n ---
echo "-----------------------------------------------------"
echo "Configurando a automação com n8n..."
N8N_DB_USER="n8n_user"
N8N_DB_NAME="n8n_db"
read -s -p "Digite a senha para o BD do n8n (Enter para gerar uma): " N8N_DB_PASSWORD
echo
if [ -z "$N8N_DB_PASSWORD" ]; then
    N8N_DB_PASSWORD=$(openssl rand -base64 20)
    echo "Senha do BD para n8n gerada: $N8N_DB_PASSWORD (ANOTE!)"
fi
create_or_update_secret "n8n_db_user" "$N8N_DB_USER"
create_or_update_secret "n8n_db_name" "$N8N_DB_NAME"
create_or_update_secret "n8n_db_password" "$N8N_DB_PASSWORD"
POSTGRES_CONTAINER_ID=$(docker ps -q --filter "name=postgres_postgres" | head -n 1)
if [ -n "$POSTGRES_CONTAINER_ID" ]; then
    echo "Aguardando o PostgreSQL ficar pronto para criar o banco de dados do n8n..."
    sleep 15 # Espera para garantir que o Postgres teve tempo de iniciar

    # ✅✅✅ AQUI ESTÁ A CORREÇÃO CRÍTICA DO 'docker exec' ✅✅✅
    # O comando psql agora é passado como argumento para ser executado DENTRO do container.
    docker exec "$POSTGRES_CONTAINER_ID" psql -U postgres -d postgres -c "CREATE USER $N8N_DB_USER WITH PASSWORD '$N8N_DB_PASSWORD';" || echo "Usuário n8n já existe. Pulando."
    docker exec "$POSTGRES_CONTAINER_ID" psql -U postgres -d postgres -c "CREATE DATABASE $N8N_DB_NAME OWNER $N8N_DB_USER;" || echo "Banco de dados n8n já existe. Pulando."
    echo "Usuário e banco de dados para n8n configurados."
else
    echo "AVISO: Container do PostgreSQL não encontrado. A criação do usuário e banco para n8n foi pulada."
fi
read -s -p "Digite a chave de criptografia do n8n (Enter para gerar uma): " N8N_ENCRYPTION_KEY
echo
if [ -z "$N8N_ENCRYPTION_KEY" ]; then
    N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
    echo "Chave de criptografia do n8n gerada: $N8N_ENCRYPTION_KEY (ANOTE! CRÍTICO!)"
fi
create_or_update_secret "n8n_encryption_key" "$N8N_ENCRYPTION_KEY"
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
DB_POSTGRESDB_PORT=5432
QUEUE_BULL_REDIS_PORT=6379
QUEUE_BULL_REDIS_DB=2
EOF
cat > entrypoint-n8n.sh <<'EOF'
#!/bin/sh
set -e
export DB_POSTGRESDB_USER=$(cat /run/secrets/n8n_db_user)
export DB_POSTGRESDB_PASSWORD=$(cat /run/secrets/n8n_db_password)
export DB_POSTGRESDB_DATABASE=$(cat /run/secrets/n8n_db_name)
export QUEUE_BULL_REDIS_PASSWORD=$(cat /run/secrets/redis_password)
export N8N_ENCRYPTION_KEY=$(cat /run/secrets/n8n_encryption_key)
export DB_POSTGRESDB_HOST=postgres
export QUEUE_BULL_REDIS_HOST=redis
exec /usr/local/bin/docker-entrypoint.sh "$@"
EOF
chmod +x entrypoint-n8n.sh
envsubst '\$DOMAIN_NAME' < n8n.yml | docker stack deploy -c - n8n
echo "Stack do n8n deployada."
echo "-----------------------------------------------------"

# --- Finalização ---
echo "Copiando todos os arquivos de configuração para o usuário deploy..."
BACKUP_SUFFIX=$(date +%Y%m%d_%H%M%S)
if [ -d "/home/deploy/FluxIE-Server-Setup-Script" ]; then
    mv /home/deploy/FluxIE-Server-Setup-Script "/home/deploy/FluxIE-Server-Setup-Script_backup_$BACKUP_SUFFIX"
fi
mkdir -p /home/deploy/FluxIE-Server-Setup-Script
cp traefik.yml portainer.yml traefik-dynamic.yml \
   postgres.yml init-db.sh \
   redis.yml \
   minio.yml \
   evolution.yml evolution.env entrypoint.sh \
   n8n.yml n8n.env entrypoint-n8n.sh \
   install.sh README.md /home/deploy/FluxIE-Server-Setup-Script/
chown -R deploy:deploy /home/deploy/FluxIE-Server-Setup-Script
echo "Arquivos de configuração copiados para /home/deploy/FluxIE-Server-Setup-Script/"

# Limpeza de pacotes
echo "Limpando pacotes desnecessários..."
apt-get autoremove -y
apt-get clean

echo "
╔═══════════════════════════════════════════════╗
║        Instalação Concluída com Sucesso!      ║
║             Powered by FluxIE                 ║
╚═══════════════════════════════════════════════╝
"
echo "Lembre-se de:"
echo "1. Apontar os DNS dos seus subdomínios (traefik, portainer, s3, s3api, api, n8n, webhook-n8n) para o IP deste servidor."
echo "2. Os arquivos de configuração foram copiados para /home/deploy/FluxIE-Server-Setup-Script/"
echo "3. Use o usuário 'deploy' para acessar o servidor (sudo agora requer senha!)."
echo "4. Suas senhas e chaves geradas foram exibidas durante a instalação. Guarde-as em um local seguro."
echo "
Serviços instalados:
- Traefik (Dashboard): https://traefik.$DOMAIN_NAME
- Portainer: https://portainer.$DOMAIN_NAME
- MinIO (Console): https://s3.$DOMAIN_NAME
- Redis Insight: https://redis-insight.$DOMAIN_NAME
- Evolution API: https://api.$DOMAIN_NAME
- n8n (Editor): https://n8n.$DOMAIN_NAME
"

# --- Desativação do Root ---
echo "IMPORTANTE: Todos os serviços foram instalados e configurados."
echo "O próximo passo é desativar o acesso root via SSH por segurança."
echo "Certifique-se de que você consegue fazer login como usuário 'deploy' em outro terminal antes de continuar."
read -p "Você está pronto para desativar o acesso root via SSH? (s/N): " DISABLE_ROOT_OK

if [ "${DISABLE_ROOT_OK,,}" = "s" ]; then
    echo "Desativando login root via SSH..."
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    # Também é uma boa prática bloquear a senha do root
    passwd -l root
    systemctl restart sshd
    echo "Acesso root via SSH desativado. Por favor, use o usuário 'deploy' para se conectar."
    echo "A sessão atual continuará ativa, mas novas conexões como root serão recusadas."
else
    echo "O acesso root via SSH não foi desativado. Você pode fazer isso manualmente mais tarde."
    echo "AVISO: Manter o acesso root via SSH ativado não é recomendado em ambiente de produção."
fi