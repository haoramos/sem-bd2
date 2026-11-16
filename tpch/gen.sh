#!/bin/bash
# Gera os dados do TPC-H com o dbgen. Uso: ./gen.sh <fator de escala>   (ex.: ./gen.sh 1)
# Precisa de git, make e gcc no Ubuntu (sudo apt install build-essential git).
# Saída: tpch/data/sf<SF>/*.tbl (ignorado pelo Git).
set -euo pipefail

SF=${1:?uso: ./gen.sh <fator de escala>}
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/.dbgen-src"
OUT="$DIR/data/sf$SF"

[ -d "$SRC" ] || git clone --depth 1 https://github.com/electrum/tpch-dbgen "$SRC"

build() {
  make MACHINE=LINUX DATABASE=POSTGRESQL || { make clean; make MACHINE=LINUX DATABASE=ORACLE; }
}

mkdir -p "$OUT"
# dbgen precisa do dists.dss no diretório atual; DSS_PATH define onde gravar.
if command -v gcc >/dev/null && command -v make >/dev/null; then
  [ -x "$SRC/dbgen" ] || (cd "$SRC" && build)
  (cd "$SRC" && DSS_PATH="$OUT" ./dbgen -s "$SF" -f)
else
  # Sem compilador no host: compila e roda dentro de um contêiner gcc (nada é instalado no host).
  echo "gcc/make ausentes; usando o contêiner gcc:13"
  docker run --rm -v "$SRC:/src" -v "$OUT:/out" -w /src -e DSS_PATH=/out gcc:13 bash -c \
    "$(declare -f build); [ -x dbgen ] || build; ./dbgen -s $SF -f"
fi
ls -lh "$OUT"
