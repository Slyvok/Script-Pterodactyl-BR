#!/bin/bash

set -e

export GITHUB_SOURCE="master"
export GITHUB_BASE_URL="https://raw.githubusercontent.com/Slyvok/Script-Pterodactyl-BR"
export CONFIGURE_FIREWALL=true
export CONFIGURE_DBHOST=true
export INSTALL_MARIADB=true
export CONFIGURE_DB_FIREWALL=true
export MYSQL_DBHOST_PASSWORD="test"

# shellcheck source=lib/lib.sh
source /tmp/lib.sh

update_repos

install_packages "curl"

bash /vagrant/installers/wings.sh
