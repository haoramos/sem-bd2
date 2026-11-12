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

Pastas previstas, ainda não criadas: `infra/postgres/` (baseline de nó único),
`tpch/` (geração de dados e queries), `airflow/` (DAGs de ingestão), `results/`.

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
