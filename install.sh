#!/bin/bash

# Script de Instalação Completa e Interativa do G-Panel
# Autor: Sistema de Deploy Enterprise
# Versão: 1.0
# Data: $(date)

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Função para log
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ [SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}❌ [ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠️  [WARNING]${NC} $1"
}

log_info() {
    echo -e "${CYAN}ℹ️  [INFO]${NC} $1"
}

log_question() {
    echo -e "${PURPLE}❓ [PERGUNTA]${NC} $1"
}

# Função para perguntar sim/não
ask_yes_no() {
    local question="$1"
    local default="${2:-n}"
    local answer
    
    while true; do
        if [ "$default" = "y" ]; then
            echo -n "${YELLOW}[?]${NC} $question [Y/n]: "
        else
            echo -n "${YELLOW}[?]${NC} $question [y/N]: "
        fi
        read -r answer </dev/tty
        
        # Se resposta vazia, usar padrão
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

# Função para perguntar input
ask_input() {
    local question="$1"
    local default="$2"
    local answer
    
    if [ -n "$default" ]; then
        echo -n "${YELLOW}[?]${NC} $question [padrão: $default]: "
    else
        echo -n "${YELLOW}[?]${NC} $question: "
    fi
    
    read -r answer </dev/tty
    
    if [ -z "$answer" ] && [ -n "$default" ]; then
        echo "$default"
    else
        echo "$answer"
    fi
}

# Função para perguntar senha
ask_password() {
    local question="$1"
    local answer
    
    echo -n "${YELLOW}[?]${NC} $question: "
    read -s answer </dev/tty
    echo
    echo "$answer"
}

# Função para gerar string aleatória
generate_random_string() {
    local length="${1:-32}"
    openssl rand -hex $length 2>/dev/null || cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w $length | head -n 1
}

# Verificar se está rodando como root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script deve ser executado como root (use sudo)"
        exit 1
    fi
}

# Banner de boas-vindas
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║                    🚀 G-PANEL INSTALLER 🚀                   ║"
    echo "║                                                              ║"
    echo "║              Instalação Completa e Automática               ║"
    echo "║                                                              ║"
    echo "║  Este script irá instalar e configurar completamente:       ║"
    echo "║  • Docker & Docker Compose                                  ║"
    echo "║  • Node.js & PM2                                            ║"
    echo "║  • Nginx (Proxy Reverso)                                    ║"
    echo "║  • SSL/TLS (Let's Encrypt)                                  ║"
    echo "║  • Configuração completa do G-Panel                        ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

# Coletar informações do usuário
collect_user_info() {
    log_info "Vamos coletar algumas informações para configurar seu painel..."
    echo
    
    # Informações básicas
    DOMAIN=$(ask_input "Qual o domínio do seu painel? (ex: painel.seusite.com)")
    EMAIL=$(ask_input "Seu email (para SSL e notificações)")
    
    # Configurações do banco
    echo
    log_info "Configurações do Banco de Dados:"
    DB_TYPE=$(ask_input "Tipo de banco [sqlite/mysql/postgresql]" "sqlite")
    
    if [ "$DB_TYPE" != "sqlite" ]; then
        DB_HOST=$(ask_input "Host do banco" "localhost")
        DB_PORT=$(ask_input "Porta do banco" "3306")
        DB_NAME=$(ask_input "Nome do banco" "gpanel")
        DB_USER=$(ask_input "Usuário do banco" "gpanel")
        DB_PASS=$(ask_password "Senha do banco")
    fi
    
    # Configurações de segurança
    echo
    log_info "Configurações de Segurança (deixe vazio para gerar automaticamente):"
    JWT_SECRET=$(ask_input "JWT Secret" "$(generate_random_string 64)")
    SESSION_SECRET=$(ask_input "Session Secret" "$(generate_random_string 64)")
    ENCRYPTION_KEY=$(ask_input "Encryption Key" "$(generate_random_string 32)")
    
    # Configurações do admin
    echo
    log_info "Configurações do Usuário Administrador:"
    ADMIN_USERNAME=$(ask_input "Username do admin" "admin")
    ADMIN_EMAIL=$(ask_input "Email do admin" "$EMAIL")
    ADMIN_PASSWORD=$(ask_password "Senha do admin")
    
    # Configurações opcionais
    echo
    log_info "Configurações Opcionais:"
    
    if ask_yes_no "Configurar email SMTP?"; then
        SMTP_HOST=$(ask_input "SMTP Host")
        SMTP_PORT=$(ask_input "SMTP Port" "587")
        SMTP_USER=$(ask_input "SMTP User")
        SMTP_PASS=$(ask_password "SMTP Password")
        SMTP_SECURE=$(ask_yes_no "SMTP Secure (TLS)?" "y")
    fi
    
    if ask_yes_no "Configurar backup automático?"; then
        BACKUP_ENABLED="true"
        BACKUP_SCHEDULE=$(ask_input "Horário do backup (cron)" "0 2 * * *")
        BACKUP_RETENTION=$(ask_input "Dias para manter backups" "30")
    fi
    
    if ask_yes_no "Habilitar SSL automático (Let's Encrypt)?"; then
        SSL_ENABLED="true"
    fi
    
    echo
    log_success "Informações coletadas! Iniciando instalação..."
    sleep 2
}

# Atualizar sistema
update_system() {
    log_info "Atualizando sistema..."
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y curl wget git unzip software-properties-common apt-transport-https ca-certificates gnupg lsb-release
    log_success "Sistema atualizado"
}

# Instalar Docker
install_docker() {
    log_info "Instalando Docker..."
    
    # Remover versões antigas
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Adicionar repositório Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Instalar Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Iniciar e habilitar Docker
    systemctl start docker
    systemctl enable docker
    
    # Instalar Docker Compose standalone
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    log_success "Docker instalado: $(docker --version)"
    log_success "Docker Compose instalado: $(docker-compose --version)"
}

# Instalar Node.js
install_nodejs() {
    log_info "Instalando Node.js..."
    
    # Instalar NodeSource repository
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
    
    # Instalar PM2
    npm install -g pm2
    
    log_success "Node.js instalado: $(node --version)"
    log_success "NPM instalado: $(npm --version)"
    log_success "PM2 instalado: $(pm2 --version)"
}

# Instalar Nginx
install_nginx() {
    log_info "Instalando Nginx..."
    
    apt-get install -y nginx
    systemctl start nginx
    systemctl enable nginx
    
    log_success "Nginx instalado e iniciado"
}

# Instalar Certbot (Let's Encrypt)
install_certbot() {
    if [ "$SSL_ENABLED" = "true" ]; then
        log_info "Instalando Certbot para SSL..."
        
        apt-get install -y certbot python3-certbot-nginx
        
        log_success "Certbot instalado"
    fi
}

# Criar usuário do sistema
create_system_user() {
    log_info "Criando usuário do sistema..."
    
    # Criar usuário gpanel se não existir
    if ! id "gpanel" &>/dev/null; then
        useradd -r -s /bin/bash -d /opt/g-panel -m gpanel
        usermod -aG docker gpanel
        log_success "Usuário 'gpanel' criado"
    else
        log_success "Usuário 'gpanel' já existe"
    fi
}

# Configurar diretórios
setup_directories() {
    log_info "Configurando diretórios..."
    
    # Criar diretórios necessários
    mkdir -p /opt/g-panel/{logs,uploads,backups,data,tmp}
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled
    mkdir -p /etc/nginx/snippets
    
    # Definir permissões
    chown -R gpanel:gpanel /opt/g-panel
    chmod 755 /opt/g-panel
    chmod 755 /opt/g-panel/{logs,uploads,backups,data,tmp}
    
    log_success "Diretórios configurados"
}

# Copiar arquivos do projeto
setup_project_files() {
    log_info "Configurando arquivos do projeto..."
    
    # Copiar todos os arquivos para /opt/g-panel
    cp -r . /opt/g-panel/
    
    # Ajustar permissões
    chown -R gpanel:gpanel /opt/g-panel
    chmod +x /opt/g-panel/scripts/*.sh
    
    # Ir para o diretório do projeto
    cd /opt/g-panel
    
    log_success "Arquivos do projeto configurados"
}

# Criar arquivo .env
create_env_file() {
    log_info "Criando arquivo de configuração (.env)..."
    
    cat > /opt/g-panel/.env << EOF
# Configurações Básicas
NODE_ENV=production
PORT=3000
APP_NAME=G-Panel
APP_URL=https://$DOMAIN
APP_VERSION=1.0.0

# Segurança
JWT_SECRET=$JWT_SECRET
SESSION_SECRET=$SESSION_SECRET
ENCRYPTION_KEY=$ENCRYPTION_KEY

# Banco de Dados
DB_TYPE=$DB_TYPE
EOF

    if [ "$DB_TYPE" != "sqlite" ]; then
        cat >> /opt/g-panel/.env << EOF
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
EOF
    else
        cat >> /opt/g-panel/.env << EOF
DB_PATH=./data/database.sqlite
EOF
    fi

    # Configurações de email
    if [ -n "$SMTP_HOST" ]; then
        cat >> /opt/g-panel/.env << EOF

# Email/SMTP
SMTP_HOST=$SMTP_HOST
SMTP_PORT=$SMTP_PORT
SMTP_USER=$SMTP_USER
SMTP_PASS=$SMTP_PASS
SMTP_SECURE=$SMTP_SECURE
MAIL_FROM=$EMAIL
EOF
    fi

    # Configurações de backup
    if [ "$BACKUP_ENABLED" = "true" ]; then
        cat >> /opt/g-panel/.env << EOF

# Backup
BACKUP_ENABLED=true
BACKUP_SCHEDULE=$BACKUP_SCHEDULE
BACKUP_RETENTION_DAYS=$BACKUP_RETENTION
BACKUP_PATH=/opt/g-panel/backups
EOF
    fi

    # Outras configurações
    cat >> /opt/g-panel/.env << EOF

# Logs
LOG_LEVEL=info
LOG_PATH=./logs

# Rate Limiting
RATE_LIMIT_ENABLED=true
RATE_LIMIT_WINDOW=15
RATE_LIMIT_MAX=100

# CORS
CORS_ORIGIN=$DOMAIN

# Uploads
UPLOAD_MAX_SIZE=10485760
UPLOAD_PATH=./uploads

# Cache
CACHE_TYPE=memory
CACHE_TTL=3600

# Monitoramento
METRICS_ENABLED=true
HEALTH_CHECK_ENABLED=true

# Desenvolvimento
DEBUG=false
VERBOSE_LOGGING=false
EOF

    # Ajustar permissões
    chown gpanel:gpanel /opt/g-panel/.env
    chmod 600 /opt/g-panel/.env
    
    log_success "Arquivo .env criado"
}

# Criar ecosystem.config.js
create_pm2_config() {
    log_info "Criando configuração do PM2..."
    
    cat > /opt/g-panel/ecosystem.config.js << 'EOF'
module.exports = {
  apps: [{
    name: 'g-panel',
    script: 'app.js',
    instances: 'max',
    exec_mode: 'cluster',
    cwd: '/opt/g-panel',
    user: 'gpanel',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    env_production: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    // Configurações de monitoramento
    watch: false,
    ignore_watch: ['node_modules', 'logs', 'uploads', 'backups'],
    
    // Configurações de restart
    max_memory_restart: '1G',
    restart_delay: 4000,
    max_restarts: 10,
    min_uptime: '10s',
    
    // Logs
    log_file: '/opt/g-panel/logs/combined.log',
    out_file: '/opt/g-panel/logs/out.log',
    error_file: '/opt/g-panel/logs/error.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    
    // Configurações avançadas
    kill_timeout: 5000,
    listen_timeout: 8000,
    
    // Health check
    health_check_grace_period: 3000,
    
    // Configurações de cluster
    instance_var: 'INSTANCE_ID',
    
    // Configurações de ambiente
    source_map_support: true,
    
    // Configurações de cron (opcional)
    cron_restart: '0 2 * * *', // Restart diário às 2h da manhã
    
    // Configurações de merge logs
    merge_logs: true,
    
    // Configurações de autorestart
    autorestart: true,
    
    // Configurações de node args
    node_args: '--max-old-space-size=1024'
  }]
};
EOF

    chown gpanel:gpanel /opt/g-panel/ecosystem.config.js
    log_success "Configuração do PM2 criada"
}

# Configurar Nginx
setup_nginx() {
    log_info "Configurando Nginx..."
    
    # Copiar configurações
    if [ -f "/opt/g-panel/nginx/g-panel.conf" ]; then
        cp /opt/g-panel/nginx/g-panel.conf /etc/nginx/sites-available/
        
        # Substituir domínio na configuração
        sed -i "s/your-domain.com/$DOMAIN/g" /etc/nginx/sites-available/g-panel.conf
    fi
    
    if [ -f "/opt/g-panel/nginx/snippets/g-panel-common.conf" ]; then
        cp /opt/g-panel/nginx/snippets/g-panel-common.conf /etc/nginx/snippets/
    fi
    
    # Habilitar site
    ln -sf /etc/nginx/sites-available/g-panel.conf /etc/nginx/sites-enabled/
    
    # Remover site padrão
    rm -f /etc/nginx/sites-enabled/default
    
    # Testar configuração
    if nginx -t; then
        systemctl reload nginx
        log_success "Nginx configurado"
    else
        log_error "Erro na configuração do Nginx"
        return 1
    fi
}

# Instalar dependências do projeto
install_project_dependencies() {
    log_info "Instalando dependências do projeto..."
    
    cd /opt/g-panel
    
    # Instalar dependências como usuário gpanel
    sudo -u gpanel npm install --production
    
    log_success "Dependências instaladas"
}

# Inicializar banco de dados
init_database() {
    log_info "Inicializando banco de dados..."
    
    cd /opt/g-panel
    
    # Executar seed como usuário gpanel
    sudo -u gpanel npm run seed 2>/dev/null || {
        log_warning "Comando 'npm run seed' não encontrado, pulando..."
    }
    
    log_success "Banco de dados inicializado"
}

# Criar usuário administrador
create_admin_user() {
    log_info "Criando usuário administrador..."
    
    cd /opt/g-panel
    
    # Criar script temporário para criar usuário
    cat > /tmp/create_admin.js << EOF
const { createUser } = require('./src/utils/userManager');

async function createAdmin() {
    try {
        await createUser({
            username: '$ADMIN_USERNAME',
            email: '$ADMIN_EMAIL',
            password: '$ADMIN_PASSWORD',
            role: 'admin'
        });
        console.log('Usuário administrador criado com sucesso!');
    } catch (error) {
        console.error('Erro ao criar usuário:', error.message);
    }
    process.exit(0);
}

createAdmin();
EOF

    # Executar como usuário gpanel
    sudo -u gpanel node /tmp/create_admin.js 2>/dev/null || {
        log_warning "Não foi possível criar usuário automaticamente"
        log_info "Você pode criar manualmente após a instalação com: npm run createUser"
    }
    
    # Limpar arquivo temporário
    rm -f /tmp/create_admin.js
    
    log_success "Usuário administrador configurado"
}

# Configurar SSL
setup_ssl() {
    if [ "$SSL_ENABLED" = "true" ]; then
        log_info "Configurando SSL com Let's Encrypt..."
        
        # Obter certificado SSL
        certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos --non-interactive --redirect
        
        if [ $? -eq 0 ]; then
            log_success "SSL configurado para $DOMAIN"
        else
            log_warning "Falha ao configurar SSL. Você pode configurar manualmente depois."
        fi
    fi
}

# Iniciar aplicação
start_application() {
    log_info "Iniciando aplicação..."
    
    cd /opt/g-panel
    
    # Iniciar com PM2 como usuário gpanel
    sudo -u gpanel pm2 start ecosystem.config.js
    sudo -u gpanel pm2 save
    
    # Configurar PM2 para iniciar no boot
    pm2 startup systemd -u gpanel --hp /opt/g-panel
    
    log_success "Aplicação iniciada com PM2"
}

# Configurar backup automático
setup_backup_cron() {
    if [ "$BACKUP_ENABLED" = "true" ]; then
        log_info "Configurando backup automático..."
        
        # Adicionar cron job para backup
        (crontab -u gpanel -l 2>/dev/null; echo "$BACKUP_SCHEDULE /opt/g-panel/scripts/backup.sh >/dev/null 2>&1") | crontab -u gpanel -
        
        log_success "Backup automático configurado"
    fi
}

# Verificar status dos serviços
check_services() {
    log_info "Verificando status dos serviços..."
    
    # Verificar Docker
    if systemctl is-active --quiet docker; then
        log_success "Docker: ✅ Rodando"
    else
        log_error "Docker: ❌ Parado"
    fi
    
    # Verificar Nginx
    if systemctl is-active --quiet nginx; then
        log_success "Nginx: ✅ Rodando"
    else
        log_error "Nginx: ❌ Parado"
    fi
    
    # Verificar PM2
    if sudo -u gpanel pm2 list | grep -q "g-panel"; then
        log_success "G-Panel: ✅ Rodando"
    else
        log_error "G-Panel: ❌ Parado"
    fi
}

# Mostrar informações finais
show_final_info() {
    clear
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║                  🎉 INSTALAÇÃO CONCLUÍDA! 🎉                 ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
    
    log_success "G-Panel instalado e configurado com sucesso!"
    echo
    
    log_info "📋 Informações do Sistema:"
    echo "   • Domínio: $DOMAIN"
    echo "   • Usuário Admin: $ADMIN_USERNAME"
    echo "   • Email Admin: $ADMIN_EMAIL"
    echo "   • Diretório: /opt/g-panel"
    echo
    
    log_info "🔗 URLs de Acesso:"
    if [ "$SSL_ENABLED" = "true" ]; then
        echo "   • Painel: https://$DOMAIN"
    else
        echo "   • Painel: http://$DOMAIN"
    fi
    echo
    
    log_info "🛠️  Comandos Úteis:"
    echo "   • Ver logs: sudo -u gpanel pm2 logs"
    echo "   • Status: sudo -u gpanel pm2 status"
    echo "   • Restart: sudo -u gpanel pm2 restart g-panel"
    echo "   • Backup: /opt/g-panel/scripts/backup.sh"
    echo "   • Deploy: /opt/g-panel/scripts/deploy.sh"
    echo
    
    log_info "📁 Arquivos Importantes:"
    echo "   • Configuração: /opt/g-panel/.env"
    echo "   • Logs: /opt/g-panel/logs/"
    echo "   • Backups: /opt/g-panel/backups/"
    echo "   • Nginx: /etc/nginx/sites-available/g-panel.conf"
    echo
    
    if [ "$SSL_ENABLED" != "true" ]; then
        log_warning "⚠️  SSL não foi configurado. Para configurar depois:"
        echo "   sudo certbot --nginx -d $DOMAIN"
        echo
    fi
    
    log_success "✨ Seu G-Panel está pronto para uso!"
}

# Função principal
main() {
    # Verificar root
    check_root
    
    # Mostrar banner
    show_banner
    
    # Coletar informações
    collect_user_info
    
    # Executar instalação
    log_info "🚀 Iniciando instalação completa..."
    
    update_system
    install_docker
    install_nodejs
    install_nginx
    install_certbot
    create_system_user
    setup_directories
    setup_project_files
    create_env_file
    create_pm2_config
    setup_nginx
    install_project_dependencies
    init_database
    create_admin_user
    setup_ssl
    start_application
    setup_backup_cron
    
    # Verificar e mostrar resultado
    check_services
    show_final_info
}

# Executar instalação
main "$@"