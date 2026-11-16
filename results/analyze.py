#!/usr/bin/env python3
"""Resume os CSVs de results/raw_*.csv: mediana, IQR e speedup contra o PostgreSQL.

Uso: python results/analyze.py [SF]          (padrão: todos os SF encontrados)
Saída: results/summary_sf<SF>.csv e tabela no terminal. Só usa a biblioteca padrão.
Speedup = mediana(pg) / mediana(gp, estratégia). Eficiência = speedup / 4 segmentos.
Se matplotlib estiver instalado, também grava results/speedup_sf<SF>.png.
"""
import csv
import glob
import os
import statistics
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
SEGMENTOS = 4


def iqr(xs):
    if len(xs) < 4:
        return 0.0
    q = statistics.quantiles(xs, n=4, method="inclusive")
    return q[2] - q[0]


def carregar(sf):
    dados = defaultdict(list)  # (sistema, schema, query) -> [ms]
    for path in glob.glob(os.path.join(HERE, f"raw_*_sf{sf}.csv")):
        with open(path, newline="") as f:
            for r in csv.DictReader(f):
                if r["ms"]:
                    dados[(r["system"], r["schema"], r["query"])].append(float(r["ms"]))
    return dados


def resumir(sf):
    dados = carregar(sf)
    if not dados:
        return []
    med = {k: statistics.median(v) for k, v in dados.items()}
    linhas = []
    for (sis, schema, q), v in sorted(dados.items(), key=lambda kv: (kv[0][2], kv[0][0], kv[0][1])):
        m = med[(sis, schema, q)]
        base = med.get(("pg", "pg", q))
        speedup = base / m if (sis == "gp" and base) else ""
        linhas.append({
            "sf": sf, "query": q, "system": sis, "schema": schema, "n": len(v),
            "median_ms": round(m, 1), "iqr_ms": round(iqr(v), 1),
            "speedup_vs_pg": round(speedup, 2) if speedup != "" else "",
            "eficiencia": round(speedup / SEGMENTOS, 2) if speedup != "" else "",
        })
    return linhas


def grafico(linhas, sf):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        return
    qs = sorted({l["query"] for l in linhas})
    esquemas = sorted({l["schema"] for l in linhas if l["system"] == "gp"})
    largura = 0.8 / max(len(esquemas), 1)
    plt.figure(figsize=(9, 4))
    for i, e in enumerate(esquemas):
        ys = [next((l["speedup_vs_pg"] for l in linhas
                    if l["query"] == q and l["schema"] == e), 0) or 0 for q in qs]
        plt.bar([x + i * largura for x in range(len(qs))], ys, largura, label=e)
    plt.axhline(1, color="k", lw=0.8, ls="--")
    plt.xticks([x + 0.4 - largura / 2 for x in range(len(qs))], qs)
    plt.ylabel("speedup vs PostgreSQL (>1 = Greenplum mais rápido)")
    plt.title(f"TPC-H SF{sf}")
    plt.legend(title="estratégia")
    plt.tight_layout()
    plt.savefig(os.path.join(HERE, f"speedup_sf{sf}.png"), dpi=150)


def main():
    if len(sys.argv) > 1:
        sfs = [sys.argv[1]]
    else:
        sfs = sorted({os.path.basename(p).split("_sf")[1][:-4]
                      for p in glob.glob(os.path.join(HERE, "raw_*_sf*.csv"))})
    if not sfs:
        sys.exit("Nenhum results/raw_*.csv encontrado. Rode results/run_bench.sh antes.")
    for sf in sfs:
        linhas = resumir(sf)
        out = os.path.join(HERE, f"summary_sf{sf}.csv")
        with open(out, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(linhas[0]))
            w.writeheader()
            w.writerows(linhas)
        print(f"\n== SF{sf} -> {out}")
        print(f"{'query':6}{'sis':4}{'schema':7}{'mediana ms':>12}{'IQR':>9}{'speedup':>9}{'efic.':>7}")
        for l in linhas:
            print(f"{l['query']:6}{l['system']:4}{l['schema']:7}{l['median_ms']:>12}"
                  f"{l['iqr_ms']:>9}{l['speedup_vs_pg']!s:>9}{l['eficiencia']!s:>7}")
        grafico(linhas, sf)


if __name__ == "__main__":
    main()
