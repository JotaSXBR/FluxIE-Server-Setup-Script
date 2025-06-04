#!/bin/bash

# Sair em caso de erro
set -e

echo "
███████╗██╗     ██╗   ██╗██╗  ██╗██╗███████╗
██╔════╝██║     ██║   ██║╚██╗██╔╝██║██╔════╝
█████╗  ██║     ██║   ██║ ╚███╔╝ ██║█████╗  
██╔══╝  ██║     ██║   ██║ ██╔██╗ ██║██╔══╝  
██║     ███████╗╚██████╔╝██╔╝ ██╗██║███████╗
╚═╝     ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝╚══════╝
                                             
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

# Configuração do sudo sem senha para o usuário deploy
echo "Configurando permissões sudo..."
echo "deploy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/deploy
chmod 440 /etc/sudoers.d/deploy

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
echo "Inicializando Docker Swarm..."
docker swarm init --advertise-addr $(hostname -i | awk '{print $1}')

# Criando rede para Traefik
echo "Criando rede para Traefik..."
docker network create --driver=overlay traefik-public

# Instalação do Docker Compose
echo "Instalando Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Verificando a versão mais recente do Traefik
echo "Obtendo a versão mais recente do Traefik..."
TRAEFIK_VERSION=$(curl -s https://api.github.com/repos/traefik/traefik/releases/latest | grep tag_name | cut -d '"' -f 4)
echo "Versão do Traefik a ser instalada: $TRAEFIK_VERSION"

# Exportando a versão do Traefik para uso no compose
export TRAEFIK_VERSION

# Deploy do Traefik
echo "Deployando Traefik..."
envsubst < traefik.yml | docker stack deploy -c - traefik

# Deploy do Portainer
echo "Deployando Portainer..."
docker stack deploy -c portainer.yml portainer

# Copiando arquivos de configuração para o usuário deploy
echo "Copiando arquivos de configuração para o usuário deploy..."
mkdir -p /home/deploy/DatabaseSAAS
cp traefik.yml portainer.yml install.sh README.md /home/deploy/DatabaseSAAS/
chown -R deploy:deploy /home/deploy/DatabaseSAAS

echo "
╔═══════════════════════════════════════════════╗
║        Instalação Concluída com Sucesso!      ║
║             Powered by FluxIE                 ║
╚═══════════════════════════════════════════════╝
"

echo "Lembre-se de:"
echo "1. Configurar os domínios no DNS para traefik.$DOMAIN_NAME e portainer.$DOMAIN_NAME"
echo "2. Os arquivos de configuração foram copiados para /home/deploy/DatabaseSAAS/"
echo "3. Use o usuário 'deploy' para acessar o servidor"
echo "4. Altere a senha do Traefik dashboard (usuário: admin, senha padrão: fluxie)"
echo "5. Configure a senha inicial do Portainer acessando https://portainer.$DOMAIN_NAME"

echo "
Serviços instalados:
- Traefik (https://traefik.$DOMAIN_NAME)
- Portainer (https://portainer.$DOMAIN_NAME)

Obrigado por usar o script de instalação FluxIE!
Para suporte, contate nossa equipe de DevOps.
"

# Verificar uma última vez se o usuário está pronto para desativar o root
echo "IMPORTANTE: Todos os serviços foram instalados e configurados."
echo "O próximo passo é desativar o acesso root."
echo "Certifique-se de que você pode fazer login como usuário 'deploy' antes de continuar."
read -p "Você está pronto para desativar o acesso root? (s/N): " DISABLE_ROOT_OK

if [ "${DISABLE_ROOT_OK,,}" = "s" ]; then
    echo "Desativando login root por questões de segurança..."
    passwd -l root
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    systemctl restart sshd
    echo "Acesso root desativado. Por favor, faça login como usuário 'deploy' para continuar."
    echo "Você será desconectado em 10 segundos..."
    sleep 10
else
    echo "O acesso root não foi desativado. Você pode executar este script novamente mais tarde para desativá-lo."
    echo "AVISO: Manter o acesso root ativado não é recomendado em ambiente de produção."
fi