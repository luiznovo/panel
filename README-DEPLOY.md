# G-Panel Enterprise Deployment Guide

## 📋 Índice

- [Visão Geral](#visão-geral)
- [Pré-requisitos](#pré-requisitos)
- [Instalação Rápida](#instalação-rápida)
- [Configuração Detalhada](#configuração-detalhada)
- [Deploy com Docker](#deploy-com-docker)
- [Configuração do Nginx](#configuração-do-nginx)
- [Backup e Rollback](#backup-e-rollback)
- [Monitoramento](#monitoramento)
- [Troubleshooting](#troubleshooting)
- [Manutenção](#manutenção)

## 🚀 Visão Geral

Este guia fornece instruções completas para deploy do G-Panel em ambiente de produção com recursos enterprise:

- ✅ **Docker** com multi-stage build otimizado
- ✅ **PM2** para gerenciamento de processos
- ✅ **Nginx** como proxy reverso e load balancer
- ✅ **Backup automático** com rotação inteligente
- ✅ **Rollback** rápido e seguro
- ✅ **Zero downtime** deployment
- ✅ **SSL/TLS** com Let's Encrypt
- ✅ **Monitoramento** e alertas
- ✅ **Rate limiting** e segurança

## 📋 Pré-requisitos

### Sistema Operacional
- Ubuntu 20.04+ / CentOS 8+ / Debian 11+
- Mínimo 2GB RAM, 20GB disco
- Acesso root ou sudo

### Software Necessário
```bash
# Node.js 18+
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# PM2
sudo npm install -g pm2

# Nginx
sudo apt update
sudo apt install -y nginx

# Utilitários
sudo apt install -y git curl wget unzip jq sqlite3
```

## ⚡ Instalação Rápida

### 1. Clone e Configure
```bash
# Clone o repositório
git clone https://github.com/seu-usuario/g-panel.git
cd g-panel

# Torne os scripts executáveis
chmod +x scripts/*.sh

# Execute o setup completo
sudo ./scripts/setup.sh
```

### 2. Configuração Inicial
```bash
# Copie e configure as variáveis de ambiente
cp .env.example .env
nano .env

# Configure pelo menos estas variáveis obrigatórias:
# JWT_SECRET=sua-chave-jwt-super-secreta
# SESSION_SECRET=sua-chave-sessao-super-secreta
# APP_URL=https://seu-dominio.com
```

### 3. Inicialização
```bash
# Executar seed e criar usuário admin
npm run seed
npm run createUser

# Iniciar com PM2
pm2 start ecosystem.config.js
pm2 save
pm2 startup
```

## 🔧 Configuração Detalhada

### Estrutura de Diretórios
```
/opt/g-panel/
├── app/                 # Código da aplicação
├── data/               # Banco de dados SQLite
├── logs/               # Logs da aplicação
├── backups/            # Backups automáticos
├── nginx/              # Configurações do Nginx
├── scripts/            # Scripts de deploy
└── uploads/            # Arquivos enviados
```

### Configuração do Usuário
```bash
# Criar usuário dedicado
sudo useradd -m -s /bin/bash g-panel
sudo usermod -aG docker g-panel

# Configurar diretórios
sudo mkdir -p /opt/g-panel/{app,data,logs,backups,nginx,uploads}
sudo chown -R g-panel:g-panel /opt/g-panel
```

### Variáveis de Ambiente
Edite o arquivo `.env` com suas configurações:

```bash
# Configurações básicas
NODE_ENV=production
PORT=3000
APP_URL=https://seu-dominio.com

# Segurança (OBRIGATÓRIO alterar)
JWT_SECRET=gere-uma-chave-super-secreta-aqui
SESSION_SECRET=gere-outra-chave-super-secreta-aqui

# Banco de dados
DB_TYPE=sqlite
DB_PATH=./data/database.sqlite

# Email (configure conforme seu provedor)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=seu-email@gmail.com
SMTP_PASS=sua-senha-de-app
```

## 🐳 Deploy com Docker

### Build da Imagem
```bash
# Build da imagem otimizada
docker build -t g-panel:latest .

# Ou usar docker-compose
docker-compose -f docker-compose.prod.yml build
```

### Execução com Docker Compose
```bash
# Iniciar todos os serviços
docker-compose -f docker-compose.prod.yml up -d

# Verificar status
docker-compose -f docker-compose.prod.yml ps

# Ver logs
docker-compose -f docker-compose.prod.yml logs -f g-panel
```

### Configuração de Volumes
```yaml
# docker-compose.prod.yml
volumes:
  - ./data:/app/data
  - ./uploads:/app/uploads
  - ./logs:/app/logs
  - ./backups:/opt/g-panel/backups
```

## 🌐 Configuração do Nginx

### Instalação da Configuração
```bash
# Copiar configuração
sudo cp nginx/g-panel.conf /etc/nginx/sites-available/
sudo cp nginx/snippets/g-panel-common.conf /etc/nginx/snippets/

# Ativar site
sudo ln -s /etc/nginx/sites-available/g-panel.conf /etc/nginx/sites-enabled/

# Remover site padrão
sudo rm -f /etc/nginx/sites-enabled/default

# Testar configuração
sudo nginx -t

# Reiniciar Nginx
sudo systemctl restart nginx
```

### Configuração SSL com Let's Encrypt
```bash
# Instalar Certbot
sudo apt install -y certbot python3-certbot-nginx

# Obter certificado
sudo certbot --nginx -d seu-dominio.com -d www.seu-dominio.com

# Renovação automática
sudo crontab -e
# Adicionar: 0 12 * * * /usr/bin/certbot renew --quiet
```

### Load Balancing
Para múltiplas instâncias, edite `/etc/nginx/sites-available/g-panel.conf`:

```nginx
upstream g_panel_backend {
    server 127.0.0.1:3000 weight=3;
    server 127.0.0.1:3001 weight=2;
    server 127.0.0.1:3002 weight=1 backup;
    
    least_conn;
    keepalive 32;
}
```

## 💾 Backup e Rollback

### Backup Automático
```bash
# Configurar backup diário
sudo crontab -e
# Adicionar: 0 2 * * * /opt/g-panel/scripts/backup.sh create

# Backup manual
./scripts/backup.sh create

# Listar backups
./scripts/backup.sh list

# Verificar backup
./scripts/backup.sh verify nome-do-backup.tar.gz
```

### Rollback
```bash
# Rollback interativo
./scripts/rollback.sh

# Rollback automático para backup específico
./scripts/rollback.sh auto daily_20231201_120000_abc123

# Rollback para o backup mais recente
./scripts/rollback.sh auto latest
```

### Estratégia de Backup
- **Diários**: Mantidos por 7 dias
- **Semanais**: Mantidos por 4 semanas
- **Mensais**: Mantidos por 12 meses
- **Deploy**: Backup antes de cada atualização

## 🚀 Deploy Automático

### Deploy com Zero Downtime
```bash
# Deploy completo
./scripts/deploy.sh

# Deploy apenas do código
./scripts/deploy.sh --code-only

# Deploy com skip de testes
./scripts/deploy.sh --skip-tests
```

### Pipeline CI/CD
Exemplo para GitHub Actions:

```yaml
# .github/workflows/deploy.yml
name: Deploy to Production

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Deploy to server
        uses: appleboy/ssh-action@v0.1.5
        with:
          host: ${{ secrets.HOST }}
          username: ${{ secrets.USERNAME }}
          key: ${{ secrets.SSH_KEY }}
          script: |
            cd /opt/g-panel
            git pull origin main
            ./scripts/deploy.sh
```

## 📊 Monitoramento

### PM2 Monitoring
```bash
# Status dos processos
pm2 status

# Logs em tempo real
pm2 logs g-panel

# Métricas
pm2 monit

# Restart automático em caso de falha
pm2 start ecosystem.config.js --watch
```

### Health Checks
```bash
# Verificar saúde da aplicação
curl http://localhost:3000/health

# Verificar Nginx
curl http://localhost/nginx-health

# Verificar SSL
ssl-cert-check -c /etc/letsencrypt/live/seu-dominio.com/cert.pem
```

### Logs
```bash
# Logs da aplicação
tail -f /opt/g-panel/logs/app.log

# Logs do Nginx
tail -f /var/log/nginx/g-panel-access.log
tail -f /var/log/nginx/g-panel-error.log

# Logs do PM2
pm2 logs g-panel --lines 100
```

## 🔧 Troubleshooting

### Problemas Comuns

#### Aplicação não inicia
```bash
# Verificar logs
pm2 logs g-panel

# Verificar configuração
node -c app.js

# Verificar dependências
npm audit
```

#### Nginx retorna 502
```bash
# Verificar se aplicação está rodando
curl http://localhost:3000

# Verificar configuração do Nginx
sudo nginx -t

# Verificar logs do Nginx
tail -f /var/log/nginx/error.log
```

#### Banco de dados corrompido
```bash
# Verificar integridade
sqlite3 /opt/g-panel/data/database.sqlite "PRAGMA integrity_check;"

# Restaurar do backup
./scripts/rollback.sh auto latest
```

#### SSL não funciona
```bash
# Verificar certificado
sudo certbot certificates

# Renovar certificado
sudo certbot renew

# Verificar configuração SSL
ssl-cert-check -c /etc/letsencrypt/live/seu-dominio.com/cert.pem
```

### Comandos de Diagnóstico
```bash
# Status geral do sistema
./scripts/status.sh

# Verificar portas
sudo netstat -tlnp | grep :3000
sudo netstat -tlnp | grep :80
sudo netstat -tlnp | grep :443

# Verificar processos
ps aux | grep node
ps aux | grep nginx

# Verificar espaço em disco
df -h
du -sh /opt/g-panel/*
```

## 🛠️ Manutenção

### Atualizações
```bash
# Atualizar sistema
sudo apt update && sudo apt upgrade -y

# Atualizar Node.js
sudo npm install -g n
sudo n stable

# Atualizar PM2
sudo npm install -g pm2@latest
pm2 update

# Atualizar dependências do projeto
npm update
```

### Limpeza
```bash
# Limpar logs antigos
find /opt/g-panel/logs -name "*.log" -mtime +30 -delete

# Limpar backups antigos
./scripts/backup.sh cleanup

# Limpar cache do Docker
docker system prune -a

# Limpar cache do npm
npm cache clean --force
```

### Otimização
```bash
# Otimizar banco de dados
sqlite3 /opt/g-panel/data/database.sqlite "VACUUM;"

# Otimizar imagens Docker
docker image prune -a

# Configurar swap (se necessário)
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### Segurança
```bash
# Atualizar certificados SSL
sudo certbot renew

# Verificar permissões
sudo find /opt/g-panel -type f -perm /o+w

# Configurar firewall
sudo ufw enable
sudo ufw allow 22
sudo ufw allow 80
sudo ufw allow 443

# Verificar logs de segurança
sudo tail -f /var/log/auth.log
```

## 📞 Suporte

### Contatos
- **Email**: suporte@g-panel.com
- **Discord**: [G-Panel Community](https://discord.gg/g-panel)
- **GitHub**: [Issues](https://github.com/seu-usuario/g-panel/issues)

### Recursos Adicionais
- [Documentação da API](https://docs.g-panel.com)
- [Guia de Desenvolvimento](./DEVELOPMENT.md)
- [Changelog](./CHANGELOG.md)
- [FAQ](https://docs.g-panel.com/faq)

---

**© 2024 G-Panel. Todos os direitos reservados.**

> 💡 **Dica**: Mantenha sempre backups atualizados e teste o processo de rollback regularmente em ambiente de desenvolvimento.