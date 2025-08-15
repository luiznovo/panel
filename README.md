# G-Panel - Sistema de Gerenciamento

## Instalação Manual - Ubuntu 24.04

### Pré-requisitos

```bash
# Atualizar sistema
sudo apt update && sudo apt upgrade -y

# Instalar dependências básicas
sudo apt install -y curl wget git unzip nginx
```

### 1. Instalar Node.js 18

```bash
# Adicionar repositório NodeSource
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -

# Instalar Node.js
sudo apt install -y nodejs

# Verificar instalação
node --version
npm --version
```

### 2. Instalar PM2

```bash
# Instalar PM2 globalmente
sudo npm install -g pm2

# Configurar PM2 para iniciar com o sistema
pm2 startup
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u $USER --hp $HOME
```

### 3. Configurar Projeto

```bash
# Criar diretório do projeto
sudo mkdir -p /opt/gpanel
sudo chown $USER:$USER /opt/gpanel

# Clonar/copiar projeto
cp -r . /opt/gpanel/
cd /opt/gpanel

# Instalar dependências
npm install --production
```

### 4. Configurar Variáveis de Ambiente

```bash
# Criar arquivo .env
cp .env.example .env

# Editar configurações
nano .env
```

**Configurações mínimas no .env:**
```env
NODE_ENV=production
PORT=3000
DB_TYPE=sqlite
DB_PATH=/opt/gpanel/data/database.sqlite
JWT_SECRET=sua_chave_jwt_aqui
SESSION_SECRET=sua_chave_session_aqui
ADMIN_USERNAME=admin
ADMIN_EMAIL=admin@localhost
ADMIN_PASSWORD=sua_senha_admin
```

### 5. Configurar Nginx

```bash
# Criar configuração do site
sudo nano /etc/nginx/sites-available/gpanel
```

**Conteúdo do arquivo:**
```nginx
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
```

```bash
# Habilitar site
sudo ln -s /etc/nginx/sites-available/gpanel /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default

# Testar e reiniciar Nginx
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx
```

### 6. Inicializar Banco de Dados

```bash
cd /opt/gpanel

# Criar diretórios necessários
mkdir -p data logs backups

# Executar migrações (se existirem)
npm run migrate || echo "Sem migrações"

# Criar usuário admin (se script existir)
npm run create-admin || echo "Sem script de admin"
```

### 7. Iniciar Aplicação

```bash
cd /opt/gpanel

# Iniciar com PM2
pm2 start ecosystem.config.js

# Salvar configuração PM2
pm2 save
```

### 8. Verificar Status

```bash
# Status dos serviços
sudo systemctl status nginx
pm2 status
pm2 logs g-panel

# Testar acesso
curl http://localhost
```

## Comandos Úteis

### Gerenciar Aplicação
```bash
# Ver logs
pm2 logs g-panel

# Reiniciar aplicação
pm2 restart g-panel

# Parar aplicação
pm2 stop g-panel

# Recarregar configuração
pm2 reload g-panel
```

### Deploy de Atualizações
```bash
cd /opt/gpanel

# Backup do banco (se SQLite)
cp data/database.sqlite backups/database-$(date +%Y%m%d-%H%M%S).sqlite

# Atualizar código
git pull origin main
# ou copiar novos arquivos

# Instalar novas dependências
npm install --production

# Reiniciar aplicação
pm2 restart g-panel
```

### Backup Manual
```bash
# Criar backup completo
tar -czf /tmp/gpanel-backup-$(date +%Y%m%d-%H%M%S).tar.gz \
    /opt/gpanel/data \
    /opt/gpanel/.env \
    /opt/gpanel/logs
```

## Estrutura do Projeto

```
/opt/gpanel/
├── app.js              # Arquivo principal
├── package.json        # Dependências
├── ecosystem.config.js # Configuração PM2
├── .env               # Variáveis de ambiente
├── data/              # Banco de dados
├── logs/              # Logs da aplicação
├── backups/           # Backups
└── public/            # Arquivos estáticos
```

## Acesso

- **URL:** http://IP_DA_VPS
- **Admin:** Conforme configurado no .env
- **Logs:** `pm2 logs g-panel`

## Troubleshooting

### Aplicação não inicia
```bash
# Verificar logs
pm2 logs g-panel

# Verificar arquivo .env
cat /opt/gpanel/.env

# Verificar permissões
ls -la /opt/gpanel/
```

### Nginx não funciona
```bash
# Verificar configuração
sudo nginx -t

# Verificar logs
sudo tail -f /var/log/nginx/error.log

# Verificar se aplicação está rodando
curl http://127.0.0.1:3000
```

### Banco de dados
```bash
# Verificar se arquivo existe
ls -la /opt/gpanel/data/

# Verificar permissões
sudo chown -R $USER:$USER /opt/gpanel/data/
```

## Configuração com Domínio (Opcional)

Se quiser adicionar domínio posteriormente:

1. Apontar domínio para IP da VPS
2. Instalar Certbot: `sudo apt install certbot python3-certbot-nginx`
3. Obter SSL: `sudo certbot --nginx -d seudominio.com`
4. Atualizar .env com o domínio
5. Reiniciar aplicação: `pm2 restart g-panel`