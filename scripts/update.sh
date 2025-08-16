#!/bin/bash

# =============================================================================
# G-PANEL - SCRIPT DE ATUALIZAÇÃO AUTOMÁTICA
# =============================================================================
# Este script automatiza o processo de atualização do G-Panel
# Uso: ./scripts/update.sh [branch]
# =============================================================================

set -e

# Configurações
APP_DIR="/opt/gpanel"
BACKUP_DIR="/opt/gpanel/backups"
LOG_FILE="/opt/gpanel/logs/update.log"
APP_NAME="gpanel"
BRANCH="${1:-main}"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log "INFO: $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log "SUCCESS: $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log "WARNING: $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log "ERROR: $1"
    exit 1
}

# Verificar se está rodando como root ou com sudo
check_permissions() {
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        error "Este script precisa ser executado com privilégios de root ou sudo"
    fi
}

# Verificar se o diretório da aplicação existe
check_app_directory() {
    if [[ ! -d "$APP_DIR" ]]; then
        error "Diretório da aplicação não encontrado: $APP_DIR"
    fi
}

# Verificar se o PM2 está instalado
check_pm2() {
    if ! command -v pm2 &> /dev/null; then
        error "PM2 não está instalado. Instale com: npm install -g pm2"
    fi
}

# Verificar se a aplicação está rodando
check_app_running() {
    if ! pm2 describe "$APP_NAME" &> /dev/null; then
        warning "Aplicação $APP_NAME não está rodando no PM2"
        return 1
    fi
    return 0
}

# Criar backup antes da atualização
create_backup() {
    info "Criando backup antes da atualização..."
    
    local backup_name="backup_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    mkdir -p "$backup_path"
    
    # Backup do código
    cp -r "$APP_DIR"/* "$backup_path/" 2>/dev/null || true
    
    # Backup do banco de dados (se SQLite)
    if [[ -f "$APP_DIR/data/database.sqlite" ]]; then
        cp "$APP_DIR/data/database.sqlite" "$backup_path/database.sqlite"
    fi
    
    # Backup das configurações
    if [[ -f "$APP_DIR/.env" ]]; then
        cp "$APP_DIR/.env" "$backup_path/.env"
    fi
    
    # Compactar backup
    cd "$BACKUP_DIR"
    tar -czf "${backup_name}.tar.gz" "$backup_name"
    rm -rf "$backup_name"
    
    success "Backup criado: $BACKUP_DIR/${backup_name}.tar.gz"
    echo "$BACKUP_DIR/${backup_name}.tar.gz" > "$APP_DIR/.last_backup"
}

# Atualizar código do repositório
update_code() {
    info "Atualizando código do repositório..."
    
    cd "$APP_DIR"
    
    # Verificar se há mudanças locais
    if ! git diff --quiet; then
        warning "Há mudanças locais não commitadas. Fazendo stash..."
        git stash push -m "Auto-stash before update $(date)"
    fi
    
    # Fazer pull das mudanças
    git fetch origin
    git checkout "$BRANCH"
    git pull origin "$BRANCH"
    
    success "Código atualizado para a branch $BRANCH"
}

# Instalar/atualizar dependências
update_dependencies() {
    info "Atualizando dependências..."
    
    cd "$APP_DIR"
    
    # Limpar cache do npm
    npm cache clean --force
    
    # Instalar dependências
    npm ci --production
    
    success "Dependências atualizadas"
}

# Executar migrações do banco de dados
run_migrations() {
    info "Executando migrações do banco de dados..."
    
    cd "$APP_DIR"
    
    if [[ -f "package.json" ]] && npm run | grep -q "migrate"; then
        npm run migrate
        success "Migrações executadas"
    else
        warning "Script de migração não encontrado"
    fi
}

# Reiniciar aplicação
restart_app() {
    info "Reiniciando aplicação..."
    
    if check_app_running; then
        pm2 restart "$APP_NAME"
    else
        pm2 start ecosystem.config.js
    fi
    
    # Aguardar a aplicação inicializar
    sleep 5
    
    # Verificar se a aplicação está rodando
    if pm2 describe "$APP_NAME" | grep -q "online"; then
        success "Aplicação reiniciada com sucesso"
    else
        error "Falha ao reiniciar a aplicação"
    fi
}

# Verificar saúde da aplicação
health_check() {
    info "Verificando saúde da aplicação..."
    
    local max_attempts=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -f -s http://localhost:3000/health &> /dev/null || 
           curl -f -s http://localhost:3000 &> /dev/null; then
            success "Aplicação está respondendo corretamente"
            return 0
        fi
        
        warning "Tentativa $attempt/$max_attempts falhou. Aguardando..."
        sleep 3
        ((attempt++))
    done
    
    error "Aplicação não está respondendo após $max_attempts tentativas"
}

# Rollback em caso de falha
rollback() {
    error "Atualização falhou. Iniciando rollback..."
    
    if [[ -f "$APP_DIR/.last_backup" ]]; then
        local backup_file=$(cat "$APP_DIR/.last_backup")
        
        if [[ -f "$backup_file" ]]; then
            info "Restaurando backup: $backup_file"
            
            # Parar aplicação
            pm2 stop "$APP_NAME" || true
            
            # Restaurar backup
            cd "$APP_DIR"
            rm -rf ./* 2>/dev/null || true
            tar -xzf "$backup_file" --strip-components=1
            
            # Reiniciar aplicação
            pm2 start ecosystem.config.js
            
            success "Rollback concluído"
        else
            error "Arquivo de backup não encontrado: $backup_file"
        fi
    else
        error "Nenhum backup disponível para rollback"
    fi
}

# Limpeza de backups antigos
cleanup_old_backups() {
    info "Limpando backups antigos..."
    
    find "$BACKUP_DIR" -name "backup_*.tar.gz" -mtime +7 -delete
    
    success "Backups antigos removidos"
}

# Função principal
main() {
    info "Iniciando atualização do G-Panel..."
    info "Branch: $BRANCH"
    
    # Verificações iniciais
    check_permissions
    check_app_directory
    check_pm2
    
    # Criar diretórios necessários
    mkdir -p "$BACKUP_DIR" "$(dirname "$LOG_FILE")"
    
    # Processo de atualização
    create_backup
    
    # Trap para rollback em caso de erro
    trap rollback ERR
    
    update_code
    update_dependencies
    run_migrations
    restart_app
    health_check
    
    # Remover trap de rollback
    trap - ERR
    
    cleanup_old_backups
    
    success "Atualização concluída com sucesso!"
    info "Logs disponíveis em: $LOG_FILE"
    info "Aplicação disponível em: http://localhost:3000"
}

# Verificar argumentos
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo "Uso: $0 [branch]"
    echo "  branch: Branch do git para atualizar (padrão: main)"
    echo "  --help: Mostra esta ajuda"
    exit 0
fi

# Executar função principal
main "$@"