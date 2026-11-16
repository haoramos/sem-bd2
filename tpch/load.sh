#!/bin/bash
# Carrega o TPC-H. Uso: ./load.sh <pg|gp> <fator de escala>
#
#  pg: cria o schema `pg` no PostgreSQL baseline e carrega os .tbl.
#  gp: carrega os .tbl no schema `e4` (distribuição padrão) e copia para
#      e1 (co-localizada), e2 (aleatória) e e3 (skew em lineitem).
#
# Idempotente: apaga e recria os schemas. Gere os dados antes com ./gen.sh.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SYS=${1:?uso: ./load.sh <pg|gp> <SF>}
SF=${2:?uso: ./load.sh <pg|gp> <SF>}
DATA="$TPCH_DIR/data/sf$SF"
[ -f "$DATA/lineitem.tbl" ] || { echo "Faltam dados em $DATA. Rode ./gen.sh $SF" >&2; exit 1; }

# render_ddl <schema> <tabela=cláusula>...  -> imprime o DDL do schema
render_ddl() {
  local schema=$1; shift
  local sed_args=() kv
  for kv in "$@"; do
    sed_args+=(-e "s|@D_${kv%%=*}@|${kv#*=}|")
  done
  sed_args+=(-e 's|@D_[A-Z]*@||')   # o que sobrar fica sem cláusula (PostgreSQL)
  echo "DROP SCHEMA IF EXISTS $schema CASCADE; CREATE SCHEMA $schema; SET search_path=$schema;"
  sed "${sed_args[@]}" "$TPCH_DIR/ddl.sql.in"
}

# Distribuições. Região e nação são pequenas: replicadas onde faz sentido.
# Uma linha por tabela, no formato TABELA=cláusula.
dist_e1() { printf '%s\n' \
  "REGION=DISTRIBUTED REPLICATED" "NATION=DISTRIBUTED REPLICATED" \
  "PART=DISTRIBUTED BY (p_partkey)" "SUPPLIER=DISTRIBUTED BY (s_suppkey)" \
  "PARTSUPP=DISTRIBUTED BY (ps_partkey)" "CUSTOMER=DISTRIBUTED BY (c_custkey)" \
  "ORDERS=DISTRIBUTED BY (o_orderkey)" "LINEITEM=DISTRIBUTED BY (l_orderkey)"; }
dist_e2() { local t; for t in REGION NATION PART SUPPLIER PARTSUPP CUSTOMER ORDERS LINEITEM; do
  echo "$t=DISTRIBUTED RANDOMLY"; done; }
dist_e3() { dist_e1 | sed 's|DISTRIBUTED BY (l_orderkey)|DISTRIBUTED BY (l_returnflag)|'; }
dist_e4() { local t; for t in REGION NATION PART SUPPLIER PARTSUPP CUSTOMER ORDERS LINEITEM; do
  echo "$t="; done; }   # padrão do Greenplum: 1ª coluna

copy_files() {  # copy_files <schema>
  local t
  for t in $TABLES; do
    echo "  carregando $1.$t"
    sed 's/|$//' "$DATA/$t.tbl" \
      | psql_sys "$SYS" -c "\\copy $1.$t from stdin with (format text, delimiter '|')"
  done
}

if [ "$SYS" = pg ]; then
  render_ddl pg | psql_sys pg
  copy_files pg
  { echo "SET search_path=pg;"; cat "$TPCH_DIR/pg_indexes.sql"; } | psql_sys pg
  psql_sys pg -c "VACUUM ANALYZE" -c "SELECT 'lineitem' t, count(*) FROM pg.lineitem"
else
  for s in e4 e1 e2 e3; do
    echo "== schema $s =="
    mapfile -t kvs < <(dist_$s)
    render_ddl "$s" "${kvs[@]}" | psql_sys gp
    if [ "$s" = e4 ]; then
      copy_files e4
    else
      for t in $TABLES; do
        echo "  copiando e4.$t -> $s.$t"
        psql_sys gp -c "INSERT INTO $s.$t SELECT * FROM e4.$t"
      done
    fi
    psql_sys gp -c "ANALYZE" -c "SET search_path=$s; SELECT '$s' schema, count(*) AS lineitem FROM lineitem"
  done
fi
echo "Carga concluída ($SYS, SF$SF)."
