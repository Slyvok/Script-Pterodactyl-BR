#!/bin/bash

RELEASE=$1
DATE=$(date +%F)

COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m'

output() {
  echo -e "* $1"
}

error() {
  echo ""
  echo -e "* ${COLOR_RED}ERRO${COLOR_NC}: $1" 1>&2
  echo ""
}

[ -z "$RELEASE" ] && error "Variável de release ausente" && exit 1

output "Realizando release $RELEASE em $DATE"

sed -i "/next-release/c\## $RELEASE (lançado em $DATE)" CHANGELOG.md

# install.sh
sed -i "s/.*SCRIPT_RELEASE=.*/SCRIPT_RELEASE=\"$RELEASE\"/" install.sh
sed -i "s/.*GITHUB_SOURCE=.*/GITHUB_SOURCE=\"$RELEASE\"/" install.sh

output "Commit da release"

git add .
git commit -S -m "Release $RELEASE"
git push

output "Release $RELEASE enviada"

output "Crie uma nova release, com o changelog abaixo - https://github.com/Slyvok/Script-Pterodactyl-BR/releases/new"
output ""

changelog=$(scripts/changelog_parse.py)

cat <<EOF
# $RELEASE

Coloque aqui uma mensagem descrevendo a release.

## Changelog

$changelog
EOF
