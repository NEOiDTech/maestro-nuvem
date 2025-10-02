#!/bin/bash

# =========================================================
# Script: instalador-maestro.sh
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
APP_DIR="$HOME/neoid-maestro-nuvem"
CONTAINER_NAME="neoid-maestro-nuvem"
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
# Função: Limpar diretório do projeto (CORRIGIDA - CAMINHOS ABSOLUTOS)
# -----------------------
clean_project_directory() {
    log "Limpando diretórios do projeto..."
    
    # Lista de diretórios possíveis onde o projeto pode estar (CAMINHOS ABSOLUTOS)
    local possible_dirs=(
        "$HOME/maestro-nuvem"
        "$HOME/neoid-maestro-nuvem" 
        "$HOME/neoid-maestro"
        "/root/maestro-nuvem"
        "/root/neoid-maestro-nuvem"
        "/root/neoid-maestro"
        "/opt/maestro-nuvem"
        "/opt/neoid-maestro-nuvem"
        "/usr/local/maestro-nuvem"
        "/usr/local/neoid-maestro-nuvem"
        "/tmp/maestro-nuvem"
        "/tmp/neoid-maestro-nuvem"
    )
    
    local dirs_found=()
    
    # Verifica quais diretórios existem
    for dir in "${possible_dirs[@]}"; do
        if [ -d "$dir" ]; then
            dirs_found+=("$dir")
            log "Diretório encontrado: $dir"
        fi
    done
    
    # 🔍 BUSCA ADICIONAL: Procura por diretórios maestro em locais comuns
    local additional_dirs=$(find /home /root /opt /usr/local /tmp -maxdepth 2 -type d -name "*maestro*" -o -name "*neoid*" 2>/dev/null | head -20)
    
    while IFS= read -r dir; do
        if [ -n "$dir" ] && [ -d "$dir" ] && [[ ! " ${dirs_found[@]} " =~ " ${dir} " ]]; then
            dirs_found+=("$dir")
            log "Diretório adicional encontrado: $dir"
        fi
    done <<< "$additional_dirs"
    
    if [ ${#dirs_found[@]} -eq 0 ]; then
        log "Nenhum diretório do projeto encontrado para limpeza."
        return 0
    fi
    
    echo "=================================================="
    echo "DIRETÓRIOS DO PROJETO ENCONTRADOS:"
    echo "=================================================="
    for dir in "${dirs_found[@]}"; do
        if [ -d "$dir" ]; then
            size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "tamanho desconhecido")
            count=$(find "$dir" -type f 2>/dev/null | wc -l || echo "0")
            echo "  📁 $dir ($size, $count arquivos)"
        fi
    done
    echo "=================================================="
    
    read -p "❓ Deseja remover TODOS estes diretórios e seu conteúdo? (s/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        local removed_count=0
        for dir in "${dirs_found[@]}"; do
            if [ -d "$dir" ]; then
                log "Removendo diretório: $dir"
                # Tenta remover sem sudo primeiro
                if rm -rf "$dir" 2>/dev/null; then
                    success "Diretório $dir removido com sucesso"
                    ((removed_count++))
                else
                    # Se falhar, tenta com sudo
                    log "Tentando remover com sudo: $dir"
                    if sudo rm -rf "$dir" 2>/dev/null; then
                        success "Diretório $dir removido com sudo"
                        ((removed_count++))
                    else
                        error "Falha ao remover diretório $dir"
                        # Tenta remover conteúdo mantendo o diretório
                        log "Tentando limpar conteúdo de: $dir"
                        if sudo find "$dir" -mindepth 1 -delete 2>/dev/null; then
                            success "Conteúdo de $dir removido (diretório mantido)"
                            ((removed_count++))
                        else
                            error "Não foi possível remover conteúdo de $dir"
                        fi
                    fi
                fi
            fi
        done
        success "Limpeza concluída! $removed_count diretórios processados."
        
        # 🔍 VERIFICAÇÃO FINAL
        log "Verificando se ainda existem diretórios do projeto..."
        local remaining_dirs=$(find /home /root /opt -maxdepth 3 -type d -name "*maestro*" -o -name "*neoid*" 2>/dev/null | head -10)
        if [ -n "$remaining_dirs" ]; then
            echo "⚠️  Diretórios ainda encontrados após limpeza:"
            echo "$remaining_dirs"
        else
            success "✅ Todos os diretórios do projeto foram removidos!"
        fi
    else
        log "Limpeza de diretórios cancelada pelo usuário."
    fi
}

# -----------------------
# Função: Limpeza completa (container + imagem + diretórios)
# -----------------------
complete_clean() {
    log "Iniciando limpeza completa do Maestro..."
    
    if check_docker; then
        stop_maestro
        remove_container
        remove_image  # Já inclui clean_project_directory
    else
        clean_project_directory
    fi
    
    success "Limpeza completa concluída!"
}

# ... (O RESTANTE DO SCRIPT PERMANECE EXATAMENTE IGUAL)
# [Todas as outras funções permanecem inalteradas]
# ...

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
    docker inspect "$CONTAINER_NAME" 2>/dev/null | jq -r '.[] | {Name: .Name, State: .State.Status, Running: .State.Running, Health: .State.Health.Status, IP: .NetworkSettings.IPAddress, Ports: .NetworkSettings.Ports}' 2>/dev/null || \
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
    IMG_IDS=$(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep -E 'maestro|neoid' | awk '{print $2}' || true)
    
    if [ -n "${IMG_IDS}" ]; then
        echo "Imagens encontradas para remoção:"
        docker images | grep -E 'maestro|neoid' || true
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
    
    # 🔧 NOVO: Limpar diretório do projeto após remover imagens
    log "Iniciando limpeza de diretórios do projeto..."
    clean_project_directory
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
# Menu (PERMANECE IGUAL)
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
        echo "7) Remover imagem + diretórios"
        echo "8) Limpeza completa"
        echo "9) Remover Docker completamente"
        echo "10) Limpar volumes órfãos"
        echo "11) Sair"
        echo "--------------------------------------------------------------------"
        read -p "Escolha uma opção [1-11]: " opt < /dev/tty

        clear
        show_banner
        case "$opt" in
            1) 
                install_docker
                read -p "Pressione ENTER para voltar ao menu..." _ < /dev/tty
                ;;
            2) 
                install_or_update_maestro
                ;;
            3) 
                status_maestro
                read -p "Pressione ENTER para voltar ao menu..." _ < /dev_tty
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
                complete_clean
                read -p "Pressione ENTER para voltar ao menu..." _ < /dev/tty
                ;;
            9) 
                remove_docker
                read -p "Pressione ENTER para voltar ao menu..." _ < /dev/tty
                ;;
            10) 
                clean_volumes
                read -p "Pressione ENTER para voltar ao menu..." _ < /dev/tty
                ;;
            11) 
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
# Execução por parâmetros (PERMANECE IGUAL)
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
            complete_clean
        else
            remove_docker
        fi
        ;;
    * ) 
        echo "Uso: $0 [install|update|status|health|stop|remove|purge]"
        exit 1 
        ;;
esac
