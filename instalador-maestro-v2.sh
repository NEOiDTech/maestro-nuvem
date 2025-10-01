#!/bin/bash

# =========================================================
# Script: maestro-install-update.sh
# Funções:
#   - Instalar dependências (Docker e Docker Compose)
#   - Instalar ou atualizar Maestro Nuvem
#   - Status / Parar container
#   - Remover container/imagem
#   - Remover Docker completamente
#   - Menu interativo
# =========================================================

set -e

REPO_URL="https://github.com/reustaquiojr/maestro-nuvem.git"
APP_DIR="$HOME/maestro-nuvem"
CONTAINER_NAME="maestro-nuvem"

# ---- Funções ----

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
    if [ -d "$APP_DIR" ]; then
        echo ">>> Atualizando repositório existente..."
        cd "$APP_DIR"
        git pull
    else
        echo ">>> Clonando repositório..."
        git clone "$REPO_URL" "$APP_DIR"
        cd "$APP_DIR"
    fi

    echo ">>> Subindo containers..."
    docker compose pull
    docker compose up -d
}

status_maestro() {
    echo ">>> Status dos containers:"
    docker ps --filter "name=$CONTAINER_NAME"
}

stop_maestro() {
    echo ">>> Parando container $CONTAINER_NAME..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || echo "Nenhum container encontrado."
}

remove_container() {
    echo ">>> Removendo container $CONTAINER_NAME..."
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || echo "Nenhum container encontrado."
}

remove_image() {
    echo ">>> Removendo imagem do Maestro..."
    IMAGE_ID=$(docker images -q reustaquiojr/maestro-nuvem)
    if [ -n "$IMAGE_ID" ]; then
        docker rmi -f "$IMAGE_ID"
    else
        echo "Nenhuma imagem encontrada."
    fi
}

remove_docker() {
    echo ">>> Removendo Docker e todos os dados..."
    sudo systemctl stop docker docker.socket || true
    sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
    sudo apt-get purge -y docker-ce docker-ce-cli containerd.io || true
    sudo rm -rf /var/lib/docker /var/lib/containerd
    echo "Docker removido."
}

clean_volumes() {
    echo ">>> Limpando volumes órfãos..."
    docker volume prune -f
}

# ---- Menu ----

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

main_menu() {
    while true; do
        clear
        show_banner
        echo "======================================"
        echo "         NEOiD MAESTRO Nuvem          "
        echo "======================================"
        echo "1) Instalar Docker"
        echo "2) Instalar/Atualizar Maestro"
        echo "3) Status do Maestro"
        echo "4) Parar Maestro"
        echo "5) Remover container"
        echo "6) Remover imagem"
        echo "7) Remover Docker completamente"
        echo "8) Limpar volumes órfãos"
        echo "9) Sair"
        echo "--------------------------------------"
        read -rp "Escolha uma opção: " option

        clear
        show_banner
        case $option in
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
        read -rp ">>> Pressione ENTER para voltar ao menu..." _
    done
}

# ---- Execução por parâmetros ----
case "$1" in
    "" ) main_menu ;;
    install ) install_docker; install_or_update_maestro ;;
    update ) install_or_update_maestro ;;
    status ) status_maestro ;;
    stop ) stop_maestro ;;
    remove ) remove_container; remove_image ;;
    purge ) stop_maestro; remove_container; remove_image; clean_volumes; remove_docker ;;
    * ) echo "Uso: $0 [install|update|status|stop|remove|purge]"; exit 1 ;;
esac
