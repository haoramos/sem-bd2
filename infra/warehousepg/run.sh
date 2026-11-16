#!/bin/bash
# Controle do cluster WarehousePG do laboratório (rodar DENTRO do WSL/Ubuntu).
#
# Uso: ./run.sh up | down | status | psql [args do psql] | reset
# SEGS=2 ./run.sh up   sobe a variante com 2 segmentos (padrão: 4). Use `down` antes de trocar.
#
# Os arquivos versionados ficam nesta pasta. A execução acontece numa cópia em
# /opt/lab/whpg (sistema de arquivos do Linux), porque o contêiner precisa alterar
# o dono e a permissão das chaves SSH, o que não funciona bem em /mnt/c.
# Senhas e chaves SSH são geradas lá e nunca entram no projeto.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN=/opt/lab/whpg
PROJ=whpg
SEGS=${SEGS:-4}
case "$SEGS" in
  4) LAB=lab.yaml;  CFG=gpinitsystem_config_no_mirrors ;;
  2) LAB=lab2.yaml; CFG=gpinitsystem_config_no_mirrors_2seg ;;
  *) echo "SEGS deve ser 2 ou 4" >&2; exit 1 ;;
esac
GP_ENV='source /usr/local/greenplum-db/greenplum_path.sh'

sync_files() {
  mkdir -p "$RUN/conf/7" "$RUN/conf/ssh" "$RUN/secrets"
  cp "$SRC/lab.yaml" "$SRC/lab2.yaml" "$SRC/.env" "$RUN/"
  cp "$SRC"/conf/7/gpinitsystem_config_no_mirrors* "$RUN/conf/7/"
  cp "$SRC/conf/hostfile_gpinitsystem" "$RUN/conf/"

  if [ ! -f "$RUN/conf/ssh/id_rsa" ]; then
    ssh-keygen -q -t rsa -b 3072 -N '' -f "$RUN/conf/ssh/id_rsa"
    cp "$RUN/conf/ssh/id_rsa.pub" "$RUN/conf/ssh/authorized_keys"
  fi
  # uid 1001 = gpadmin dentro da imagem
  chown 1001:1001 "$RUN/conf/ssh/id_rsa" "$RUN/conf/ssh/id_rsa.pub"
  chmod 600 "$RUN/conf/ssh/id_rsa"
  chmod 644 "$RUN/conf/ssh/id_rsa.pub" "$RUN/conf/ssh/authorized_keys"

  for f in gpdb_password gpmon_password; do
    if [ ! -f "$RUN/secrets/$f" ]; then
      head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20 > "$RUN/secrets/$f"
    fi
    chmod 644 "$RUN/secrets/$f"   # o usuário do contêiner precisa ler
  done
}

dc() { (cd "$RUN" && docker compose -p "$PROJ" -f "$LAB" "$@"); }

wait_ready() {
  echo "Aguardando o cluster (até ~5 min)..."
  for _ in $(seq 1 60); do
    if docker exec -u gpadmin master bash -lc "$GP_ENV; psql -d demo -Atc 'select 1'" >/dev/null 2>&1; then
      echo "Cluster pronto."
      return 0
    fi
    sleep 5
  done
  echo "Tempo esgotado. Veja: docker logs --tail 50 master" >&2
  return 1
}

case "${1:-}" in
  up)     sync_files; dc up -d; wait_ready ;;
  down)   dc down ;;
  reset)  dc down -v || true; sync_files; dc up -d; wait_ready ;;
  status) docker ps -a --filter name=master --filter name=segment --format '{{.Names}}\t{{.Status}}' ;;
  psql)   shift
          if [ -t 0 ]; then TTY=-it; else TTY=-i; fi
          ARGS=$(printf '%q ' "$@")
          docker exec $TTY -u gpadmin master bash -lc "$GP_ENV; psql -d demo $ARGS" ;;
  *)      echo "Uso: $0 up|down|status|psql [args]|reset" >&2; exit 1 ;;
esac
