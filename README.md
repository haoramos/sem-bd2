# Seminário BD2: Banco de dados distribuído com Greenplum

Projeto do seminário de Banco de Dados 2. O roteiro e o plano experimental estão em
[plano-greenplum.html](plano-greenplum.html).

## Estrutura

```
infra/warehousepg/   cluster WarehousePG 7.5.0 em Docker (1 coordinator + 4 segmentos)
  lab.yaml           compose do laboratório
  .env               imagem e versão
  conf/              configuração de inicialização do cluster
  run.sh             up | down | status | psql | reset
```

```
infra/postgres/      baseline PostgreSQL 12 de nó único (porta 5433), mesmo run.sh
tpch/                gen.sh (dbgen), load.sh (carga pg/gp), ddl.sql.in, queries/q*.sql
results/             run_bench.sh, explain.sh, analyze.py e os CSVs de medição
slides/              roteiro dos slides
```

Fora do escopo do seminário (ficam para o TCC): `airflow/`, Cloudberry, TPC-DS, AO-column.

## Fluxo do benchmark

Dentro do Ubuntu, a partir da raiz do projeto. Um sistema por vez (RAM de 5 GB):

```bash
tpch/gen.sh 1                                  # dados SF1 em tpch/data/sf1
sudo infra/postgres/run.sh up && tpch/load.sh pg 1
results/run_bench.sh pg 1                      # 1 aquecimento + 5 medidas por query
infra/postgres/run.sh down
sudo infra/warehousepg/run.sh up && tpch/load.sh gp 1
results/run_bench.sh gp 1                      # estratégias e1..e4
results/explain.sh gp e1 q03                   # compare com e2: Motions
python3 results/analyze.py 1                   # mediana, IQR, speedup, eficiência
```

Estratégias no Greenplum (schemas): `e1` co-localizada (orders/lineitem por `orderkey`),
`e2` aleatória, `e3` skew (`lineitem` por `l_returnflag`), `e4` padrão (1ª coluna).
Foram incluídas as 9 queries foco (Q1, Q3, Q5, Q6, Q9, Q13, Q18, Q21, Q22), com os
parâmetros de validação do TPC-H; as outras 13 não foram escritas.

**Estado:** scripts escritos em 2026-11-16, ainda **não executados**. O `gen.sh` clona
`electrum/tpch-dbgen` e o `make` pode precisar de ajuste.

## Ambiente

Windows 11 com WSL2 (Ubuntu) e Docker Engine dentro do Ubuntu. O WSL está limitado
a 5 GB de RAM em `C:\Users\<usuario>\.wslconfig`. Com essa RAM, rodar o cluster, o
PostgreSQL de comparação e o Airflow **um de cada vez** durante as medições.

## Subir o cluster

Dentro do Ubuntu (`wsl -d Ubuntu`), a partir da pasta do projeto:

```bash
cd /mnt/c/Users/heito/Documents/sem_bd2/infra/warehousepg
sudo ./run.sh up        # a primeira subida leva alguns minutos
./run.sh status
./run.sh psql -c "select * from gp_segment_configuration order by dbid;"
```

O script copia os arquivos para `/opt/lab/whpg` e gera as chaves SSH e as senhas lá.
Elas não ficam no projeto e não devem ir para o Git.

## Origem e notas

- A imagem é `woblerr/warehousepg` (comunitária, de terceiros). A configuração do
  compose foi adaptada de [woblerr/docker-greenplum](https://github.com/woblerr/docker-greenplum).
  Ao reutilizar, conferir a licença do repositório de origem.
- Ajustes em relação ao original: `GPPERFMON`, `DISKQUOTA` e `PXF` desligados (menos
  RAM), porta do coordinator só em `127.0.0.1`, chaves e senhas geradas localmente.
- Validado em 2026-11-11: WarehousePG 7.5.0 (base PostgreSQL 12.12), 4 segmentos
  primários sem mirrors, otimizador GPORCA, `Redistribute Motion` visto no plano do
  exemplo `student`/`class` do artigo do SIGMOD 2021.
- `./run.sh up`, `status` e `psql` foram testados em 2026-11-11, subindo o cluster do zero.
  `down` e `reset` ainda não foram testados.
- Os contêineres não têm política de reinício: quando o WSL desliga (por ociosidade ou
  `wsl --shutdown`), o cluster para. Para religar, basta `sudo ./run.sh up`. Os dados
  não são persistentes (sem volumes), então um `down` ou `reset` apaga as tabelas.
