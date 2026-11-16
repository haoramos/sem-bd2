#!/bin/bash
# Controle do PostgreSQL baseline do laboratório (rodar DENTRO do WSL/Ubuntu).
#
# Uso: ./run.sh up | down | status | psql [args do psql] | reset
#
# Mesmo padrão de ../warehousepg/run.sh: a execução acontece numa cópia em
# /opt/lab/pg e a senha é gerada lá, fora do projeto.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN=/opt/lab/pg
PROJ=pgbase

sync_files() {
  mkdir -p "$RUN/secrets"
  cp "$SRC/pg.yaml" "$SRC/.env" "$RUN/"
  if [ ! -f "$RUN/secrets/pg_password" ]; then
    head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20 > "$RUN/secrets/pg_password"
  fi
  chmod 644 "$RUN/secrets/pg_password"
}

dc() { (cd "$RUN" && docker compose -p "$PROJ" -f pg.yaml "$@"); }

wait_ready() {
  echo "Aguardando o PostgreSQL..."
  for _ in $(seq 1 30); do
    if docker exec pg_baseline pg_isready -U postgres -d demo >/dev/null 2>&1; then
      echo "PostgreSQL pronto."
      return 0
    fi
    sleep 2
  done
  echo "Tempo esgotado. Veja: docker logs --tail 50 pg_baseline" >&2
  return 1
}

case "${1:-}" in
  up)     sync_files; dc up -d; wait_ready ;;
  down)   dc down ;;
  reset)  dc down -v || true; sync_files; dc up -d; wait_ready ;;
  status) docker ps -a --filter name=pg_baseline --format '{{.Names}}\t{{.Status}}' ;;
  psql)   shift
          if [ -t 0 ]; then TTY=-it; else TTY=-i; fi
          docker exec $TTY pg_baseline psql -U postgres -d demo "$@" ;;
  *)      echo "Uso: $0 up|down|status|psql [args]|reset" >&2; exit 1 ;;
esac
