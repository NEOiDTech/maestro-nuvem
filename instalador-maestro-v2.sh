#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Script: maestro-install-update.sh
# - detecta docker-compose no repo e usa if present
# - fallback para `docker run` com imagem neoidtech/maestro
# - funciona com: curl ... | bash -s -- install
# =========================================================

REPO_URL="https://github.com/reustaquiojr/maestro-nuvem.git"
APP_DIR="${HOME}/maestro-nuvem"
IMAGE="neoidtech/maestro"
CONTAINER_NAME="neoid_maestro"
DATA_DIR="/opt/neoid/data"
RESTART="always"
NETWORK="host"
PRIVILEGED="true"

# -----------------------
# Helpers
# -----------------------
log() { echo -e "[INFO] $*"; }
err() { echo -e "[ERRO] $*" >&2; }

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
# Docker helpers
# -----------------------
ensure_docker() {
  log "Verificando Docker..."
  if ! command -v docker &>/dev/null; then
    log "Docker não encontrado — instalando (get.docker.com)..."
    curl -fsSL https://get.docker.com | sh
    sudo systemctl enable --now docker || true
  else
    log "Docker detectado: $(docker --version 2>/dev/null || true)"
  fi
  # tenta instalar docker compose (plugin) se não houver
  if ! docker compose version &>/dev/null 2>&1 && ! command -v docker-compose &>/dev/null; then
    log "Instalando docker-compose (binário fallback)..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
  fi
}

# procura um arquivo de compose dentro de APP_DIR (retorna caminho ou vazio)
find_compose_file() {
  local f
  local candidates=(docker-compose.yml docker-compose.yaml compose.yml docker-compose.yaml)
  for f in "${candidates[@]}"; do
    [ -f "${APP_DIR}/${f}" ] && { echo "${APP_DIR}/${f}"; return 0; }
  done
  # busca recursiva curta (até subdir)
  f=$(find "${APP_DIR}" -maxdepth 2 -type f -iname 'docker-compose*.y*ml' -print -quit 2>/dev/null || true)
  [ -n "$f" ] && { echo "$f" ; return 0; }
  return 1
}

# -----------------------
# Install / Update (compose OR run fallback)
# -----------------------
install_or_update_maestro() {
  log ">>> Instalando ou atualizando Maestro..."
  if [ -d "${APP_DIR}/.git" ]; then
    log "Repositório já clonado. Atualizando (git pull)..."
    git -C "${APP_DIR}" pull --ff-only || git -C "${APP_DIR}" pull || true
  else
    log "Clonando repositório em ${APP_DIR}..."
    git clone "${REPO_URL}" "${APP_DIR}"
  fi

  local compose_file
  compose_file="$(find_compose_file || true)"

  if [ -n "${compose_file}" ]; then
    log "Arquivo compose detectado: ${compose_file}"
    # executa no diretório do compose
    local compose_dir
    compose_dir="$(dirname "${compose_file}")"
    cd "${compose_dir}"
    if docker compose version &>/dev/null; then
      log "Usando 'docker compose' (plugin)"
      docker compose pull || true
      docker compose up -d
    elif command -v docker-compose &>/dev/null; then
      log "Usando 'docker-compose' (binário)"
      docker-compose pull || true
      docker-compose up -d
    else
      err "Nenhum docker compose disponível (plugin ou binário). Abortando."
      return 1
    fi
    log "Containers levantados via compose."
    return 0
  fi

  # fallback: rodar diretamente a imagem com docker run
  log "Nenhum docker-compose encontrado — aplicando fallback com 'docker run' usando imagem ${IMAGE}."
  ensure_docker

  # puxar imagem
  log "Pull da imagem ${IMAGE}..."
  docker pull "${IMAGE}"

  # stop + remove container antigo (se existir)
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
    log "Container ${CONTAINER_NAME} existe — parando e removendo..."
    docker stop "${CONTAINER_NAME}" || true
    docker rm -f "${CONTAINER_NAME}" || true
  fi

  # cria dir de dados
  log "Criando/ajustando diretório de dados em ${DATA_DIR}..."
  sudo mkdir -p "${DATA_DIR}"
  sudo chown "$(id -u):$(id -g)" "${DATA_DIR}" || true

  # monta flags
  local PRIV_FLAG=""
  [ "${PRIVILEGED}" = "true" ] && PRIV_FLAG="--privileged"

  log "Iniciando container ${CONTAINER_NAME} a partir de ${IMAGE} (network=${NETWORK})..."
  docker run -dit \
    --name "${CONTAINER_NAME}" \
    --restart="${RESTART}" \
    -v "${DATA_DIR}:/data" \
    ${PRIV_FLAG} \
    --user root \
    --network "${NETWORK}" \
    "${IMAGE}" || {
      err "Falha ao criar container (docker run). Verifique logs e permissões."
      return 1
    }

  log "Container criado com sucesso. Acesse a WEBUI em http://<seu_ip>:8080 (se aplicável)."
}

# -----------------------
# Outras ações
# -----------------------
status_maestro() {
  echo ">>> Status dos containers:"
  docker ps --filter "name=${CONTAINER_NAME}" || true
}

stop_maestro() {
  echo ">>> Parando container ${CONTAINER_NAME}..."
  docker stop "${CONTAINER_NAME}" 2>/dev/null || echo "Nenhum container em execução com esse nome."
}

remove_container() {
  echo ">>> Removendo container ${CONTAINER_NAME}..."
  docker rm -f "${CONTAINER_NAME}" 2>/dev/null || echo "Nenhum container encontrado."
}

remove_image() {
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

clean_volumes() {
  echo ">>> Limpando volumes órfãos..."
  docker volume prune -f || true
}

remove_docker() {
  echo ">>> Removendo Docker (somente apt suportado aqui) e dados..."
  sudo systemctl stop docker docker.socket || true
  if command -v apt-get &>/dev/null; then
    sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
    sudo apt-get purge -y docker-ce docker-ce-cli containerd.io || true
    sudo apt-get autoremove -y --purge || true
  else
    echo "Remoção automática suportada só com apt. Remova manualmente se necessário."
  fi
  sudo rm -rf /var/lib/docker /var/lib/containerd || true
  echo "Operação de remoção do Docker finalizada (se aplicável)."
}

# -----------------------
# Menu interativo (usa /dev/tty)
# -----------------------
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
    case "${opt}" in
      1) ensure_docker ;;
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
# Execução por parâmetro
# -----------------------
case "${1:-}" in
  "" ) main_menu ;;
  install ) ensure_docker; install_or_update_maestro ;;
  update ) install_or_update_maestro ;;
  status ) status_maestro ;;
  stop ) stop_maestro ;;
  remove ) remove_container; remove_image ;;
  purge ) stop_maestro; remove_container; remove_image; clean_volumes; remove_docker ;;
  * ) echo "Uso: $0 [install|update|status|stop|remove|purge]"; exit 1 ;;
esac
