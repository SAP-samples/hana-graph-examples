/*************************************/
-- SAP HANA Graph examples - How to use the SHORTEST_PATH_ONE_TO_ALL function
-- 2020-04-15
-- This script was developed for SAP HANA Cloud 2021 Q1
-- See also https://help.sap.com/viewer/11afa2e60a5f4192a381df30f94863f9/cloud/en-US/3b0a971b129c446c9e40a797bdb29c2b.html
/*************************************/

/*************************************/
-- 1 Create schema, tables, graph workspace, and load some sample data
DROP SCHEMA "GRAPHSCRIPT" CASCADE;
CREATE SCHEMA "GRAPHSCRIPT";
CREATE COLUMN TABLE "GRAPHSCRIPT"."VERTICES" (
	"ID" BIGINT PRIMARY KEY,
	"NAME" VARCHAR(100)
);
CREATE COLUMN TABLE "GRAPHSCRIPT"."EDGES" (
	"ID" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	"SOURCE" BIGINT REFERENCES "GRAPHSCRIPT"."VERTICES"("ID") ON DELETE CASCADE NOT NULL,
	"TARGET" BIGINT REFERENCES "GRAPHSCRIPT"."VERTICES"("ID") ON DELETE CASCADE NOT NULL,
	"WEIGHT" DOUBLE
);
INSERT INTO "GRAPHSCRIPT"."VERTICES"("ID", "NAME") VALUES (1, 'one');
INSERT INTO "GRAPHSCRIPT"."VERTICES"("ID", "NAME") VALUES (2, 'two');
INSERT INTO "GRAPHSCRIPT"."VERTICES"("ID", "NAME") VALUES (3, 'three');
INSERT INTO "GRAPHSCRIPT"."VERTICES"("ID", "NAME") VALUES (4, 'four');
INSERT INTO "GRAPHSCRIPT"."VERTICES"("ID", "NAME") VALUES (5, 'five');
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (1, 2, 0.5);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (1, 3, 0.1);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (2, 3, 1.5);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (2, 4, 0.1);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (3, 4, 0.2);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (5, 4, 0.8);

CREATE GRAPH WORKSPACE "GRAPHSCRIPT"."GRAPHWS"
	EDGE TABLE "GRAPHSCRIPT"."EDGES"
		SOURCE COLUMN "SOURCE"
		TARGET COLUMN "TARGET"
		KEY COLUMN "ID"
	VERTEX TABLE "GRAPHSCRIPT"."VERTICES"
		KEY COLUMN "ID";

/*************************************/
-- 2 How to use the SHORTEST_PATH_ONE_TO_ALL function in a GRAPH"Script" procedure
-- The procedure identifies the shortest paths, given two input parameters: i_startVertex, traversing edges in i_direction
-- The procedure returns a table containing the reachable vertices, and traversed edges
CREATE TYPE "GRAPHSCRIPT"."TT_VERTICES_SPOA" AS TABLE ("ID" BIGINT, "DISTANCE" DOUBLE);
CREATE TYPE "GRAPHSCRIPT"."TT_EDGES_SPOA" AS TABLE ("ID" BIGINT, "SOURCE" BIGINT, "TARGET" BIGINT, "WEIGHT" DOUBLE);

CREATE OR REPLACE PROCEDURE "GRAPHSCRIPT"."GS_SPOA"(
	IN i_startVertex BIGINT, 		-- the key of the start vertex
	IN i_direction NVARCHAR(10), 	-- the the direction of the edge traversal: OUTGOING (default), INCOMING, ANY
	OUT o_vertices "GRAPHSCRIPT"."TT_VERTICES_SPOA",
	OUT o_edges "GRAPHSCRIPT"."TT_EDGES_SPOA"
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	-- Create an instance of the graph, refering to the graph workspace object
	GRAPH g = Graph("GRAPHSCRIPT", "GRAPHWS");
	-- Create an instance of the start vertex
	VERTEX v_start = Vertex(:g, :i_startVertex);
	-- Running shortest paths one to all, which returns a subgraph. The WEIGHT based path length to a vertex is stored in the attribute CALCULATED_COST
	GRAPH g_spoa = SHORTEST_PATHS_ONE_TO_ALL(:g, :v_start, "DISTANCE", (Edge e) => DOUBLE{ return :e."WEIGHT"; }, :i_direction);
	o_vertices = SELECT :v."ID", :v."DISTANCE" FOREACH v IN Vertices(:g_spoa);
	o_edges = SELECT :e."ID", :e."SOURCE", :e."TARGET", :e."WEIGHT" FOREACH e IN Edges(:g_spoa);
END;

CALL "GRAPHSCRIPT"."GS_SPOA"(i_startVertex => 1, i_direction => 'OUTGOING', o_vertices => ?, o_edges => ?);
CALL "GRAPHSCRIPT"."GS_SPOA"(i_startVertex => 1, i_direction => 'ANY', o_vertices => ?, o_edges => ?);



/*************************************/
-- 3 How to wrap the SPOA procedure in a table function.
CREATE OR REPLACE FUNCTION "GRAPHSCRIPT"."F_SPOA_VERTICES" (
	IN i_startVertex BIGINT,
	IN i_dir NVARCHAR(10),
	IN i_maxDepth BIGINT
	)
	RETURNS TABLE ("ID" BIGINT, "DISTANCE" DOUBLE)
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
	CALL "GRAPHSCRIPT"."GS_SPOA"(:i_startVertex, :i_dir, o_vertices, o_edges);
	RETURN SELECT * FROM :o_vertices;
END;

SELECT * FROM "GRAPHSCRIPT"."F_SPOA_VERTICES"(1, 'OUTGOING', 1000);



/*************************************/
-- 4 How to use the SPOA in a GRAPH"Script" anonymous block.
-- The code between BEGIN and END is the same as in the procedure.
DO (
	IN i_startVertex BIGINT => 1,
	IN i_direction NVARCHAR(10) => 'OUTGOING',
	OUT o_vertices TABLE ("ID" BIGINT, "DISTANCE" DOUBLE) => ?,
	OUT o_edges TABLE ("ID" BIGINT, "SOURCE" BIGINT, "TARGET" BIGINT, "WEIGHT" DOUBLE) => ?
	)
LANGUAGE GRAPH
BEGIN
	GRAPH g = Graph("GRAPHSCRIPT", "GRAPHWS");
	VERTEX v_start = Vertex(:g, :i_startVertex);
	GRAPH g_spoa = SHORTEST_PATHS_ONE_TO_ALL(:g, :v_start, "CALCULATED_COST", (Edge e) => DOUBLE{ return :e."WEIGHT"; }, :i_direction);
	o_vertices = SELECT :v."ID", :v."CALCULATED_COST" FOREACH v IN Vertices(:g_spoa);
	o_edges = SELECT :e."ID", :e."SOURCE", :e."TARGET", :e."WEIGHT" FOREACH e IN Edges(:g_spoa);
END;

