#!/usr/bin/env bash
# maestro-install-update.sh
# Script interativo para instalar, atualizar e gerenciar o NEOiD MAESTRO NUVEM (container Docker)
# Baseado no README do reustaquiojr/maestro-nuvem
# Execute com sudo: sudo ./maestro-install-update.sh

set -euo pipefail
IFS=$'\n\t'

# ==================================
# DEFAULTS
# ==================================
IMAGE_DEFAULT="neoidtech/maestro"
CONTAINER_NAME_DEFAULT="neoid_maestro"
DATA_DIR_DEFAULT="/opt/neoid/data"
HOST_PORT_DEFAULT=8080
CONTAINER_PORT=8080 # Porta interna do container (Maestro)
RESTART_POLICY_DEFAULT="always"
PRIVILEGED_DEFAULT=true

# ==================================
# ASCII BANNER
# ==================================
MAESTRO_BANNER=$(cat << "EOF"
  _   _ _____ ____ ___ ___ _  _ _  _ _____ _  _ 
 | \ | | ____|  _ \_ _|_ _| \ | |  _|_   _| || |
 |  \| |  _| | |_) | | | ||  \| | | | | | | || |
 | |\  | |___|  _ <| | | || |\  | |_| | | |   |
 |_| \_|_____|_| \_\_|___|_|_| \_|\___/  |_| |_||_|
  __  __ ____ _   _ ___ __    _             _   __
 |  \| |  _ \  \/ / | \/  / |  | | |  | | | |   /
 | | \ | | | |\  /  | |\/| | |  | | | |  | | | |_  
 | |\  | |_| | /  \ | |  | | |  | |_| |  | | | __|
 |_| \_|____/ /\_/\_|_|  |_| \_|  \___/   \_|   \  
                                                   
=======================================================================
                                                   
EOF
)

# ==================================
# HELPERS
# ==================================

# Funções de log formatadas
log() { echo -e "[\e[1;34mINFO\e[0m] $*"; }
err() { echo -e "[\e[1;31mERRO\e[0m] $*" >&2; }
warn() { echo -e "[\e[1;33mALERTA\e[0m] $*"; }

# Confirmação interativa
confirm() {
  local msg=${1:-"Confirm? (y/n): "}
  # O '/dev/tty' garante que a leitura ocorre a partir do terminal de controle.
  read -r -p "$msg" ans < /dev/tty
  case "$ans" in
    [Yy]|[Yy][Ee][Ss]) return 0;;
    *) return 1;;
  esac
}

# Requisito de execução como root
require_root() {
  if [ "$EUID" -ne 0 ]; then
    err "Este script precisa ser executado como root. Execute: sudo $0"
    exit 1
  fi
}

# Detecção do gerenciador de pacotes
detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  elif command -v pacman >/dev/null 2>&1; then
    echo "pacman"
  else
    echo "unknown"
  fi
}

# ==================================
# DOCKER MANAGEMENT
# ==================================

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker detectado: $(docker --version)"
    return 0
  fi

  log "Docker não encontrado. Deseja instalar o Docker?"
  if confirm "Instalar Docker agora (via get.docker.com ou repositórios)? (y/n): "; then
    local pm
    pm=$(detect_pkg_manager)
    case "$pm" in
      apt)
        log "Instalando Docker para Debian/Ubuntu (via script get.docker.com)..."
        apt-get update || true 
        apt-get install -y ca-certificates curl gnupg lsb-release
        curl -fsSL https://get.docker.com | sh
        ;;
      dnf|yum)
        log "Instalando Docker via get.docker.com (RedHat/Fedora)..."
        curl -fsSL https://get.docker.com | sh
        ;;
      pacman)
        log "Instalando docker via pacman (Arch/Manjaro)..."
        pacman -Syu --noconfirm docker
        systemctl enable --now docker
        ;;
      *)
        err "Gerenciador de pacotes '$pm' não suportado. Instale o Docker manualmente e rode o script novamente."
        return 1
        ;;
    esac
    log "Instalação Docker finalizada. Versão: $(docker --version 2>/dev/null || echo 'não detectada')"
  else
    err "Docker é necessário. Abortando."
    exit 1
  fi
}

pull_image() {
  local image="$1"
  log "Fazendo pull da imagem: $image"
  docker pull "$image"
}

run_container() {
  local image="$1" name="$2" data_dir="$3" host_port="$4" privileged="$5" restart_policy="$6"

  mkdir -p "$data_dir"
  chown -R 0:0 "$data_dir"
  chmod 700 "$data_dir"

  local privileged_flag=""
  if [ "$privileged" = true ]; then
    privileged_flag="--privileged"
  fi

  log "Iniciando container $name a partir de $image"
  docker run -itd \
    --name "$name" \
    --restart="$restart_policy" \
    -v "$data_dir":/data \
    -p "$host_port:$CONTAINER_PORT" \
    $privileged_flag \
    --user root \
    "$image"

  if [ $? -eq 0 ]; then
    log "Container iniciado com sucesso!"
    log "Acesse a interface em: http://<IP_DO_HOST>:$host_port"
  else
    err "Falha ao iniciar o container. Verifique os logs."
    return 1
  fi
}

# Funções de gerenciamento simples
start_container() { docker start "$1" || warn "Container $1 não está presente ou já está rodando."; }
stop_container() { docker stop "$1" || warn "Container $1 não está rodando."; }
remove_container() { docker rm -f "$1" || warn "Container $1 não existe."; }
show_logs() { docker logs -f --tail 200 "$1" || warn "Não foi possível exibir os logs de $1. Container pode não existir."; }
status_container() { docker ps -a --filter "name=$1" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}"; }

backup_data() {
  local data_dir="$1" dest="/tmp/maestro-backup-$(date +%F-%H%M%S).tar.gz"
  if [ ! -d "$data_dir" ]; then
    err "Diretório de dados não existe: $data_dir"
    return 1
  fi
  log "Compactando $data_dir -> $dest"
  tar -czf "$dest" -C "$(dirname "$data_dir")" "$(basename "$data_dir")"
  log "Backup criado: $dest"
}

update_container() {
  local image="$1" name="$2" data_dir="$3" privileged="$4" restart_policy="$5" host_port="$6"

  log "Executando rotina de update para $name usando imagem $image"
  log "Será criado backup do diretório de dados antes de recriar o container."
  if confirm "Continuar e criar backup antes do update? (y/n): "; then
    backup_data "$data_dir"
  else
    warn "Usuário optou por não criar backup. Prosseguindo mesmo assim."
  fi

  log "Pull da nova imagem..."
  docker pull "$image"

  log "Parando e removendo container atual (se existir)..."
  docker stop "$name" >/dev/null 2>&1 || true
  docker rm "$name" >/dev/null 2>&1 || true

  log "Recriar container com a nova imagem..."
  run_container "$image" "$name" "$data_dir" "$host_port" "$privileged" "$restart_policy"
  log "Update concluído."
}

# ==================================
# MAIN MENU
# ==================================

main_menu() {
  local image="$IMAGE_DEFAULT" name="$CONTAINER_NAME_DEFAULT" data_dir="$DATA_DIR_DEFAULT" host_port="$HOST_PORT_DEFAULT"
  local privileged="$PRIVILEGED_DEFAULT" restart_policy="$RESTART_POLICY_DEFAULT"

  while true; do
    echo
    # Exibe o BANNER ASCII
    echo -e "\e[1;36m${MAESTRO_BANNER}\e[0m"
    
    echo "--- CONFIGURAÇÕES ATUAIS ---"
    echo "Imagem: $image"
    echo "Container: $name"
    echo "Dados (host): $data_dir"
    echo "Porta WEBUI (host -> container): $host_port -> $CONTAINER_PORT"
    echo "Privileged: $privileged   Restart: $restart_policy"
    echo "----------------------------"
    echo "1) Garantir Docker instalado"
    echo "2) Instalar / Rodar MAESTRO NUVEM (pull + run)"
    echo "3) Atualizar MAESTRO NUVEM (pull + recreate)"
    echo "4) Iniciar container"
    echo "5) Parar container"
    echo "6) Reiniciar container"
    echo "7) Logs (follow)"
    echo "8) Status do container"
    echo "9) Remover container"
    echo "10) Fazer backup do diretório de dados"
    echo "11) Alterar configurações"
    echo "12) Sair"
    
    # Leitura da opção do menu
    read -r -p "Escolha uma opção [1-12]: " opt < /dev/tty
    
    case "$opt" in
      1)
        ensure_docker
        ;;
      2)
        ensure_docker
        pull_image "$image"
        if confirm "Rodar container $name com $image e porta $host_port? (y/n): "; then
          run_container "$image" "$name" "$data_dir" "$host_port" "$privileged" "$restart_policy"
        else
          log "Operação cancelada pelo usuário."
        fi
        ;;
      3)
        ensure_docker
        update_container "$image" "$name" "$data_dir" "$privileged" "$restart_policy" "$host_port"
        ;;
      4)
        start_container "$name"
        ;;
      5)
        stop_container "$name"
        ;;
      6)
        stop_container "$name" && start_container "$name"
        ;;
      7)
        show_logs "$name"
        ;;
      8)
        status_container "$name"
        ;;
      9)
        if confirm "Remover container $name (irá parar e remover)? (y/n): "; then
          remove_container "$name"
        else
          log "Operação cancelada."
        fi
        ;;
      10)
        backup_data "$data_dir"
        ;;
      11)
        read -r -p "Imagem (enter para manter: $image): " val < /dev/tty; [ -n "$val" ] && image="$val"
        read -r -p "Nome do container (enter para manter: $name): " val < /dev/tty; [ -n "$val" ] && name="$val"
        read -r -p "Diretório de dados host (enter para manter: $data_dir): " val < /dev/tty; [ -n "$val" ] && data_dir="$val"
        read -r -p "Porta WEBUI host (enter para manter: $host_port): " val < /dev/tty; [ -n "$val" ] && host_port="$val"
        read -r -p "Privileged (true/false) (enter para manter: $privileged): " val < /dev/tty; [ -n "$val" ] && privileged="$val"
        read -r -p "Restart policy (enter para manter: $restart_policy): " val < /dev/tty; [ -n "$val" ] && restart_policy="$val"
        log "Configurações atualizadas temporariamente no menu. Use opção 2 para aplicar."
        ;;
      12)
        log "Saindo..."
        exit 0
        ;;
      *)
        warn "Opção inválida: $opt"
        ;;
    esac
  done
}

# ==================================
# SCRIPT ENTRY POINT
# ==================================

# Permitir execução direta de algumas operações via linha de comando simples
case "${1:-}" in
  install)
    require_root
    ensure_docker
    pull_image "$IMAGE_DEFAULT"
    run_container "$IMAGE_DEFAULT" "$CONTAINER_NAME_DEFAULT" "$DATA_DIR_DEFAULT" "$HOST_PORT_DEFAULT" "$PRIVILEGED_DEFAULT" "$RESTART_POLICY_DEFAULT"
    exit 0
    ;;
  update)
    require_root
    ensure_docker
    update_container "$IMAGE_DEFAULT" "$CONTAINER_NAME_DEFAULT" "$DATA_DIR_DEFAULT" "$PRIVILEGED_DEFAULT" "$RESTART_POLICY_DEFAULT" "$HOST_PORT_DEFAULT"
    exit 0
    ;;
  status)
    status_container "$CONTAINER_NAME_DEFAULT"
    exit 0
    ;;
  *)
    require_root
    main_menu
    ;;
esac
