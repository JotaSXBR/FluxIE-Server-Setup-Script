# FluxIE Server Setup Script

<div align="center">

```
███████╗██╗     ██╗   ██╗██╗  ██╗██╗███████╗
██╔════╝██║     ██║   ██║╚██╗██╔╝██║██╔════╝
█████╗  ██║     ██║   ██║ ╚███╔╝ ██║█████╗  
██╔══╝  ██║     ██║   ██║ ██╔██╗ ██║██╔══╝  
██║     ███████╗╚██████╔╝██╔╝ ██╗██║███████╗
╚═╝     ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝╚══════╝
```

Script automatizado para configuração de servidor Ubuntu LTS com Docker Swarm, Traefik e Portainer

</div>

## 🚀 Recursos

- ✨ Configuração automatizada do servidor
- 🔒 Configurações de segurança aprimoradas
- 🐳 Docker e Docker Swarm
- 🌐 Traefik como reverse proxy
- 📊 Portainer para gerenciamento do Docker
- 👤 Criação de usuário deploy com permissões adequadas
- 🔑 Desativação do usuário root por segurança

## 📋 Pré-requisitos

- Ubuntu LTS (18.04, 20.04, ou 22.04)
- Acesso root inicial
- Domínios configurados para Traefik e Portainer

## 🛠️ Instalação

1. Clone este repositório:
```bash
git clone https://github.com/JotaSXBR/FluxIE-Server-Setup-Script.git
cd FluxIE-Server-Setup-Script
```

2. Torne o script executável:
```bash
chmod +x install.sh
```

3. Execute o script:
```bash
sudo ./install.sh
```

## 📁 Estrutura do Projeto

```
.
├── install.sh       # Script principal de instalação
├── traefik.yml     # Configuração do Traefik
├── portainer.yml   # Configuração do Portainer
└── README.md       # Este arquivo
```

## ⚙️ O que o Script Faz

1. **Configuração Inicial**
   - Atualiza o sistema
   - Cria usuário deploy
   - Configura permissões sudo

2. **Segurança**
   - Prepara o ambiente para desativar o login root (cria usuário 'deploy', configura SSH)
   - Configura chaves SSH
   - Configura permissões adequadas

3. **Docker**
   - Instala Docker
   - Configura Docker Swarm
   - Instala Docker Compose

4. **Serviços**
   - Configura Traefik como reverse proxy
   - Instala Portainer para gerenciamento
   - Cria rede overlay para comunicação

## 🎯 Pós-instalação

1. Configure os domínios DNS:
   - `traefik.SEU_DOMINIO.COM` (substitua `SEU_DOMINIO.COM` pelo domínio que você informou ao script)
   - `portainer.SEU_DOMINIO.COM` (substitua `SEU_DOMINIO.COM` pelo domínio que você informou ao script)

2. Configure as senhas:
   - Traefik dashboard: usuário `admin`. A senha foi gerada aleatoriamente e exibida durante a execução do script. Certifique-se de tê-la anotado.
   - Portainer: defina a senha do administrador no primeiro acesso.

3. Use o usuário `deploy` para acessar o servidor

## 🔒 Segurança

- O script prepara o sistema para que o acesso root via senha seja desativado (recomendado como passo manual adicional, editando `/etc/ssh/sshd_config` e reiniciando o serviço SSH).

## 📞 Suporte

Para suporte, entre em contato com nossa equipe de DevOps.

## 📝 Licença

Este projeto está sob a licença [MIT](LICENSE).

---

Desenvolvido com ❤️ por FluxIE
