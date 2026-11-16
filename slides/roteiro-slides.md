# Roteiro dos slides (23 min, 7 blocos)

Ajustar à duração real definida pelo professor. Fontes: `plano-greenplum.html`.

| # | Bloco | Min | Conteúdo | Material |
|---|-------|-----|----------|----------|
| 1 | Motivação | 2 | Quando um nó único deixa de bastar? Pergunta central | — |
| 2 | Arquitetura MPP | 5 | Coordinator, segmentos, interconnect, GPORCA; distribuição por hash/aleatória/replicada | artigo SIGMOD 2021 |
| 3 | Motions | 3 | Redistribute, Broadcast, Gather; exemplo `student`/`class` | `explain.sh gp e1/e2` |
| 4 | COST | 3 | McSherry 2015: distribuído só compensa se vencer um nó único bem feito | HotOS 2015 |
| 5 | Experimento | 4 | TPC-H, PG vs Greenplum, estratégias e1..e4, método (aquecimento + 5 medidas, mediana/IQR) | `tpch/`, `results/` |
| 6 | Resultados | 4 | Tabela e gráfico de speedup, ponto de cruzamento, skew (e3) | `results/summary_sf*.csv`, `speedup_sf*.png` |
| 7 | Conclusão | 2 | HI1..HI4 confirmadas ou não; limites (containers num só host); ponte para o TCC | — |

## Demo ao vivo (bloco 3)

```bash
infra/warehousepg/run.sh psql -c "EXPLAIN SELECT * FROM e2.orders o JOIN e2.customer c ON c.c_custkey=o.o_custkey"
infra/warehousepg/run.sh psql -c "EXPLAIN SELECT * FROM e1.orders o JOIN e1.lineitem l ON l.l_orderkey=o.o_orderkey"
```

Mostrar `Redistribute Motion` em e2 e a junção local (sem Motion nos dados) em e1.

## Ressalvas a dizer em voz alta

- Cluster em containers num único host: mede arquitetura, não escala de rede real.
- Baseline PostgreSQL com índices nas chaves de junção e paralelismo ligado.
- Escalas pequenas (SF1, talvez SF10): o ponto de cruzamento pode não aparecer.
