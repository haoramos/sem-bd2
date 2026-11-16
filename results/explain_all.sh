#!/bin/bash
# EXPLAIN ANALYZE das queries de análise em todas as estratégias do Greenplum (cluster já carregado).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
for e in e1 e2 e3 e4; do
  ./explain.sh gp "$e" q03 q05 q09 q18 q21
done
