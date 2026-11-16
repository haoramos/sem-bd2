#!/bin/bash
# Guarda o EXPLAIN ANALYZE das queries foco. Uso: ./explain.sh <pg|gp> <schema> [queries...]
# Ex.: ./explain.sh gp e1 q03 q05   (compare com e2 para ver Redistribute/Broadcast Motion)
# Saída: results/explain/<sistema>_<schema>_<query>.txt
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../tpch/common.sh"

SYS=${1:?uso: ./explain.sh <pg|gp> <schema> [queries...]}
SCHEMA=${2:?uso: ./explain.sh <pg|gp> <schema> [queries...]}
shift 2
QUERIES=${*:-q01 q03 q05 q06 q09 q13 q18 q21 q22}
mkdir -p "$ROOT/results/explain"

for q in $QUERIES; do
  f="$ROOT/tpch/queries/$q.sql"
  out="$ROOT/results/explain/${SYS}_${SCHEMA}_${q}.txt"
  { echo "SET search_path=$SCHEMA;"; echo -n "EXPLAIN ANALYZE "; cat "$f"; } \
    | psql_sys "$SYS" > "$out"
  echo "$out ($(grep -c 'Motion' "$out" || true) linhas com Motion)"
done
