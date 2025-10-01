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
# =========================================================

set -euo pipefail

REPO_URL="https://github.com/neoidtech/maestro-nuvem.git"
APP_DIR="$HOME/maestro-nuvem"
CONTAINER_NAME="maestro-nuvem"

# -----------------------
# Funções principais
# -----------------------

install_docker() {
    echo ">>> Instalando Docker e dependências..."
    if ! command -v docker &>/dev/null; then
        curl -fsSL https://get.docker.com | sh
        sudo systemctl enable docker
        sudo systemctl start docker
    else
        echo "Docker já está instalado."
    fi

    if ! command -v docker-compose &>/dev/null; then
        echo ">>> Instalando Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    else
        echo "Docker Compose já está instalado."
    fi
}

install_or_update_maestro() {
    echo ">>> Instalando ou atualizando Maestro..."

    if [ -d "$REPO_DIR" ]; then
        echo ">>> Atualizando repositório existente..."
        cd "$REPO_DIR" || exit 1
        git pull
    else
        echo ">>> Clonando repositório..."
        git clone "$REPO_URL" "$REPO_DIR"
        cd "$REPO_DIR" || exit 1
    fi

    echo ">>> Procurando arquivo docker-compose..."

    # Detecta possíveis arquivos de compose
    for file in docker-compose.yml docker-compose.yaml compose.yaml compose.yml; do
        if [ -f "$file" ]; then
            COMPOSE_FILE="$file"
            break
        fi
    done

    if [ -n "$COMPOSE_FILE" ]; then
        echo ">>> Arquivo de compose encontrado: $COMPOSE_FILE"
        docker compose -f "$COMPOSE_FILE" up -d
    else
        echo ">>> Nenhum arquivo de compose encontrado. Usando fallback com docker run..."
        
        # Parar e remover container antigo
        if docker ps -a --format '{{.Names}}' | grep -Eq "^$CONTAINER_NAME\$"; then
            echo ">>> Parando container antigo..."
            docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
            echo ">>> Removendo container antigo..."
            docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
        fi

        echo ">>> Baixando imagem mais recente do Maestro..."
        docker pull neoidtech/maestro:latest

        echo ">>> Subindo novo container..."
        docker run -d \
            --name "$CONTAINER_NAME" \
            --restart unless-stopped \
            -p 8080:8080 \
            neoidtech/maestro:latest
    fi
}
# -----------------------
# Outras ações
# -----------------------
status_maestro() {
    if ! command -v docker &>/dev/null; then
        echo "Docker não está instalado."
        return 0
    fi
    echo ">>> Status dos containers:"
    docker ps --filter "name=${CONTAINER_NAME}" || true
}

stop_maestro() {
    if ! command -v docker &>/dev/null; then
        echo "Docker não está instalado."
        return 0
    fi
    echo ">>> Parando container ${CONTAINER_NAME}..."
    docker stop "${CONTAINER_NAME}" 2>/dev/null || echo "Nenhum container em execução com esse nome."
}

remove_container() {
    if ! command -v docker &>/dev/null; then
        echo "Docker não está instalado."
        return 0
    fi
    echo ">>> Removendo container ${CONTAINER_NAME}..."
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || echo "Nenhum container encontrado."
}

remove_image() {
    if ! command -v docker &>/dev/null; then
        echo "Docker não está instalado."
        return 0
    fi
    echo ">>> Removendo imagens relacionadas ao Maestro (se encontradas)..."
    local IMG_IDS
    IMG_IDS="$(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep -E 'maestro|neoid|reustaquiojr' | awk '{print $2}' || true)"
    if [ -n "${IMG_IDS}" ]; then
        docker rmi -f ${IMG_IDS} || true
        echo "Imagens removidas."
    else
        echo "Nenhuma imagem automática encontrada."
    fi
}

remove_docker() {
    echo ">>> Removendo Docker e todos os dados..."
    if command -v docker &>/dev/null; then
        sudo systemctl stop docker docker.socket || true
    fi
    sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
    sudo apt-get purge -y docker-ce docker-ce-cli containerd.io || true
    sudo apt-get autoremove -y --purge || true
    sudo rm -rf /var/lib/docker /var/lib/containerd
    echo "Docker removido."
}

clean_volumes() {
    if ! command -v docker &>/dev/null; then
        echo "Docker não está instalado."
        return 0
    fi
    echo ">>> Limpando volumes órfãos..."
    docker volume prune -f || true
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
        echo "4) Parar Maestro"
        echo "5) Remover container"
        echo "6) Remover imagem"
        echo "7) Remover Docker completamente"
        echo "8) Limpar volumes órfãos"
        echo "9) Sair"
        echo "--------------------------------------------------------------------"
        read -p "Escolha uma opção [1-9]: " opt < /dev/tty

        clear
        show_banner
        case "$opt" in
            1) install_docker ;;
            2) install_or_update_maestro ;;
            3) status_maestro ;;
            4) stop_maestro ;;
            5) remove_container ;;
            6) remove_image ;;
            7) remove_docker ;;
            8) clean_volumes ;;
            9) echo "Saindo..."; exit 0 ;;
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
    stop ) stop_maestro ;;
    remove ) remove_container; remove_image ;;
    purge ) stop_maestro; remove_container; remove_image; clean_volumes; remove_docker ;;
    * ) echo "Uso: $0 [install|update|status|stop|remove|purge]"; exit 1 ;;
esac
