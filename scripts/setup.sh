#!/bin/bash

# G-Panel Enterprise Setup Script
# Configuração completa para produção com Docker, PM2, backup e rollback

set -e  # Exit on any error

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurações
PANEL_DIR="/opt/g-panel"
PANEL_USER="g-panel"
GIT_REPO="https://github.com/seu-usuario/g-panel.git"  # Altere para seu repo
DOMAIN="beta.gratian.pro"  # Altere para seu domínio

# Funções auxiliares
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script deve ser executado como root (sudo)"
        exit 1
    fi
}

check_system() {
    log_info "Verificando sistema..."
    
    # Verificar Ubuntu/Debian
    if ! command -v apt &> /dev/null; then
        log_error "Este script é para sistemas Ubuntu/Debian"
        exit 1
    fi
    
    # Verificar conectividade
    if ! ping -c 1 google.com &> /dev/null; then
        log_error "Sem conexão com a internet"
        exit 1
    fi
    
    log_success "Sistema verificado"
}

install_dependencies() {
    log_info "Instalando dependências do sistema..."
    
    # Atualizar sistema
    apt update && apt upgrade -y
    
    # Instalar dependências básicas
    apt install -y \
        curl \
        wget \
        git \
        unzip \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        ufw \
        fail2ban \
        htop \
        nano \
        sqlite3
    
    log_success "Dependências instaladas"
}

install_docker() {
    log_info "Instalando Docker..."
    
    # Verificar se Docker está instalado
    if ! command -v docker &> /dev/null; then
        log_warning "Docker não encontrado. Instalando..."
        
        # Remover versões antigas
        apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
        
        # Atualizar repositórios
        apt-get update
        
        # Instalar dependências
        apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
        
        # Adicionar chave GPG do Docker
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
        # Adicionar repositório do Docker
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Instalar Docker
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
        log_success "Docker instalado com sucesso"
    else
        log_success "Docker já está instalado"
    fi
    
    # Iniciar e habilitar Docker
    systemctl start docker
    systemctl enable docker
    
    # Verificar se Docker está rodando
    if ! systemctl is-active --quiet docker; then
        log_error "Falha ao iniciar Docker"
        exit 1
    fi
    
    # Adicionar usuário ao grupo docker
    usermod -aG docker $PANEL_USER 2>/dev/null || true
    
    log_success "Docker configurado"
 }

# Função para instalar Docker Compose
install_docker_compose() {
    log_info "Verificando Docker Compose..."
    
    if ! command -v docker-compose &> /dev/null; then
        log_warning "Docker Compose não encontrado. Instalando..."
        
        # Baixar Docker Compose
        DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
        curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        
        # Dar permissão de execução
        chmod +x /usr/local/bin/docker-compose
        
        # Criar link simbólico
        ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
        
        log_success "Docker Compose instalado: $(docker-compose --version)"
    else
        log_success "Docker Compose já está instalado: $(docker-compose --version)"
    fi
}

install_nodejs() {
    log_info "Instalando Node.js e PM2..."
    
    # Instalar Node.js 18
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
    
    # Instalar PM2 globalmente
    npm install -g pm2
    
    # Configurar PM2 para iniciar no boot
    pm2 startup systemd -u $PANEL_USER --hp /home/$PANEL_USER
    
    log_success "Node.js e PM2 instalados"
}

install_nginx() {
    log_info "Instalando e configurando Nginx..."
    
    apt install -y nginx
    
    # Iniciar e habilitar Nginx
    systemctl start nginx
    systemctl enable nginx
    
    log_success "Nginx instalado"
}

create_user() {
    log_info "Criando usuário do sistema..."
    
    # Criar usuário se não existir
    if ! id "$PANEL_USER" &>/dev/null; then
        useradd -m -s /bin/bash $PANEL_USER
        usermod -aG sudo $PANEL_USER
        log_success "Usuário $PANEL_USER criado"
    else
        log_warning "Usuário $PANEL_USER já existe"
    fi
}

setup_directories() {
    log_info "Criando estrutura de diretórios..."
    
    # Criar diretórios principais
    mkdir -p $PANEL_DIR/{data,logs,backups,nginx/{conf.d,logs},ssl,scripts}
    
    # Definir permissões
    chown -R $PANEL_USER:$PANEL_USER $PANEL_DIR
    chmod -R 755 $PANEL_DIR
    
    log_success "Diretórios criados"
}

clone_repository() {
    log_info "Clonando repositório..."
    
    # Clonar ou atualizar repositório
    if [ -d "$PANEL_DIR/app" ]; then
        log_warning "Diretório da aplicação já existe, fazendo backup..."
        mv $PANEL_DIR/app $PANEL_DIR/app.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # Clonar repositório
    git clone $GIT_REPO $PANEL_DIR/app
    chown -R $PANEL_USER:$PANEL_USER $PANEL_DIR/app
    
    log_success "Repositório clonado"
}

setup_application() {
    log_info "Configurando aplicação..."
    
    cd $PANEL_DIR/app
    
    # Instalar dependências como usuário do painel
    sudo -u $PANEL_USER npm install --production
    
    # Executar seed do banco
    log_info "Executando seed do banco de dados..."
    sudo -u $PANEL_USER npm run seed
    
    # Criar usuário admin
    log_info "Criando usuário administrador..."
    sudo -u $PANEL_USER npm run createUser
    
    log_success "Aplicação configurada"
}

setup_nginx_config() {
    log_info "Configurando Nginx..."
    
    # Criar configuração do Nginx
    cat > $PANEL_DIR/nginx/conf.d/g-panel.conf << EOF
upstream g_panel_backend {
    server 127.0.0.1:3000;
    keepalive 32;
}

server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;
    
    # SSL Configuration (configure depois)
    # ssl_certificate /etc/nginx/ssl/cert.pem;
    # ssl_certificate_key /etc/nginx/ssl/key.pem;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=panel:10m rate=10r/s;
    limit_req zone=panel burst=20 nodelay;
    
    # Main location
    location / {
        proxy_pass http://g_panel_backend;
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
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)\$ {
        proxy_pass http://g_panel_backend;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Health check
    location /health {
        proxy_pass http://g_panel_backend/health;
        access_log off;
    }
}
EOF
    
    # Criar link simbólico
    ln -sf $PANEL_DIR/nginx/conf.d/g-panel.conf /etc/nginx/sites-available/g-panel
    ln -sf /etc/nginx/sites-available/g-panel /etc/nginx/sites-enabled/g-panel
    
    # Remover configuração padrão
    rm -f /etc/nginx/sites-enabled/default
    
    # Testar configuração
    nginx -t
    
    log_success "Nginx configurado"
}

setup_firewall() {
    log_info "Configurando firewall..."
    
    # Configurar UFW
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    
    # Permitir SSH, HTTP, HTTPS
    ufw allow ssh
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Ativar firewall
    ufw --force enable
    
    log_success "Firewall configurado"
}

setup_pm2() {
    log_info "Configurando PM2..."
    
    cd $PANEL_DIR/app
    
    # Criar arquivo de configuração do PM2
    cat > ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: 'g-panel',
    script: 'index.js',
    instances: 1,
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: '$PANEL_DIR/logs/error.log',
    out_file: '$PANEL_DIR/logs/out.log',
    log_file: '$PANEL_DIR/logs/combined.log',
    time: true,
    max_memory_restart: '500M',
    node_args: '--max-old-space-size=512',
    watch: false,
    ignore_watch: ['node_modules', 'logs', 'data'],
    restart_delay: 4000,
    max_restarts: 10,
    min_uptime: '10s'
  }]
};
EOF
    
    chown $PANEL_USER:$PANEL_USER ecosystem.config.js
    
    # Iniciar aplicação com PM2
    sudo -u $PANEL_USER pm2 start ecosystem.config.js
    sudo -u $PANEL_USER pm2 save
    
    log_success "PM2 configurado"
}

setup_ssl() {
    log_info "Configurando SSL com Let's Encrypt..."
    
    # Instalar Certbot
    apt install -y certbot python3-certbot-nginx
    
    # Obter certificado (apenas se domínio estiver configurado)
    if [[ "$DOMAIN" != "beta.gratian.pro" ]]; then
        certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN
        
        # Configurar renovação automática
        echo "0 12 * * * /usr/bin/certbot renew --quiet" | crontab -
        
        log_success "SSL configurado"
    else
        log_warning "Configure seu domínio na variável DOMAIN para obter SSL"
    fi
}

setup_monitoring() {
    log_info "Configurando monitoramento..."
    
    # Instalar PM2 monitoring
    sudo -u $PANEL_USER pm2 install pm2-logrotate
    
    # Configurar logrotate
    cat > /etc/logrotate.d/g-panel << EOF
$PANEL_DIR/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 $PANEL_USER $PANEL_USER
    postrotate
        sudo -u $PANEL_USER pm2 reloadLogs
    endscript
}
EOF
    
    log_success "Monitoramento configurado"
}

setup_backup_cron() {
    log_info "Configurando backup automático..."
    
    # Criar cron job para backup diário
    echo "0 2 * * * $PANEL_DIR/scripts/backup.sh" | sudo -u $PANEL_USER crontab -
    
    log_success "Backup automático configurado"
}

finalize_setup() {
    log_info "Finalizando configuração..."
    
    # Reiniciar serviços
    systemctl restart nginx
    sudo -u $PANEL_USER pm2 restart all
    
    # Mostrar status
    echo
    log_success "=== INSTALAÇÃO CONCLUÍDA ==="
    echo
    log_info "Painel G-Panel instalado com sucesso!"
    echo
    log_info "Informações importantes:"
    echo "  • Diretório: $PANEL_DIR"
    echo "  • Usuário: $PANEL_USER"
    echo "  • Logs: $PANEL_DIR/logs/"
    echo "  • Backups: $PANEL_DIR/backups/"
    echo
    log_info "Comandos úteis:"
    echo "  • Ver status: sudo -u $PANEL_USER pm2 status"
    echo "  • Ver logs: sudo -u $PANEL_USER pm2 logs"
    echo "  • Restart: sudo -u $PANEL_USER pm2 restart g-panel"
    echo "  • Deploy: $PANEL_DIR/scripts/deploy.sh"
    echo "  • Backup: $PANEL_DIR/scripts/backup.sh"
    echo "  • Rollback: $PANEL_DIR/scripts/rollback.sh"
    echo
    log_info "Acesse o painel em: http://$(curl -s ifconfig.me):3000"
    echo
}

# Função principal
main() {
    log_info "Iniciando instalação do G-Panel Enterprise..."
    
    check_root
    check_system
    install_dependencies
    create_user
    install_docker
    install_nodejs
    install_nginx
    setup_directories
    clone_repository
    setup_application
    setup_nginx_config
    setup_firewall
    setup_pm2
    setup_ssl
    setup_monitoring
    setup_backup_cron
    finalize_setup
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi