#!/bin/bash

# =============================================================================
# G-PANEL - SCRIPT DE ROLLBACK
# =============================================================================
# Este script permite fazer rollback para uma versão anterior do G-Panel
# Uso: ./scripts/rollback.sh [backup_file]
# =============================================================================

set -e

# Configurações
APP_DIR="/opt/gpanel"
BACKUP_DIR="/opt/gpanel/backups"
LOG_FILE="/opt/gpanel/logs/rollback.log"
APP_NAME="gpanel"

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

# Listar backups disponíveis
list_backups() {
    info "Backups disponíveis:"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        warning "Diretório de backup não encontrado: $BACKUP_DIR"
        return 1
    fi
    
    local backups=($(find "$BACKUP_DIR" -name "backup_*.tar.gz" -type f | sort -r))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        warning "Nenhum backup encontrado"
        return 1
    fi
    
    echo
    for i in "${!backups[@]}"; do
        local backup_file="${backups[$i]}"
        local backup_name=$(basename "$backup_file" .tar.gz)
        local backup_date=$(echo "$backup_name" | sed 's/backup_//' | sed 's/_/ /')
        local file_size=$(du -h "$backup_file" | cut -f1)
        local file_date=$(stat -c %y "$backup_file" | cut -d' ' -f1,2 | cut -d'.' -f1)
        
        echo "  $((i+1)). $backup_name"
        echo "     Arquivo: $(basename "$backup_file")"
        echo "     Tamanho: $file_size"
        echo "     Criado: $file_date"
        echo
    done
    
    return 0
}

# Selecionar backup interativamente
select_backup() {
    local backups=($(find "$BACKUP_DIR" -name "backup_*.tar.gz" -type f | sort -r))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        error "Nenhum backup disponível"
    fi
    
    echo "Selecione o backup para rollback:"
    read -p "Digite o número do backup (1-${#backups[@]}): " selection
    
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ $selection -lt 1 ]] || [[ $selection -gt ${#backups[@]} ]]; then
        error "Seleção inválida"
    fi
    
    echo "${backups[$((selection-1))]}"
}

# Validar arquivo de backup
validate_backup() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        error "Arquivo de backup não encontrado: $backup_file"
    fi
    
    # Verificar se é um arquivo tar.gz válido
    if ! tar -tzf "$backup_file" &> /dev/null; then
        error "Arquivo de backup corrompido ou inválido: $backup_file"
    fi
    
    info "Backup validado: $(basename "$backup_file")"
}

# Criar backup da versão atual antes do rollback
create_current_backup() {
    info "Criando backup da versão atual..."
    
    local backup_name="backup_before_rollback_$(date +%Y%m%d_%H%M%S)"
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
    
    success "Backup da versão atual criado: $BACKUP_DIR/${backup_name}.tar.gz"
}

# Parar aplicação
stop_app() {
    info "Parando aplicação..."
    
    if pm2 describe "$APP_NAME" &> /dev/null; then
        pm2 stop "$APP_NAME"
        success "Aplicação parada"
    else
        warning "Aplicação não estava rodando"
    fi
}

# Restaurar backup
restore_backup() {
    local backup_file="$1"
    
    info "Restaurando backup: $(basename "$backup_file")"
    
    # Criar backup temporário do diretório atual
    local temp_backup="/tmp/gpanel_temp_$(date +%s)"
    mv "$APP_DIR" "$temp_backup"
    
    # Criar novo diretório da aplicação
    mkdir -p "$APP_DIR"
    
    # Extrair backup
    cd "$APP_DIR"
    tar -xzf "$backup_file" --strip-components=1
    
    # Verificar se a extração foi bem-sucedida
    if [[ ! -f "$APP_DIR/package.json" ]]; then
        error "Falha na extração do backup. Restaurando versão anterior..."
        rm -rf "$APP_DIR"
        mv "$temp_backup" "$APP_DIR"
        exit 1
    fi
    
    # Remover backup temporário
    rm -rf "$temp_backup"
    
    success "Backup restaurado com sucesso"
}

# Instalar dependências
install_dependencies() {
    info "Instalando dependências..."
    
    cd "$APP_DIR"
    
    if [[ -f "package.json" ]]; then
        npm ci --production
        success "Dependências instaladas"
    else
        warning "package.json não encontrado"
    fi
}

# Iniciar aplicação
start_app() {
    info "Iniciando aplicação..."
    
    cd "$APP_DIR"
    
    if [[ -f "ecosystem.config.js" ]]; then
        pm2 start ecosystem.config.js
    else
        # Tentar encontrar arquivo principal
        if [[ -f "app.js" ]]; then
            pm2 start app.js --name "$APP_NAME"
        elif [[ -f "index.js" ]]; then
            pm2 start index.js --name "$APP_NAME"
        elif [[ -f "server.js" ]]; then
            pm2 start server.js --name "$APP_NAME"
        else
            error "Arquivo principal da aplicação não encontrado"
        fi
    fi
    
    # Aguardar a aplicação inicializar
    sleep 5
    
    # Verificar se a aplicação está rodando
    if pm2 describe "$APP_NAME" | grep -q "online"; then
        success "Aplicação iniciada com sucesso"
    else
        error "Falha ao iniciar a aplicação"
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

# Confirmar rollback
confirm_rollback() {
    local backup_file="$1"
    local backup_name=$(basename "$backup_file" .tar.gz)
    
    echo
    warning "ATENÇÃO: Você está prestes a fazer rollback para:"
    echo "  Backup: $backup_name"
    echo "  Arquivo: $backup_file"
    echo
    warning "Esta ação irá:"
    echo "  1. Parar a aplicação atual"
    echo "  2. Fazer backup da versão atual"
    echo "  3. Restaurar a versão do backup selecionado"
    echo "  4. Reinstalar dependências"
    echo "  5. Reiniciar a aplicação"
    echo
    
    read -p "Tem certeza que deseja continuar? (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Rollback cancelado pelo usuário"
        exit 0
    fi
}

# Função principal
main() {
    local backup_file="$1"
    
    info "Iniciando rollback do G-Panel..."
    
    # Verificações iniciais
    check_permissions
    check_app_directory
    check_pm2
    
    # Criar diretório de logs
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Se não foi especificado um backup, listar e permitir seleção
    if [[ -z "$backup_file" ]]; then
        if ! list_backups; then
            error "Nenhum backup disponível para rollback"
        fi
        
        backup_file=$(select_backup)
    fi
    
    # Validar backup
    validate_backup "$backup_file"
    
    # Confirmar rollback
    confirm_rollback "$backup_file"
    
    # Processo de rollback
    create_current_backup
    stop_app
    restore_backup "$backup_file"
    install_dependencies
    start_app
    health_check
    
    success "Rollback concluído com sucesso!"
    info "Logs disponíveis em: $LOG_FILE"
    info "Aplicação disponível em: http://localhost:3000"
}

# Verificar argumentos
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo "Uso: $0 [backup_file]"
    echo "  backup_file: Caminho para o arquivo de backup (opcional)"
    echo "  --list: Lista backups disponíveis"
    echo "  --help: Mostra esta ajuda"
    exit 0
fi

if [[ "$1" == "--list" ]]; then
    list_backups
    exit 0
fi

# Executar função principal
main "$@"