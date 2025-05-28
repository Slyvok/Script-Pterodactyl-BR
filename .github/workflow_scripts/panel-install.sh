#!/bin/bash

set -e


export GITHUB_SOURCE="master"
export GITHUB_BASE_URL="https://raw.githubusercontent.com/Slyvok/Script-Pterodactyl-BR"
export email="test@test.com"
export user_email="test@test.com"
export user_username="test"
export user_firstname="test"
export user_lastname="test"
export user_password="test"
export CONFIGURE_FIREWALL=true

# shellcheck source=lib/lib.sh
source /tmp/lib.sh

update_repos

install_packages "curl"

bash /vagrant/installers/panel.sh
