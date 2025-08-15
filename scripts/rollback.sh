#!/bin/bash

# G-Panel Enterprise Rollback Script
# Script para reverter atualizações e restaurar versões anteriores

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
LOG_FILE="$PANEL_DIR/logs/rollback.log"
PM2_APP_NAME="g-panel"
SERVICE_NAME="g-panel"
HEALTH_CHECK_URL="http://localhost:3000/health"
HEALTH_CHECK_TIMEOUT=30
ROLLBACK_TIMEOUT=300  # 5 minutos

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

show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

check_prerequisites() {
    log_info "Verificando pré-requisitos para rollback..."
    
    # Verificar se está rodando como usuário correto
    if [[ "$(whoami)" != "root" ]] && [[ "$(whoami)" != "$PANEL_USER" ]]; then
        log_error "Execute como root ou usuário $PANEL_USER"
        exit 1
    fi
    
    # Verificar se diretórios existem
    if [[ ! -d "$APP_DIR" ]]; then
        log_error "Diretório da aplicação não encontrado: $APP_DIR"
        exit 1
    fi
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "Diretório de backups não encontrado: $BACKUP_DIR"
        exit 1
    fi
    
    # Verificar se PM2 está disponível
    if ! command -v pm2 &> /dev/null; then
        log_error "PM2 não está instalado"
        exit 1
    fi
    
    # Verificar se Node.js está disponível
    if ! command -v node &> /dev/null; then
        log_error "Node.js não está instalado"
        exit 1
    fi
    
    log_success "Pré-requisitos verificados"
}

list_available_backups() {
    log_info "=== Backups Disponíveis para Rollback ==="
    
    cd $BACKUP_DIR
    
    local backups=()
    local counter=1
    
    # Listar todos os backups disponíveis
    for backup in $(ls -t *.tar.gz 2>/dev/null); do
        if [[ -f "$backup" ]]; then
            local backup_date=$(stat -c %y "$backup" | cut -d' ' -f1,2 | cut -d'.' -f1)
            local backup_size=$(du -h "$backup" | cut -f1)
            
            # Extrair metadados se disponível
            local temp_dir=$(mktemp -d)
            tar -xzf "$backup" -C $temp_dir backup_metadata.json 2>/dev/null || true
            
            local version="unknown"
            local git_hash="unknown"
            local backup_type="unknown"
            
            if [[ -f "$temp_dir/backup_metadata.json" ]]; then
                version=$(cat $temp_dir/backup_metadata.json | jq -r .panel_version 2>/dev/null || echo "unknown")
                git_hash=$(cat $temp_dir/backup_metadata.json | jq -r .git_info 2>/dev/null | cut -d'|' -f1 | cut -c1-8 || echo "unknown")
                backup_type=$(cat $temp_dir/backup_metadata.json | jq -r .backup_type 2>/dev/null || echo "unknown")
            fi
            
            rm -rf $temp_dir
            
            printf "%2d) %-40s %s (%s) [%s] %s\n" $counter "$backup" "$backup_date" "$backup_size" "$backup_type" "v$version ($git_hash)"
            backups+=($backup)
            ((counter++))
        fi
    done
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log_error "Nenhum backup disponível para rollback"
        exit 1
    fi
    
    echo
    echo "${backups[@]}"
}

get_current_version() {
    local current_version="unknown"
    local current_hash="unknown"
    
    if [[ -f "$APP_DIR/package.json" ]]; then
        current_version=$(cat $APP_DIR/package.json | jq -r .version 2>/dev/null || echo "unknown")
    fi
    
    if [[ -d "$APP_DIR/.git" ]]; then
        cd $APP_DIR
        current_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    fi
    
    echo "$current_version ($current_hash)"
}

verify_backup_integrity() {
    local backup_file=$1
    
    log_info "Verificando integridade do backup: $(basename $backup_file)"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Arquivo de backup não encontrado: $backup_file"
        return 1
    fi
    
    # Verificar integridade do arquivo tar
    if ! tar -tzf "$backup_file" > /dev/null 2>&1; then
        log_error "Arquivo de backup corrompido: $backup_file"
        return 1
    fi
    
    # Verificar se contém arquivos essenciais
    local required_files=("backup_metadata.json" "database.sqlite" "app/package.json")
    
    for file in "${required_files[@]}"; do
        if ! tar -tzf "$backup_file" | grep -q "$file"; then
            log_warning "Arquivo essencial não encontrado no backup: $file"
        fi
    done
    
    log_success "Backup verificado com sucesso"
    return 0
}

create_emergency_backup() {
    log_info "Criando backup de emergência antes do rollback..."
    
    local emergency_backup="emergency_$(date +%Y%m%d_%H%M%S)_pre_rollback.tar.gz"
    local temp_dir=$(mktemp -d)
    
    # Backup rápido dos arquivos essenciais
    mkdir -p $temp_dir/app
    mkdir -p $temp_dir/data
    
    # Copiar aplicação (sem node_modules)
    rsync -av --exclude='node_modules' $APP_DIR/ $temp_dir/app/
    
    # Copiar banco de dados
    if [[ -f "$DATA_DIR/database.sqlite" ]]; then
        cp $DATA_DIR/database.sqlite $temp_dir/data/
    fi
    
    # Criar metadados
    cat > $temp_dir/emergency_metadata.json << EOF
{
  "type": "emergency_backup",
  "created_at": "$(date -Iseconds)",
  "reason": "pre_rollback",
  "current_version": "$(get_current_version)",
  "hostname": "$(hostname)"
}
EOF
    
    # Comprimir
    cd $BACKUP_DIR
    tar -czf "$emergency_backup" -C $temp_dir .
    rm -rf $temp_dir
    
    log_success "Backup de emergência criado: $emergency_backup"
    echo "$emergency_backup"
}

stop_application() {
    log_info "Parando aplicação..."
    
    # Parar PM2
    if pm2 list | grep -q $PM2_APP_NAME; then
        pm2 stop $PM2_APP_NAME
        log_success "Aplicação PM2 parada"
    fi
    
    # Parar Docker se estiver rodando
    if command -v docker &> /dev/null; then
        if docker ps | grep -q g-panel; then
            docker stop g-panel 2>/dev/null || true
            log_success "Container Docker parado"
        fi
    fi
    
    # Aguardar um momento para garantir que parou
    sleep 2
}

restore_from_backup() {
    local backup_file=$1
    local temp_dir=$(mktemp -d)
    
    log_info "Restaurando do backup: $(basename $backup_file)"
    
    # Extrair backup
    tar -xzf "$backup_file" -C $temp_dir
    
    # Backup do diretório atual (caso algo dê errado)
    if [[ -d "$APP_DIR" ]]; then
        mv $APP_DIR "${APP_DIR}.rollback_backup_$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Restaurar aplicação
    if [[ -d "$temp_dir/app" ]]; then
        cp -r $temp_dir/app $APP_DIR
        chown -R $PANEL_USER:$PANEL_USER $APP_DIR
        log_success "Aplicação restaurada"
    fi
    
    # Restaurar banco de dados
    if [[ -f "$temp_dir/database.sqlite" ]]; then
        mkdir -p $DATA_DIR
        cp $temp_dir/database.sqlite $DATA_DIR/
        chown $PANEL_USER:$PANEL_USER $DATA_DIR/database.sqlite
        log_success "Banco de dados restaurado"
    fi
    
    # Restaurar configurações
    if [[ -f "$temp_dir/.env" ]]; then
        cp $temp_dir/.env $APP_DIR/
        chown $PANEL_USER:$PANEL_USER $APP_DIR/.env
        log_success "Configurações restauradas"
    fi
    
    # Restaurar configurações do Nginx
    if [[ -d "$temp_dir/nginx" ]]; then
        cp -r $temp_dir/nginx $PANEL_DIR/
        log_success "Configurações do Nginx restauradas"
    fi
    
    rm -rf $temp_dir
}

install_dependencies() {
    log_info "Instalando dependências..."
    
    cd $APP_DIR
    
    # Verificar se package.json existe
    if [[ ! -f "package.json" ]]; then
        log_error "package.json não encontrado"
        return 1
    fi
    
    # Instalar dependências
    if [[ -f "package-lock.json" ]]; then
        npm ci --production
    else
        npm install --production
    fi
    
    log_success "Dependências instaladas"
}

run_database_migrations() {
    log_info "Executando migrações do banco de dados..."
    
    cd $APP_DIR
    
    # Verificar se há script de migração
    if npm run | grep -q "migrate"; then
        npm run migrate
        log_success "Migrações executadas"
    else
        log_warning "Script de migração não encontrado"
    fi
}

start_application() {
    log_info "Iniciando aplicação..."
    
    cd $APP_DIR
    
    # Iniciar com PM2
    if [[ -f "ecosystem.config.js" ]]; then
        pm2 start ecosystem.config.js
    else
        pm2 start npm --name $PM2_APP_NAME -- start
    fi
    
    # Aguardar inicialização
    sleep 5
    
    log_success "Aplicação iniciada"
}

verify_application_health() {
    log_info "Verificando saúde da aplicação..."
    
    local attempts=0
    local max_attempts=$((HEALTH_CHECK_TIMEOUT / 5))
    
    while [[ $attempts -lt $max_attempts ]]; do
        if curl -f -s $HEALTH_CHECK_URL > /dev/null 2>&1; then
            log_success "Aplicação está respondendo corretamente"
            return 0
        fi
        
        ((attempts++))
        log_info "Tentativa $attempts/$max_attempts - Aguardando aplicação..."
        sleep 5
    done
    
    log_error "Aplicação não está respondendo após $HEALTH_CHECK_TIMEOUT segundos"
    return 1
}

show_rollback_summary() {
    local backup_file=$1
    local emergency_backup=$2
    
    log_success "=== Rollback Concluído ==="
    
    echo
    echo "Informações do Rollback:"
    echo "  Backup utilizado: $(basename $backup_file)"
    echo "  Backup de emergência: $emergency_backup"
    echo "  Versão atual: $(get_current_version)"
    echo "  Data/Hora: $(date)"
    echo
    
    # Mostrar status do PM2
    echo "Status do PM2:"
    pm2 list | grep $PM2_APP_NAME || echo "  Aplicação não encontrada no PM2"
    echo
    
    # Mostrar logs recentes
    echo "Logs recentes (últimas 10 linhas):"
    pm2 logs $PM2_APP_NAME --lines 10 --nostream 2>/dev/null || echo "  Logs não disponíveis"
}

interactive_rollback() {
    log_info "=== Rollback Interativo do G-Panel ==="
    
    # Mostrar versão atual
    echo "Versão atual: $(get_current_version)"
    echo
    
    # Listar backups disponíveis
    local available_backups=($(list_available_backups))
    
    if [[ ${#available_backups[@]} -eq 0 ]]; then
        log_error "Nenhum backup disponível"
        exit 1
    fi
    
    echo
    read -p "Selecione o número do backup para rollback (ou 'q' para sair): " selection
    
    if [[ "$selection" == "q" ]] || [[ "$selection" == "Q" ]]; then
        log_info "Rollback cancelado pelo usuário"
        exit 0
    fi
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [[ $selection -lt 1 ]] || [[ $selection -gt ${#available_backups[@]} ]]; then
        log_error "Seleção inválida"
        exit 1
    fi
    
    local selected_backup="$BACKUP_DIR/${available_backups[$((selection-1))]}"
    
    echo
    log_warning "ATENÇÃO: Esta operação irá:"
    echo "  1. Parar a aplicação atual"
    echo "  2. Criar um backup de emergência"
    echo "  3. Restaurar do backup selecionado"
    echo "  4. Reinstalar dependências"
    echo "  5. Reiniciar a aplicação"
    echo
    
    read -p "Tem certeza que deseja continuar? (sim/não): " confirm
    
    if [[ "$confirm" != "sim" ]] && [[ "$confirm" != "s" ]] && [[ "$confirm" != "yes" ]] && [[ "$confirm" != "y" ]]; then
        log_info "Rollback cancelado pelo usuário"
        exit 0
    fi
    
    perform_rollback "$selected_backup"
}

automated_rollback() {
    local backup_identifier=$1
    
    log_info "=== Rollback Automatizado do G-Panel ==="
    
    local backup_file=""
    
    # Procurar backup por nome ou padrão
    if [[ -f "$BACKUP_DIR/$backup_identifier" ]]; then
        backup_file="$BACKUP_DIR/$backup_identifier"
    elif [[ -f "$BACKUP_DIR/${backup_identifier}.tar.gz" ]]; then
        backup_file="$BACKUP_DIR/${backup_identifier}.tar.gz"
    else
        # Procurar por padrão (ex: latest, daily, weekly)
        case "$backup_identifier" in
            "latest")
                backup_file=$(ls -t $BACKUP_DIR/*.tar.gz 2>/dev/null | head -1)
                ;;
            "daily")
                backup_file=$(ls -t $BACKUP_DIR/daily_*.tar.gz 2>/dev/null | head -1)
                ;;
            "weekly")
                backup_file=$(ls -t $BACKUP_DIR/weekly_*.tar.gz 2>/dev/null | head -1)
                ;;
            "monthly")
                backup_file=$(ls -t $BACKUP_DIR/monthly_*.tar.gz 2>/dev/null | head -1)
                ;;
        esac
    fi
    
    if [[ -z "$backup_file" ]] || [[ ! -f "$backup_file" ]]; then
        log_error "Backup não encontrado: $backup_identifier"
        exit 1
    fi
    
    log_info "Backup selecionado: $(basename $backup_file)"
    perform_rollback "$backup_file"
}

perform_rollback() {
    local backup_file=$1
    
    log_info "Iniciando processo de rollback..."
    
    # Verificar pré-requisitos
    check_prerequisites
    
    # Verificar integridade do backup
    if ! verify_backup_integrity "$backup_file"; then
        log_error "Backup inválido, abortando rollback"
        exit 1
    fi
    
    # Criar backup de emergência
    local emergency_backup=$(create_emergency_backup)
    
    # Parar aplicação
    stop_application
    
    # Restaurar do backup
    restore_from_backup "$backup_file"
    
    # Instalar dependências
    install_dependencies
    
    # Executar migrações se necessário
    run_database_migrations
    
    # Iniciar aplicação
    start_application
    
    # Verificar saúde da aplicação
    if verify_application_health; then
        show_rollback_summary "$backup_file" "$emergency_backup"
    else
        log_error "Aplicação não está funcionando corretamente após rollback"
        log_warning "Considere restaurar do backup de emergência: $emergency_backup"
        exit 1
    fi
}

show_help() {
    echo "G-Panel Rollback Script"
    echo
    echo "Uso: $0 [comando] [opções]"
    echo
    echo "Comandos:"
    echo "  interactive           Rollback interativo (padrão)"
    echo "  auto <backup>         Rollback automatizado"
    echo "  list                  Listar backups disponíveis"
    echo "  verify <backup>       Verificar integridade de um backup"
    echo "  emergency <backup>    Restaurar do backup de emergência"
    echo "  help                  Mostrar esta ajuda"
    echo
    echo "Exemplos:"
    echo "  $0                                    # Rollback interativo"
    echo "  $0 interactive                       # Rollback interativo"
    echo "  $0 auto latest                       # Rollback para o backup mais recente"
    echo "  $0 auto daily_20231201_120000_abc123  # Rollback para backup específico"
    echo "  $0 auto daily                        # Rollback para o backup diário mais recente"
    echo "  $0 list                              # Listar backups"
    echo "  $0 verify backup_file.tar.gz         # Verificar backup"
    echo
    echo "Identificadores de backup suportados:"
    echo "  latest    - Backup mais recente"
    echo "  daily     - Backup diário mais recente"
    echo "  weekly    - Backup semanal mais recente"
    echo "  monthly   - Backup mensal mais recente"
    echo "  <nome>    - Nome específico do arquivo de backup"
}

# Função principal
main() {
    # Criar diretório de logs se não existir
    mkdir -p $(dirname $LOG_FILE)
    
    # Log do início
    echo "$(date -Iseconds) - Rollback iniciado por $(whoami)" >> $LOG_FILE
    
    case "${1:-interactive}" in
        "interactive"|"")
            interactive_rollback
            ;;
        "auto")
            if [[ -n "$2" ]]; then
                automated_rollback "$2"
            else
                log_error "Especifique o backup para rollback automatizado"
                exit 1
            fi
            ;;
        "list")
            list_available_backups > /dev/null
            ;;
        "verify")
            if [[ -n "$2" ]]; then
                verify_backup_integrity "$BACKUP_DIR/$2"
            else
                log_error "Especifique o arquivo de backup para verificar"
                exit 1
            fi
            ;;
        "emergency")
            if [[ -n "$2" ]]; then
                log_warning "Restaurando do backup de emergência: $2"
                perform_rollback "$BACKUP_DIR/$2"
            else
                log_error "Especifique o backup de emergência para restaurar"
                exit 1
            fi
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