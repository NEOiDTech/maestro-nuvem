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
APP_DIR="$HOME/neoid-maestro-nuvem"
CONTAINER_NAME="neoid-maestro-nuvem"
HEALTH_CHECK_TIMEOUT=60
HEALTH_CHECK_INTERVAL=5

# ... (restante das funções permanecem iguais até remove_image)

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
    
    # 🔧 NOVA FUNCIONALIDADE: Limpar diretório do projeto
    clean_project_directory
}

# -----------------------
# Nova função: Limpar diretório do projeto
# -----------------------
clean_project_directory() {
    log "Limpando diretório do projeto..."
    
    # Lista de diretórios possíveis onde o projeto pode estar
    local possible_dirs=(
        "$HOME/maestro-nuvem"
        "$HOME/neoid-maestro-nuvem" 
        "$HOME/neoid-maestro"
        "/root/maestro-nuvem"
        "/root/neoid-maestro-nuvem"
        "/root/neoid-maestro"
        "./maestro-nuvem"
        "./neoid-maestro-nuvem"
    )
    
    local dirs_found=()
    
    # Verifica quais diretórios existem
    for dir in "${possible_dirs[@]}"; do
        if [ -d "$dir" ]; then
            dirs_found+=("$dir")
        fi
    done
    
    if [ ${#dirs_found[@]} -eq 0 ]; then
        log "Nenhum diretório do projeto encontrado para limpeza."
        return 0
    fi
    
    echo "Diretórios do projeto encontrados:"
    for dir in "${dirs_found[@]}"; do
        echo "  - $dir"
    done
    
    read -p "Deseja remover TODOS estes diretórios e seu conteúdo? (s/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        for dir in "${dirs_found[@]}"; do
            if [ -d "$dir" ]; then
                log "Removendo diretório: $dir"
                rm -rf "$dir"
                success "Diretório $dir removido"
            fi
        done
        log "Limpeza de diretórios concluída."
    else
        log "Limpeza de diretórios cancelada."
    fi
}

# -----------------------
# Nova função: Limpeza completa (container + imagem + diretórios)
# -----------------------
complete_clean() {
    log "Iniciando limpeza completa do Maestro..."
    
    if check_docker; then
        stop_maestro
        remove_container
        remove_image
        # Não chama clean_project_directory aqui pois remove_image já chama
    else
        clean_project_directory
    fi
    
    # Limpeza adicional de volumes (opcional)
    read -p "Deseja também limpar volumes não utilizados? (s/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        clean_volumes
    fi
    
    success "Limpeza completa concluída!"
}

# -----------------------
# Atualizar o menu principal
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
                remove_image  # Agora inclui limpeza de diretórios
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
# Atualizar execução por parâmetros
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
            remove_image  # Agora inclui limpeza de diretórios
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
