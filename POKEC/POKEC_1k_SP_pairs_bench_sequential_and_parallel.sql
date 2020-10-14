/******************************************/
-- 2020-10-01
-- This script compares sequential vs parallel execution of 1000 shortest path queries to the POKEC dataset.
-- It also serves as a template how to explicitly parallelize GRAPH procedures using the MAP_MERGE operator of SQLScript.
-- It runs on SAP HANA Cloud Q2 (45 GB memory, 3vCPUs)

-- The POKEC dataset can be downloaded from https://snap.stanford.edu/data/soc-Pokec.html
-- POKEC contains 1632803 vertices and 30622564 edges.
-- It is assumed that the data is loaded and a GRAPH WORKSPACE "POKEC"."GRAPH" has been created.

-- The 1000 source-target pairs can be found on https://www.arangodb.com/2018/02/nosql-performance-benchmark-2018-mongodb-postgresql-orientdb-neo4j-arangodb/
-- See also https://github.com/weinberger/nosql-tests

-- (1) GRAPH procedure calling the built-in Shortest_Path function on a single source-target pair
-- (2) SQLScript function wrapped around (1) for better handling
-- (3) SQLScript function that calls (2) on 1000 source-target pairs sequentially. Takes about 4 sec.
-- (4) SQLScript function that calls (2) on 1000 source-target pairs in parellel. Takes about 180 ms.

-- (1) GRAPH procedure calling the built-in Shortest_Path function on a single source-target pair
CREATE OR REPLACE PROCEDURE "POKEC"."POKEC_SHORTEST_PATH_LENGTH"(
	IN "SOURCE" bigint, IN "TARGET" bigint, IN i_dir nvarchar(10),
	OUT o_len BIGINT
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
  GRAPH g = Graph("POKEC", "GRAPH");
  VERTEX v_s = Vertex(:g, :SOURCE);
  VERTEX v_t = Vertex(:g, :TARGET);
  WeightedPath<BIGINT> p = Shortest_Path(:g, :v_s, :v_t, :i_dir);
  o_len = LENGTH(:p);
END;
CALL "POKEC"."POKEC_SHORTEST_PATH_LENGTH"(8414, 743803, 'ANY', ?);

-- (2) SQLScript function wrapped around (1) for better handling
CREATE OR REPLACE FUNCTION "POKEC"."POKEC_SHORTEST_PATH_LENGTH_FUNCTION"(
	IN "SOURCE" bigint, IN "TARGET" bigint, IN i_dir nvarchar(10)
	)
	RETURNS TABLE (O_LEN BIGINT)
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
	DECLARE o_len BIGINT;
	CALL "POKEC"."POKEC_SHORTEST_PATH_LENGTH"(:SOURCE, :TARGET, :i_dir, o_len);
	RETURN SELECT :o_len AS O_LEN FROM DUMMY;
END;
SELECT * FROM "POKEC"."POKEC_SHORTEST_PATH_LENGTH_FUNCTION"(8414, 743803, 'ANY');

-- (3) SQLScript function that calls (2) on 1000 source-target pairs sequentially. Takes about 4 sec.
CREATE OR REPLACE FUNCTION "POKEC"."POKEC_SEQUENTIAL_RUN"(
	IN i_limit INT,
	IN i_dir nvarchar(10)
	)
	RETURNS TABLE ("ID" INT, "SOURCE" BIGINT, "TARGET" BIGINT, "HOP_DIST" BIGINT, "TS" TIMESTAMP)
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
	DECLARE o_path_length BIGINT = 0;
	DECLARE v_i INT;
	DECLARE v_id bigint;
	DECLARE v_s bigint;
	DECLARE v_t bigint;
	t_pairs = SELECT "ID", "source" AS "SOURCE", "target" AS "TARGET" FROM "POKEC"."SP_PAIRS" order by id LIMIT :i_limit;
	o_res = SELECT 0 AS "ID", 0 AS "SOURCE", 0 AS "TARGET", 0 AS "HOP_DIST", NOW() AS "TS" FROM DUMMY;
	FOR v_i IN 1..RECORD_COUNT(:t_pairs) DO
		v_id = :t_pairs."ID"[:v_i];
		v_s = :t_pairs."SOURCE"[:v_i];
		v_t = :t_pairs."TARGET"[:v_i];
		CALL "POKEC"."POKEC_SHORTEST_PATH_LENGTH"(:v_s, :v_t, :i_dir, o_path_length);
		o_res = SELECT * FROM :o_res UNION SELECT :v_id AS "ID", :v_s AS "SOURCE", :v_t AS "TARGET", :o_path_length as "HOP_DIST", NOW() AS "TS" FROM DUMMY;
	END FOR;
	RETURN :o_res;
END;
SELECT * FROM "POKEC"."POKEC_SEQUENTIAL_RUN"(1000, 'ANY');
-- calculate some stats on the runtime
SELECT "HOP_DIST", COUNT(*) AS "NUMBER OF QUERIES", MIN(TS_DIFF_MS), MAX(TS_DIFF_MS), AVG(TS_DIFF_MS), STDDEV(TS_DIFF_MS) FROM (
	SELECT *, LAG("TS") OVER (ORDER BY "ID") AS "LAG", NANO100_BETWEEN(LAG("TS") OVER (ORDER BY "ID"), "TS")/10000 AS "TS_DIFF_MS"
	FROM "POKEC"."POKEC_SEQUENTIAL_RUN"(1000, 'ANY')
	)
WHERE "LAG" IS NOT NULL
GROUP BY "HOP_DIST"
ORDER BY "HOP_DIST" ASC;


-- (4) SQLScript function that calls (2) on 1000 source-target pairs in parellel. Takes about 180 ms.
CREATE OR REPLACE FUNCTION "POKEC"."POKEC_PARALLEL_RUN" (IN i_limit BIGINT, IN i_dir NVARCHAR(10))
	RETURNS TABLE(O_LEN BIGINT)
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
	t_pairs = SELECT "ID", "source" AS "SOURCE", "target" AS "TARGET" FROM "POKEC"."SP_PAIRS" LIMIT :i_limit;
	o_res = MAP_MERGE(:t_pairs, "POKEC"."POKEC_SHORTEST_PATH_LENGTH_FUNCTION"(:t_pairs."SOURCE", :t_pairs."TARGET", :i_dir));
	RETURN :o_res;
END;
SELECT * FROM "POKEC"."POKEC_PARALLEL_RUN"(1000, 'ANY');
