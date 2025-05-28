#!/bin/bash

set -e  # Encerra o script ao encontrar qualquer erro

# Verifica se o script da biblioteca está carregado; se não, tenta carregar ou falha.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  source /tmp/lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/$GITHUB_SOURCE"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* ERRO: Não foi possível carregar o script da biblioteca" && exit 1
fi

# ------------------ Variáveis ------------------ #

FQDN="${FQDN:-localhost}"  # Nome de domínio ou IP

# Credenciais padrão do MySQL
MYSQL_DB="${MYSQL_DB:-panel}"
MYSQL_USER="${MYSQL_USER:-pterodactyl}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(gen_passwd 64)}"

# Ambiente
timezone="${timezone:-America/Sao_Paulo}"

# SSL
ASSUME_SSL="${ASSUME_SSL:-false}"
CONFIGURE_LETSENCRYPT="${CONFIGURE_LETSENCRYPT:-false}"

# Firewall
CONFIGURE_FIREWALL="${CONFIGURE_FIREWALL:-false}"

# Variáveis obrigatórias (sem valor padrão)
email="${email:-}"
user_email="${user_email:-}"
user_username="${user_username:-}"
user_firstname="${user_firstname:-}"
user_lastname="${user_lastname:-}"
user_password="${user_password:-}"

# Verificações das variáveis obrigatórias
[[ -z "${email}" ]] && error "Email é obrigatório" && exit 1
[[ -z "${user_email}" ]] && error "Email do usuário é obrigatório" && exit 1
[[ -z "${user_username}" ]] && error "Nome de usuário é obrigatório" && exit 1
[[ -z "${user_firstname}" ]] && error "Primeiro nome é obrigatório" && exit 1
[[ -z "${user_lastname}" ]] && error "Último nome é obrigatório" && exit 1
[[ -z "${user_password}" ]] && error "Senha do usuário é obrigatória" && exit 1

# ------------- Funções principais ------------- #

install_composer() {
  output "Instalando o Composer..."
  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
  success "Composer instalado!"
}

ptdl_dl() {
  output "Baixando os arquivos do painel Pterodactyl..."
  mkdir -p /var/www/pterodactyl
  cd /var/www/pterodactyl || exit

  curl -Lo panel.tar.gz "$PANEL_DL_URL"
  tar -xzvf panel.tar.gz
  chmod -R 755 storage/* bootstrap/cache/

  cp .env.example .env

  success "Arquivos do painel baixados com sucesso!"
}

install_composer_deps() {
  output "Instalando dependências do Composer..."
  [ "$OS" == "rocky" ] || [ "$OS" == "almalinux" ] && export PATH=/usr/local/bin:$PATH
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
  success "Dependências do Composer instaladas!"
}

configure() {
  output "Configurando o ambiente..."

  local app_url="http://$FQDN"
  [ "$ASSUME_SSL" == true ] && app_url="https://$FQDN"
  [ "$CONFIGURE_LETSENCRYPT" == true ] && app_url="https://$FQDN"

  php artisan key:generate --force

  php artisan p:environment:setup \
    --author="$email" \
    --url="$app_url" \
    --timezone="$timezone" \
    --cache="redis" \
    --session="redis" \
    --queue="redis" \
    --redis-host="localhost" \
    --redis-pass="null" \
    --redis-port="6379" \
    --settings-ui=true

  php artisan p:environment:database \
    --host="127.0.0.1" \
    --port="3306" \
    --database="$MYSQL_DB" \
    --username="$MYSQL_USER" \
    --password="$MYSQL_PASSWORD"

  php artisan migrate --seed --force

  php artisan p:user:make \
    --email="$user_email" \
    --username="$user_username" \
    --name-first="$user_firstname" \
    --name-last="$user_lastname" \
    --password="$user_password" \
    --admin=1

  success "Ambiente configurado!"
}

set_folder_permissions() {
  case "$OS" in
  debian | ubuntu)
    chown -R www-data:www-data ./*
    ;;
  rocky | almalinux)
    chown -R nginx:nginx ./*
    ;;
  esac
}

insert_cronjob() {
  output "Instalando cronjob..."

  crontab -l | {
    cat
    output "* * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
  } | crontab -

  success "Cronjob instalado!"
}

install_pteroq() {
  output "Instalando serviço pteroq..."

  curl -o /etc/systemd/system/pteroq.service "$GITHUB_URL"/configs/pteroq.service

  case "$OS" in
  debian | ubuntu)
    sed -i -e "s@<user>@www-data@g" /etc/systemd/system/pteroq.service
    ;;
  rocky | almalinux)
    sed -i -e "s@<user>@nginx@g" /etc/systemd/system/pteroq.service
    ;;
  esac

  systemctl enable pteroq.service
  systemctl start pteroq

  success "Serviço pteroq instalado!"
}

enable_services() {
  case "$OS" in
  ubuntu | debian)
    systemctl enable redis-server
    systemctl start redis-server
    ;;
  rocky | almalinux)
    systemctl enable redis
    systemctl start redis
    ;;
  esac

  systemctl enable nginx
  systemctl enable mariadb
  systemctl start mariadb
}

selinux_allow() {
  setsebool -P httpd_can_network_connect 1 || true
  setsebool -P httpd_execmem 1 || true
  setsebool -P httpd_unified 1 || true
}

php_fpm_conf() {
  curl -o /etc/php-fpm.d/www-pterodactyl.conf "$GITHUB_URL"/configs/www-pterodactyl.conf
  systemctl enable php-fpm
  systemctl start php-fpm
}

# Dependências para cada sistema operacional
ubuntu_dep() { ... }
debian_dep() { ... }
alma_rocky_dep() { ... }

dep_install() {
  output "Instalando dependências para $OS $OS_VER..."

  update_repos

  [ "$CONFIGURE_FIREWALL" == true ] && install_firewall && firewall_ports

  case "$OS" in
  ubuntu | debian)
    ...
    ;;
  rocky | almalinux)
    ...
    ;;
  esac

  enable_services
  success "Dependências instaladas!"
}

firewall_ports() {
  output "Abrindo portas: 22 (SSH), 80 (HTTP) e 443 (HTTPS)"
  firewall_allow_ports "22 80 443"
  success "Portas abertas no firewall!"
}

letsencrypt() {
  FAILED=false

  output "Configurando Let's Encrypt..."

  certbot --nginx --redirect --no-eff-email --email "$email" -d "$FQDN" || FAILED=true

  if [ ! -d "/etc/letsencrypt/live/$FQDN/" ] || [ "$FAILED" == true ]; then
    warning "Falha ao obter certificado Let's Encrypt!"
    echo -n "* Ainda assim assumir SSL? (s/N): "
    read -r CONFIGURE_SSL

    if [[ "$CONFIGURE_SSL" =~ [Ss] ]]; then
      ASSUME_SSL=true
      CONFIGURE_LETSENCRYPT=false
      configure_nginx
    else
      ASSUME_SSL=false
      CONFIGURE_LETSENCRYPT=false
    fi
  else
    success "Certificado Let's Encrypt obtido com sucesso!"
  fi
}

configure_nginx() {
  output "Configurando Nginx..."

  if [ "$ASSUME_SSL" == true ] && [ "$CONFIGURE_LETSENCRYPT" == false ]; then
    DL_FILE="nginx_ssl.conf"
  else
    DL_FILE="nginx.conf"
  fi

  case "$OS" in
  ubuntu | debian)
    PHP_SOCKET="/run/php/php8.3-fpm.sock"
    CONFIG_PATH_AVAIL="/etc/nginx/sites-available"
    CONFIG_PATH_ENABL="/etc/nginx/sites-enabled"
    ;;
  rocky | almalinux)
    PHP_SOCKET="/var/run/php-fpm/pterodactyl.sock"
    CONFIG_PATH_AVAIL="/etc/nginx/conf.d"
    CONFIG_PATH_ENABL="$CONFIG_PATH_AVAIL"
    ;;
  esac

  rm -rf "$CONFIG_PATH_ENABL"/default

  curl -o "$CONFIG_PATH_AVAIL"/pterodactyl.conf "$GITHUB_URL"/configs/$DL_FILE

  sed -i -e "s@<domain>@${FQDN}@g" "$CONFIG_PATH_AVAIL"/pterodactyl.conf
  sed -i -e "s@<php_socket>@${PHP_SOCKET}@g" "$CONFIG_PATH_AVAIL"/pterodactyl.conf

  [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ] && ln -sf "$CONFIG_PATH_AVAIL"/pterodactyl.conf "$CONFIG_PATH_ENABL"/pterodactyl.conf

  [ "$ASSUME_SSL" == false ] && [ "$CONFIGURE_LETSENCRYPT" == false ] && systemctl restart nginx

  success "Nginx configurado!"
}

perform_install() {
  output "Iniciando a instalação... isso pode levar algum tempo!"
  dep_install
  install_composer
  ptdl_dl
  install_composer_deps
  create_db_user "$MYSQL_USER" "$MYSQL_PASSWORD"
  create_db "$MYSQL_DB" "$MYSQL_USER"
  configure
  set_folder_permissions
  insert_cronjob
  install_pteroq
  configure_nginx
  [ "$CONFIGURE_LETSENCRYPT" == true ] && letsencrypt
  return 0
}

# ---------------- Executar ---------------- #

perform_install
