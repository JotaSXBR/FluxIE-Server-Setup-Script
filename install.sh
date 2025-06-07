#!/bin/bash

# Sair em caso de erro
set -e

# Função para tratamento de erros
handle_error() {
    echo "ERRO: Falha na linha $1. O script será encerrado."
    exit 1
}

trap 'handle_error $LINENO' ERR

# --- Função para criar secrets de forma idempotente ---
create_or_update_secret() {
    local secret_name=$1
    local secret_value=$2
    if docker secret inspect "$secret_name" &>/dev/null; then
        echo "Secret '$secret_name' já existe. Pulando."
    else
        echo "$secret_value" | docker secret create "$secret_name" -
        echo "Secret '$secret_name' criado com sucesso."
    fi
}

# --- Função principal para organizar o script ---
main() {
    echo "
    ███████╗██╗     ██╗   ██╗██╗  ██╗██╗███████╗
    ██╔════╝██║     ██║   ██║╚██╗██╔╝██║██╔════╝
    █████╗  ██║     ██║   ██║ ╚███╔╝ ██║█████╗  
    ██╔══╝  ██║     ██║   ██║ ██╔██╗ ██║██╔══╝  
    ██║     ███████╗╚██████╔╝██╔╝ ██╗██║███████╗
    ╚═╝     ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝╚════════╝
                                                 
    Script de Instalação e Configuração do Servidor
    "

    # --- Configuração de Domínio e Usuário ---
    read -p "Digite seu domínio (ex: exemplo.com.br): " DOMAIN_NAME
    export DOMAIN_NAME

    if id -u deploy &>/dev/null; then
        echo "Usuário 'deploy' já existe. Pulando criação."
    else
        echo "Configurando o usuário 'deploy'..."
        
        # ✅✅✅ AQUI ESTÁ A CORREÇÃO ✅✅✅
        # Separamos os comandos read em linhas distintas para evitar problemas de buffer.
        
        # Loop para garantir que a senha seja digitada corretamente
        while true; do
            read -s -p "Digite a senha para o novo usuário deploy: " DEPLOY_PASSWORD
            echo
            read -s -p "Confirme a senha: " DEPLOY_PASSWORD_CONFIRM
            echo

            if [ "$DEPLOY_PASSWORD" = "$DEPLOY_PASSWORD_CONFIRM" ]; then
                if [ -z "$DEPLOY_PASSWORD" ]; then
                    echo "A senha não pode ser vazia. Tente novamente."
                else
                    # Senhas coincidem e não estão vazias, pode sair do loop
                    break
                fi
            else
                echo "As senhas não coincidem. Por favor, tente novamente."
            fi
        done
        
        echo "Criando usuário deploy..."
        useradd -m -s /bin/bash deploy && echo "deploy:$DEPLOY_PASSWORD" | chpasswd && usermod -aG sudo deploy
    fi

    # --- Instalação de Pacotes e Docker ---
    echo "Atualizando pacotes e instalando dependências..."
    apt-get update && apt-get upgrade -y
    apt-get install -y apt-transport-https ca-certificates curl gnupg apache2-utils

    if ! command -v docker &> /dev/null; then
        echo "Instalando Docker..."
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
    fi
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    usermod -aG docker deploy
    systemctl start docker && systemctl enable docker

    # --- Configuração do Docker Swarm e Redes ---
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        echo "Inicializando Docker Swarm..."; IP_ADDRESSES=$(hostname -I); # ... (Lógica de seleção de IP) ...
        docker swarm init --advertise-addr $IP_ADDRESSES # Simplificado, ajuste se necessário
    else
        echo "Docker Swarm já está ativo."; fi
    if ! docker network ls | grep -q "traefik-public"; then docker network create --driver=overlay traefik-public; else echo "Rede 'traefik-public' já existe."; fi
    if ! docker network ls | grep -q "backend-network"; then docker network create --driver=overlay --attachable backend-network; else echo "Rede 'backend-network' já existe."; fi

    # --- Deploy dos Serviços ---
    
    # Traefik
    if ! docker service ls | grep -q "traefik_traefik"; then
        echo "-----------------------------------------------------"; echo "Configurando o Traefik..."
        read -p "Digite seu e-mail para notificações do Let's Encrypt: " LETSENCRYPT_EMAIL; export LETSENCRYPT_EMAIL
        TRAEFIK_PASS=$(openssl rand -base64 16); echo "--- Senha do Traefik: $TRAEFIK_PASS (ANOTE!) ---"
        create_or_update_secret "traefik_dashboard_users" "$(htpasswd -nbB admin "$TRAEFIK_PASS")"
        envsubst '\$DOMAIN_NAME \$LETSENCRYPT_EMAIL' < traefik.yml | docker stack deploy -c - traefik
    else echo "Stack do Traefik já parece estar rodando. Pulando."; fi
    
    # Portainer
    if ! docker service ls | grep -q "portainer_portainer"; then
        echo "-----------------------------------------------------"; echo "Configurando o Portainer..."
        envsubst '\$DOMAIN_NAME' < portainer.yml | docker stack deploy -c - portainer
    else echo "Stack do Portainer já parece estar rodando. Pulando."; fi
    
    # PostgreSQL
    if ! docker service ls | grep -q "postgres_postgres"; then
        echo "-----------------------------------------------------"; echo "Configurando o PostgreSQL..."
        read -p "Digite o nome do BD (ex: main_db): " PG_DATABASE; read -p "Digite o nome do usuário do BD (ex: main_user): " PG_USER
        read -s -p "Digite a senha do usuário '$PG_USER' (Enter para gerar): "; echo
        [ -z "$PG_PASSWORD" ] && PG_PASSWORD=$(openssl rand -base64 20) && echo "Senha do PG gerada: $PG_PASSWORD (ANOTE!)"
        create_or_update_secret "postgres_db" "$PG_DATABASE"; create_or_update_secret "postgres_user" "$PG_USER"; create_or_update_secret "postgres_password" "$PG_PASSWORD"
        cat > init-db.sh <<'EOF'
#!/bin/bash
set -e;DB_NAME=$(cat "$POSTGRES_DB_FILE");DB_USER=$(cat "$POSTGRES_USER_FILE");DB_PASSWORD=$(cat "$POSTGRES_PASSWORD_FILE")
psql -v ON_ERROR_STOP=1 --username "postgres" --dbname "$DB_NAME" <<-EOSQL
DO \$do\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$DB_USER') THEN CREATE ROLE "$DB_USER" WITH LOGIN PASSWORD '$DB_PASSWORD'; END IF; END \$do\$;
GRANT ALL PRIVILEGES ON DATABASE "$DB_NAME" TO "$DB_USER"; \c "$DB_NAME" "$DB_USER"; GRANT ALL ON SCHEMA public TO "$DB_USER"; CREATE EXTENSION IF NOT EXISTS vector;
EOSQL
EOF
        chmod +x init-db.sh; docker stack deploy -c postgres.yml postgres
    else echo "Stack do PostgreSQL já parece estar rodando. Pulando."; fi

    # Redis
    if ! docker service ls | grep -q "redis_redis"; then
        echo "-----------------------------------------------------"; echo "Configurando o Redis..."
        read -s -p "Digite a senha para o Redis (Enter para gerar): "; echo
        [ -z "$REDIS_PASSWORD" ] && REDIS_PASSWORD=$(openssl rand -base64 20) && echo "Senha do Redis gerada: $REDIS_PASSWORD (ANOTE!)"
        create_or_update_secret "redis_password" "$REDIS_PASSWORD"
        envsubst '\$DOMAIN_NAME' < redis.yml | docker stack deploy -c - redis
    else echo "Stack do Redis já parece estar rodando. Pulando."; fi

    # MinIO
    if ! docker service ls | grep -q "minio_minio"; then
        echo "-----------------------------------------------------"; echo "Configurando o MinIO..."
        read -p "Usuário ROOT do MinIO (Enter para 'admin'): " MINIO_ROOT_USER; [ -z "$MINIO_ROOT_USER" ] && MINIO_ROOT_USER="admin"
        read -s -p "Senha ROOT do MinIO (Enter para gerar): "; echo
        [ -z "$MINIO_ROOT_PASSWORD" ] && MINIO_ROOT_PASSWORD=$(openssl rand -base64 20) && echo "Senha ROOT do MinIO gerada: $MINIO_ROOT_PASSWORD (ANOTE!)"
        create_or_update_secret "minio_root_user" "$MINIO_ROOT_USER"; create_or_update_secret "minio_root_password" "$MINIO_ROOT_PASSWORD"
        envsubst '\$DOMAIN_NAME' < minio.yml | docker stack deploy -c - minio
    else echo "Stack do MinIO já parece estar rodando. Pulando."; fi

    # Evolution API
    if ! docker service ls | grep -q "evolution_evolution-api"; then
        echo "-----------------------------------------------------"; echo "Configurando a Evolution API..."
        read -s -p "Chave de API da Evolution (Enter para gerar): "; echo
        [ -z "$EVOLUTION_API_KEY" ] && EVOLUTION_API_KEY=$(openssl rand -hex 16) && echo "Chave API Evolution gerada: $EVOLUTION_API_KEY (ANOTE!)"
        create_or_update_secret "evolution_api_key" "$EVOLUTION_API_KEY"
        cat > evolution.env <<EOF
SERVER_URL=https://api.${DOMAIN_NAME};DEL_INSTANCE=false;LANGUAGE=pt-BR;DATABASE_ENABLED=true;DATABASE_PROVIDER=postgresql;DATABASE_SAVE_DATA_INSTANCE=true;DATABASE_SAVE_DATA_NEW_MESSAGE=true;DATABASE_SAVE_MESSAGE_UPDATE=true;DATABASE_SAVE_DATA_CONTACTS=true;DATABASE_SAVE_DATA_CHATS=true;CACHE_REDIS_ENABLED=true;CACHE_REDIS_PREFIX_KEY=evolution_api;S3_ENABLED=true;S3_PORT=443;S3_ENDPOINT=s3api.${DOMAIN_NAME};S3_USE_SSL=true;S3_BUCKET=evolution;AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=true;PROVIDER_ENABLED=false;RABBITMQ_ENABLED=false;SQS_ENABLED=false;WEBSOCKET_ENABLED=false
EOF
        cat > entrypoint.sh <<'EOF'
#!/bin/sh
set -e;PG_DB=$(cat /run/secrets/postgres_db);PG_USER=$(cat /run/secrets/postgres_user);PG_PASS=$(cat /run/secrets/postgres_password);REDIS_PASS=$(cat /run/secrets/redis_password);MINIO_USER=$(cat /run/secrets/minio_root_user);MINIO_PASS=$(cat /run/secrets/minio_root_password);EVO_API_KEY=$(cat /run/secrets/evolution_api_key)
export DATABASE_CONNECTION_URI="postgresql://${PG_USER}:${PG_PASS}@postgres:5432/${PG_DB}";export CACHE_REDIS_URI="redis://:${REDIS_PASS}@redis:6379/0";export S3_ACCESS_KEY="${MINIO_USER}";export S3_SECRET_KEY="${MINIO_PASS}";export AUTHENTICATION_API_KEY="${EVO_API_KEY}"
exec "$@"
EOF
        chmod +x entrypoint.sh; envsubst '\$DOMAIN_NAME' < evolution.yml | docker stack deploy -c - evolution
    else echo "Stack da Evolution API já parece estar rodando. Pulando."; fi

    # n8n
    if ! docker service ls | grep -q "n8n_n8n-editor"; then
        echo "-----------------------------------------------------"; echo "Configurando o n8n..."
        N8N_DB_USER="n8n_user"; N8N_DB_NAME="n8n_db"
        read -s -p "Senha para o BD do n8n (Enter para gerar): "; echo
        [ -z "$N8N_DB_PASSWORD" ] && N8N_DB_PASSWORD=$(openssl rand -base64 20) && echo "Senha BD n8n gerada: $N8N_DB_PASSWORD (ANOTE!)"
        create_or_update_secret "n8n_db_user" "$N8N_DB_USER"; create_or_update_secret "n8n_db_name" "$N8N_DB_NAME"; create_or_update_secret "n8n_db_password" "$N8N_DB_PASSWORD"
        POSTGRES_CONTAINER_ID=$(docker ps -q --filter "name=postgres_postgres" | head -n 1)
        if [ -n "$POSTGRES_CONTAINER_ID" ]; then
            echo "Criando usuário e banco de dados para n8n no PostgreSQL..."
            docker exec "$POSTGRES_CONTAINER_ID" psql -U postgres -c "CREATE USER $N8N_DB_USER WITH PASSWORD '$N8N_DB_PASSWORD';" || echo "Usuário $N8N_DB_USER já existe."
            docker exec "$POSTGRES_CONTAINER_ID" psql -U postgres -c "CREATE DATABASE $N8N_DB_NAME OWNER $N8N_DB_USER;" || echo "BD $N8N_DB_NAME já existe."
        fi
        read -s -p "Chave de criptografia do n8n (Enter para gerar): "; echo
        [ -z "$N8N_ENCRYPTION_KEY" ] && N8N_ENCRYPTION_KEY=$(openssl rand -hex 16) && echo "Chave n8n gerada: $N8N_ENCRYPTION_KEY (ANOTE! CRÍTICO!)"
        create_or_update_secret "n8n_encryption_key" "$N8N_ENCRYPTION_KEY"
        cat > n8n.env <<EOF
N8N_HOST=n8n.${DOMAIN_NAME};N8N_PROTOCOL=https;N8N_EDITOR_BASE_URL=https://n8n.${DOMAIN_NAME};WEBHOOK_URL=https://webhook-n8n.${DOMAIN_NAME};NODE_ENV=production;GENERIC_TIMEZONE=America/Sao_Paulo;TZ=America/Sao_Paulo;EXECUTIONS_MODE=queue;QUEUE_CONCURRENCY=10;N8N_REINSTALL_MISSING_PACKAGES=true;N8N_COMMUNITY_PACKAGES_ENABLED=true;N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true;DB_TYPE=postgresdb;DB_POSTGRESDB_PORT=5432;QUEUE_BULL_REDIS_PORT=6379;QUEUE_BULL_REDIS_DB=2
EOF
        cat > entrypoint-n8n.sh <<'EOF'
#!/bin/sh
set -e;export DB_POSTGRESDB_USER=$(cat /run/secrets/n8n_db_user);export DB_POSTGRESDB_PASSWORD=$(cat /run/secrets/n8n_db_password);export DB_POSTGRESDB_DATABASE=$(cat /run/secrets/n8n_db_name);export QUEUE_BULL_REDIS_PASSWORD=$(cat /run/secrets/redis_password);export N8N_ENCRYPTION_KEY=$(cat /run/secrets/n8n_encryption_key)
export DB_POSTGRESDB_HOST=postgres;export QUEUE_BULL_REDIS_HOST=redis
exec /usr/local/bin/docker-entrypoint.sh "$@"
EOF
        chmod +x entrypoint-n8n.sh; envsubst '\$DOMAIN_NAME' < n8n.yml | docker stack deploy -c - n8n
    else echo "Stack do n8n já parece estar rodando. Pulando."; fi

    # --- Finalização ---
    echo "-----------------------------------------------------"
    echo "Copiando todos os arquivos de configuração para o usuário deploy..."
    BACKUP_SUFFIX=$(date +%Y%m%d_%H%M%S)
    if [ -d "/home/deploy/FluxIE-Server-Setup-Script" ]; then
        mv /home/deploy/FluxIE-Server-Setup-Script "/home/deploy/FluxIE-Server-Setup-Script_backup_$BACKUP_SUFFIX"
    fi
    mkdir -p /home/deploy/FluxIE-Server-Setup-Script
    cp traefik.yml portainer.yml traefik-dynamic.yml postgres.yml init-db.sh redis.yml minio.yml evolution.yml evolution.env entrypoint.sh n8n.yml n8n.env entrypoint-n8n.sh install.sh README.md /home/deploy/FluxIE-Server-Setup-Script/ 2>/dev/null || true
    chown -R deploy:deploy /home/deploy/FluxIE-Server-Setup-Script
    echo "Arquivos de configuração copiados para /home/deploy/FluxIE-Server-Setup-Script/"
    
    echo "Limpando pacotes desnecessários..."
    apt-get autoremove -y > /dev/null && apt-get clean > /dev/null

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
}

# --- Execução do Script ---
# Chama a função principal, passando quaisquer argumentos que o script tenha recebido
main "$@"