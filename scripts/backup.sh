#!/bin/bash

# G-Panel Enterprise Backup Script
# Backup automático do banco de dados, configurações e código

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
APP_DIR="$PANEL_DIR/app"
BACKUP_DIR="$PANEL_DIR/backups"
DATA_DIR="$PANEL_DIR/data"
LOG_FILE="$PANEL_DIR/logs/backup.log"
MAX_BACKUPS=30  # Manter 30 backups (1 mês)
MAX_DAILY_BACKUPS=7  # Manter 7 backups diários
MAX_WEEKLY_BACKUPS=4  # Manter 4 backups semanais
MAX_MONTHLY_BACKUPS=12  # Manter 12 backups mensais
COMPRESSION_LEVEL=6  # Nível de compressão (1-9)

# Configurações de armazenamento remoto (opcional)
REMOTE_BACKUP_ENABLED=false
REMOTE_BACKUP_PATH="/remote/backups"
S3_BUCKET=""  # Para backup no S3
S3_REGION="us-east-1"

# Funções auxiliares
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a $LOG_FILE
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a $LOG_FILE
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a $LOG_FILE
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a $LOG_FILE
}

get_backup_type() {
    local day_of_week=$(date +%u)  # 1=Monday, 7=Sunday
    local day_of_month=$(date +%d)
    
    if [[ "$day_of_month" == "01" ]]; then
        echo "monthly"
    elif [[ "$day_of_week" == "7" ]]; then  # Sunday
        echo "weekly"
    else
        echo "daily"
    fi
}

get_backup_name() {
    local backup_type=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local version=$(cd $APP_DIR && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    
    echo "${backup_type}_${timestamp}_${version}"
}

check_prerequisites() {
    log_info "Verificando pré-requisitos..."
    
    # Verificar se diretórios existem
    if [[ ! -d "$APP_DIR" ]]; then
        log_error "Diretório da aplicação não encontrado: $APP_DIR"
        exit 1
    fi
    
    # Criar diretório de backup se não existir
    mkdir -p $BACKUP_DIR
    
    # Verificar espaço em disco
    local available_space=$(df $BACKUP_DIR | awk 'NR==2 {print $4}')
    local required_space=1048576  # 1GB em KB
    
    if [[ $available_space -lt $required_space ]]; then
        log_warning "Pouco espaço em disco disponível: $(($available_space/1024))MB"
    fi
    
    log_success "Pré-requisitos verificados"
}

backup_database() {
    local backup_path=$1
    
    log_info "Fazendo backup do banco de dados..."
    
    if [[ -f "$DATA_DIR/database.sqlite" ]]; then
        # Backup do SQLite com checkpoint para garantir consistência
        sqlite3 $DATA_DIR/database.sqlite ".backup $backup_path/database.sqlite"
        
        # Verificar integridade do backup
        if sqlite3 $backup_path/database.sqlite "PRAGMA integrity_check;" | grep -q "ok"; then
            log_success "Backup do banco de dados criado e verificado"
        else
            log_error "Backup do banco de dados corrompido"
            return 1
        fi
        
        # Criar dump SQL como backup adicional
        sqlite3 $DATA_DIR/database.sqlite ".dump" | gzip > $backup_path/database_dump.sql.gz
        
        # Estatísticas do banco
        local db_size=$(du -h $DATA_DIR/database.sqlite | cut -f1)
        local table_count=$(sqlite3 $DATA_DIR/database.sqlite "SELECT COUNT(*) FROM sqlite_master WHERE type='table';")
        
        echo "Database size: $db_size" >> $backup_path/backup_stats.txt
        echo "Table count: $table_count" >> $backup_path/backup_stats.txt
    else
        log_warning "Banco de dados não encontrado: $DATA_DIR/database.sqlite"
    fi
}

backup_application() {
    local backup_path=$1
    
    log_info "Fazendo backup da aplicação..."
    
    # Backup do código (excluindo node_modules e arquivos temporários)
    rsync -av --exclude='node_modules' \
              --exclude='.git' \
              --exclude='*.log' \
              --exclude='*.tmp' \
              --exclude='.env.local' \
              $APP_DIR/ $backup_path/app/
    
    # Backup das configurações
    if [[ -f "$APP_DIR/.env" ]]; then
        cp $APP_DIR/.env $backup_path/.env
    fi
    
    # Backup do package.json e package-lock.json
    cp $APP_DIR/package*.json $backup_path/ 2>/dev/null || true
    
    log_success "Backup da aplicação criado"
}

backup_logs() {
    local backup_path=$1
    
    log_info "Fazendo backup dos logs..."
    
    if [[ -d "$PANEL_DIR/logs" ]]; then
        mkdir -p $backup_path/logs
        
        # Backup dos logs dos últimos 7 dias
        find $PANEL_DIR/logs -name "*.log" -mtime -7 -exec cp {} $backup_path/logs/ \;
        
        # Comprimir logs antigos
        find $backup_path/logs -name "*.log" -exec gzip {} \;
        
        log_success "Backup dos logs criado"
    fi
}

backup_nginx_config() {
    local backup_path=$1
    
    log_info "Fazendo backup das configurações do Nginx..."
    
    if [[ -d "$PANEL_DIR/nginx" ]]; then
        cp -r $PANEL_DIR/nginx $backup_path/
        log_success "Backup das configurações do Nginx criado"
    fi
    
    # Backup da configuração global do Nginx
    if [[ -f "/etc/nginx/sites-available/g-panel" ]]; then
        mkdir -p $backup_path/system_config
        cp /etc/nginx/sites-available/g-panel $backup_path/system_config/
    fi
}

create_backup_metadata() {
    local backup_path=$1
    local backup_name=$2
    local backup_type=$3
    
    log_info "Criando metadados do backup..."
    
    # Informações do sistema
    local system_info=$(uname -a)
    local disk_usage=$(df -h $PANEL_DIR)
    local memory_info=$(free -h)
    local git_info="unknown"
    
    if [[ -d "$APP_DIR/.git" ]]; then
        cd $APP_DIR
        git_info=$(git log -1 --pretty=format:"%H|%an|%ad|%s" --date=iso)
    fi
    
    # Status do PM2
    local pm2_status="not_available"
    if command -v pm2 &> /dev/null; then
        pm2_status=$(pm2 jlist 2>/dev/null || echo "[]")
    fi
    
    # Criar arquivo de metadados
    cat > $backup_path/backup_metadata.json << EOF
{
  "backup_name": "$backup_name",
  "backup_type": "$backup_type",
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "system_info": "$system_info",
  "git_info": "$git_info",
  "pm2_status": $pm2_status,
  "panel_version": "$(cat $APP_DIR/package.json | jq -r .version 2>/dev/null || echo 'unknown')",
  "node_version": "$(node --version)",
  "npm_version": "$(npm --version)",
  "backup_size": "$(du -sh $backup_path | cut -f1)"
}
EOF
    
    # Criar checksum dos arquivos importantes
    find $backup_path -type f \( -name "*.sqlite" -o -name "*.json" -o -name ".env" \) -exec sha256sum {} \; > $backup_path/checksums.txt
    
    log_success "Metadados do backup criados"
}

compress_backup() {
    local backup_path=$1
    local backup_name=$2
    
    log_info "Comprimindo backup..."
    
    cd $BACKUP_DIR
    
    # Comprimir com tar e gzip
    tar -czf "${backup_name}.tar.gz" -C $backup_path .
    
    # Verificar integridade do arquivo comprimido
    if tar -tzf "${backup_name}.tar.gz" > /dev/null 2>&1; then
        log_success "Backup comprimido com sucesso: ${backup_name}.tar.gz"
        
        # Remover diretório temporário
        rm -rf $backup_path
        
        # Mostrar tamanho do backup
        local backup_size=$(du -h "${backup_name}.tar.gz" | cut -f1)
        log_info "Tamanho do backup: $backup_size"
    else
        log_error "Erro na compressão do backup"
        return 1
    fi
}

upload_to_remote() {
    local backup_file=$1
    
    if [[ "$REMOTE_BACKUP_ENABLED" == "true" ]]; then
        log_info "Enviando backup para armazenamento remoto..."
        
        # Upload para S3 (se configurado)
        if [[ -n "$S3_BUCKET" ]] && command -v aws &> /dev/null; then
            aws s3 cp $backup_file s3://$S3_BUCKET/g-panel-backups/ --region $S3_REGION
            log_success "Backup enviado para S3: s3://$S3_BUCKET/g-panel-backups/$(basename $backup_file)"
        fi
        
        # Upload para servidor remoto via rsync (se configurado)
        if [[ -n "$REMOTE_BACKUP_PATH" ]]; then
            rsync -av $backup_file $REMOTE_BACKUP_PATH/
            log_success "Backup enviado para: $REMOTE_BACKUP_PATH/$(basename $backup_file)"
        fi
    fi
}

cleanup_old_backups() {
    log_info "Limpando backups antigos..."
    
    cd $BACKUP_DIR
    
    # Limpar backups diários (manter apenas os últimos N)
    ls -t daily_*.tar.gz 2>/dev/null | tail -n +$((MAX_DAILY_BACKUPS + 1)) | xargs -r rm -f
    
    # Limpar backups semanais
    ls -t weekly_*.tar.gz 2>/dev/null | tail -n +$((MAX_WEEKLY_BACKUPS + 1)) | xargs -r rm -f
    
    # Limpar backups mensais
    ls -t monthly_*.tar.gz 2>/dev/null | tail -n +$((MAX_MONTHLY_BACKUPS + 1)) | xargs -r rm -f
    
    # Limpar backups de deploy antigos
    ls -t backup_*.tar.gz 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm -f
    
    log_success "Backups antigos removidos"
}

list_backups() {
    log_info "=== Backups Disponíveis ==="
    
    cd $BACKUP_DIR
    
    echo "Backups Diários:"
    ls -lh daily_*.tar.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ", " $6 " " $7 " " $8 ")"}' || echo "  Nenhum backup diário encontrado"
    
    echo
    echo "Backups Semanais:"
    ls -lh weekly_*.tar.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ", " $6 " " $7 " " $8 ")"}' || echo "  Nenhum backup semanal encontrado"
    
    echo
    echo "Backups Mensais:"
    ls -lh monthly_*.tar.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ", " $6 " " $7 " " $8 ")"}' || echo "  Nenhum backup mensal encontrado"
    
    echo
    echo "Backups de Deploy:"
    ls -lh backup_*.tar.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ", " $6 " " $7 " " $8 ")"}' || echo "  Nenhum backup de deploy encontrado"
    
    echo
    local total_size=$(du -sh . 2>/dev/null | cut -f1)
    echo "Tamanho total dos backups: $total_size"
}

verify_backup() {
    local backup_file=$1
    
    log_info "Verificando integridade do backup: $backup_file"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Arquivo de backup não encontrado: $backup_file"
        return 1
    fi
    
    # Verificar integridade do arquivo tar
    if ! tar -tzf "$backup_file" > /dev/null 2>&1; then
        log_error "Arquivo de backup corrompido: $backup_file"
        return 1
    fi
    
    # Extrair e verificar metadados
    local temp_dir=$(mktemp -d)
    tar -xzf "$backup_file" -C $temp_dir backup_metadata.json 2>/dev/null || true
    
    if [[ -f "$temp_dir/backup_metadata.json" ]]; then
        local backup_info=$(cat $temp_dir/backup_metadata.json)
        log_success "Backup válido: $(echo $backup_info | jq -r .backup_name)"
        echo "  Tipo: $(echo $backup_info | jq -r .backup_type)"
        echo "  Data: $(echo $backup_info | jq -r .timestamp)"
        echo "  Versão: $(echo $backup_info | jq -r .panel_version)"
    fi
    
    rm -rf $temp_dir
    log_success "Verificação concluída"
}

# Função principal de backup
create_backup() {
    local backup_type=$(get_backup_type)
    local backup_name=$(get_backup_name $backup_type)
    local backup_path="$BACKUP_DIR/$backup_name"
    
    log_info "=== Iniciando Backup do G-Panel ==="
    log_info "Tipo: $backup_type"
    log_info "Nome: $backup_name"
    
    check_prerequisites
    
    # Criar diretório temporário para o backup
    mkdir -p $backup_path
    
    # Executar backups
    backup_database $backup_path
    backup_application $backup_path
    backup_logs $backup_path
    backup_nginx_config $backup_path
    create_backup_metadata $backup_path $backup_name $backup_type
    
    # Comprimir backup
    compress_backup $backup_path $backup_name
    
    # Upload para armazenamento remoto
    upload_to_remote "$BACKUP_DIR/${backup_name}.tar.gz"
    
    # Limpeza de backups antigos
    cleanup_old_backups
    
    log_success "=== Backup concluído com sucesso ==="
    log_info "Arquivo: ${backup_name}.tar.gz"
    log_info "Localização: $BACKUP_DIR"
}

# Função para mostrar ajuda
show_help() {
    echo "G-Panel Backup Script"
    echo
    echo "Uso: $0 [comando]"
    echo
    echo "Comandos:"
    echo "  create        Criar novo backup"
    echo "  list          Listar backups disponíveis"
    echo "  verify <file> Verificar integridade de um backup"
    echo "  cleanup       Limpar backups antigos"
    echo "  help          Mostrar esta ajuda"
    echo
    echo "Exemplos:"
    echo "  $0 create"
    echo "  $0 list"
    echo "  $0 verify daily_20231201_120000_abc123.tar.gz"
    echo "  $0 cleanup"
}

# Função principal
main() {
    # Criar diretório de logs se não existir
    mkdir -p $(dirname $LOG_FILE)
    
    # Log do início
    echo "$(date -Iseconds) - Backup iniciado por $(whoami)" >> $LOG_FILE
    
    case "${1:-create}" in
        "create")
            create_backup
            ;;
        "list")
            list_backups
            ;;
        "verify")
            if [[ -n "$2" ]]; then
                verify_backup "$BACKUP_DIR/$2"
            else
                log_error "Especifique o arquivo de backup para verificar"
                exit 1
            fi
            ;;
        "cleanup")
            cleanup_old_backups
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            log_error "Comando inválido: $1"
            show_help
            exit 1
            ;;
    esac
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi