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

echo "Iniciando script de configuração do servidor..."

# Atualização dos pacotes do sistema
echo "Atualizando pacotes do sistema..."
apt-get update
apt-get upgrade -y

# Criação do usuário deploy e adição ao grupo sudo
echo "Criando usuário deploy..."
useradd -m -s /bin/bash deploy
usermod -aG sudo deploy
mkdir -p /home/deploy/.ssh
cp /root/.ssh/authorized_keys /home/deploy/.ssh/ 2>/dev/null || echo "Nenhuma chave SSH para copiar"
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys 2>/dev/null || true

# Configuração do sudo sem senha para o usuário deploy
echo "Configurando permissões sudo..."
echo "deploy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/deploy
chmod 440 /etc/sudoers.d/deploy

# Desativação do login root
echo "Desativando login root por questões de segurança..."
passwd -l root
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd

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

echo "
╔═══════════════════════════════════════════════╗
║        Instalação Concluída com Sucesso!      ║
║             Powered by FluxIE                 ║
╚═══════════════════════════════════════════════╝
"

echo "Lembre-se de:"
echo "1. Configurar os domínios no DNS para traefik.fluxie.com.br e portainer.fluxie.com.br"
echo "2. Configurar as chaves SSH para o usuário deploy caso ainda não tenha feito"
echo "3. O usuário root foi desativado por segurança"
echo "4. Use o usuário 'deploy' para acessar o servidor"
echo "5. Altere a senha do Traefik dashboard (usuário: admin, senha padrão: fluxie)"
echo "6. Configure a senha inicial do Portainer acessando https://portainer.fluxie.com.br"

echo "
Serviços instalados:
- Traefik (https://traefik.fluxie.com.br)
- Portainer (https://portainer.fluxie.com.br)

Obrigado por usar o script de instalação FluxIE!
Para suporte, contate nossa equipe de DevOps.
"