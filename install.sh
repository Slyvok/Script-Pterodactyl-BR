#!/bin/bash

set -e

######################################################################################
#                                                                                    #
# Projeto 'Script Instalador Pterodactyl BR'                                         #
#                                                                                    #
# Copyright (C) 2024 - 2025, SlyProductios                                           #
#                                                                                    #
#   Este programa é software livre: você pode redistribuí-lo e/ou modificá-lo        #
#   sob os termos da Licença Pública Geral GNU conforme publicada pela                #
#   Free Software Foundation, seja a versão 3 da licença, ou (a seu critério)        #
#   qualquer versão posterior.                                                       #
#                                                                                    #
#   Este programa é distribuído na esperança de que seja útil,                      #
#   mas SEM QUALQUER GARANTIA; sem mesmo a garantia implícita de                    #
#   COMERCIABILIDADE ou ADEQUAÇÃO A UM DETERMINADO FIM. Veja a                      #
#   Licença Pública Geral GNU para mais detalhes.                                   #
#                                                                                    #
#   Você deve ter recebido uma cópia da Licença Pública Geral GNU                   #
#   junto com este programa. Se não, veja <https://www.gnu.org/licenses/>.          #
#                                                                                    #
# https://github.com/Slyvok/Script-Pterodactyl-BR/blob/main/LICENSE                  #
#                                                                                    #
# Este script não está associado ao projeto oficial Pterodactyl.                    #
# https://github.com/Slyvok/Script-Pterodactyl-BR                                    #
#                                                                                    #
######################################################################################

export GITHUB_SOURCE="v1.1.1"
export SCRIPT_RELEASE="v1.1.1"
export GITHUB_BASE_URL="https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer"

LOG_PATH="/var/log/pterodactyl-installer.log"

# verifica se o curl está instalado
if ! [ -x "$(command -v curl)" ]; then
  echo "* O curl é necessário para que este script funcione."
  echo "* Instale usando apt (Debian e derivados) ou yum/dnf (CentOS)"
  exit 1
fi

# Sempre remove lib.sh antes de baixá-lo
[ -f /tmp/lib.sh ] && rm -rf /tmp/lib.sh
curl -sSL -o /tmp/lib.sh "$GITHUB_BASE_URL"/master/lib/lib.sh
# shellcheck source=lib/lib.sh
source /tmp/lib.sh

execute() {
  echo -e "\n\n* pterodactyl-installer $(date) \n\n" >>$LOG_PATH

  [[ "$1" == *"canary"* ]] && export GITHUB_SOURCE="master" && export SCRIPT_RELEASE="canary"
  update_lib_source
  run_ui "${1//_canary/}" |& tee -a $LOG_PATH

  if [[ -n $2 ]]; then
    echo -e -n "* A instalação de $1 foi concluída. Deseja prosseguir com a instalação de $2? (s/N): "
    read -r CONFIRM
    if [[ "$CONFIRM" =~ [Ss] ]]; then
      execute "$2"
    else
      error "Instalação de $2 abortada."
      exit 1
    fi
  fi
}

welcome ""

done=false
while [ "$done" == false ]; do
  options=(
    "Instalar o painel"
    "Instalar Wings"
    "Instalar ambos [0] e [1] na mesma máquina (o script do Wings roda após o painel)"
    # "Desinstalar painel ou wings\n"

    "Instalar painel com a versão canary do script (versões no master, podem estar instáveis!)"
    "Instalar Wings com a versão canary do script (versões no master, podem estar instáveis!)"
    "Instalar ambos [3] e [4] na mesma máquina (o script do Wings roda após o painel)"
    "Desinstalar painel ou wings com a versão canary do script (versões no master, podem estar instáveis!)"
  )

  actions=(
    "panel"
    "wings"
    "panel;wings"
    # "uninstall"

    "panel_canary"
    "wings_canary"
    "panel_canary;wings_canary"
    "uninstall_canary"
  )

  output "O que você gostaria de fazer?"

  for i in "${!options[@]}"; do
    output "[$i] ${options[$i]}"
  done

  echo -n "* Digite um número de 0 a $((${#actions[@]} - 1)): "
  read -r action

  [ -z "$action" ] && error "Entrada é obrigatória" && continue

  valid_input=("$(for ((i = 0; i <= ${#actions[@]} - 1; i += 1)); do echo "${i}"; done)")
  [[ ! " ${valid_input[*]} " =~ ${action} ]] && error "Opção inválida"
  [[ " ${valid_input[*]} " =~ ${action} ]] && done=true && IFS=";" read -r i1 i2 <<<"${actions[$action]}" && execute "$i1" "$i2"
done

# Remove lib.sh, assim na próxima execução do script a versão mais nova será baixada
rm -rf /tmp/lib.sh
