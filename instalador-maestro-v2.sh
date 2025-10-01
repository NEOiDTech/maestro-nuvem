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
# Funções principais
# -----------------------

install_docker() {
    log "Instalando Docker e dependências..."
    
    if ! command -v docker &>/dev/null; then
        log "Instalando Docker..."
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker $USER
        sudo systemctl enable docker
        sudo systemctl start docker
        log "Docker instalado com sucesso"
        echo ">>> Nota: Você precisa fazer logout e login novamente para usar Docker sem sudo"
    else
        log "Docker já está instalado."
    fi

    if ! command -v docker-compose &>/dev/null; then
        log "Instalando Docker Compose..."
        local COMPOSE_VERSION
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
        sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        log "Docker Compose ${COMPOSE_VERSION} instalado"
    else
        log "Docker Compose já está instalado."
    fi
}

install_or_update_maestro() {
    if ! check_git; then
        error "Git é necessário para instalar/atualizar o Maestro"
        return 1
    fi

    log "Instalando ou atualizando Maestro..."

    if [ -d "$APP_DIR" ]; then
        log "Atualizando repositório existente..."
        cd "$APP_DIR" || exit 1
        git pull
    else
        log "Clonando repositório..."
        git clone "$REPO_URL" "$APP_DIR"
        cd "$APP_DIR" || exit 1
    fi

    log "Procurando arquivo docker-compose..."
    local COMPOSE_FILE=""

    for file in docker-compose.yml docker-compose.yaml compose.yaml compose.yml; do
        if [ -f "$file" ]; then
            COMPOSE_FILE="$file"
            break
        fi
    done

    if [ -n "$COMPOSE_FILE" ]; then
        log "Arquivo de compose encontrado: $COMPOSE_FILE"
        docker compose -f "$COMPOSE_FILE" up -d --build
        log "Maestro iniciado com docker-compose"
    else
        log "Nenhum arquivo de compose encontrado. Usando fallback com docker run..."
        
        # Parar e remover container antigo
        if docker ps -a --format '{{.Names}}' | grep -Eq "^$CONTAINER_NAME\$"; then
            log "Parando container antigo..."
            docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
            log "Removendo container antigo..."
            docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
        fi

        log "Baixando imagem mais recente do Maestro..."
        docker pull neoidtech/maestro:latest

        log "Subindo novo container..."
        docker run -d \
            --name "$CONTAINER_NAME" \
            --restart unless-stopped \
            -p 8080:8080 \
            neoidtech/maestro:latest
        
        log "Maestro iniciado com docker run"
    fi
    
    # Executar verificação de saúde após instalação/atualização
    log "Aguardando container iniciar..."
    sleep 10
    check_health
}

# -----------------------
# Verificação de Saúde
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

    log "Container está em execução. Verificando saúde..."
    
    # Verifica logs recentes por erros
    local recent_logs
    recent_logs=$(docker logs "$CONTAINER_NAME" --tail 20 2>&1)
    
    if echo "$recent_logs" | grep -i "error\|exception\|failed" | head -5; then
        error "Foram encontrados erros nos logs do container:"
        echo "$recent_logs" | grep -i "error\|exception\|failed" | head -5
    else
        log "✓ Logs do container estão limpos"
    fi

    # Verifica consumo de recursos
    local container_stats
    container_stats=$(docker stats "$CONTAINER_NAME" --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}" | tail -1)
    log "Consumo de recursos: $container_stats"

    # Verifica se a aplicação responde (porta 8080)
    log "Testando conectividade na porta 8080..."
    if command -v curl &>/dev/null; then
        local health_response
        if health_response=$(curl -s -f "http://localhost:8080" || health_response=$(curl -s -f "http://127.0.0.1:8080")); then
            log "✓ Aplicação respondendo na porta 8080"
            
            # Verifica se é uma resposta HTML (indicando aplicação web)
            if echo "$health_response" | grep -q "<html\|<!DOCTYPE"; then
                log "✓ Resposta HTML detectada - aplicação web parece funcionar"
            fi
        else
            error "✗ Aplicação não responde na porta 8080"
            return 1
        fi
    else
        log "curl não disponível, pulando teste de conectividade HTTP"
    fi

    # Verifica saúde do container via Docker
    local container_status
    container_status=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "no-health-check")
    
    if [ "$container_status" = "healthy" ]; then
        log "✓ Container reporta status HEALTHY"
    elif [ "$container_status" = "no-health-check" ]; then
        log "ℹ Container não possui health check configurado"
    else
        error "Container reporta status: $container_status"
        return 1
    fi

    log "✓ Verificação de saúde concluída com sucesso"
    return 0
}

wait_for_healthy() {
    log "Aguardando container ficar healthy (timeout: ${HEALTH_CHECK_TIMEOUT}s)..."
    
    local start_time=$(date +%s)
    
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
                log "✓ Container está healthy!"
                return 0
                ;;
            "unhealthy")
                error "Container está unhealthy"
                docker logs "$CONTAINER_NAME" --tail 10
                return 1
                ;;
            *)
                log "Container status: $health_status - Aguardando..."
                sleep $HEALTH_CHECK_INTERVAL
                ;;
        esac
    done
}

# -----------------------
# Outras ações
# -----------------------
status_maestro() {
    if ! check_docker; then
        error "Docker não está instalado ou não está rodando."
        return 1
    fi
    
    log "Status dos containers:"
    docker ps --filter "name=${CONTAINER_NAME}" || true
    
    echo
    log "Informações detalhadas do container:"
    docker inspect "$CONTAINER_NAME" 2>/dev/null | jq -r '.[] | {Name: .Name, State: .State.Status, Running: .State.Running, Health: .State.Health.Status, IP: .NetworkSettings.IPAddress, Ports: .NetworkSettings.Ports}' || \
        echo "Container não encontrado ou jq não instalado"
    
    echo
    log "Últimos logs do container:"
    docker logs "$CONTAINER_NAME" --tail 10 2>&1 || echo "Não foi possível acessar os logs"
}

stop_maestro() {
    if ! check_docker; then
        error "Docker não está instalado ou não está rodando."
        return 1
    fi
    
    log "Parando container ${CONTAINER_NAME}..."
    docker stop "${CONTAINER_NAME}" 2>/dev/null || echo "Nenhum container em execução com esse nome."
}

remove_container() {
    if ! check_docker; then
        error "Docker não está instalado ou não está rodando."
        return 1
    fi
    
    log "Removendo container ${CONTAINER_NAME}..."
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || echo "Nenhum container encontrado."
}

remove_image() {
    if ! check_docker; then
        error "Docker não está instalado ou não está rodando."
        return 1
    fi
    
    log "Removendo imagens relacionadas ao Maestro..."
    local IMG_IDS
    IMG_IDS=$(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep -E 'maestro|neoid|reustaquiojr' | awk '{print $2}' || true)
    
    if [ -n "${IMG_IDS}" ]; then
        echo "Imagens encontradas para remoção:"
        docker images | grep -E 'maestro|neoid|reustaquiojr' || true
        read -p "Confirma remoção destas imagens? (s/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            docker rmi -f ${IMG_IDS} || true
            log "Imagens removidas."
        else
            log "Remoção cancelada."
        fi
    else
        log "Nenhuma imagem automática encontrada."
    fi
}

remove_docker() {
    log "Removendo Docker e todos os dados..."
    
    if command -v docker &>/dev/null; then
        sudo systemctl stop docker docker.socket containerd 2>/dev/null || true
    fi
    
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    sudo apt-get purge -y docker-ce docker-ce-cli containerd.io 2>/dev/null || true
    sudo apt-get autoremove -y --purge 2>/dev/null || true
    sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker
    sudo rm -f /etc/apt/sources.list.d/docker.list
    
    log "Docker removido completamente."
    log "AVISO: Todos os containers, imagens e volumes foram perdidos."
}

clean_volumes() {
    if ! check_docker; then
        error "Docker não está instalado ou não está rodando."
        return 1
    fi
    
    log "Limpando volumes órfãos..."
    read -p "Isso removerá todos os volumes não utilizados. Continuar? (s/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        docker volume prune -f
        log "Volumes limpos."
    else
        log "Operação cancelada."
    fi
}

# -----------------------
# Banner
# -----------------------
show_banner() {
cat <<'EOF'
  _  _ ___ ___  _ ___                                                
 | \| | __/ _ \(_)   \                                               
 | .` | _| (_) | | |) |                                              
 |_|\_|___\___/|_|___/ _____ ___  ___    _  _ _   ___   _____ __  __ 
 |  \/  | /_\ | __/ __|_   _| _ \/ _ \  | \| | | | \ \ / / __|  \/  |
 | |\/| |/ _ \| _|\__ \ | | |   / (_) | | .` | |_| |\ V /| _|| |\/| |
 |_|  |_/_/ \_\___|___/ |_| |_|_\\___/  |_|\_|\___/  \_/ |___|_|  |_| 
EOF
echo
}

# -----------------------
# Menu
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
            4) check_health ;;
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
# Execução por parâmetros
# -----------------------
case "${1:-}" in
    "" ) main_menu ;;
    install ) install_docker; install_or_update_maestro ;;
    update ) install_or_update_maestro ;;
    status ) status_maestro ;;
    health ) check_health ;;
    stop ) stop_maestro ;;
    remove ) remove_container; remove_image ;;
    purge ) stop_maestro; remove_container; remove_image; clean_volumes; remove_docker ;;
    * ) echo "Uso: $0 [install|update|status|health|stop|remove|purge]"; exit 1 ;;
esac
