#!/bin/bash

# =========================================================
# Script: maestro-install-update.sh
# Funções:
#   - Instalar dependências (Docker e Docker Compose)
#   - Instalar ou atualizar Maestro Nuvem
#   - Status / Parar container
#   - Remover container/imagem
#   - Remover Docker completamente
#   - Menu interativo ou execução por parâmetros
#   - Verificação de saúde do container
# =========================================================

set -euo pipefail

REPO_URL="https://github.com/neoidtech/maestro-nuvem.git"
APP_DIR="$HOME/maestro-nuvem"
CONTAINER_NAME="maestro-nuvem"
HEALTH_CHECK_TIMEOUT=60
HEALTH_CHECK_INTERVAL=5

# -----------------------
# Funções de utilitário
# -----------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[ERRO] $1" >&2
}

success() {
    echo "✓ $1"
}

info() {
    echo "ℹ $1"
}

check_docker() {
    if ! command -v docker &>/dev/null; then
        error "Docker não está instalado."
        return 1
    fi
    
    # Verifica se o serviço docker está rodando
    if ! docker info >/dev/null 2>&1; then
        error "Docker não está rodando. Inicie o serviço com: sudo systemctl start docker"
        return 1
    fi
    
    return 0
}

check_git() {
    if ! command -v git &>/dev/null; then
        error "Git não está instalado."
        return 1
    fi
    return 0
}

# -----------------------
# Verificação de Saúde - CORRIGIDA
# -----------------------
check_health() {
    log "Iniciando verificação de saúde do container..."
    
    if ! check_docker; then
        error "Docker não disponível para verificação de saúde"
        return 1
    fi

    # Verifica se o container existe
    if ! docker ps -a --format '{{.Names}}' | grep -Eq "^$CONTAINER_NAME\$"; then
        error "Container '$CONTAINER_NAME' não encontrado"
        return 1
    fi

    # Verifica se o container está rodando
    if ! docker ps --filter "name=${CONTAINER_NAME}" --filter "status=running" | grep -q "${CONTAINER_NAME}"; then
        error "Container '$CONTAINER_NAME' não está em execução"
        docker ps -a --filter "name=${CONTAINER_NAME}"
        return 1
    fi

    success "Container está em execução"
    
    # Verifica saúde do container via Docker (sem tratar como erro se não houver health check)
    local container_status
    container_status=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "no-health-check")
    
    case "$container_status" in
        "healthy")
            success "Container reporta status HEALTHY"
            ;;
        "unhealthy")
            error "Container reporta status UNHEALTHY"
            # Mostra os últimos logs para ajudar no diagnóstico
            log "Últimos logs do container:"
            docker logs "$CONTAINER_NAME" --tail 15 2>&1
            return 1
            ;;
        "starting")
            info "Container ainda está iniciando"
            ;;
        "no-health-check")
            info "Container não possui health check configurado - usando verificações manuais"
            ;;
        *)
            info "Container status: $container_status"
            ;;
    esac

    echo
    log "Realizando verificações manuais..."

    # Verifica logs recentes por erros
    local recent_logs
    recent_logs=$(docker logs "$CONTAINER_NAME" --tail 25 2>&1)
    
    local error_count
    error_count=$(echo "$recent_logs" | grep -i "error\|exception\|failed" | wc -l)
    
    if [ "$error_count" -gt 0 ]; then
        error "Foram encontrados $error_count erro(s) nos logs do container:"
        echo "$recent_logs" | grep -i "error\|exception\|failed" | head -8
    else
        success "Logs do container estão limpos"
    fi

    # Verifica consumo de recursos
    local container_stats
    container_stats=$(docker stats "$CONTAINER_NAME" --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" | tail -1)
    info "Consumo de recursos: $container_stats"

    # Verifica se a aplicação responde (porta 8080)
    log "Testando conectividade na porta 8080..."
    if command -v curl &>/dev/null; then
        local http_status
        local response_time
        
        # Testa com timeout de 10 segundos
        if http_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://localhost:8080"); then
            success "Aplicação respondendo na porta 8080 (HTTP: $http_status)"
            
            # Teste adicional para verificar se é uma aplicação web
            if response_content=$(curl -s --max-time 10 "http://localhost:8080"); then
                if echo "$response_content" | grep -q "<html\|<!DOCTYPE\|React\|Vue\|Angular"; then
                    success "Resposta HTML/JavaScript detectada - aplicação web funcionando"
                else
                    info "Resposta não-HTML recebida (pode ser API ou outro tipo de serviço)"
                fi
            fi
            
        else
            error "Aplicação não responde na porta 8080 ou demorou muito"
            
            # Verifica se a porta está sendo ouvida
            if command -v netstat &>/dev/null; then
                if netstat -tuln | grep -q ":8080 "; then
                    info "Porta 8080 está sendo ouvida, mas a aplicação não responde"
                else
                    error "Porta 8080 não está sendo ouvida"
                fi
            fi
            return 1
        fi
    else
        info "curl não disponível, pulando teste de conectividade HTTP"
        
        # Fallback: verifica se a porta está aberta
        if command -v nc &>/dev/null; then
            if nc -z localhost 8080 &>/dev/null; then
                success "Porta 8080 está aberta e aceitando conexões"
            else
                error "Porta 8080 não está aceitando conexões"
                return 1
            fi
        fi
    fi

    # Verifica processos dentro do container
    log "Verificando processos no container..."
    local process_count
    process_count=$(docker top "$CONTAINER_NAME" 2>/dev/null | wc -l)
    if [ "$process_count" -gt 1 ]; then
        success "Container possui $((process_count-1)) processo(s) em execução"
    else
        error "Container não possui processos em execução"
        return 1
    fi

    echo
    success "Verificação de saúde concluída com sucesso!"
    info "O Maestro está funcionando corretamente na porta 8080"
    return 0
}

wait_for_healthy() {
    log "Aguardando container ficar healthy (timeout: ${HEALTH_CHECK_TIMEOUT}s)..."
    
    local start_time=$(date +%s)
    local health_check_configured=false
    
    # Verifica se o container tem health check configurado
    if docker inspect --format='{{.State.Health}}' "$CONTAINER_NAME" 2>/dev/null | grep -q "Health"; then
        health_check_configured=true
    fi
    
    if [ "$health_check_configured" = "false" ]; then
        info "Container não possui health check configurado - aguardando tempo fixo"
        sleep 20
        return 0
    fi
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -gt $HEALTH_CHECK_TIMEOUT ]; then
            error "Timeout atingido aguardando container ficar healthy"
            return 1
        fi
        
        local health_status
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "starting")
        
        case "$health_status" in
            "healthy")
                success "Container está healthy!"
                return 0
                ;;
            "unhealthy")
                error "Container está unhealthy"
                docker logs "$CONTAINER_NAME" --tail 10
                return 1
                ;;
            *)
                info "Container status: $health_status - Aguardando... ($elapsed/${HEALTH_CHECK_TIMEOUT}s)"
                sleep $HEALTH_CHECK_INTERVAL
                ;;
        esac
    done
}

# ... (o restante das funções permanece igual - install_docker, install_or_update_maestro, etc.)

# -----------------------
# Menu - ATUALIZADO
# -----------------------
main_menu() {
    while true; do
        clear
        show_banner
        echo "===================================================================="
        echo "1) Instalar Docker"
        echo "2) Instalar/Atualizar Maestro"
        echo "3) Status do Maestro"
        echo "4) Verificar Saúde do Maestro"
        echo "5) Parar Maestro"
        echo "6) Remover container"
        echo "7) Remover imagem"
        echo "8) Remover Docker completamente"
        echo "9) Limpar volumes órfãos"
        echo "10) Sair"
        echo "--------------------------------------------------------------------"
        read -p "Escolha uma opção [1-10]: " opt < /dev/tty

        clear
        show_banner
        case "$opt" in
            1) install_docker ;;
            2) install_or_update_maestro ;;
            3) status_maestro ;;
            4) 
                log "Executando verificação de saúde completa..."
                if check_health; then
                    success "Verificação de saúde concluída - sistema operacional normal"
                else
                    error "Problemas detectados na verificação de saúde"
                fi
                ;;
            5) stop_maestro ;;
            6) remove_container ;;
            7) remove_image ;;
            8) remove_docker ;;
            9) clean_volumes ;;
            10) echo "Saindo..."; exit 0 ;;
            *) echo "Opção inválida!" ;;
        esac

        echo
        read -p ">>> Pressione ENTER para voltar ao menu..." _ < /dev/tty
    done
}

# -----------------------
# Execução por parâmetros - ATUALIZADO
# -----------------------
case "${1:-}" in
    "" ) main_menu ;;
    install ) install_docker; install_or_update_maestro ;;
    update ) install_or_update_maestro ;;
    status ) status_maestro ;;
    health ) 
        if check_health; then
            echo "SAUDE: OK - Maestro funcionando corretamente"
            exit 0
        else
            echo "SAUDE: ERRO - Problemas detectados"
            exit 1
        fi
        ;;
    stop ) stop_maestro ;;
    remove ) remove_container; remove_image ;;
    purge ) stop_maestro; remove_container; remove_image; clean_volumes; remove_docker ;;
    * ) echo "Uso: $0 [install|update|status|health|stop|remove|purge]"; exit 1 ;;
esac
