#!/bin/bash

set -e

# Verifica se o script está carregado, carrega se não estiver ou falha caso contrário.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/$GITHUB_SOURCE"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* ERRO: Não foi possível carregar o script da biblioteca" && exit 1
fi

CHECKIP_URL="https://checkip.pterodactyl-installer.se"
DNS_SERVER="8.8.8.8"

# Sai com código de erro se o usuário não for root
if [[ $EUID -ne 0 ]]; then
  echo "* Este script deve ser executado com privilégios de root (sudo)." 1>&2
  exit 1
fi

fail() {
  output "O registro DNS ($dns_record) não corresponde ao IP do seu servidor. Por favor, certifique-se de que o FQDN $fqdn está apontando para o IP do seu servidor, $ip"
  output "Se você estiver usando Cloudflare, por favor, desabilite o proxy ou opte por não usar o Let's Encrypt."

  echo -n "* Deseja continuar mesmo assim (sua instalação pode ficar quebrada se você não souber o que está fazendo)? (s/N): "
  read -r override

  [[ ! "$override" =~ [Ss] ]] && error "FQDN ou registro DNS inválido" && exit 1
  return 0
}

dep_install() {
  update_repos true

  case "$OS" in
  ubuntu | debian)
    install_packages "dnsutils" true
    ;;
  rocky | almalinux)
    install_packages "bind-utils" true
    ;;
  esac

  return 0
}

confirm() {
  output "Este script irá realizar uma requisição HTTPS para o endpoint"
  output "Não irá registrar nem compartilhar qualquer informação de IP com terceiros."
  output "Se desejar usar outro serviço, fique à vontade para modificar o script."

  echo -e -n "* Eu concordo que esta requisição HTTPS será realizada (s/N): "
  read -r confirm
  [[ "$confirm" =~ [Ss] ]] || (error "Usuário não concordou" && false)
}

dns_verify() {
  output "Resolvendo DNS para $fqdn"
  ip=$(curl -4 -s $CHECKIP_URL)
  dns_record=$(dig +short @$DNS_SERVER "$fqdn" | tail -n1)
  [ "${ip}" != "${dns_record}" ] && fail
  output "DNS verificado com sucesso!"
}

main() {
  fqdn="$1"
  dep_install
  confirm && dns_verify
  true
}

main "$1" "$2"
