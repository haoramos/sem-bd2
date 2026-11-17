#!/bin/bash
# Investiga anomalias do SF3: EXPLAIN ANALYZE + 3 medidas de cada caso. Uso: SEGS=<2|4> ./investigar.sh
# Casos: Q21 e1/e4 e Q9 e3/e4. Saída: results/explain/sf3_gp<SEGS>_<schema>_<query>.txt
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../tpch/common.sh"
SEGS=${SEGS:-4}
OUT="$ROOT/results/explain"; mkdir -p "$OUT"
for caso in q21:e1 q21:e4 q09:e3 q09:e4; do
  q=${caso%%:*}; e=${caso##*:}; f="$ROOT/tpch/queries/$q.sql"
  { echo "SET search_path=$e;"; echo -n "EXPLAIN ANALYZE "; cat "$f"; } | psql_sys gp > "$OUT/sf3_gp${SEGS}_${e}_${q}.txt"
  for r in 1 2 3; do
    ms=$({ echo "SET search_path=$e;"; echo '\timing on'; echo '\o /dev/null'; cat "$f"; } | psql_sys gp | sed -n 's/^Time: \([0-9.]*\) ms.*/\1/p' | tail -n1)
    echo "gp$SEGS $e $q rep$r ${ms}ms"
  done
done
