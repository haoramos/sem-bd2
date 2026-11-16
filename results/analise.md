# Análise dos resultados (TPC-H SF1 e SF3)

Medições: 1 aquecimento + 5 execuções por query, mediana (dados em `summary_sf*.csv`).
Máquina: WSL2, 8 núcleos, 4,9 GB de RAM; todos os "segmentos" são contêineres no mesmo host.
SF10 não foi executado (RAM e tempo). Planos: `results/explain/` (SF1, Greenplum com 4 segmentos).

## 1. Quando o Greenplum compensa (HI1)
- Queries pesadas de junção/agregação sobre `lineitem` ganham muito com a escala. SF3, melhor
  estratégia com 4 segmentos contra o PostgreSQL: Q18 93,0 s -> 7,3 s (12,7x), Q9 15,4 s -> 3,5 s (4,4x),
  Q13 4,0 s -> 1,1 s (3,8x), Q21 12,5 s -> 3,0 s (4,1x).
- Queries curtas perdem: Q22 (225 ms contra 730 ms) e Q5 (954 ms contra 1109 ms). O custo fixo de
  coordenação (Gather/Broadcast Motion, planejamento) não é pago pelo ganho de paralelismo.
- De SF1 para SF3 o ponto de cruzamento se move a favor do Greenplum: Q21 e Q9 passaram a favorecê-lo.
  Em SF1, Q5, Q21 e Q22 ainda eram mais rápidas no PostgreSQL.

## 2. Chave de distribuição e Motions (HI2/HI3)
Contagem de Motions nos planos (SF1, 4 segmentos), Q18: e1 2 Redistribute, e4 2, e3 4, e2 6.
Os tempos seguem a contagem: Q18 SF3 = 7,3 s (e1), 10,5 s (e4), 15,2 s (e3), 68,0 s (e2).
- e1 (orders/lineitem por `orderkey`) evita redistribuir a tabela maior na junção principal.
- e2 (aleatória) obriga a redistribuir `lineitem` (1,5 milhão de linhas por segmento em SF1) em
  quase toda junção.
- e4 (padrão: 1ª coluna) coincide com e1 para orders/lineitem; os planos de Q18 são iguais.
  Não é um tratamento distinto na prática.
- Exceção: Q21 em SF1 foi um pouco melhor em e4 e e2 do que em e1 (1,4 s e 1,9 s contra 2,3 s no
  EXPLAIN); não explicado.

## 3. Skew (HI3)
e3 (`lineitem` por `l_returnflag`, só 3 valores) concentra as linhas em poucos segmentos:
pior ou quase pior caso em Q1, Q3, Q5, Q6 e Q9. Q9 em SF3 com 4 segmentos: 50,1 s (e3) contra 3,5 s (e4).
Com 2 segmentos o mesmo caso levou 4,4 s: não explicado, desconfio de variação do planejador
(plano diferente), mas não verifiquei o plano.

## 4. Escala com o número de segmentos
Reduzir de 4 para 2 segmentos costuma custar 1,3x a 1,9x, abaixo do 2x ideal: parte do tempo não
escala (Motions, coordenação, e os segmentos compartilham os mesmos 8 núcleos).
Eficiência (speedup/segmentos) fica entre 0,1 e 0,9 em SF1; maior em Q13 e Q3.
Anomalia: Q21 SF3 e1 com 2 segmentos = 37,0 s (contra 7,4 s com 4). Não investigado.

## Limites
- Contêineres num só host: mede a arquitetura, não rede ou discos de verdade.
- Só 5 repetições por ponto e uma execução da sequência: diferenças pequenas ficam dentro do ruído
  (veja o IQR nos CSVs).
- Os tempos do `EXPLAIN ANALYZE` (SF1) são maiores que os do benchmark (instrumentação), servem
  só para comparar planos.
- Baseline PostgreSQL com índices nas chaves de junção, paralelismo de 2 workers e `work_mem` de
  64 MB; Q18 em SF3 (93 s) provavelmente gastou tempo em disco.
- As 13 queries do TPC-H fora do foco não foram medidas.
