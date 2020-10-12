/*************************************/
-- SAP HANA Graph examples - How to use the SHORTEST_PATH function
-- 2020-10-01
-- This script was developed for SAP HANA Cloud 2020 Q2
-- See also https://help.sap.com/viewer/11afa2e60a5f4192a381df30f94863f9/cloud/en-US/3b0a971b129c446c9e40a797bdb29c2b.html
/*************************************/

/*************************************/
-- 1 Create schema, tables, graph workspace, and load some sample data
DROP SCHEMA "GRAPHSCRIPT" CASCADE;
CREATE SCHEMA "GRAPHSCRIPT";
CREATE COLUMN TABLE "GRAPHSCRIPT"."VERTICES" (
	"ID" BIGINT PRIMARY KEY
);
CREATE COLUMN TABLE "GRAPHSCRIPT"."EDGES" (
	"ID" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	"SOURCE" BIGINT REFERENCES "GRAPHSCRIPT"."VERTICES"("ID") ON DELETE CASCADE NOT NULL,
	"TARGET" BIGINT REFERENCES "GRAPHSCRIPT"."VERTICES"("ID") ON DELETE CASCADE NOT NULL,
	"WEIGHT" DOUBLE
);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (1);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (2);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (3);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (4);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (5);
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
-- How to use the SHORTEST_PATH function in a GRAPH"Script" procedure
-- The procedure identifies the shortest path, given three input parameters: i_startVertex, i_endVertex, traversing edges in i_direction
-- The procedure returns a table containing the path's vertices, edges, length (= hop distance), and weight (= sum of WEIGHT values)

CREATE TYPE "GRAPHSCRIPT"."TT_VERTICES_SPOO" AS TABLE ("ID" BIGINT, "VERTEX_ORDER" BIGINT);
CREATE TYPE "GRAPHSCRIPT"."TT_EDGES_SPOO" AS TABLE ("ID" BIGINT, "SOURCE" BIGINT, "TARGET" BIGINT, "EDGE_ORDER" BIGINT);

CREATE OR REPLACE PROCEDURE "GRAPHSCRIPT"."GS_SPOO"(
	IN i_startVertex BIGINT, 		-- the ID of the start vertex
	IN i_endVertex BIGINT, 			-- the ID of the end vertex
	IN i_direction NVARCHAR(10), 	-- the the direction of the edge traversal: OUTGOING (default), INCOMING, ANY
	OUT o_path_length BIGINT,		-- the hop distance between start and end
	OUT o_path_weight DOUBLE,		-- the path weight/cost based on the WEIGHT attribute
	OUT o_vertices "GRAPHSCRIPT"."TT_VERTICES_SPOO",
	OUT o_edges "GRAPHSCRIPT"."TT_EDGES_SPOO"
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	-- Create an instance of the graph, refering to the graph workspace object
	GRAPH g = Graph("GRAPHSCRIPT", "GRAPHWS");
	-- Check if vertices exist
	IF (NOT VERTEX_EXISTS(:g, :i_startVertex) OR NOT VERTEX_EXISTS(:g, :i_endVertex)) {
		o_path_length = 0L;
		o_path_weight = 0.0;
		return;
	}
	-- Create an instance of the start/end vertex
	VERTEX v_start = Vertex(:g, :i_startVertex);
	VERTEX v_end = Vertex(:g, :i_endVertex);
	-- Running shortest path using the WEIGHT column as cost
	WeightedPath<DOUBLE> p = Shortest_Path(:g, :v_start, :v_end, (Edge e) => DOUBLE{ return :e."WEIGHT"; }, :i_direction);
	-- Project the results from the path
	o_path_length = LENGTH(:p);
	o_path_weight = WEIGHT(:p);
	o_vertices = SELECT :v."ID", :VERTEX_ORDER FOREACH v IN Vertices(:p) WITH ORDINALITY AS VERTEX_ORDER;
	o_edges = SELECT :e."ID", :e."SOURCE", :e."TARGET", :EDGE_ORDER FOREACH e IN Edges(:p) WITH ORDINALITY AS EDGE_ORDER;
END;

-- Finding the shortest path between vertex "1" and "4", traversing edges in any direction
CALL "GRAPHSCRIPT"."GS_SPOO"(i_startVertex => 1, i_endVertex => 4, i_direction => 'ANY', o_path_length => ?, o_path_weight => ?, o_vertices => ?, o_edges => ?);
