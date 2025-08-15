#!/bin/bash

# G-Panel Enterprise Deploy Script
# Deploy automático com backup, rollback e zero downtime

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
LOG_FILE="$PANEL_DIR/logs/deploy.log"
MAX_ROLLBACK_VERSIONS=5
HEALTH_CHECK_TIMEOUT=60
HEALTH_CHECK_INTERVAL=5

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

check_prerequisites() {
    log_info "Verificando pré-requisitos..."
    
    # Verificar se está rodando como root ou usuário correto
    if [[ $EUID -eq 0 ]]; then
        log_warning "Rodando como root, mudando para usuário $PANEL_USER"
        exec sudo -u $PANEL_USER "$0" "$@"
    fi
    
    # Verificar se diretórios existem
    if [[ ! -d "$APP_DIR" ]]; then
        log_error "Diretório da aplicação não encontrado: $APP_DIR"
        exit 1
    fi
    
    # Verificar se PM2 está instalado
    if ! command -v pm2 &> /dev/null; then
        log_error "PM2 não está instalado"
        exit 1
    fi
    
    # Verificar se Git está disponível
    if ! command -v git &> /dev/null; then
        log_error "Git não está instalado"
        exit 1
    fi
    
    log_success "Pré-requisitos verificados"
}

get_current_version() {
    cd $APP_DIR
    git rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

get_current_branch() {
    cd $APP_DIR
    git branch --show-current 2>/dev/null || echo "unknown"
}

create_backup() {
    log_info "Criando backup da versão atual..."
    
    local current_version=$(get_current_version)
    local backup_name="backup_${current_version}_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    # Criar diretório de backup
    mkdir -p $backup_path
    
    # Backup do código
    cp -r $APP_DIR $backup_path/app
    
    # Backup do banco de dados
    if [[ -f "$PANEL_DIR/data/database.sqlite" ]]; then
        cp $PANEL_DIR/data/database.sqlite $backup_path/database.sqlite
    fi
    
    # Backup das configurações
    if [[ -f "$APP_DIR/.env" ]]; then
        cp $APP_DIR/.env $backup_path/.env
    fi
    
    # Salvar informações do backup
    cat > $backup_path/backup_info.json << EOF
{
  "version": "$current_version",
  "branch": "$(get_current_branch)",
  "timestamp": "$(date -Iseconds)",
  "backup_name": "$backup_name",
  "pm2_status": $(pm2 jlist | jq '.[0]' 2>/dev/null || echo 'null')
}
EOF
    
    # Comprimir backup
    cd $BACKUP_DIR
    tar -czf "${backup_name}.tar.gz" $backup_name
    rm -rf $backup_name
    
    log_success "Backup criado: ${backup_name}.tar.gz"
    echo $backup_name
}

cleanup_old_backups() {
    log_info "Limpando backups antigos..."
    
    cd $BACKUP_DIR
    
    # Manter apenas os últimos N backups
    ls -t backup_*.tar.gz 2>/dev/null | tail -n +$((MAX_ROLLBACK_VERSIONS + 1)) | xargs -r rm -f
    
    log_success "Backups antigos removidos"
}

health_check() {
    log_info "Verificando saúde da aplicação..."
    
    local timeout=$HEALTH_CHECK_TIMEOUT
    local interval=$HEALTH_CHECK_INTERVAL
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        if curl -f -s http://localhost:3000/health > /dev/null 2>&1; then
            log_success "Aplicação está saudável"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        log_info "Aguardando aplicação... ($elapsed/${timeout}s)"
    done
    
    log_error "Aplicação não respondeu no tempo esperado"
    return 1
}

update_code() {
    log_info "Atualizando código..."
    
    cd $APP_DIR
    
    # Verificar se há mudanças locais
    if ! git diff --quiet; then
        log_warning "Há mudanças locais não commitadas"
        git stash push -m "Auto-stash before deploy $(date -Iseconds)"
    fi
    
    # Fetch latest changes
    git fetch origin
    
    # Get current and latest commit
    local current_commit=$(git rev-parse HEAD)
    local latest_commit=$(git rev-parse origin/$(get_current_branch))
    
    if [[ "$current_commit" == "$latest_commit" ]]; then
        log_info "Código já está atualizado"
        return 1  # Não há atualizações
    fi
    
    # Pull latest changes
    git pull origin $(get_current_branch)
    
    log_success "Código atualizado para $(get_current_version)"
    return 0  # Há atualizações
}

update_dependencies() {
    log_info "Verificando dependências..."
    
    cd $APP_DIR
    
    # Verificar se package.json mudou
    if git diff --name-only HEAD~1 HEAD | grep -q package.json; then
        log_info "package.json foi modificado, atualizando dependências..."
        npm ci --production
        log_success "Dependências atualizadas"
    else
        log_info "Nenhuma mudança nas dependências"
    fi
}

run_migrations() {
    log_info "Executando migrações..."
    
    cd $APP_DIR
    
    # Verificar se há script de migração
    if npm run | grep -q "migrate"; then
        npm run migrate
        log_success "Migrações executadas"
    else
        log_info "Nenhuma migração encontrada"
    fi
}

restart_application() {
    log_info "Reiniciando aplicação..."
    
    # Graceful restart com PM2
    pm2 reload g-panel --wait-ready --listen-timeout 10000
    
    # Aguardar um pouco para estabilizar
    sleep 5
    
    log_success "Aplicação reiniciada"
}

rollback_on_failure() {
    local backup_name=$1
    
    log_error "Deploy falhou, iniciando rollback..."
    
    if [[ -n "$backup_name" ]]; then
        $PANEL_DIR/scripts/rollback.sh $backup_name
    else
        log_error "Nenhum backup disponível para rollback"
    fi
}

send_notification() {
    local status=$1
    local version=$2
    local message=$3
    
    # Aqui você pode adicionar notificações (Slack, Discord, email, etc.)
    log_info "Notificação: Deploy $status - Versão $version - $message"
    
    # Exemplo para webhook do Discord/Slack:
    # curl -X POST -H 'Content-type: application/json' \
    #   --data "{\"text\":\"Deploy $status - Versão $version - $message\"}" \
    #   $WEBHOOK_URL
}

show_deploy_info() {
    log_info "Informações do deploy:"
    echo "  • Versão atual: $(get_current_version)"
    echo "  • Branch: $(get_current_branch)"
    echo "  • Status PM2: $(pm2 describe g-panel | grep status | awk '{print $4}')"
    echo "  • Uptime: $(pm2 describe g-panel | grep uptime | awk '{print $3}')"
    echo "  • Memória: $(pm2 describe g-panel | grep memory | awk '{print $3}')"
    echo "  • CPU: $(pm2 describe g-panel | grep cpu | awk '{print $3}')"
}

# Função principal de deploy
deploy() {
    local force_deploy=${1:-false}
    
    log_info "=== Iniciando Deploy do G-Panel ==="
    
    check_prerequisites
    
    # Criar backup antes de qualquer mudança
    local backup_name=$(create_backup)
    
    # Verificar se há atualizações
    if ! update_code && [[ "$force_deploy" != "true" ]]; then
        log_info "Nenhuma atualização disponível"
        cleanup_old_backups
        return 0
    fi
    
    local new_version=$(get_current_version)
    
    # Trap para rollback em caso de erro
    trap "rollback_on_failure $backup_name" ERR
    
    # Atualizar dependências se necessário
    update_dependencies
    
    # Executar migrações
    run_migrations
    
    # Reiniciar aplicação
    restart_application
    
    # Verificar se aplicação está funcionando
    if ! health_check; then
        log_error "Health check falhou após deploy"
        rollback_on_failure $backup_name
        exit 1
    fi
    
    # Limpar trap de erro
    trap - ERR
    
    # Limpeza de backups antigos
    cleanup_old_backups
    
    # Mostrar informações
    show_deploy_info
    
    # Enviar notificação de sucesso
    send_notification "SUCCESS" $new_version "Deploy realizado com sucesso"
    
    log_success "=== Deploy concluído com sucesso ==="
    log_info "Versão: $new_version"
    log_info "Backup: $backup_name"
}

# Função para deploy forçado
force_deploy() {
    deploy true
}

# Função para mostrar status
status() {
    log_info "=== Status do G-Panel ==="
    show_deploy_info
    
    echo
    log_info "Últimos logs:"
    pm2 logs g-panel --lines 10 --nostream
}

# Função para mostrar ajuda
show_help() {
    echo "G-Panel Deploy Script"
    echo
    echo "Uso: $0 [comando]"
    echo
    echo "Comandos:"
    echo "  deploy        Deploy normal (apenas se houver atualizações)"
    echo "  force-deploy  Deploy forçado (mesmo sem atualizações)"
    echo "  status        Mostrar status da aplicação"
    echo "  help          Mostrar esta ajuda"
    echo
    echo "Exemplos:"
    echo "  $0 deploy"
    echo "  $0 force-deploy"
    echo "  $0 status"
}

# Função principal
main() {
    # Criar diretório de logs se não existir
    mkdir -p $(dirname $LOG_FILE)
    
    # Log do início
    echo "$(date -Iseconds) - Deploy iniciado por $(whoami)" >> $LOG_FILE
    
    case "${1:-deploy}" in
        "deploy")
            deploy
            ;;
        "force-deploy")
            force_deploy
            ;;
        "status")
            status
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