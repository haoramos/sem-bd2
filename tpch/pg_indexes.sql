-- Índices do baseline PostgreSQL: só as chaves de junção/filtro mais usadas.
-- Um baseline sem índice nenhum seria injusto com o nó único.
CREATE INDEX ON lineitem (l_orderkey);
CREATE INDEX ON lineitem (l_partkey, l_suppkey);
CREATE INDEX ON lineitem (l_shipdate);
CREATE INDEX ON orders (o_orderkey);
CREATE INDEX ON orders (o_custkey);
CREATE INDEX ON customer (c_custkey);
CREATE INDEX ON supplier (s_suppkey);
CREATE INDEX ON part (p_partkey);
CREATE INDEX ON partsupp (ps_partkey, ps_suppkey);
