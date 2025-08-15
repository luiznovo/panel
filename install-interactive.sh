#!/bin/bash

# Script de Instalação Interativo do G-Panel
# Versão com captura de input robusta

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logs
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Função para capturar input de forma robusta
get_input() {
    local prompt="$1"
    local default="$2"
    local result
    
    if [ -n "$default" ]; then
        printf "${YELLOW}[?]${NC} %s [padrão: %s]: " "$prompt" "$default"
    else
        printf "${YELLOW}[?]${NC} %s: " "$prompt"
    fi
    
    # Força o flush do buffer
    exec 3<&0
    read -u 3 result
    
    if [ -z "$result" ] && [ -n "$default" ]; then
        echo "$default"
    else
        echo "$result"
    fi
}

# Função para capturar senha
get_password() {
    local prompt="$1"
    local result
    
    printf "${YELLOW}[?]${NC} %s: " "$prompt"
    
    # Desabilita echo e captura senha
    stty -echo
    exec 3<&0
    read -u 3 result
    stty echo
    echo
    
    echo "$result"
}

# Função para sim/não
get_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local result
    
    while true; do
        if [ "$default" = "y" ]; then
            printf "${YELLOW}[?]${NC} %s [Y/n]: " "$prompt"
        else
            printf "${YELLOW}[?]${NC} %s [y/N]: " "$prompt"
        fi
        
        exec 3<&0
        read -u 3 result
        
        if [ -z "$result" ]; then
            result="$default"
        fi
        
        case "$result" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Por favor, responda sim (y) ou não (n)." ;;
        esac
    done
}

# Verificar root
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
    echo "║                  Versão Interativa v3.0                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

# Teste de input
test_input() {
    log_info "Testando captura de input..."
    echo
    
    local test_result
    test_result=$(get_input "Digite 'teste' para continuar" "teste")
    
    if [ "$test_result" = "teste" ]; then
        log_success "Captura de input funcionando!"
        echo
        return 0
    else
        log_error "Problema na captura de input. Resultado: '$test_result'"
        echo
        return 1
    fi
}

# Coletar informações
collect_info() {
    log_info "Coletando informações para configuração..."
    echo
    
    echo "=== INFORMAÇÕES BÁSICAS ==="
    DOMAIN=$(get_input "Domínio do painel (ex: painel.seusite.com)")
    echo "Domínio definido: $DOMAIN"
    echo
    
    EMAIL=$(get_input "Seu email para SSL e notificações")
    echo "Email definido: $EMAIL"
    echo
    
    echo "=== CONFIGURAÇÕES DO BANCO ==="
    DB_TYPE=$(get_input "Tipo de banco [sqlite/mysql/postgresql]" "sqlite")
    echo "Banco definido: $DB_TYPE"
    echo
    
    if [ "$DB_TYPE" != "sqlite" ]; then
        DB_HOST=$(get_input "Host do banco" "localhost")
        DB_PORT=$(get_input "Porta do banco" "3306")
        DB_NAME=$(get_input "Nome do banco" "gpanel")
        DB_USER=$(get_input "Usuário do banco" "gpanel")
        DB_PASS=$(get_password "Senha do banco")
        echo "Configurações do banco coletadas."
        echo
    fi
    
    echo "=== USUÁRIO ADMINISTRADOR ==="
    ADMIN_USERNAME=$(get_input "Username do admin" "admin")
    echo "Username admin: $ADMIN_USERNAME"
    
    ADMIN_EMAIL=$(get_input "Email do admin" "$EMAIL")
    echo "Email admin: $ADMIN_EMAIL"
    
    ADMIN_PASSWORD=$(get_password "Senha do admin")
    echo "Senha do admin definida."
    echo
    
    echo "=== CONFIGURAÇÕES OPCIONAIS ==="
    
    if get_yes_no "Configurar email SMTP?"; then
        SMTP_HOST=$(get_input "Host SMTP" "smtp.gmail.com")
        SMTP_PORT=$(get_input "Porta SMTP" "587")
        SMTP_USER=$(get_input "Usuário SMTP")
        SMTP_PASS=$(get_password "Senha SMTP")
        
        if get_yes_no "Usar SSL/TLS?" "y"; then
            SMTP_SECURE="true"
        else
            SMTP_SECURE="false"
        fi
        
        log_success "SMTP configurado"
    else
        log_info "SMTP não será configurado"
    fi
    echo
    
    if get_yes_no "Configurar backup automático?"; then
        BACKUP_ENABLED="true"
        BACKUP_SCHEDULE=$(get_input "Horário do backup (formato cron)" "0 2 * * *")
        BACKUP_RETENTION=$(get_input "Dias para manter backups" "7")
        log_success "Backup automático configurado"
    else
        BACKUP_ENABLED="false"
        log_info "Backup automático não será configurado"
    fi
    echo
}

# Confirmar configurações
confirm_settings() {
    echo "=== RESUMO DAS CONFIGURAÇÕES ==="
    echo "Domínio: $DOMAIN"
    echo "Email: $EMAIL"
    echo "Banco: $DB_TYPE"
    echo "Admin: $ADMIN_USERNAME ($ADMIN_EMAIL)"
    
    if [ -n "$SMTP_HOST" ]; then
        echo "SMTP: $SMTP_HOST:$SMTP_PORT"
    fi
    
    if [ "$BACKUP_ENABLED" = "true" ]; then
        echo "Backup: Habilitado ($BACKUP_SCHEDULE)"
    fi
    
    echo
    
    if get_yes_no "Confirma as configurações acima?" "y"; then
        return 0
    else
        log_info "Configuração cancelada pelo usuário"
        exit 0
    fi
}

# Gerar secrets
generate_secrets() {
    log_info "Gerando chaves de segurança..."
    
    JWT_SECRET=$(openssl rand -hex 64 2>/dev/null || head -c 64 /dev/urandom | base64 | tr -d '\n')
    SESSION_SECRET=$(openssl rand -hex 64 2>/dev/null || head -c 64 /dev/urandom | base64 | tr -d '\n')
    ENCRYPTION_KEY=$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | base64 | tr -d '\n')
    
    log_success "Chaves geradas"
}

# Instalar dependências básicas
install_basic_deps() {
    log_info "Instalando dependências básicas..."
    
    apt update
    apt install -y curl wget git unzip software-properties-common apt-transport-https ca-certificates gnupg lsb-release openssl
    
    log_success "Dependências básicas instaladas"
}

# Instalar Docker
install_docker() {
    if command -v docker &> /dev/null; then
        log_info "Docker já está instalado"
        return 0
    fi
    
    log_info "Instalando Docker..."
    
    # Adicionar repositório Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Instalar Docker
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Iniciar Docker
    systemctl enable docker
    systemctl start docker
    
    log_success "Docker instalado"
}

# Instalar Docker Compose
install_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        log_info "Docker Compose já está instalado"
        return 0
    fi
    
    log_info "Instalando Docker Compose..."
    
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    log_success "Docker Compose instalado"
}

# Instalar Node.js
install_nodejs() {
    if command -v node &> /dev/null; then
        log_info "Node.js já está instalado"
        return 0
    fi
    
    log_info "Instalando Node.js..."
    
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
    
    log_success "Node.js instalado"
}

# Instalar PM2
install_pm2() {
    if command -v pm2 &> /dev/null; then
        log_info "PM2 já está instalado"
        return 0
    fi
    
    log_info "Instalando PM2..."
    
    npm install -g pm2
    
    log_success "PM2 instalado"
}

# Instalar Nginx
install_nginx() {
    if command -v nginx &> /dev/null; then
        log_info "Nginx já está instalado"
        return 0
    fi
    
    log_info "Instalando Nginx..."
    
    apt install -y nginx
    systemctl enable nginx
    
    log_success "Nginx instalado"
}

# Configurar projeto
setup_project() {
    log_info "Configurando projeto..."
    
    # Criar diretórios
    mkdir -p /opt/gpanel/{data,logs,backups,ssl}
    mkdir -p /var/log/gpanel
    
    # Copiar arquivos
    cp -r . /opt/gpanel/
    cd /opt/gpanel
    
    # Instalar dependências
    if [ -f "package.json" ]; then
        npm install --production
    fi
    
    log_success "Projeto configurado"
}

# Criar .env
create_env() {
    log_info "Criando arquivo .env..."
    
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
    log_info "Criando configuração PM2..."
    
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
    restart_delay: 4000,
    max_restarts: 10,
    min_uptime: '10s'
  }]
};
EOF

    log_success "Configuração PM2 criada"
}

# Configurar Nginx
setup_nginx() {
    log_info "Configurando Nginx..."
    
    # Remover default
    rm -f /etc/nginx/sites-enabled/default
    
    # Criar configuração
    cat > /etc/nginx/sites-available/gpanel << EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    
    ssl_certificate /opt/gpanel/ssl/cert.pem;
    ssl_certificate_key /opt/gpanel/ssl/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    
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
    }
}
EOF

    # Habilitar site
    ln -sf /etc/nginx/sites-available/gpanel /etc/nginx/sites-enabled/
    
    log_success "Nginx configurado"
}

# Configurar SSL temporário
setup_ssl() {
    log_info "Configurando SSL temporário..."
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /opt/gpanel/ssl/key.pem \
        -out /opt/gpanel/ssl/cert.pem \
        -subj "/C=BR/ST=State/L=City/O=Organization/CN=$DOMAIN"
    
    log_success "SSL temporário criado"
}

# Iniciar serviços
start_services() {
    log_info "Iniciando serviços..."
    
    # Testar Nginx
    nginx -t
    systemctl restart nginx
    
    # Iniciar aplicação
    cd /opt/gpanel
    pm2 start ecosystem.config.js
    pm2 save
    pm2 startup
    
    log_success "Serviços iniciados"
}

# Verificar instalação
verify_installation() {
    log_info "Verificando instalação..."
    
    echo
    echo "=== STATUS ==="
    
    if systemctl is-active --quiet nginx; then
        log_success "Nginx: Ativo"
    else
        log_error "Nginx: Inativo"
    fi
    
    if pm2 list | grep -q "g-panel"; then
        log_success "G-Panel: Ativo"
    else
        log_error "G-Panel: Inativo"
    fi
    
    echo
    echo "=== ACESSO ==="
    echo "URL: https://$DOMAIN"
    echo "Admin: $ADMIN_USERNAME"
    echo "Email: $ADMIN_EMAIL"
    echo
    echo "=== COMANDOS ==="
    echo "Logs: pm2 logs g-panel"
    echo "Status: pm2 status"
    echo "SSL real: certbot --nginx -d $DOMAIN"
    echo
}

# Função principal
main() {
    check_root
    show_banner
    
    # Teste de input primeiro
    if ! test_input; then
        log_error "Falha no teste de input. Verifique o terminal."
        exit 1
    fi
    
    # Coletar informações
    collect_info
    
    # Confirmar
    confirm_settings
    
    # Executar instalação
    log_info "Iniciando instalação..."
    
    generate_secrets
    install_basic_deps
    install_docker
    install_docker_compose
    install_nodejs
    install_pm2
    install_nginx
    setup_project
    create_env
    create_pm2_config
    setup_nginx
    setup_ssl
    start_services
    verify_installation
    
    log_success "Instalação concluída!"
    log_info "Acesse: https://$DOMAIN"
}

# Executar
main "$@"