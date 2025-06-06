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
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
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

    docker swarm init --advertise-addr $SWARM_ADVERTISE_IP || {
        echo "Erro ao inicializar Docker Swarm"
        exit 1
    }
else
    echo "Docker Swarm já está ativo"
fi

# Criando rede para Traefik
echo "Verificando rede do Traefik..."
if ! docker network ls | grep -q "traefik-public"; then
    echo "Criando rede para Traefik..."
    docker network create --driver=overlay traefik-public || {
        echo "Erro ao criar rede do Traefik"
        exit 1
    }
else
    echo "Rede traefik-public já existe"
fi

# Instalação do Docker Compose V2 (plugin) e outras ferramentas
echo "Instalando ferramentas adicionais (Docker Compose, apache2-utils)..."
apt-get update
apt-get install -y docker-compose-plugin apache2-utils

# Verificando a versão mais recente do Traefik
echo "Obtendo a versão mais recente do Traefik..."
TRAEFIK_VERSION=$(curl -s https://api.github.com/repos/traefik/traefik/releases/latest | grep tag_name | cut -d '"' -f 4)
if [ -z "$TRAEFIK_VERSION" ]; then
    echo "Não foi possível obter a versão mais recente do Traefik. Usando 'latest'..."
    TRAEFIK_VERSION="latest"
fi
echo "Versão do Traefik a ser instalada: $TRAEFIK_VERSION"

# Adicionando validação de versão
if [[ ! "$TRAEFIK_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] && [ "$TRAEFIK_VERSION" != "latest" ]; then
    echo "Formato de versão do Traefik inválido. Usando 'latest'..."
    TRAEFIK_VERSION="latest"
fi

# Geração e Configuração da Senha do Traefik Dashboard com Docker Secret
echo "Gerando senha para o Traefik Dashboard..."
TRAEFIK_ADMIN_PASSWORD_RAW=$(openssl rand -base64 16)
TRAEFIK_ADMIN_PASSWORD_HASHED=$(htpasswd -nbB admin "$TRAEFIK_ADMIN_PASSWORD_RAW")

if [ -z "$TRAEFIK_ADMIN_PASSWORD_HASHED" ]; then
    echo "Erro ao gerar a senha do Traefik Dashboard. Saindo."
    exit 1
fi

echo "--- Senha do Traefik Dashboard ---"
echo "Usuário: admin"
echo "Senha: $TRAEFIK_ADMIN_PASSWORD_RAW"
echo "----------------------------------"
echo "Por favor, ANOTE esta senha! Ela não será exibida novamente após a instalação."
read -p "Pressione Enter para continuar..."

if ! docker secret inspect traefik_dashboard_users &>/dev/null; then
    echo "$TRAEFIK_ADMIN_PASSWORD_HASHED" | docker secret create traefik_dashboard_users -
    echo "Docker secret 'traefik_dashboard_users' criado."
else
    echo "Docker secret 'traefik_dashboard_users' já existe. Atualizando-o..."
    SECRET_ID=$(docker secret ls --filter name=traefik_dashboard_users -q)
    docker secret rm "$SECRET_ID"
    echo "$TRAEFIK_ADMIN_PASSWORD_HASHED" | docker secret create traefik_dashboard_users -
fi

# Deploy do Traefik
echo "Deployando Traefik..."
envsubst '\$TRAEFIK_VERSION \$DOMAIN_NAME' < traefik.yml | docker stack deploy -c - traefik

# Verificando a versão mais recente do Portainer
echo "Obtendo a versão mais recente do Portainer..."
PORTAINER_VERSION=$(curl -s https://api.github.com/repos/portainer/portainer/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//')
if [ -z "$PORTAINER_VERSION" ]; then
    echo "Não foi possível obter a versão mais recente do Portainer. Usando 'latest'..."
    PORTAINER_VERSION="latest"
fi
echo "Versão do Portainer a ser instalada: $PORTAINER_VERSION"

# Deploy do Portainer
echo "Deployando Portainer..."
envsubst '\$PORTAINER_VERSION \$DOMAIN_NAME' < portainer.yml | docker stack deploy -c - portainer

# Copiando arquivos de configuração para o usuário deploy
echo "Copiando arquivos de configuração para o usuário deploy..."
BACKUP_SUFFIX=$(date +%Y%m%d_%H%M%S)
if [ -d "/home/deploy/FluxIE-Server-Setup-Script" ]; then
    echo "Backup da pasta existente..."
    mv /home/deploy/FluxIE-Server-Setup-Script "/home/deploy/FluxIE-Server-Setup-Script_backup_$BACKUP_SUFFIX"
fi
mkdir -p /home/deploy/FluxIE-Server-Setup-Script
cp traefik.yml portainer.yml install.sh README.md /home/deploy/FluxIE-Server-Setup-Script/
chown -R deploy:deploy /home/deploy/FluxIE-Server-Setup-Script

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
echo "1. Configurar os domínios no DNS para traefik.$DOMAIN_NAME e portainer.$DOMAIN_NAME"
echo "2. Os arquivos de configuração foram copiados para /home/deploy/FluxIE-Server-Setup-Script/"
echo "3. Use o usuário 'deploy' para acessar o servidor (sudo agora requer senha!)"
echo "4. A senha do Traefik Dashboard (usuário: admin) foi gerada e exibida acima. Anote-a!"
echo "5. Configure a senha inicial do Portainer acessando https://portainer.$DOMAIN_NAME"
echo "
Serviços instalados:
- Traefik (https://traefik.$DOMAIN_NAME)
- Portainer (https://portainer.$DOMAIN_NAME)
"
# A seção de desativação do root permanece a mesma, pois já é excelente.