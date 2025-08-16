#!/bin/bash

# =============================================================================
# G-PANEL - SCRIPT DE BACKUP AUTOMÁTICO
# =============================================================================
# Este script cria backups automáticos do G-Panel incluindo código e banco de dados
# Uso: ./scripts/backup.sh [tipo]
# Tipos: manual, daily, weekly, monthly
# =============================================================================

set -e

# Configurações
APP_DIR="/opt/gpanel"
BACKUP_DIR="/opt/gpanel/backups"
LOG_FILE="/opt/gpanel/logs/backup.log"
APP_NAME="gpanel"
MAX_BACKUPS_DAILY=7
MAX_BACKUPS_WEEKLY=4
MAX_BACKUPS_MONTHLY=12
MAX_BACKUPS_MANUAL=10

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

# Criar diretórios necessários
setup_directories() {
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Definir permissões corretas
    chmod 755 "$BACKUP_DIR"
    chmod 755 "$(dirname "$LOG_FILE")"
}

# Obter informações da versão atual
get_version_info() {
    local version="unknown"
    local git_hash="unknown"
    local git_branch="unknown"
    
    if [[ -f "$APP_DIR/package.json" ]]; then
        version=$(cat "$APP_DIR/package.json" | grep '"version"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    fi
    
    if [[ -d "$APP_DIR/.git" ]]; then
        cd "$APP_DIR"
        git_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        git_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    fi
    
    echo "$version|$git_hash|$git_branch"
}

# Criar metadados do backup
create_metadata() {
    local backup_type="$1"
    local backup_path="$2"
    local version_info=$(get_version_info)
    
    cat > "$backup_path/backup_metadata.json" << EOF
{
  "backup_type": "$backup_type",
  "created_at": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "panel_version": "$(echo $version_info | cut -d'|' -f1)",
  "git_hash": "$(echo $version_info | cut -d'|' -f2)",
  "git_branch": "$(echo $version_info | cut -d'|' -f3)",
  "backup_size": "0",
  "files_count": 0,
  "database_included": false,
  "config_included": false
}
EOF
}

# Fazer backup do código da aplicação
backup_application() {
    local backup_path="$1"
    
    info "Fazendo backup do código da aplicação..."
    
    # Criar diretório para a aplicação
    mkdir -p "$backup_path/app"
    
    # Copiar arquivos da aplicação (excluindo node_modules e outros desnecessários)
    rsync -av \
        --exclude='node_modules' \
        --exclude='.git' \
        --exclude='logs' \
        --exclude='backups' \
        --exclude='tmp' \
        --exclude='*.log' \
        --exclude='.env.local' \
        --exclude='.env.development' \
        "$APP_DIR/" "$backup_path/app/"
    
    success "Backup do código concluído"
}

# Fazer backup do banco de dados
backup_database() {
    local backup_path="$1"
    
    info "Fazendo backup do banco de dados..."
    
    # Verificar se existe banco SQLite
    if [[ -f "$APP_DIR/data/database.sqlite" ]]; then
        mkdir -p "$backup_path/data"
        cp "$APP_DIR/data/database.sqlite" "$backup_path/data/"
        success "Backup do banco SQLite concluído"
        return 0
    fi
    
    # Verificar se existe configuração de banco externo
    if [[ -f "$APP_DIR/.env" ]]; then
        local db_type=$(grep '^DB_TYPE=' "$APP_DIR/.env" | cut -d'=' -f2 | tr -d '"' || echo "")
        
        case "$db_type" in
            "mysql"|"mariadb")
                backup_mysql "$backup_path"
                ;;
            "postgresql"|"postgres")
                backup_postgresql "$backup_path"
                ;;
            "mongodb")
                backup_mongodb "$backup_path"
                ;;
            *)
                warning "Tipo de banco não identificado ou não suportado: $db_type"
                ;;
        esac
    else
        warning "Arquivo .env não encontrado, pulando backup do banco"
    fi
}

# Backup MySQL/MariaDB
backup_mysql() {
    local backup_path="$1"
    
    if ! command -v mysqldump &> /dev/null; then
        warning "mysqldump não encontrado, pulando backup MySQL"
        return 1
    fi
    
    local db_host=$(grep '^DB_HOST=' "$APP_DIR/.env" | cut -d'=' -f2 | tr -d '"')
    local db_port=$(grep '^DB_PORT=' "$APP_DIR/.env" | cut -d'=' -f2 | tr -d '"')
    local db_name=$(grep '^DB_NAME=' "$APP_DIR/.env" | cut -d'=' -f2 | tr -d '"')
    local db_user=$(grep '^DB_USER=' "$APP_DIR/.env" | cut -d'=' -f2 | tr -d '"')
    local db_pass=$(grep '^DB_PASS=' "$APP_DIR/.env" | cut -d'=' -f2 | tr -d '"')
    
    mkdir -p "$backup_path/data"
    
    MYSQL_PWD="$db_pass" mysqldump \
        -h "${db_host:-localhost}" \
        -P "${db_port:-3306}" \
        -u "$db_user" \
        --single-transaction \
        --routines \
        --triggers \
        "$db_name" > "$backup_path/data/mysql_dump.sql"
    
    success "Backup MySQL concluído"
}

# Backup PostgreSQL
backup_postgresql() {
    local backup_path="$1"
    
    if ! command -v pg_dump &> /dev/null; then
        warning "pg_dump não encontrado, pulando backup PostgreSQL"
        return 1
    fi
    
    local db_host=$(grep '^DB_HOST=' "$APP_DIR/.env" | cut -d'=' -f2 | tr -d '"')
    local db_port=$(grep '^DB_PORT=' "$APP_DIR/.env" | cut -d'=' -f2 | tr -d '"')
    local db_name=$(grep '^DB_NAME=' "$APP_DIR/.env" | cut -d'=' -f2 | tr -d '"')
    local db_user=$(grep '^DB_USER=' "$APP_DIR/.env" | cut -d'=' -f2 | tr -d '"')
    local db_pass=$(grep '^DB_PASS=' "$APP_DIR/.env" | cut -d'=' -f2 | tr -d '"')
    
    mkdir -p "$backup_path/data"
    
    PGPASSWORD="$db_pass" pg_dump \
        -h "${db_host:-localhost}" \
        -p "${db_port:-5432}" \
        -U "$db_user" \
        -d "$db_name" \
        --no-password \
        --clean \
        --if-exists > "$backup_path/data/postgresql_dump.sql"
    
    success "Backup PostgreSQL concluído"
}

# Backup MongoDB
backup_mongodb() {
    local backup_path="$1"
    
    if ! command -v mongodump &> /dev/null; then
        warning "mongodump não encontrado, pulando backup MongoDB"
        return 1
    fi
    
    local db_host=$(grep '^DB_HOST=' "$APP_DIR/.env" | cut -d'=' -f2 | tr -d '"')
    local db_port=$(grep '^DB_PORT=' "$APP_DIR/.env" | cut -d'=' -f2 | tr -d '"')
    local db_name=$(grep '^DB_NAME=' "$APP_DIR/.env" | cut -d'=' -f2 | tr -d '"')
    local db_user=$(grep '^DB_USER=' "$APP_DIR/.env" | cut -d'=' -f2 | tr -d '"')
    local db_pass=$(grep '^DB_PASS=' "$APP_DIR/.env" | cut -d'=' -f2 | tr -d '"')
    
    mkdir -p "$backup_path/data"
    
    mongodump \
        --host "${db_host:-localhost}:${db_port:-27017}" \
        --db "$db_name" \
        --username "$db_user" \
        --password "$db_pass" \
        --out "$backup_path/data/mongodb"
    
    success "Backup MongoDB concluído"
}

# Fazer backup das configurações
backup_configs() {
    local backup_path="$1"
    
    info "Fazendo backup das configurações..."
    
    mkdir -p "$backup_path/config"
    
    # Backup do .env
    if [[ -f "$APP_DIR/.env" ]]; then
        cp "$APP_DIR/.env" "$backup_path/config/"
    fi
    
    # Backup do ecosystem.config.js
    if [[ -f "$APP_DIR/ecosystem.config.js" ]]; then
        cp "$APP_DIR/ecosystem.config.js" "$backup_path/config/"
    fi
    
    # Backup de configurações do Nginx (se existirem)
    if [[ -f "/etc/nginx/sites-available/gpanel" ]]; then
        mkdir -p "$backup_path/config/nginx"
        cp "/etc/nginx/sites-available/gpanel" "$backup_path/config/nginx/"
    fi
    
    # Backup de certificados SSL (se existirem)
    if [[ -d "/etc/letsencrypt/live" ]]; then
        local ssl_dir=$(find /etc/letsencrypt/live -name "*gpanel*" -o -name "*panel*" | head -1)
        if [[ -n "$ssl_dir" ]]; then
            mkdir -p "$backup_path/config/ssl"
            cp -r "$ssl_dir" "$backup_path/config/ssl/"
        fi
    fi
    
    success "Backup das configurações concluído"
}

# Compactar backup
compress_backup() {
    local backup_name="$1"
    local backup_path="$2"
    
    info "Compactando backup..."
    
    cd "$BACKUP_DIR"
    tar -czf "${backup_name}.tar.gz" "$backup_name"
    
    # Calcular tamanho e atualizar metadados
    local backup_size=$(du -h "${backup_name}.tar.gz" | cut -f1)
    local files_count=$(find "$backup_name" -type f | wc -l)
    
    # Atualizar metadados
    if [[ -f "$backup_name/backup_metadata.json" ]]; then
        sed -i "s/\"backup_size\": \"0\"/\"backup_size\": \"$backup_size\"/" "$backup_name/backup_metadata.json"
        sed -i "s/\"files_count\": 0/\"files_count\": $files_count/" "$backup_name/backup_metadata.json"
    fi
    
    # Remover diretório temporário
    rm -rf "$backup_name"
    
    success "Backup compactado: ${backup_name}.tar.gz ($backup_size)"
}

# Limpar backups antigos
cleanup_old_backups() {
    local backup_type="$1"
    local max_backups
    
    case "$backup_type" in
        "daily")
            max_backups=$MAX_BACKUPS_DAILY
            ;;
        "weekly")
            max_backups=$MAX_BACKUPS_WEEKLY
            ;;
        "monthly")
            max_backups=$MAX_BACKUPS_MONTHLY
            ;;
        "manual")
            max_backups=$MAX_BACKUPS_MANUAL
            ;;
        *)
            return 0
            ;;
    esac
    
    info "Limpando backups antigos do tipo $backup_type (mantendo $max_backups)..."
    
    cd "$BACKUP_DIR"
    
    # Listar backups do tipo específico, ordenados por data (mais antigos primeiro)
    local old_backups=($(ls -t backup_${backup_type}_*.tar.gz 2>/dev/null | tail -n +$((max_backups + 1))))
    
    if [[ ${#old_backups[@]} -gt 0 ]]; then
        for backup in "${old_backups[@]}"; do
            rm -f "$backup"
            info "Backup removido: $backup"
        done
        success "${#old_backups[@]} backup(s) antigo(s) removido(s)"
    else
        info "Nenhum backup antigo para remover"
    fi
}

# Verificar espaço em disco
check_disk_space() {
    local required_space_mb=1000  # 1GB mínimo
    local available_space_mb=$(df "$BACKUP_DIR" | awk 'NR==2 {print int($4/1024)}')
    
    if [[ $available_space_mb -lt $required_space_mb ]]; then
        warning "Pouco espaço em disco disponível: ${available_space_mb}MB (mínimo: ${required_space_mb}MB)"
        warning "Considere limpar backups antigos ou aumentar o espaço em disco"
    else
        info "Espaço em disco suficiente: ${available_space_mb}MB disponível"
    fi
}

# Criar backup
create_backup() {
    local backup_type="${1:-manual}"
    
    info "Iniciando backup do tipo: $backup_type"
    
    # Verificar espaço em disco
    check_disk_space
    
    # Gerar nome do backup
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="backup_${backup_type}_${timestamp}"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    # Criar diretório do backup
    mkdir -p "$backup_path"
    
    # Criar metadados
    create_metadata "$backup_type" "$backup_path"
    
    # Fazer backup dos componentes
    backup_application "$backup_path"
    backup_database "$backup_path"
    backup_configs "$backup_path"
    
    # Compactar backup
    compress_backup "$backup_name" "$backup_path"
    
    # Limpar backups antigos
    cleanup_old_backups "$backup_type"
    
    success "Backup concluído: $BACKUP_DIR/${backup_name}.tar.gz"
    
    # Mostrar informações do backup
    local backup_size=$(du -h "$BACKUP_DIR/${backup_name}.tar.gz" | cut -f1)
    info "Tamanho do backup: $backup_size"
    info "Localização: $BACKUP_DIR/${backup_name}.tar.gz"
}

# Listar backups existentes
list_backups() {
    info "Backups disponíveis:"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        warning "Diretório de backup não encontrado: $BACKUP_DIR"
        return 1
    fi
    
    cd "$BACKUP_DIR"
    
    local backups=($(ls -t backup_*.tar.gz 2>/dev/null))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        warning "Nenhum backup encontrado"
        return 1
    fi
    
    echo
    printf "%-5s %-40s %-20s %-10s %-20s\n" "#" "Nome" "Data" "Tamanho" "Tipo"
    echo "────────────────────────────────────────────────────────────────────────────────────────"
    
    for i in "${!backups[@]}"; do
        local backup_file="${backups[$i]}"
        local backup_name=$(basename "$backup_file" .tar.gz)
        local backup_type=$(echo "$backup_name" | cut -d'_' -f2)
        local file_size=$(du -h "$backup_file" | cut -f1)
        local file_date=$(stat -c %y "$backup_file" | cut -d' ' -f1,2 | cut -d'.' -f1)
        
        printf "%-5s %-40s %-20s %-10s %-20s\n" "$((i+1))" "$backup_name" "$file_date" "$file_size" "$backup_type"
    done
    
    echo
    info "Total de backups: ${#backups[@]}"
    
    # Mostrar uso do espaço
    local total_size=$(du -sh "$BACKUP_DIR" | cut -f1)
    info "Espaço total usado: $total_size"
}

# Verificar integridade de um backup
verify_backup() {
    local backup_file="$1"
    
    if [[ -z "$backup_file" ]]; then
        error "Especifique o arquivo de backup para verificar"
    fi
    
    if [[ ! -f "$BACKUP_DIR/$backup_file" ]]; then
        error "Backup não encontrado: $backup_file"
    fi
    
    info "Verificando integridade do backup: $backup_file"
    
    # Verificar se é um arquivo tar.gz válido
    if tar -tzf "$BACKUP_DIR/$backup_file" &> /dev/null; then
        success "Backup íntegro: $backup_file"
        
        # Mostrar conteúdo
        info "Conteúdo do backup:"
        tar -tzf "$BACKUP_DIR/$backup_file" | head -20
        
        local file_count=$(tar -tzf "$BACKUP_DIR/$backup_file" | wc -l)
        if [[ $file_count -gt 20 ]]; then
            info "... e mais $((file_count - 20)) arquivo(s)"
        fi
        
        info "Total de arquivos: $file_count"
    else
        error "Backup corrompido: $backup_file"
    fi
}

# Função principal
main() {
    local command="${1:-create}"
    local backup_type="${2:-manual}"
    
    # Verificações iniciais
    check_permissions
    check_app_directory
    setup_directories
    
    case "$command" in
        "create"|"")
            create_backup "$backup_type"
            ;;
        "list")
            list_backups
            ;;
        "verify")
            verify_backup "$backup_type"
            ;;
        "cleanup")
            cleanup_old_backups "$backup_type"
            ;;
        "help"|"--help"|"--h")
            echo "Uso: $0 [comando] [tipo/arquivo]"
            echo
            echo "Comandos:"
            echo "  create [tipo]     Criar backup (padrão: manual)"
            echo "  list              Listar backups disponíveis"
            echo "  verify <arquivo>  Verificar integridade de um backup"
            echo "  cleanup <tipo>    Limpar backups antigos de um tipo"
            echo "  help              Mostrar esta ajuda"
            echo
            echo "Tipos de backup:"
            echo "  manual            Backup manual (padrão)"
            echo "  daily             Backup diário"
            echo "  weekly            Backup semanal"
            echo "  monthly           Backup mensal"
            echo
            echo "Exemplos:"
            echo "  $0                        # Criar backup manual"
            echo "  $0 create daily           # Criar backup diário"
            echo "  $0 list                   # Listar backups"
            echo "  $0 verify backup_file.tar.gz  # Verificar backup"
            echo "  $0 cleanup daily          # Limpar backups diários antigos"
            ;;
        *)
            error "Comando inválido: $command"
            ;;
    esac
}

# Executar função principal
main "$@"