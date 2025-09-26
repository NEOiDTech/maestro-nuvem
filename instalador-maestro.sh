#!/usr/bin/env bash
# maestro-install-update.sh
# Script interativo para instalar, atualizar e gerenciar o NEOiD Maestro (container Docker)
# Baseado no README do reustaquiojr/maestro-nuvem
# Use: salvar como maestro-install-update.sh && chmod +x maestro-install-update.sh
# Execute com sudo: sudo ./maestro-install-update.sh

set -euo pipefail
IFS=$'\n\t'

# Defaults (pode alterar interativamente no menu)
IMAGE_DEFAULT="neoidtech/maestro"
CONTAINER_NAME_DEFAULT="neoid_maestro"
DATA_DIR_DEFAULT="/opt/neoid/data"
HOST_PORT_DEFAULT=8080
RESTART_POLICY_DEFAULT="always"
USER_ID_DEFAULT=0
GROUP_ID_DEFAULT=0
PRIVILEGED_DEFAULT=true
NETWORK_MODE_DEFAULT="host"

# Helpers
log() { echo -e "[\e[1;34mINFO\e[0m] $*"; }
err() { echo -e "[\e[1;31mERRO\e[0m] $*" >&2; }
confirm() {
  local msg=${1:-"Confirm? (y/n): "}
  read -r -p "$msg" ans
  case "$ans" in
    [Yy]|[Yy][Ee][Ss]) return 0;;
    *) return 1;;
  esac
}

require_root() {
  if [ "$EUID" -ne 0 ]; then
    err "Este script precisa ser executado como root. Execute: sudo $0"
    exit 1
  fi
}

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

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker detectado: $(docker --version)"
    return 0
  fi

  log "Docker não encontrado. Deseja instalar o Docker (get.docker.com)?"
  if confirm "Instalar Docker agora? (y/n): "; then
    local pm
    pm=$(detect_pkg_manager)
    case "$pm" in
      apt)
        log "Instalando dependências e Docker (apt)..."
        apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release
        curl -fsSL https://get.docker.com | sh
        ;;
      dnf|yum)
        log "Instalando Docker via get.docker.com"
        curl -fsSL https://get.docker.com | sh
        ;;
      pacman)
        log "Instalando docker via pacman"
        pacman -Syu --noconfirm docker
        systemctl enable --now docker
        ;;
      *)
        err "Gerenciador de pacotes não suportado. Instale o Docker manualmente e rode o script novamente."
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
  local image="$1" name="$2" data_dir="$3" host_port="$4" privileged="$5" restart_policy="$6" network_mode="$7"

  mkdir -p "$data_dir"

  local privileged_flag=""
  if [ "$privileged" = true ]; then
    privileged_flag="--privileged"
  fi

  log "Iniciando container $name a partir de $image"
  docker run -itd \
    --name "$name" \
    --restart="$restart_policy" \
    -v "$data_dir":/data \
    $privileged_flag \
    --user root \
    --network $network_mode \
    "$image"

  log "Container iniciado. Use './maestro-install-update.sh status' ou opção 'Status' no menu para checar."
}

start_container() { docker start "$1" || true; }
stop_container() { docker stop "$1" || true; }
remove_container() { docker rm -f "$1" || true; }
show_logs() { docker logs -f --tail 200 "$1" || true; }
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
  local image="$1" name="$2" data_dir="$3" privileged="$4" restart_policy="$5" network_mode="$6"

  log "Executando rotina de update para $name usando imagem $image"
  log "Será criado backup do diretório de dados antes de recriar o container."
  if confirm "Continuar e criar backup antes do update? (y/n): "; then
    backup_data "$data_dir"
  else
    log "Usuário optou por não criar backup. Prosseguindo mesmo assim."
  fi

  log "Pull da nova imagem..."
  docker pull "$image"

  log "Parando container atual (se existir)..."
  docker stop "$name" || true
  log "Removendo container atual (se existir)..."
  docker rm "$name" || true

  log "Recriar container com a nova imagem..."
  run_container "$image" "$name" "$data_dir" "$HOST_PORT_DEFAULT" "$privileged" "$restart_policy" "$network_mode"
  log "Update concluído."
}

# Menu interativo
main_menu() {
  local image="$IMAGE_DEFAULT" name="$CONTAINER_NAME_DEFAULT" data_dir="$DATA_DIR_DEFAULT" host_port="$HOST_PORT_DEFAULT"
  local privileged="$PRIVILEGED_DEFAULT" restart_policy="$RESTART_POLICY_DEFAULT" network_mode="$NETWORK_MODE_DEFAULT"

  while true; do
    echo
    echo "========================= NEOiD MAESTRO NUVEM ========================="
    echo "Imagem atual: $image"
    echo "Nome do container: $name"
    echo "Diretório de dados (host): $data_dir"
    echo "Porta WEBUI (host): $host_port"
    echo "Privileged: $privileged   Restart: $restart_policy   Network: $network_mode"
    echo "======================================================================="
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
    echo "11) Alterar configurações (imagem/nome/diretório/porta/privileged/network)"
    echo "12) Sair"
    echo -n "Escolha uma opção [1-12]: "
    read opt < /dev/tty
    case "$opt" in
      1)
        ensure_docker
        ;;
      2)
        ensure_docker
        pull_image "$image"
        if confirm "Rodar container $name com $image? (y/n): "; then
          run_container "$image" "$name" "$data_dir" "$host_port" "$privileged" "$restart_policy" "$network_mode"
        else
          log "Operação cancelada pelo usuário."
        fi
        ;;
      3)
        ensure_docker
        update_container "$image" "$name" "$data_dir" "$privileged" "$restart_policy" "$network_mode"
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
        echo -n "Imagem (enter para manter: $image): "; read -r val; [ -n "$val" ] && image="$val"
        echo -n "Nome do container (enter para manter: $name): "; read -r val; [ -n "$val" ] && name="$val"
        echo -n "Diretório de dados host (enter para manter: $data_dir): "; read -r val; [ -n "$val" ] && data_dir="$val"
        echo -n "Porta WEBUI host (enter para manter: $host_port): "; read -r val; [ -n "$val" ] && host_port="$val"
        echo -n "Privileged (true/false) (enter para manter: $privileged): "; read -r val; [ -n "$val" ] && privileged="$val"
        echo -n "Restart policy (enter para manter: $restart_policy): "; read -r val; [ -n "$val" ] && restart_policy="$val"
        echo -n "Network mode (enter para manter: $network_mode): "; read -r val; [ -n "$val" ] && network_mode="$val"
        log "Configurações atualizadas temporariamente no menu. Use opção 2 para aplicar."
        ;;
      12)
        log "Saindo..."
        exit 0
        ;;
      *)
        echo "Opção inválida"
        ;;
    esac
  done
}

# Permitir execução direta de algumas operações via linha de comando simples
case "${1:-}" in
  install)
    require_root
    ensure_docker
    pull_image "$IMAGE_DEFAULT"
    run_container "$IMAGE_DEFAULT" "$CONTAINER_NAME_DEFAULT" "$DATA_DIR_DEFAULT" "$HOST_PORT_DEFAULT" "$PRIVILEGED_DEFAULT" "$RESTART_POLICY_DEFAULT" "$NETWORK_MODE_DEFAULT"
    exit 0
    ;;
  update)
    require_root
    ensure_docker
    update_container "$IMAGE_DEFAULT" "$CONTAINER_NAME_DEFAULT" "$DATA_DIR_DEFAULT" "$PRIVILEGED_DEFAULT" "$RESTART_POLICY_DEFAULT" "$NETWORK_MODE_DEFAULT"
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
