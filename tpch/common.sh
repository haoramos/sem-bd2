#!/bin/bash
# Funções comuns (usar com `source`). Rodar tudo DENTRO do WSL/Ubuntu.
# Sistemas: pg = PostgreSQL baseline, gp = WarehousePG.

TPCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TPCH_DIR/.." && pwd)"

# psql_sys <pg|gp> [args do psql]; o SQL vem por stdin ou -c
psql_sys() {
  local sys=$1; shift
  case "$sys" in
    pg) docker exec -i pg_baseline psql -U postgres -d demo -X -q -v ON_ERROR_STOP=1 "$@" ;;
    gp) "$ROOT/infra/warehousepg/run.sh" psql -X -q -v ON_ERROR_STOP=1 "$@" ;;
    *)  echo "sistema inválido: $sys (use pg ou gp)" >&2; return 1 ;;
  esac
}

TABLES="region nation part supplier partsupp customer orders lineitem"
