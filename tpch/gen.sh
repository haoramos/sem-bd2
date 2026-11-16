#!/bin/bash
# Gera os dados do TPC-H com o dbgen. Uso: ./gen.sh <fator de escala>   (ex.: ./gen.sh 1)
# Precisa de git, make e gcc no Ubuntu (sudo apt install build-essential git).
# Saída: tpch/data/sf<SF>/*.tbl (ignorado pelo Git).
set -euo pipefail

SF=${1:?uso: ./gen.sh <fator de escala>}
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/.dbgen-src"
OUT="$DIR/data/sf$SF"

if [ ! -x "$SRC/dbgen" ]; then
  [ -d "$SRC" ] || git clone --depth 1 https://github.com/electrum/tpch-dbgen "$SRC"
  (cd "$SRC" \
    && { make MACHINE=LINUX DATABASE=POSTGRESQL \
         || { make clean; make MACHINE=LINUX DATABASE=ORACLE; }; })
fi

mkdir -p "$OUT"
# dbgen precisa do dists.dss no diretório atual; DSS_PATH define onde gravar.
(cd "$SRC" && DSS_PATH="$OUT" ./dbgen -s "$SF" -f)
ls -lh "$OUT"
