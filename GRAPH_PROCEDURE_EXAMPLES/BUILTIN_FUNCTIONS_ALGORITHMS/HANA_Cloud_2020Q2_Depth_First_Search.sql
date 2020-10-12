/*************************************/
-- SAP HANA Graph examples - How to use Depth First Search statement
-- 2020-10-01
-- This script was developed for SAP HANA Cloud 2020 Q2
-- See also https://help.sap.com/viewer/11afa2e60a5f4192a381df30f94863f9/2020_03_QRC/en-US/2bd40d9848124781b27a37ce66344730.html
-- Wikipedia https://en.wikipedia.org/wiki/Depth-first_search
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
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (6);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (1, 2, 0.3);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (1, 3, 0.1);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (1, 4, 0.2);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (2, 3, 1.5);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (2, 5, 0.2);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (3, 5, 0.1);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (4, 5, 0.4);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (6, 5, 0.8);

CREATE GRAPH WORKSPACE "GRAPHSCRIPT"."GRAPHWS"
	EDGE TABLE "GRAPHSCRIPT"."EDGES"
		SOURCE COLUMN "SOURCE"
		TARGET COLUMN "TARGET"
		KEY COLUMN "ID"
	VERTEX TABLE "GRAPHSCRIPT"."VERTICES"
		KEY COLUMN "ID";

/*************************************/
-- How to use the DFS traversal statement in a GRAPH"Script" procedure.
-- The procedure traverses the graph in a depth first search manner, starting ftom i_startVertex
-- The procedure returns a table containing vertex keys, their visit and exit order, and a level number indicating the hop distance from the startVertex.

CREATE TYPE "GRAPHSCRIPT"."TT_VERTICES_DFS" AS TABLE ("ID" BIGINT, "VISIT_ORDER" BIGINT, "EXIT_ORDER" BIGINT, "LEVEL" BIGINT);

CREATE OR REPLACE PROCEDURE "GRAPHSCRIPT"."GS_DEPTH_FIRST_SEARCH"(
	IN i_startVertex BIGINT,		-- the ID of the start vertex
	OUT o_vertices "GRAPHSCRIPT"."TT_VERTICES_DFS"
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph("GRAPHSCRIPT","GRAPHWS");
	-- counters for the "visit vertex" and "exit vertex" event
	BIGINT c_visit = 0L;
	BIGINT c_exit = 0L;
	ALTER g ADD TEMPORARY VERTEX ATTRIBUTE (BIGINT "VISIT_ORDER");
	ALTER g ADD TEMPORARY VERTEX ATTRIBUTE (BIGINT "EXIT_ORDER");
	ALTER g ADD TEMPORARY VERTEX ATTRIBUTE (BIGINT "LEVEL");
	-- create an instance of the start vertex
	VERTEX v_start = Vertex(:g, :i_startVertex);
	-- traverse the graph from the start node, "hooking" into each vertex visit and exit.
	TRAVERSE DFS('OUTGOING') :g FROM :v_start
		ON VISIT VERTEX (Vertex v_visited, BIGINT lvl) {
			c_visit = :c_visit + 1L;
			v_visited."VISIT_ORDER" = :c_visit;
			v_visited."LEVEL" = :lvl;
		}
		-- the "exit vertex" hook is executed when each neighboring node has been processed
		ON EXIT VERTEX (Vertex v_exited) {
			c_exit = :c_exit + 1L;
			v_exited."EXIT_ORDER" = :c_exit;
	};
	o_vertices = SELECT :v."ID", :v."VISIT_ORDER", :v."EXIT_ORDER", :v."LEVEL" FOREACH v IN Vertices(:g);
END;
CALL "GRAPHSCRIPT"."GS_DEPTH_FIRST_SEARCH"(i_startVertex => 1, o_vertices => ?);

/*************************************/
-- wrap the procedure in a function
CREATE OR REPLACE FUNCTION "GRAPHSCRIPT"."F_DEPTH_FIRST_SEARCH"( IN i_startVertex BIGINT )
    RETURNS "GRAPHSCRIPT"."TT_VERTICES_DFS"
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    CALL "GRAPHSCRIPT"."GS_DEPTH_FIRST_SEARCH"(:i_startVertex, o_res);
    RETURN :o_res;
END;

SELECT * FROM "GRAPHSCRIPT"."F_DEPTH_FIRST_SEARCH"(i_startVertex => 1) ORDER BY "VISIT_ORDER" ASC;
