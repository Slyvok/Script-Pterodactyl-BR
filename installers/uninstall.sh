#!/bin/bash

set -e

# Verifica se o script está carregado, carrega se não estiver ou falha caso contrário.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/$GITHUB_SOURCE"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* ERRO: Não foi possível carregar o script lib" && exit 1
fi

# ------------------ Variáveis ----------------- #

RM_PANEL="${RM_PANEL:-true}"
RM_WINGS="${RM_WINGS:-true}"

# ---------- Funções de desinstalação ---------- #

rm_panel_files() {
  output "Removendo arquivos do painel..."
  rm -rf /var/www/pterodactyl /usr/local/bin/composer
  [ "$OS" != "centos" ] && unlink /etc/nginx/sites-enabled/pterodactyl.conf
  [ "$OS" != "centos" ] && rm -f /etc/nginx/sites-available/pterodactyl.conf
  [ "$OS" != "centos" ] && ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
  [ "$OS" == "centos" ] && rm -f /etc/nginx/conf.d/pterodactyl.conf
  systemctl restart nginx
  success "Arquivos do painel removidos."
}

rm_docker_containers() {
  output "Removendo containers e imagens Docker..."

  docker system prune -a -f

  success "Containers e imagens Docker removidos."
}

rm_wings_files() {
  output "Removendo arquivos do Wings..."

  systemctl disable --now wings
  [ -f /etc/systemd/system/wings.service ] && rm -rf /etc/systemd/system/wings.service

  [ -d /etc/pterodactyl ] && rm -rf /etc/pterodactyl
  [ -f /usr/local/bin/wings ] && rm -rf /usr/local/bin/wings
  [ -d /var/lib/pterodactyl ] && rm -rf /var/lib/pterodactyl
  success "Arquivos do Wings removidos."
}

rm_services() {
  output "Removendo serviços..."
  systemctl disable --now pteroq
  rm -rf /etc/systemd/system/pteroq.service
  case "$OS" in
  debian | ubuntu)
    systemctl disable --now redis-server
    ;;
  centos)
    systemctl disable --now redis
    systemctl disable --now php-fpm
    rm -rf /etc/php-fpm.d/www-pterodactyl.conf
    ;;
  esac
  success "Serviços removidos."
}

rm_cron() {
  output "Removendo tarefas agendadas (cron jobs)..."
  crontab -l | grep -vF "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1" | crontab -
  success "Tarefas agendadas removidas."
}

rm_database() {
  output "Removendo banco de dados..."
  valid_db=$(mariadb -u root -e "SELECT schema_name FROM information_schema.schemata;" | grep -v -E -- 'schema_name|information_schema|performance_schema|mysql')
  warning "Cuidado! Este banco de dados será deletado!"
  if [[ "$valid_db" == *"panel"* ]]; then
    echo -n "* Um banco chamado panel foi detectado. É o banco do pterodactyl? (s/N): "
    read -r is_panel
    if [[ "$is_panel" =~ [Ss] ]]; then
      DATABASE=panel
    else
      print_list "$valid_db"
    fi
  else
    print_list "$valid_db"
  fi
  while [ -z "$DATABASE" ] || [[ $valid_db != *"$database_input"* ]]; do
    echo -n "* Escolha o banco de dados do painel (para pular, não digite nada): "
    read -r database_input
    if [[ -n "$database_input" ]]; then
      DATABASE="$database_input"
    else
      break
    fi
  done
  [[ -n "$DATABASE" ]] && mariadb -u root -e "DROP DATABASE $DATABASE;"
  # Exclui nomes de usuário User e root (espera-se que ninguém use "User")
  output "Removendo usuário do banco de dados..."
  valid_users=$(mariadb -u root -e "SELECT user FROM mysql.user;" | grep -v -E -- 'user|root')
  warning "Cuidado! Este usuário será deletado!"
  if [[ "$valid_users" == *"pterodactyl"* ]]; then
    echo -n "* Usuário chamado pterodactyl foi detectado. É o usuário do pterodactyl? (s/N): "
    read -r is_user
    if [[ "$is_user" =~ [Ss] ]]; then
      DB_USER=pterodactyl
    else
      print_list "$valid_users"
    fi
  else
    print_list "$valid_users"
  fi
  while [ -z "$DB_USER" ] || [[ $valid_users != *"$user_input"* ]]; do
    echo -n "* Escolha o usuário do painel (para pular, não digite nada): "
    read -r user_input
    if [[ -n "$user_input" ]]; then
      DB_USER=$user_input
    else
      break
    fi
  done
  [[ -n "$DB_USER" ]] && mariadb -u root -e "DROP USER $DB_USER@'127.0.0.1';"
  mariadb -u root -e "FLUSH PRIVILEGES;"
  success "Banco de dados e usuário removidos."
}

# --------------- Funções principais --------------- #

perform_uninstall() {
  [ "$RM_PANEL" == true ] && rm_panel_files
  [ "$RM_PANEL" == true ] && rm_cron
  [ "$RM_PANEL" == true ] && rm_database
  [ "$RM_PANEL" == true ] && rm_services
  [ "$RM_WINGS" == true ] && rm_docker_containers
  [ "$RM_WINGS" == true ] && rm_wings_files

  return 0
}

# ------------------ Desinstalação ----------------- #

perform_uninstall
