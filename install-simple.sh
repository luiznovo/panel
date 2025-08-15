#!/bin/bash

# Script de Instalação Simplificado do G-Panel
# Versão otimizada para melhor interatividade

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função de log
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Função para input simples
ask_simple() {
    local question="$1"
    local default="$2"
    local answer
    
    if [ -n "$default" ]; then
        echo -e "${YELLOW}[?]${NC} $question [padrão: $default]"
        echo -n "Resposta: "
    else
        echo -e "${YELLOW}[?]${NC} $question"
        echo -n "Resposta: "
    fi
    
    read answer
    
    if [ -z "$answer" ] && [ -n "$default" ]; then
        echo "$default"
    else
        echo "$answer"
    fi
}

# Função para senha
ask_password_simple() {
    local question="$1"
    local answer
    
    echo -e "${YELLOW}[?]${NC} $question"
    echo -n "Senha: "
    read -s answer
    echo
    echo "$answer"
}

# Função para sim/não
ask_yes_no_simple() {
    local question="$1"
    local default="${2:-n}"
    local answer
    
    while true; do
        if [ "$default" = "y" ]; then
            echo -e "${YELLOW}[?]${NC} $question [Y/n]"
        else
            echo -e "${YELLOW}[?]${NC} $question [y/N]"
        fi
        echo -n "Resposta: "
        read answer
        
        if [ -z "$answer" ]; then
            answer="$default"
        fi
        
        case $answer in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Por favor, responda sim (y) ou não (n).";;
        esac
    done
}

# Verificar se está rodando como root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script deve ser executado como root (use sudo)"
        exit 1
    fi
}

# Banner
show_banner() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    G-PANEL INSTALLER                        ║"
    echo "║                  Instalação Simplificada                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

# Coletar informações básicas
collect_basic_info() {
    log_info "Vamos configurar seu painel G-Panel..."
    echo
    
    echo "=== INFORMAÇÕES BÁSICAS ==="
    DOMAIN=$(ask_simple "Qual o domínio do seu painel? (ex: painel.seusite.com)")
    EMAIL=$(ask_simple "Seu email (para SSL e notificações)")
    
    echo
    echo "=== CONFIGURAÇÕES DO BANCO ==="
    DB_TYPE=$(ask_simple "Tipo de banco [sqlite/mysql/postgresql]" "sqlite")
    
    if [ "$DB_TYPE" != "sqlite" ]; then
        DB_HOST=$(ask_simple "Host do banco" "localhost")
        DB_PORT=$(ask_simple "Porta do banco" "3306")
        DB_NAME=$(ask_simple "Nome do banco" "gpanel")
        DB_USER=$(ask_simple "Usuário do banco" "gpanel")
        DB_PASS=$(ask_password_simple "Senha do banco")
    fi
    
    echo
    echo "=== USUÁRIO ADMINISTRADOR ==="
    ADMIN_USERNAME=$(ask_simple "Username do admin" "admin")
    ADMIN_EMAIL=$(ask_simple "Email do admin" "$EMAIL")
    ADMIN_PASSWORD=$(ask_password_simple "Senha do admin")
    
    echo
    echo "=== CONFIGURAÇÕES OPCIONAIS ==="
    
    if ask_yes_no_simple "Configurar email SMTP?"; then
        SMTP_HOST=$(ask_simple "Host SMTP" "smtp.gmail.com")
        SMTP_PORT=$(ask_simple "Porta SMTP" "587")
        SMTP_USER=$(ask_simple "Usuário SMTP")
        SMTP_PASS=$(ask_password_simple "Senha SMTP")
        SMTP_SECURE=$(ask_yes_no_simple "Usar SSL/TLS?" "y")
    fi
    
    if ask_yes_no_simple "Configurar backup automático?"; then
        BACKUP_ENABLED="true"
        BACKUP_SCHEDULE=$(ask_simple "Horário do backup (formato cron)" "0 2 * * *")
        BACKUP_RETENTION=$(ask_simple "Dias para manter backups" "7")
    fi
}

# Gerar strings aleatórias
generate_secrets() {
    log_info "Gerando chaves de segurança..."
    
    JWT_SECRET=$(openssl rand -hex 64 2>/dev/null || cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1)
    SESSION_SECRET=$(openssl rand -hex 64 2>/dev/null || cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1)
    ENCRYPTION_KEY=$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
    
    log_success "Chaves de segurança geradas"
}

# Instalar dependências
install_dependencies() {
    log_info "Instalando dependências do sistema..."
    
    # Atualizar sistema
    apt update && apt upgrade -y
    
    # Instalar dependências básicas
    apt install -y curl wget git unzip software-properties-common apt-transport-https ca-certificates gnupg lsb-release openssl
    
    # Instalar Docker
    if ! command -v docker &> /dev/null; then
        log_info "Instalando Docker..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt update
        apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        systemctl enable docker
        systemctl start docker
        log_success "Docker instalado"
    fi
    
    # Instalar Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_info "Instalando Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        log_success "Docker Compose instalado"
    fi
    
    # Instalar Node.js
    if ! command -v node &> /dev/null; then
        log_info "Instalando Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        apt install -y nodejs
        log_success "Node.js instalado"
    fi
    
    # Instalar PM2
    if ! command -v pm2 &> /dev/null; then
        log_info "Instalando PM2..."
        npm install -g pm2
        log_success "PM2 instalado"
    fi
    
    # Instalar Nginx
    if ! command -v nginx &> /dev/null; then
        log_info "Instalando Nginx..."
        apt install -y nginx
        systemctl enable nginx
        log_success "Nginx instalado"
    fi
}

# Configurar projeto
setup_project() {
    log_info "Configurando projeto G-Panel..."
    
    # Criar diretórios
    mkdir -p /opt/gpanel/{data,logs,backups,ssl}
    mkdir -p /var/log/gpanel
    
    # Copiar arquivos do projeto
    cp -r . /opt/gpanel/
    cd /opt/gpanel
    
    # Instalar dependências do projeto
    npm install --production
    
    log_success "Projeto configurado"
}

# Criar arquivo .env
create_env_file() {
    log_info "Criando arquivo de configuração..."
    
    cat > /opt/gpanel/.env << EOF
# Configurações Básicas
NODE_ENV=production
PORT=3000
DOMAIN=$DOMAIN
BASE_URL=https://$DOMAIN

# Banco de Dados
DB_TYPE=$DB_TYPE
EOF

    if [ "$DB_TYPE" != "sqlite" ]; then
        cat >> /opt/gpanel/.env << EOF
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
EOF
    else
        cat >> /opt/gpanel/.env << EOF
DB_PATH=/opt/gpanel/data/database.sqlite
EOF
    fi

    cat >> /opt/gpanel/.env << EOF

# Segurança
JWT_SECRET=$JWT_SECRET
SESSION_SECRET=$SESSION_SECRET
ENCRYPTION_KEY=$ENCRYPTION_KEY

# Admin
ADMIN_USERNAME=$ADMIN_USERNAME
ADMIN_EMAIL=$ADMIN_EMAIL
ADMIN_PASSWORD=$ADMIN_PASSWORD
EOF

    if [ -n "$SMTP_HOST" ]; then
        cat >> /opt/gpanel/.env << EOF

# SMTP
SMTP_HOST=$SMTP_HOST
SMTP_PORT=$SMTP_PORT
SMTP_USER=$SMTP_USER
SMTP_PASS=$SMTP_PASS
SMTP_SECURE=$SMTP_SECURE
EOF
    fi

    if [ "$BACKUP_ENABLED" = "true" ]; then
        cat >> /opt/gpanel/.env << EOF

# Backup
BACKUP_ENABLED=true
BACKUP_SCHEDULE=$BACKUP_SCHEDULE
BACKUP_RETENTION=$BACKUP_RETENTION
BACKUP_PATH=/opt/gpanel/backups
EOF
    fi

    chmod 600 /opt/gpanel/.env
    log_success "Arquivo .env criado"
}

# Criar ecosystem.config.js
create_pm2_config() {
    log_info "Criando configuração do PM2..."
    
    cat > /opt/gpanel/ecosystem.config.js << 'EOF'
module.exports = {
  apps: [{
    name: 'g-panel',
    script: 'app.js',
    cwd: '/opt/gpanel',
    instances: 'max',
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    log_file: '/var/log/gpanel/combined.log',
    out_file: '/var/log/gpanel/out.log',
    error_file: '/var/log/gpanel/error.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    merge_logs: true,
    max_memory_restart: '1G',
    node_args: '--max-old-space-size=1024',
    restart_delay: 4000,
    max_restarts: 10,
    min_uptime: '10s',
    kill_timeout: 5000,
    wait_ready: true,
    listen_timeout: 10000,
    health_check_grace_period: 3000
  }]
};
EOF

    log_success "Configuração do PM2 criada"
}

# Configurar Nginx
setup_nginx() {
    log_info "Configurando Nginx..."
    
    # Remover configuração padrão
    rm -f /etc/nginx/sites-enabled/default
    
    # Criar configuração do G-Panel
    cat > /etc/nginx/sites-available/gpanel << EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    
    # SSL Configuration
    ssl_certificate /opt/gpanel/ssl/cert.pem;
    ssl_certificate_key /opt/gpanel/ssl/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security Headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Proxy to Node.js
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }
    
    # Static files
    location /static/ {
        alias /opt/gpanel/public/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

    # Habilitar site
    ln -sf /etc/nginx/sites-available/gpanel /etc/nginx/sites-enabled/
    
    # Testar configuração
    nginx -t
    
    log_success "Nginx configurado"
}

# Configurar SSL
setup_ssl() {
    log_info "Configurando SSL..."
    
    # Instalar Certbot
    apt install -y certbot python3-certbot-nginx
    
    # Gerar certificado temporário
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /opt/gpanel/ssl/key.pem \
        -out /opt/gpanel/ssl/cert.pem \
        -subj "/C=BR/ST=State/L=City/O=Organization/CN=$DOMAIN"
    
    # Reiniciar Nginx
    systemctl restart nginx
    
    log_success "SSL temporário configurado"
    log_info "Para SSL real, execute: certbot --nginx -d $DOMAIN"
}

# Inicializar banco
init_database() {
    log_info "Inicializando banco de dados..."
    
    cd /opt/gpanel
    
    # Executar migrações
    npm run migrate 2>/dev/null || echo "Migrações não encontradas"
    
    # Criar usuário admin
    npm run create-admin 2>/dev/null || echo "Script de admin não encontrado"
    
    log_success "Banco inicializado"
}

# Iniciar aplicação
start_application() {
    log_info "Iniciando aplicação..."
    
    cd /opt/gpanel
    
    # Iniciar com PM2
    pm2 start ecosystem.config.js
    pm2 save
    pm2 startup
    
    # Verificar status
    sleep 5
    pm2 status
    
    log_success "Aplicação iniciada"
}

# Verificar instalação
verify_installation() {
    log_info "Verificando instalação..."
    
    echo
    echo "=== STATUS DOS SERVIÇOS ==="
    
    # Docker
    if systemctl is-active --quiet docker; then
        log_success "Docker: Ativo"
    else
        log_error "Docker: Inativo"
    fi
    
    # Nginx
    if systemctl is-active --quiet nginx; then
        log_success "Nginx: Ativo"
    else
        log_error "Nginx: Inativo"
    fi
    
    # PM2
    if pm2 list | grep -q "g-panel"; then
        log_success "G-Panel: Ativo"
    else
        log_error "G-Panel: Inativo"
    fi
    
    echo
    echo "=== INFORMAÇÕES DE ACESSO ==="
    echo "URL: https://$DOMAIN"
    echo "Admin: $ADMIN_USERNAME"
    echo "Email: $ADMIN_EMAIL"
    echo
    echo "=== COMANDOS ÚTEIS ==="
    echo "Ver logs: pm2 logs g-panel"
    echo "Reiniciar: pm2 restart g-panel"
    echo "Status: pm2 status"
    echo "SSL real: certbot --nginx -d $DOMAIN"
    echo
}

# Função principal
main() {
    check_root
    show_banner
    
    log_info "Iniciando instalação do G-Panel..."
    echo
    
    collect_basic_info
    generate_secrets
    install_dependencies
    setup_project
    create_env_file
    create_pm2_config
    setup_nginx
    setup_ssl
    init_database
    start_application
    verify_installation
    
    log_success "Instalação concluída com sucesso!"
    echo
    log_info "Acesse seu painel em: https://$DOMAIN"
}

# Executar instalação
main "$@"