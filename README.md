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
git clone https://github.com/fluxie/server-setup.git
cd server-setup
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
   - Desativa login root
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
   - traefik.fluxie.com.br
   - portainer.fluxie.com.br

2. Configure as senhas:
   - Traefik dashboard (usuário: admin, senha padrão: fluxie)
   - Portainer (primeiro acesso)

3. Use o usuário `deploy` para acessar o servidor

## 🔒 Segurança

- O acesso root é desativado por padrão
- Autenticação básica no dashboard do Traefik
- Comunicação HTTPS com certificados automáticos Let's Encrypt
- Usuário deploy com permissões sudo controladas

## 📞 Suporte

Para suporte, entre em contato com nossa equipe de DevOps.

## 📝 Licença

Este projeto está sob a licença [MIT](LICENSE).

---

Desenvolvido com ❤️ por FluxIE
