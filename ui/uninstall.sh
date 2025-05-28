#!/bin/bash

set -e

# Verifica se a função está carregada, carrega se não estiver ou falha caso contrário.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/$GITHUB_SOURCE"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* ERRO: Não foi possível carregar o script lib" && exit 1
fi

# ------------------ Variáveis ----------------- #

export RM_PANEL=false
export RM_WINGS=false

# --------------- Funções principais --------------- #

main() {
  welcome ""

  if [ -d "/var/www/pterodactyl" ]; then
    output "Instalação do painel detectada."
    echo -e -n "* Deseja remover o painel? (s/N): "
    read -r RM_PANEL_INPUT
    [[ "$RM_PANEL_INPUT" =~ [Ss] ]] && RM_PANEL=true
  fi

  if [ -d "/etc/pterodactyl" ]; then
    output "Instalação do Wings detectada."
    warning "Isso irá remover todos os servidores!"
    echo -e -n "* Deseja remover o Wings (daemon)? (s/N): "
    read -r RM_WINGS_INPUT
    [[ "$RM_WINGS_INPUT" =~ [Ss] ]] && RM_WINGS=true
  fi

  if [ "$RM_PANEL" == false ] && [ "$RM_WINGS" == false ]; then
    error "Nada para desinstalar!"
    exit 1
  fi

  summary

  # confirma desinstalação
  echo -e -n "* Continuar com a desinstalação? (s/N): "
  read -r CONFIRM
  if [[ "$CONFIRM" =~ [Ss] ]]; then
    run_installer "uninstall"
  else
    error "Desinstalação abortada."
    exit 1
  fi
}

summary() {
  print_brake 30
  output "Remover painel? $RM_PANEL"
  output "Remover Wings? $RM_WINGS"
  print_brake 30
}

goodbye() {
  print_brake 62
  [ "$RM_PANEL" == true ] && output "Desinstalação do painel concluída"
  [ "$RM_WINGS" == true ] && output "Desinstalação do Wings concluída"
  output "Obrigado por usar este script."
  print_brake 62
}

main
goodbye
