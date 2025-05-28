#!/bin/bash

set -e

# Check if script is loaded, load if not or fail otherwise.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/$GITHUB_SOURCE"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* ERRO: Não foi possível carregar o script lib" && exit 1
fi

# ------------------ Variáveis ----------------- #

# Nome de domínio / IP
export FQDN=""

# Credenciais padrão do MySQL
export MYSQL_DB=""
export MYSQL_USER=""
export MYSQL_PASSWORD=""

# Ambiente
export timezone=""
export email=""

# Conta admin inicial
export user_email=""
export user_username=""
export user_firstname=""
export user_lastname=""
export user_password=""

# Assume SSL, buscará configuração diferente se verdadeiro
export ASSUME_SSL=false
export CONFIGURE_LETSENCRYPT=false

# Firewall
export CONFIGURE_FIREWALL=false

# ------------ Funções de entrada do usuário ------------ #

ask_letsencrypt() {
  if [ "$CONFIGURE_UFW" == false ] && [ "$CONFIGURE_FIREWALL_CMD" == false ]; then
    warning "O Let's Encrypt requer que as portas 80/443 estejam abertas! Você optou por não configurar o firewall automaticamente; use isso por sua conta e risco (se as portas 80/443 estiverem fechadas, o script falhará)!"
  fi

  echo -e -n "* Deseja configurar HTTPS automaticamente usando o Let's Encrypt? (s/N): "
  read -r CONFIRM_SSL

  if [[ "$CONFIRM_SSL" =~ [Ss] ]]; then
    CONFIGURE_LETSENCRYPT=true
    ASSUME_SSL=false
  fi
}

ask_assume_ssl() {
  output "O Let's Encrypt não será configurado automaticamente por este script (usuário optou por não configurar)."
  output "Você pode 'assumir' o uso do Let's Encrypt, o que significa que o script baixará uma configuração nginx configurada para usar certificado Let's Encrypt, mas não obterá o certificado para você."
  output "Se você assumir SSL e não obter o certificado, sua instalação não funcionará."
  echo -n "* Deseja assumir SSL? (s/N): "
  read -r ASSUME_SSL_INPUT

  [[ "$ASSUME_SSL_INPUT" =~ [Ss] ]] && ASSUME_SSL=true
  true
}

check_FQDN_SSL() {
  if [[ $(invalid_ip "$FQDN") == 1 && $FQDN != 'localhost' ]]; then
    SSL_AVAILABLE=true
  else
    warning "* Let's Encrypt não estará disponível para endereços IP."
    output "Para usar o Let's Encrypt, você deve usar um nome de domínio válido."
  fi
}

main() {
  # verifica se já existe uma instalação
  if [ -d "/var/www/pterodactyl" ]; then
    warning "O script detectou que você já possui o painel Pterodactyl instalado! Não é possível executar o script múltiplas vezes, ele irá falhar!"
    echo -e -n "* Tem certeza que deseja continuar? (s/N): "
    read -r CONFIRM_PROCEED
    if [[ ! "$CONFIRM_PROCEED" =~ [Ss] ]]; then
      error "Instalação abortada!"
      exit 1
    fi
  fi

  welcome "painel"

  check_os_x86_64

  # configurar credenciais do banco de dados
  output "Configuração do banco de dados."
  output ""
  output "Estas serão as credenciais usadas para comunicação entre o MySQL"
  output "e o painel. Você não precisa criar o banco de dados"
  output "antes de rodar este script, ele fará isso para você."
  output ""

  MYSQL_DB="-"
  while [[ "$MYSQL_DB" == *"-"* ]]; do
    required_input MYSQL_DB "Nome do banco de dados (painel): " "" "painel"
    [[ "$MYSQL_DB" == *"-"* ]] && error "Nome do banco de dados não pode conter hífens"
  done

  MYSQL_USER="-"
  while [[ "$MYSQL_USER" == *"-"* ]]; do
    required_input MYSQL_USER "Usuário do banco de dados (pterodactyl): " "" "pterodactyl"
    [[ "$MYSQL_USER" == *"-"* ]] && error "Usuário do banco de dados não pode conter hífens"
  done

  # entrada de senha MySQL
  rand_pw=$(gen_passwd 64)
  password_input MYSQL_PASSWORD "Senha (pressione enter para usar senha gerada aleatoriamente): " "Senha do MySQL não pode ser vazia" "$rand_pw"

  readarray -t valid_timezones <<<"$(curl -s "$GITHUB_URL"/configs/valid_timezones.txt)"
  output "Lista de fusos horários válidos em $(hyperlink "https://www.php.net/manual/en/timezones.php")"

  while [ -z "$timezone" ]; do
    echo -n "* Selecione o fuso horário [America/Sao_Paulo]: "
    read -r timezone_input

    array_contains_element "$timezone_input" "${valid_timezones[@]}" && timezone="$timezone_input"
    [ -z "$timezone_input" ] && timezone="America/Sao_Paulo"
  done

  email_input email "Informe o e-mail que será usado para configurar o Let's Encrypt e o Pterodactyl: " "Email não pode ser vazio ou inválido"

  # Conta admin inicial
  email_input user_email "Email para a conta inicial de administrador: " "Email não pode ser vazio ou inválido"
  required_input user_username "Nome de usuário para a conta inicial de administrador: " "Nome de usuário não pode ser vazio"
  required_input user_firstname "Primeiro nome para a conta inicial de administrador: " "Nome não pode ser vazio"
  required_input user_lastname "Sobrenome para a conta inicial de administrador: " "Nome não pode ser vazio"
  password_input user_password "Senha para a conta inicial de administrador: " "Senha não pode ser vazia"

  print_brake 72

  # definir FQDN
  while [ -z "$FQDN" ]; do
    echo -n "* Defina o FQDN deste painel (painel.exemplo.com): "
    read -r FQDN
    [ -z "$FQDN" ] && error "FQDN não pode ser vazio"
  done

  # Verificar se SSL está disponível
  check_FQDN_SSL

  # Perguntar se firewall será configurado
  ask_firewall CONFIGURE_FIREWALL

  # Perguntar sobre SSL só se disponível
  if [ "$SSL_AVAILABLE" == true ]; then
    # Perguntar se Let's Encrypt será configurado
    ask_letsencrypt
    # Se ainda for falso, pergunta sobre assumir SSL
    [ "$CONFIGURE_LETSENCRYPT" == false ] && ask_assume_ssl
  fi

  # verificar FQDN se usuário escolheu assumir SSL ou configurar Let's Encrypt
  [ "$CONFIGURE_LETSENCRYPT" == true ] || [ "$ASSUME_SSL" == true ] && bash <(curl -s "$GITHUB_URL"/lib/verify-fqdn.sh) "$FQDN"

  # resumo
  summary

  # confirmar instalação
  echo -e -n "\n* Configuração inicial concluída. Continuar com a instalação? (s/N): "
  read -r CONFIRM
  if [[ "$CONFIRM" =~ [Ss] ]]; then
    run_installer "painel"
  else
    error "Instalação abortada."
    exit 1
  fi
}

summary() {
  print_brake 62
  output "Painel Pterodactyl $PTERODACTYL_PANEL_VERSION com nginx no $OS"
  output "Nome do banco de dados: $MYSQL_DB"
  output "Usuário do banco de dados: $MYSQL_USER"
  output "Senha do banco de dados: (oculta)"
  output "Fuso horário: $timezone"
  output "Email: $email"
  output "Email do usuário: $user_email"
  output "Nome de usuário: $user_username"
  output "Primeiro nome: $user_firstname"
  output "Sobrenome: $user_lastname"
  output "Senha do usuário: (oculta)"
  output "Hostname/FQDN: $FQDN"
  output "Configurar Firewall? $CONFIGURE_FIREWALL"
  output "Configurar Let's Encrypt? $CONFIGURE_LETSENCRYPT"
  output "Assumir SSL? $ASSUME_SSL"
  print_brake 62
}

goodbye() {
  print_brake 62
  output "Instalação do painel concluída"
  output ""

  [ "$CONFIGURE_LETSENCRYPT" == true ] && output "Seu painel deve estar acessível em $(hyperlink "$FQDN")"
  [ "$ASSUME_SSL" == true ] && [ "$CONFIGURE_LETSENCRYPT" == false ] && output "Você optou por usar SSL, mas não via Let's Encrypt automaticamente. Seu painel não funcionará até que o SSL seja configurado."
  [ "$ASSUME_SSL" == false ] && [ "$CONFIGURE_LETSENCRYPT" == false ] && output "Seu painel deve estar acessível em $(hyperlink "$FQDN")"

  output ""
  output "A instalação está usando nginx no $OS"
  output "Obrigado por usar este script."
  [ "$CONFIGURE_FIREWALL" == false ] && echo -e "* ${COLOR_RED}Nota${COLOR_NC}: Se você não configurou o firewall: as portas 80/443 (HTTP/HTTPS) precisam estar abertas!"
  print_brake 62
}

# rodar script
main
goodbye
