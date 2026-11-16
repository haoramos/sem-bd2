# Proposta de TCC

**Título provisório:** Quando compensa distribuir? Uma análise experimental de um banco de dados MPP (Greenplum/WarehousePG) frente ao PostgreSQL de nó único

**Status:** rascunho para conversa com o professor orientador. Nada da parte experimental do TCC foi executado ainda. Itens marcados **[a validar]** vêm de conhecimento geral ou de buscas rápidas e precisam ser conferidos antes de entrarem no texto final.

---

## 1. Contexto e motivação

Bancos de dados distribuídos prometem escalar além de uma máquina, mas distribuir tem custo: coordenação, movimentação de dados entre nós, complexidade operacional e, em alguns casos, desempenho pior que um único servidor bem configurado. A decisão de adotar uma arquitetura distribuída costuma ser tomada por tendência ou por argumento de fornecedor, e não por medição.

O Greenplum é um banco MPP (Massively Parallel Processing) de arquitetura shared-nothing, derivado do PostgreSQL, voltado a análise de dados em larga escala. Ele é um bom objeto de estudo porque expõe os mecanismos que decidem se distribuir compensa: distribuição das linhas por chave, movimentação de dados entre segmentos (Motion), otimizador próprio e opções de armazenamento.

Este trabalho nasce de um seminário da disciplina de Banco de Dados 2, cujo tema é "Banco de dados distribuído: quando compensa? Uma análise com o Greenplum". O TCC aprofunda a parte experimental do seminário.

## 2. Problema e pergunta de pesquisa

**Pergunta principal:** em cargas analíticas, a partir de que volume de dados, e sob quais escolhas de modelagem, um banco MPP (Greenplum/WarehousePG) supera um PostgreSQL de nó único?

**Perguntas secundárias:**

1. Como a chave de distribuição (co-localizada, aleatória, com skew, padrão) altera o desempenho e o ponto de cruzamento?
2. Quais tipos de consulta escalam bem e quais são dominados por movimentação de dados (Motions)?
3. Como o desempenho cresce com o número de segmentos (speedup e eficiência)?
4. (Opcional) Qual o custo e o comportamento da **ingestão** de dados em cada sistema, usando um pipeline orquestrado pelo Airflow?
5. (Opcional) O tipo de armazenamento (heap, AO-row, AO-column) muda o resultado?

## 3. Hipóteses

| ID | Hipótese | Como refutar |
|---|---|---|
| H1 | Em volumes pequenos, o nó único vence, porque o MPP paga overhead de coordenação e Motions. | O MPP é mais rápido já no menor fator de escala. |
| H2 | Quando os dados passam da RAM, o MPP começa a vencer, mas só nas consultas que escalam bem. | Nenhum cruzamento nos fatores de escala testados. Esse resultado também é válido. |
| H3 | Distribuição co-localizada por chave de join supera a aleatória, que supera a com skew. | Ordem diferente ou diferença desprezível. |
| H4 | Consultas de scan e agregação em uma tabela são pouco sensíveis à chave; consultas com muitos joins são muito sensíveis. | Sensibilidade igual entre os dois grupos. |
| HI1 | Carga por `COPY` em uma conexão não escala com o número de segmentos, porque os dados passam pelo coordinator. **[a validar]** | A vazão cresce com os segmentos. |
| HI2 | Um caminho de carga paralelo (tabela externa com `gpfdist`) escala melhor. **[a validar]** | Sem ganho sobre o `COPY`. |
| HI3 | AO-column com compressão carrega mais devagar que heap, mas ocupa bem menos disco. **[a validar]** | Resultado contrário. |

HI1 a HI3 só se aplicam se a ingestão (opcional, seção 5.5) for incluída no escopo.

## 4. Objetivos

**Geral:** determinar, de forma experimental e reproduzível, em que condições um banco MPP compensa frente a um PostgreSQL de nó único em cargas analíticas.

**Específicos:**

- Descrever a arquitetura do Greenplum e os mecanismos que determinam seu desempenho (seção 7).
- Montar um ambiente de teste reproduzível, com o baseline ajustado de forma justa.
- Medir o ponto de cruzamento entre os sistemas para um benchmark baseado em TPC-H.
- Isolar o efeito da chave de distribuição, do skew e das Motions.
- (Opcional) Medir a ingestão de dados com um pipeline no Airflow.
- Documentar limitações e ameaças à validade.

## 5. Metodologia

### 5.1 Sistemas comparados

- **Baseline:** PostgreSQL de nó único, com paralelismo ligado e parâmetros ajustados (`shared_buffers`, `work_mem`, `effective_cache_size`, `max_parallel_workers_per_gather`). O ajuste do baseline é crítico: sem ele, o MPP parece melhor do que merece.
- **MPP:** WarehousePG 7.5.0 (fork do Greenplum, base PostgreSQL 12.12), com coordinator e 4 segmentos primários sem mirrors, em Docker.
- **Segundo sistema MPP: Apache Cloudberry.** Fork do ecossistema Greenplum, projeto da Apache Software Foundation em incubação (desde outubro de 2024), com a versão 2.1.0 lançada em abril de 2026. A linha 2.x usa kernel PostgreSQL 14, enquanto o WarehousePG 7.5.0 usa PostgreSQL 12.12 (conferido no cluster do laboratório). A compatibilidade com o Greenplum é meta do projeto, mas há diferenças de comportamento. Papel no trabalho:
  - **Teste de robustez:** repetir ao menos os experimentos de ponto de cruzamento e de chave de distribuição. Resultados parecidos nos dois forks reforçam as conclusões; resultados diferentes são um achado.
  - **Condição:** só entra se o sandbox (oficial, base Rocky Linux 9) couber nos 5 GB de RAM do WSL. Isso ainda não foi testado. **[a validar]**
  - **Alternativa:** se o orientador preferir um único sistema mantido por uma fundação, o Cloudberry pode virar o principal, porque o experimento usa SQL padrão e TPC-H.
- **Outras extensões possíveis:** Greengage (outro fork, listado no repositório das imagens Docker) ou o Citus. Ficam fora do escopo mínimo.

### 5.2 Carga de trabalho

- **TPC-H** gerado com o `dbgen` oficial, chamado de "baseado em TPC-H" (não é um resultado certificado).
- Fatores de escala planejados: SF1, SF10, e SF30 ou maior se o hardware permitir. Opcional: TPC-DS, para ter skew e esquemas mais variados.
- As 22 consultas rodam, com aprofundamento em cerca de 8 de perfis diferentes. Os perfis esperados são hipóteses a confirmar com `EXPLAIN ANALYZE`:

| Query | Perfil esperado |
|---|---|
| Q1, Q6 | Scan e agregação em `lineitem`. Devem escalar bem. |
| Q3, Q5 | Joins de 3 e 6 tabelas. Sensíveis à co-localização. |
| Q9 | Join grande e pesado. |
| Q13 | Outer join com agregação. |
| Q18 | Agregação grande por `orderkey`. |
| Q21 | Subconsultas `EXISTS`/`NOT EXISTS`. |
| Q22 | Anti-join e subconsulta. Um relato da EDB aponta o Postgres-XL pior que nó único nessa query. |

### 5.3 Estratégias de distribuição

| ID | Estratégia | Como |
|---|---|---|
| E1 | Co-localizada | `lineitem` e `orders` por `orderkey`; `customer` por `custkey`; `part` e `partsupp` por `partkey`; `supplier` por `suppkey`; `nation` e `region` replicadas. |
| E2 | Aleatória | Tudo `DISTRIBUTED RANDOMLY`, exceto `nation` e `region`. |
| E3 | Chave ruim (skew) | `lineitem` por `l_returnflag` (poucos valores, um dominante). |
| E4 | Padrão | Sem cláusula de distribuição. |

### 5.4 Procedimento de medição

- 1 execução de aquecimento descartada e 5 medidas por consulta, com mediana e dispersão (IQR).
- Timeout definido (ex.: 30 min), registrado como "timeout" e nunca omitido.
- Uma consulta por vez, sem outras cargas. Decidir e declarar se o resultado é com cache frio, quente ou ambos.
- `EXPLAIN (ANALYZE)` guardado para cada combinação consulta, estratégia e escala (tipo e volume de Motions, tempo por segmento).
- Verificação de skew após cada carga (contagem de linhas por `gp_segment_id`).

### 5.5 Ingestão com Airflow (opcional)

**Papel no trabalho:** a ingestão não é necessária para responder à pergunta principal (ponto de cruzamento e efeito da chave de distribuição). O núcleo do TCC carrega os dados com scripts simples (por exemplo `COPY`), fora do Airflow, e mede só as consultas. A ingestão com Airflow entra como extensão se sobrar tempo, ou se o orientador considerar que ela enriquece o trabalho. Critério sugerido: incluí-la apenas depois que os experimentos 1 e 2 estiverem concluídos.

Pipeline: gerar dados, carregar no PostgreSQL, carregar no Greenplum, `ANALYZE`, validar contagens, opcionalmente rodar consultas.

- Métricas: linhas por segundo, MB por segundo, tempo por etapa, tamanho em disco e efeito da chave de distribuição.
- **Medir no banco, não na DAG:** o tempo de uma task do Airflow inclui agendamento e overhead. Reportar o tempo da DAG separadamente.
- O Airflow usa banco de metadados próprio, separado dos bancos em teste.
- O Airflow não roda de forma nativa no Windows, então roda em Docker ou WSL2. **[a validar]**
- O Greenplum fala o protocolo do PostgreSQL, então o provider Postgres do Airflow deve conectar. **[a validar]**

### 5.6 Métricas de análise

- **Speedup** = tempo do PostgreSQL ÷ tempo do MPP, por consulta e escala; média geométrica no resumo.
- **Ponto de cruzamento:** escala em que o speedup passa de 1.
- **Eficiência** = speedup ÷ número de segmentos. O conceito de COST (McSherry et al.) serve de lente: quantos segmentos são necessários para bater o nó único.
- **Skew:** razão entre o segmento mais cheio e a média, relacionada ao tempo das consultas afetadas.
- **Motions:** contagem, tipo e fração do tempo gasta nelas.

## 6. Ambiente de teste (estado atual)

| Item | Situação |
|---|---|
| Máquina | Notebook Windows 11, Core i5-12450H (8 cores, 12 threads), 7,7 GB de RAM, SSD NVMe de ~183 GB. |
| Virtualização | WSL2 com Ubuntu, limitado a 5 GB de RAM, 8 processadores e 4 GB de swap (`.wslconfig`). |
| Contêineres | Docker Engine dentro do Ubuntu. |
| MPP | Imagem comunitária `woblerr/warehousepg:7.5.0-WHPG-ubuntu22.04`, validada: 4 segmentos `up`, otimizador GPORCA, `Redistribute Motion` observado no exemplo do artigo do SIGMOD 2021. |

**Ainda não existem:** PostgreSQL de comparação, gerador TPC-H, DAGs do Airflow (opcional) e resultados.

**Limitações do ambiente:**

- **Uma máquina só.** Os 4 segmentos compartilham CPU, RAM e disco. O experimento mede overhead de MPP e paralelismo local, não latência de rede entre nós reais. Isso precisa constar na metodologia e nas conclusões.
- **RAM de 7,7 GB.** Impede rodar cluster, PostgreSQL e Airflow juntos; os testes rodam um de cada vez. Em contrapartida, o volume que excede a RAM é alcançado com escalas pequenas.
- **Disco de ~93 GB livres.** Comporta até SF10 com folga; SF30 ou maior é incerto com as duas bases e as variações.
- Se houver acesso a mais máquinas ou a cloud, o TCC ganha muito (ver seção 9).

## 7. Fundamentação teórica (resumo)

Base: artigo *Greenplum: A Hybrid Database for Transactional and Analytical Workloads* (SIGMOD 2021), cuja arquitetura foi conferida.

- **Shared-nothing:** cada segmento é um PostgreSQL ampliado, com memória e dados próprios. O coordinator recebe as consultas, gera o plano distribuído, despacha, reúne os resultados e responde ao cliente.
- **Plano distribuído:** o nó Motion movimenta tuplas entre segmentos e corta o plano em *slices*, executados por grupos de processos (*gangs*), com a técnica SPMD.
- **Distribuição dos dados:** por hash de chave, aleatória ou replicada **[replicada: a validar]**. Skew concentra dados em poucos segmentos e o mais lento define o tempo.
- **Armazenamento:** heap, AO-row e AO-column (append-optimized, com compressão), além de particionamento.
- **Otimizadores:** Orca (baseado em custo, para análise) e o planejador do PostgreSQL adaptado (consultas curtas).
- **Transações:** snapshots distribuídos e two-phase commit; o artigo propõe detector de deadlock global, commit em uma fase e resource groups.
- **Interconnect:** UDP por padrão, com confirmação (ACK) do receptor.
- **Contraponto teórico:** McSherry et al. (HotOS 2015) propõem o COST, a configuração que supera uma implementação single-thread, e mostram que muitos sistemas distribuídos precisam de centenas de cores para isso.

## 8. Lacuna na literatura e contribuição esperada

Numa busca inicial e **não sistemática**, os benchmarks de PostgreSQL distribuído que apareceram são quase todos de fornecedores (Citus, Postgres-XL, Swarm64), e não encontrei um estudo independente que indique um ponto de cruzamento nem uma análise acadêmica de skew e Motions no Greenplum com TPC-H. **Essa conclusão precisa de uma revisão bibliográfica sistemática antes de ser afirmada no TCC.**

Contribuições esperadas, se a lacuna se confirmar:

- Uma comparação independente e reproduzível, com baseline ajustado, código aberto e metodologia documentada.
- Uma classificação das consultas TPC-H entre as que escalam bem e as dominadas por Motions.
- (Opcional, se a ingestão entrar) Dados de ingestão em pipeline orquestrado, que costumam faltar nos benchmarks de consulta.

Resultados negativos (por exemplo, o nó único vencer em todas as escalas testadas) também têm valor e são parte do plano.

## 9. Riscos e ameaças à validade

| Risco | Mitigação |
|---|---|
| Uma máquina só, sem rede real | Declarar a limitação; avaliar uma máquina maior ou cloud (custo a orçar). |
| Baseline mal ajustado | Documentar cada parâmetro; revisão cruzada. |
| Cache e variância | Repetições, mediana e dispersão. |
| TPC-H tem dados uniformes | O skew vem só da estratégia E3; considerar TPC-DS ou dados sintéticos com skew. |
| Estado do projeto Greenplum | O repositório open source foi arquivado em 2024 **[a validar]**; usamos o WarehousePG, um fork. Resultados valem para a versão testada. |
| Imagem Docker de terceiros | Ler o Dockerfile e registrar a versão; o Cloudberry, com sandbox oficial, é a alternativa. |
| Forks com kernels diferentes (PostgreSQL 12 vs 14) | Reportar versões exatas; tratar diferenças entre forks como resultado, não como erro. Nenhum dos dois é o Greenplum original. |
| Cloudberry ainda em incubação na Apache | Registrar a versão testada; usá-lo como segundo sistema, não como única base. |
| RAM limitada | Rodar sistemas em momentos diferentes; limitar o fator de escala. |
| Generalização | Vale para carga analítica estilo TPC-H, não para OLTP. |

## 10. Cronograma sugerido

Sem prazos definidos. Os blocos estão em ordem de prioridade e as durações são estimativas a combinar com o orientador.

| Etapa | Entrega |
|---|---|
| 1 | Revisão bibliográfica sistemática e fechamento da pergunta de pesquisa |
| 2 | Ambiente do núcleo: PostgreSQL ajustado, geração e carga do TPC-H por scripts |
| 3 | Experimento 1: ponto de cruzamento (SF1 a SF10 ou mais) |
| 4 | Experimento 2: chaves de distribuição, skew e Motions |
| 5 | Extensões opcionais, em ordem de prioridade a combinar: segundo MPP (Cloudberry), ingestão com Airflow, mais segmentos, TPC-DS, armazenamento |
| 6 | Análise, escrita e revisão |

## 11. Estrutura prevista do texto

1. Introdução e pergunta de pesquisa
2. Fundamentação: shared-nothing e MPP, arquitetura do Greenplum, COST
3. Trabalhos relacionados e lacuna
4. Metodologia
5. Resultados: cruzamento, efeito da chave (e ingestão, se incluída)
6. Discussão: por que cada consulta se comporta assim
7. Ameaças à validade, conclusão e trabalhos futuros

## 12. Decisões em aberto

- O professor aceita o escopo (comparação MPP vs nó único, com ponto de cruzamento e chave de distribuição), ou prefere outro recorte?
- A ingestão com Airflow entra no TCC ou fica de fora? (Hoje: opcional, só depois dos experimentos 1 e 2.)
- Há acesso a mais de uma máquina ou a créditos de cloud para testar com nós reais?
- Qual fork será o principal do TCC? (Hoje: WarehousePG 7.5.0, com Apache Cloudberry como segundo sistema. O orientador prefere um sistema só, e qual?)
- O Cloudberry roda na máquina atual (5 GB de RAM no WSL)? Testar o sandbox antes de confirmá-lo no escopo.
- TPC-DS e armazenamento entram no escopo ou ficam como trabalho futuro?
- Prazos e formato exigidos pelo curso.

## 13. Referências

Verificadas (consultadas nesta pesquisa):

- Lyu, Z. et al. *Greenplum: A Hybrid Database for Transactional and Analytical Workloads.* SIGMOD 2021. https://arxiv.org/pdf/2103.11080
- McSherry, F.; Isard, M.; Murray, D. *Scalability! But at what COST?* HotOS XV, 2015. https://usenix.org/conference/hotos15/workshop-program/presentation/mcsherry

Fontes secundárias e de fornecedores (ler com cautela):

- EnterpriseDB. *Benchmarking Postgres-XL.* https://www.enterprisedb.com/blog/benchmarking-postgres-xl
- Citus Data. *Making PostgreSQL scale Hadoop-style.* https://www.citusdata.com/blog/2014/10/31/postgres-scale-hadoop-style/
- Alibaba Cloud. *Performance evaluation methods for distributed MPP databases.* https://www.alibabacloud.com/blog/performance-evaluation-methods-for-distributed-mpp-databases---best-practice-for-postgresql_334288
- Imagens e configuração de laboratório: https://github.com/woblerr/docker-greenplum e https://hub.docker.com/r/woblerr/warehousepg
- Apache Cloudberry, sandbox Docker: https://cloudberry.apache.org/docs/build/sandbox
- Apache Cloudberry, relatório de incubação de maio de 2026 (versão 2.1.0, status de incubação): https://cloudberry.apache.org/blog/apache-cloudberry-incubation-report-202605
- Apache Cloudberry, comparação de funcionalidades com o Greenplum (kernel PostgreSQL 14): https://cloudberry.apache.org/docs/introduction/cbdb-vs-gp-features
- Yandex Cloud, mudanças incompatíveis do Cloudberry em relação ao Greenplum: https://docs.yandex.cloud/int/en/managed-greenplum/concepts/cloudberry-vs-greenplum/breaking-changes.md

**A confirmar antes de citar** (listadas de memória, ainda não verificadas):

- Soliman, M. et al. *Orca: a modular query optimizer architecture for big data.* SIGMOD 2014.
- Stonebraker, M. *The Case for Shared Nothing.* 1986.
- DeWitt, D.; Gray, J. *Parallel Database Systems: The Future of High Performance Database Systems.* CACM, 1992.
- Pavlo, A. et al. *A Comparison of Approaches to Large-Scale Data Analysis.* SIGMOD 2009.

---

## Anexo: para retomar este trabalho em outra sessão

Contexto mínimo para quem (pessoa ou assistente) continuar:

- O seminário de BD2 é o ponto de partida. O laboratório montado para ele (WarehousePG 7.5.0 em Docker, dentro do WSL2) serve de referência técnica, mas o código e o repositório do TCC serão separados.
- Pendências técnicas do TCC: PostgreSQL de comparação, geração e carga do TPC-H, DAGs do Airflow (opcional) e organização dos resultados.
- Itens marcados **[a validar]** neste documento devem ser conferidos na documentação oficial antes de virarem afirmação.
