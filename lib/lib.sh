#!/bin/bash

set -e

# ------------------ Variáveis ----------------- #

# Versionamento
export GITHUB_SOURCE=${GITHUB_SOURCE:-master}
export SCRIPT_RELEASE=${SCRIPT_RELEASE:-canary}

# Versões do Pterodactyl
export PTERODACTYL_PANEL_VERSION=""
export PTERODACTYL_WINGS_VERSION=""

# Path (exporta tudo que for possível, não importa se já existe)
export PATH="$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"

# Sistema operacional
export OS=""
export OS_VER_MAJOR=""
export CPU_ARCHITECTURE=""
export ARCH=""
export SUPORTADO=false

# URLs para download
export PANEL_DL_URL="https://github.com/Next-Panel/Pterodactyl-BR/releases/latest/download/panel.tar.gz"
export WINGS_DL_BASE_URL="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_"
export MARIADB_URL="https://downloads.mariadb.com/MariaDB/mariadb_repo_setup"
export GITHUB_BASE_URL=${GITHUB_BASE_URL:-"https://raw.githubusercontent.com/Slyvok/Script-Pterodactyl-BR"}
export GITHUB_URL="$GITHUB_BASE_URL/$GITHUB_SOURCE"

# Cores
COLOR_YELLOW='\033[1;33m'
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m'

# Regex para validação de e-mail
email_regex="^(([A-Za-z0-9]+((\.|\-|\_|\+)?[A-Za-z0-9]?)*[A-Za-z0-9]+)|[A-Za-z0-9]+)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"

# Charset usado para gerar senhas aleatórias
password_charset='A-Za-z0-9!"#%&()*+,-./:;<=>?@[\]^_`{|}~'

# --------------------- Biblioteca -------------------- #

lib_loaded() {
  return 0
}

# -------------- Funções visuais -------------- #

output() {
  echo -e "* $1"
}

success() {
  echo ""
  output "${COLOR_GREEN}SUCESSO${COLOR_NC}: $1"
  echo ""
}

error() {
  echo ""
  echo -e "* ${COLOR_RED}ERRO${COLOR_NC}: $1" 1>&2
  echo ""
}

warning() {
  echo ""
  output "${COLOR_YELLOW}AVISO${COLOR_NC}: $1"
  echo ""
}

print_brake() {
  for ((n = 0; n < $1; n++)); do
    echo -n "#"
  done
  echo ""
}

print_list() {
  print_brake 30
  for word in $1; do
    output "$word"
  done
  print_brake 30
  echo ""
}

hyperlink() {
  echo -e "\e]8;;${1}\a${1}\e]8;;\a"
}

# Primeiro argumento é wings / panel / nenhum
welcome() {
  get_latest_versions

  print_brake 70
  output "Script de instalação do painel Pterodactyl @ $SCRIPT_RELEASE"
  output ""
  output "Copyright (C) 2025, SlyProductions - BY: Slyvok"
  output "https://github.com/Slyvok/Script-Pterodactyl-BR"
  output ""
  output "Este script não é associado ao projeto oficial Pterodactyl."
  output ""
  output "Executando $OS versão $OS_VER."
  if [ "$1" == "panel" ]; then
    output "Última versão do pterodactyl/panel é $PTERODACTYL_PANEL_VERSION"
  elif [ "$1" == "wings" ]; then
    output "Última versão do pterodactyl/wings é $PTERODACTYL_WINGS_VERSION"
  fi
  print_brake 70
}


# ---------------- Funções da biblioteca --------------- #

get_latest_release() {
  curl -sL "https://api.github.com/repos/$1/releases/latest" | # Pega a última release pela API do GitHub
    grep '"tag_name":' |                                       # Pega a linha da tag
    sed -E 's/.*"([^"]+)".*/\1/'                               # Extrai o valor do JSON
}

get_latest_versions() {
  output "Recuperando informações das releases..."
  PTERODACTYL_PANEL_VERSION=$(get_latest_release "pterodactyl/panel")
  PTERODACTYL_WINGS_VERSION=$(get_latest_release "pterodactyl/wings")
}

update_lib_source() {
  GITHUB_URL="$GITHUB_BASE_URL/$GITHUB_SOURCE"
  rm -rf /tmp/lib.sh
  curl -sSL -o /tmp/lib.sh "$GITHUB_URL"/lib/lib.sh
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh
}

run_installer() {
  bash <(curl -sSL "$GITHUB_URL/installers/$1.sh")
}

run_ui() {
  bash <(curl -sSL "$GITHUB_URL/ui/$1.sh")
}

array_contains_element() {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

valid_email() {
  [[ $1 =~ ${email_regex} ]]
}

invalid_ip() {
  ip route get "$1" >/dev/null 2>&1
  echo $?
}

gen_passwd() {
  local length=$1
  local password=""
  while [ ${#password} -lt "$length" ]; do
    password=$(echo "$password""$(head -c 100 /dev/urandom | LC_ALL=C tr -dc "$password_charset")" | fold -w "$length" | head -n 1)
  done
  echo "$password"
}

# -------------------- MYSQL ------------------- #

create_db_user() {
  local db_user_name="$1"
  local db_user_password="$2"
  local db_host="${3:-127.0.0.1}"

  output "Criando usuário de banco de dados $db_user_name..."

  mariadb -u root -e "CREATE USER '$db_user_name'@'$db_host' IDENTIFIED BY '$db_user_password';"
  mariadb -u root -e "FLUSH PRIVILEGES;"

  output "Usuário do banco de dados $db_user_name criado"
}

grant_all_privileges() {
  local db_name="$1"
  local db_user_name="$2"
  local db_host="${3:-127.0.0.1}"

  output "Concedendo todos os privilégios para $db_name ao usuário $db_user_name..."

  mariadb -u root -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user_name'@'$db_host' WITH GRANT OPTION;"
  mariadb -u root -e "FLUSH PRIVILEGES;"

  output "Privilégios concedidos"
}

create_db() {
  local db_name="$1"
  local db_user_name="$2"
  local db_host="${3:-127.0.0.1}"

  output "Criando banco de dados $db_name..."

  mariadb -u root -e "CREATE DATABASE $db_name;"
  grant_all_privileges "$db_name" "$db_user_name" "$db_host"

  output "Banco de dados $db_name criado"
}

# --------------- Gerenciador de Pacotes -------------- #

# Argumento para modo silencioso
update_repos() {
  local args=""
  [[ $1 == true ]] && args="-qq"
  case "$OS" in
  ubuntu | debian)
    apt-get -y $args update
    ;;
  *)
    # Não faz nada pois AlmaLinux e RockyLinux atualizam os metadados antes da instalação dos pacotes.
    ;;
  esac
}

# Primeiro argumento: lista de pacotes para instalar, segundo argumento: modo silencioso
install_packages() {
  local args=""
  if [[ $2 == true ]]; then
    case "$OS" in
    ubuntu | debian) args="-qq" ;;
    *) args="-q" ;;
    esac
  fi

  # Eval necessário para expansão correta dos argumentos
  case "$OS" in
  ubuntu | debian)
    eval apt-get -y $args install "$1"
    ;;
  rocky | almalinux)
    eval dnf -y $args install "$1"
    ;;
  esac
}

# ------------ Funções para entrada do usuário ------------ #

required_input() {
  local __resultvar=$1
  local result=''

  while [ -z "$result" ]; do
    echo -n "* ${2}"
    read -r result

    if [ -z "${3}" ]; then
      [ -z "$result" ] && result="${4}"
    else
      [ -z "$result" ] && error "${3}"
    fi
  done

  eval "$__resultvar="'$result'""  
}

email_input() {
  local __resultvar=$1
  local result=''

  while ! valid_email "$result"; do
    echo -n "* ${2}"
    read -r result

    valid_email "$result" || error "${3}"
  done

  eval "$__resultvar="'$result'""  
}

password_input() {
  local __resultvar=$1
  local result=''
  local default="$4"

  while [ -z "$result" ]; do
    echo -n "* ${2}"

    # modificado de https://stackoverflow.com/a/22940001
    while IFS= read -r -s -n1 char; do
      [[ -z $char ]] && {
        printf '\n'
        break
      }                               # ENTER pressionado; imprime \n e sai.
      if [[ $char == $'\177' ]]; then # BACKSPACE pressionado
        if [[ -n $result ]]; then
          result=${result%?}
          printf '\b \b'
        fi
      else
        result+=$char
        printf '*'
      fi
    done

    if [ -z "$result" ]; then
      if [ -n "$default" ]; then
        result=$default
      else
        error "${3}"
      fi
    fi
  done

  eval "$__resultvar="'$result'""  
}

yn_input() {
  local __resultvar=$1
  local prompt=$2
  local default=$3
  local result=''

  while ! [[ $result =~ ^(Y|y|N|n|)$ ]]; do
    echo -n "* $prompt"
    read -r result
    result=${result:-$default}

    [[ $result =~ ^(Y|y|N|n)$ ]] || error "Digite 'y' para sim ou 'n' para não."
  done

  eval "$__resultvar"='${result,,}'
}

# ---------------------- Detecta OS e arquitetura ---------------------- #

get_os() {
  local os
  local os_ver
  local os_major_ver
  local arch

  os=$(awk -F= '/^ID=/{print $2}' /etc/os-release | tr -d '"')
  os_ver=$(awk -F= '/^VERSION_ID=/{print $2}' /etc/os-release | tr -d '"')

  # Para distribuições como Ubuntu 22.04
  os_major_ver=$(echo "$os_ver" | cut -d'.' -f1)

  arch=$(uname -m)

  echo "$os" "$os_major_ver" "$arch"
}

is_supported_os() {
  local os=$1
  local arch=$2

  if [[ "$os" == "ubuntu" || "$os" == "debian" || "$os" == "rocky" || "$os" == "almalinux" ]]; then
    if [[ "$arch" == "x86_64" ]]; then
      return 0
    fi
  fi

  return 1
}
