#!/bin/bash
# Mede as queries foco. Uso: ./run_bench.sh <pg|gp> <SF> [runs=5]
#
# pg: roda no schema `pg`.  gp: roda nos schemas e1..e4 (estratégias de distribuição).
# Cada query: 1 execução de aquecimento (descartada) + <runs> medidas.
# Tempo = o `\timing` do psql (servidor + rede local), em ms. Os resultados da
# query vão para /dev/null (dentro do contêiner) para não pesar no tempo.
# Saída (acrescenta ao CSV): results/raw_<pg|gp4|gp2>_sf<SF>.csv  (SEGS=2 para o cluster de 2 segmentos)
# Rode um sistema por vez (RAM) e deixe o outro derrubado com ./run.sh down.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../tpch/common.sh"

SYS=${1:?uso: ./run_bench.sh <pg|gp> <SF> [runs]}
SF=${2:?uso: ./run_bench.sh <pg|gp> <SF> [runs]}
RUNS=${3:-5}
# Rótulo do sistema na saída: pg, gp4 ou gp2 (nº de segmentos = SEGS, padrão 4)
LABEL=$SYS; [ "$SYS" = gp ] && LABEL="gp${SEGS:-4}"
OUT="$ROOT/results/raw_${LABEL}_sf${SF}.csv"
QUERIES="q01 q03 q05 q06 q09 q13 q18 q21 q22"

if [ "$SYS" = pg ]; then SCHEMAS="pg"; else SCHEMAS="e1 e2 e3 e4"; fi
[ -f "$OUT" ] || echo "system,schema,sf,query,run,ms" > "$OUT"

# time_query <schema> <arquivo.sql> -> imprime ms
time_query() {
  { echo "SET search_path=$1;"; echo '\timing on'; echo '\o /dev/null'; cat "$2"; } \
    | psql_sys "$SYS" | sed -n 's/^Time: \([0-9.]*\) ms.*/\1/p' | tail -n1
}

for s in $SCHEMAS; do
  for q in $QUERIES; do
    f="$ROOT/tpch/queries/$q.sql"
    time_query "$s" "$f" >/dev/null   # aquecimento
    for r in $(seq 1 "$RUNS"); do
      ms=$(time_query "$s" "$f")
      echo "$LABEL,$s,$SF,$q,$r,$ms" | tee -a "$OUT"
    done
  done
done
echo "Gravado em $OUT"
