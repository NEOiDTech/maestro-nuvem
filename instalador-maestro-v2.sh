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

check_docker_compose() {
    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
        error "Docker Compose não está instalado."
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
    # Verifica se Docker está instalado ANTES de qualquer operação
    if ! check_docker; then
        error "Docker não está instalado ou não está rodando."
        echo
        echo "Para instalar o Maestro, você precisa primeiro instalar o Docker."
        echo "Use a opção 1 do menu para instalar o Docker ou execute:"
        echo "  $0 install"
        echo
        read -p "Pressione ENTER para voltar ao menu..."
        return 1
    fi

    if ! check_git; then
        error "Git é necessário para instalar/atualizar o Maestro"
        echo "Instale o Git com: sudo apt-get install git"
        read -p "Pressione ENTER para voltar ao menu..."
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
        
        # Verifica se docker-compose está disponível
        if command -v docker-compose &>/dev/null; then
            docker-compose -f "$COMPOSE_FILE" up -d --build
        elif docker compose version &>/dev/null; then
            docker compose -f "$COMPOSE_FILE" up -d --build
        else
            error "Docker Compose não está disponível."
            echo "Instale o Docker Compose com a opção 1 do menu."
            read -p "Pressione ENTER para voltar ao menu..."
            return 1
        fi
        
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

# ... (o restante das funções permanece igual - check_health, status_maestro, etc.)

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
            1) 
                install_docker
                read -p "Pressione ENTER para voltar ao menu..." _ < /dev/tty
                ;;
            2) 
                install_or_update_maestro
                # Não precisa de read aqui pois a função já trata isso
                ;;
            3) 
                status_maestro
                read -p "Pressione ENTER para voltar ao menu..." _ < /dev/tty
                ;;
            4) 
                log "Executando verificação de saúde completa..."
                if check_health; then
                    success "Verificação de saúde concluída - sistema operacional normal"
                else
                    error "Problemas detectados na verificação de saúde"
                fi
                read -p "Pressione ENTER para voltar ao menu..." _ < /dev/tty
                ;;
            5) 
                stop_maestro
                read -p "Pressione ENTER para voltar ao menu..." _ < /dev/tty
                ;;
            6) 
                remove_container
                read -p "Pressione ENTER para voltar ao menu..." _ < /dev/tty
                ;;
            7) 
                remove_image
                read -p "Pressione ENTER para voltar ao menu..." _ < /dev/tty
                ;;
            8) 
                remove_docker
                read -p "Pressione ENTER para voltar ao menu..." _ < /dev/tty
                ;;
            9) 
                clean_volumes
                read -p "Pressione ENTER para voltar ao menu..." _ < /dev/tty
                ;;
            10) 
                echo "Saindo..."
                exit 0 
                ;;
            *) 
                echo "Opção inválida!"
                read -p "Pressione ENTER para voltar ao menu..." _ < /dev/tty
                ;;
        esac
    done
}

# -----------------------
# Execução por parâmetros
# -----------------------
case "${1:-}" in
    "" ) main_menu ;;
    install ) 
        install_docker
        install_or_update_maestro 
        ;;
    update ) 
        if check_docker; then
            install_or_update_maestro
        else
            error "Docker não está instalado. Use: $0 install"
            exit 1
        fi
        ;;
    status ) 
        if check_docker; then
            status_maestro
        else
            error "Docker não está instalado."
            exit 1
        fi
        ;;
    health ) 
        if check_docker; then
            if check_health; then
                echo "SAUDE: OK - Maestro funcionando corretamente"
                exit 0
            else
                echo "SAUDE: ERRO - Problemas detectados"
                exit 1
            fi
        else
            error "Docker não está instalado."
            exit 1
        fi
        ;;
    stop ) 
        if check_docker; then
            stop_maestro
        else
            error "Docker não está instalado."
            exit 1
        fi
        ;;
    remove ) 
        if check_docker; then
            remove_container
            remove_image
        else
            error "Docker não está instalado."
            exit 1
        fi
        ;;
    purge ) 
        if check_docker; then
            stop_maestro
            remove_container
            remove_image
            clean_volumes
            remove_docker
        else
            remove_docker
        fi
        ;;
    * ) 
        echo "Uso: $0 [install|update|status|health|stop|remove|purge]"
        exit 1 
        ;;
esac
