#!/usr/bin/env bash
set -uo pipefail

# =========================
# Variáveis de Configuração
# =========================
IMAGE="neoidtech/maestro"
CONTAINER_NAME="neoid_maestro"
DATA_DIR="/opt/neoid/data"
WEBUI_PORT=8080
PRIVILEGED="true"
RESTART="always"
NETWORK="host"

# =========================
# Funções Auxiliares
# =========================
ensure_docker() {
    echo "[*] Verificando instalação do Docker..."
    if ! command -v docker &>/dev/null; then
        echo "[*] Instalando Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
    else
        echo "[✓] Docker já está instalado."
    fi
    sleep 2
}

install_maestro() {
    ensure_docker
    echo "[*] Criando diretório de dados: $DATA_DIR"
    mkdir -p "$DATA_DIR"

    echo "[*] Baixando imagem: $IMAGE"
    docker pull "$IMAGE"

    echo "[*] Executando container: $CONTAINER_NAME"
    docker run -dit \
        --name "$CONTAINER_NAME" \
        --restart="$RESTART" \
        -v "$DATA_DIR:/data" \
        ${PRIVILEGED:+--privileged} \
        --network "$NETWORK" \
        -p "$WEBUI_PORT:8080" \
        "$IMAGE"
    echo "[✓] Maestro instalado e em execução."
    sleep 3
}

update_maestro() {
    echo "[*] Atualizando Maestro..."
    docker pull "$IMAGE"
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    install_maestro
}

start_container() {
    docker start "$CONTAINER_NAME"
    echo "[✓] Container iniciado."
    sleep 2
}

stop_container() {
    docker stop "$CONTAINER_NAME"
    echo "[✓] Container parado."
    sleep 2
}

restart_container() {
    docker restart "$CONTAINER_NAME"
    echo "[✓] Container reiniciado."
    sleep 2
}

logs_container() {
    docker logs -f "$CONTAINER_NAME"
}

status_container() {
    docker ps -a --filter "name=$CONTAINER_NAME"
    read -rp "Pressione ENTER para voltar ao menu..."
}

remove_container() {
    echo "[*] Removendo container: $CONTAINER_NAME"
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    echo "[✓] Container removido."
    sleep 2
}

remove_image() {
    echo "[*] Removendo imagem: $IMAGE"
    docker rmi "$IMAGE" 2>/dev/null || true
    echo "[✓] Imagem removida."
    sleep 2
}

remove_docker() {
    echo "[*] Removendo Docker e todos os dados..."
    systemctl stop docker docker.socket
    apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
    apt-get autoremove -y --purge || true
    rm -rf /var/lib/docker /var/lib/containerd
    echo "[✓] Docker removido."
    sleep 2
}

backup_data() {
    BACKUP_FILE="/opt/neoid/backup-$(date +%F-%H%M%S).tar.gz"
    echo "[*] Fazendo backup do diretório $DATA_DIR em $BACKUP_FILE"
    tar -czf "$BACKUP_FILE" -C "$DATA_DIR" .
    echo "[✓] Backup concluído."
    sleep 2
}

configure_settings() {
    echo "Configurações atuais:"
    echo "1) Imagem: $IMAGE"
    echo "2) Nome do container: $CONTAINER_NAME"
    echo "3) Diretório de dados: $DATA_DIR"
    echo "4) Porta WEBUI: $WEBUI_PORT"
    echo "5) Privileged: $PRIVILEGED"
    echo "6) Restart policy: $RESTART"
    echo "7) Network mode: $NETWORK"
    read -rp "Escolha qual deseja alterar [1-7]: " opt
    case $opt in
        1) read -rp "Nova imagem: " IMAGE ;;
        2) read -rp "Novo nome do container: " CONTAINER_NAME ;;
        3) read -rp "Novo diretório de dados: " DATA_DIR ;;
        4) read -rp "Nova porta WEBUI: " WEBUI_PORT ;;
        5) read -rp "Privileged (true/false): " PRIVILEGED ;;
        6) read -rp "Restart policy: " RESTART ;;
        7) read -rp "Network mode: " NETWORK ;;
        *) echo "Opção inválida." ;;
    esac
}

# =========================
# Menu Interativo
# =========================
main_menu() {
    while true; do
        clear
        echo "================= NEOiD MAESTRO - Gerenciador Interativo ================="
        echo "Imagem atual: $IMAGE"
        echo "Nome do container: $CONTAINER_NAME"
        echo "Diretório de dados (host): $DATA_DIR"
        echo "Porta WEBUI (host): $WEBUI_PORT"
        echo "Privileged: $PRIVILEGED  Restart: $RESTART  Network: $NETWORK"
        echo "=========================================================================="
        echo " 1) Garantir Docker instalado"
        echo " 2) Instalar / Rodar Maestro (pull + run)"
        echo " 3) Atualizar Maestro (pull + recreate)"
        echo " 4) Iniciar container"
        echo " 5) Parar container"
        echo " 6) Reiniciar container"
        echo " 7) Logs (follow)"
        echo " 8) Status do container"
        echo " 9) Remover container"
        echo "10) Remover imagem"
        echo "11) Remover Docker (completo)"
        echo "12) Backup do diretório de dados"
        echo "13) Alterar configurações"
        echo "14) Sair"
        echo "=========================================================================="
        read -rp "Escolha uma opção [1-14]: " opcao

        case $opcao in
            1) ensure_docker ;;
            2) install_maestro ;;
            3) update_maestro ;;
            4) start_container ;;
            5) stop_container ;;
            6) restart_container ;;
            7) logs_container ;;
            8) status_container ;;
            9) remove_container ;;
           10) remove_image ;;
           11) remove_docker ;;
           12) backup_data ;;
           13) configure_settings ;;
           14) exit 0 ;;
           *) echo "Opção inválida!" ; sleep 2 ;;
        esac
    done
}

# =========================
# Execução
# =========================
main_menu
