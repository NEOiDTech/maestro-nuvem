#!/bin/bash

# =========================================================
# Script: maestro-install-update.sh
# Funções:
#   - Instalar dependências (Docker e Docker Compose)
#   - Instalar ou atualizar Maestro Nuvem
#   - Status / Parar container
#   - Remover container/imagem
#   - Remover Docker completamente
#   - Menu interativo (funciona com curl | bash -s --)
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
        git pull --ff-only || git pull
    else
        echo ">>> Clonando repositório..."
        git clone "$REPO_URL" "$APP_DIR"
        cd "$APP_DIR"
    fi

    echo ">>> Subindo containers (docker compose)..."
    # tenta usar 'docker compose' (plugin) e, se não existir, tenta 'docker-compose'
    if docker compose version &>/dev/null; then
        docker compose pull || true
        docker compose up -d
    else
        docker-compose pull || true
        docker-compose up -d
    fi
}

status_maestro() {
    echo ">>> Status dos containers:"
    docker ps --filter "name=$CONTAINER_NAME" || true
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
    echo ">>> Removendo imagem do Maestro (se existir)..."
    # tenta descobrir imagens relacionadas ao repo clonado ou nome do container
    IMG_IDS="$(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep -E 'maestro|neoid|reustaquiojr' | awk '{print $2}' | tr '\n' ' ')"
    if [ -n "$IMG_IDS" ]; then
        docker rmi -f $IMG_IDS || true
        echo "Imagens removidas (se havia)."
    else
        echo "Nenhuma imagem identificada automaticamente."
    fi
}

remove_docker() {
    echo ">>> Removendo Docker e todos os dados... (requer apt/dpkg)"
    sudo systemctl stop docker docker.socket || true
    if command -v apt-get &>/dev/null; then
        sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
        sudo apt-get purge -y docker-ce docker-ce-cli containerd.io || true
        sudo apt-get autoremove -y --purge || true
    else
        echo "Remoção automática do Docker suportada apenas para apt neste script. Remova manualmente se necessário."
    fi
    sudo rm -rf /var/lib/docker /var/lib/containerd || true
    echo "Docker removido (se aplicável)."
}

clean_volumes() {
    echo ">>> Limpando volumes órfãos..."
    docker volume prune -f || true
}

# ---- Banner ----

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

# ---- Menu ----

main_menu() {
    while true; do
        clear
        show_banner
        echo "===================================================================="
        echo " 1) Instalar Docker"
        echo " 2) Instalar/Atualizar Maestro"
        echo " 3) Status do Maestro"
        echo " 4) Parar Maestro"
        echo " 5) Remover container"
        echo " 6) Remover imagem"
        echo " 7) Remover Docker completamente"
        echo " 8) Limpar volumes órfãos"
        echo " 9) Sair"
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
