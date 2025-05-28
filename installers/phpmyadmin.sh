#!/bin/bash

set -e

# Verifica se a função está carregada, carrega se não estiver ou falha caso contrário.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/$GITHUB_SOURCE"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* ERRO: Não foi possível carregar o script de biblioteca" && exit 1
fi

# Quando o #280 for mesclado
