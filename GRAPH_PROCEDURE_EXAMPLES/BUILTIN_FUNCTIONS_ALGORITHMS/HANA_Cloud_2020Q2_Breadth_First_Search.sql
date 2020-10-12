/*************************************/
-- SAP HANA Graph examples - How to use Breadth First Search statement
-- 2020-10-01
-- This script was developed for SAP HANA Cloud 2020 Q2
-- See also https://help.sap.com/viewer/11afa2e60a5f4192a381df30f94863f9/2020_03_QRC/en-US/2bd40d9848124781b27a37ce66344730.html
-- Wikipedia https://en.wikipedia.org/wiki/Breadth-first_search
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
	"TARGET" BIGINT REFERENCES "GRAPHSCRIPT"."VERTICES"("ID") ON DELETE CASCADE NOT NULL
);

INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (1);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (2);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (3);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (4);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (5);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (1, 2);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (1, 3);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (2, 3);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (3, 1);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (2, 4);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (3, 4);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (5, 4);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (4, 5);

CREATE GRAPH WORKSPACE "GRAPHSCRIPT"."GRAPHWS"
	EDGE TABLE "GRAPHSCRIPT"."EDGES"
		SOURCE COLUMN "SOURCE"
		TARGET COLUMN "TARGET"
		KEY COLUMN "ID"
	VERTEX TABLE "GRAPHSCRIPT"."VERTICES"
		KEY COLUMN "ID";

/*************************************/
-- How to use the BFS traversal statement in a GRAPH"Script" procedure.
-- The procedure traverses the graph in a breadth first search manner, starting ftom i_startVertex, traversing in direction i_dir, with a maximum depth of i_maxDepth.
-- The procedure returns two tables - one for traversed vertices, one for edges, including (hop) distance information.

CREATE TYPE "GRAPHSCRIPT"."TT_VERTICES_BFS" AS TABLE ("ID" BIGINT, "DISTANCE" BIGINT);
CREATE TYPE "GRAPHSCRIPT"."TT_EDGES_BFS" AS TABLE ("ID" BIGINT, "SOURCE" BIGINT, "TARGET" BIGINT, "DISTANCE" BIGINT);

CREATE OR REPLACE PROCEDURE "GRAPHSCRIPT"."GS_BREADTH_FIRST_SEARCH"(
	IN i_startVertex BIGINT,
	IN i_dir NVARCHAR(10),
  IN i_maxDepth BIGINT,
	OUT o_vertices "GRAPHSCRIPT"."TT_VERTICES_BFS",
	OUT o_edges "GRAPHSCRIPT"."TT_EDGES_BFS"
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph("GRAPHSCRIPT","GRAPHWS");
	-- add a vertex/edge attribute to store data. In this case, the hop "DISTANCE".
	ALTER g ADD TEMPORARY VERTEX ATTRIBUTE (BIGINT "DISTANCE" = -1L);
	ALTER g ADD TEMPORARY EDGE ATTRIBUTE (BIGINT "DISTANCE" = -1L);
	VERTEX v_start = Vertex(:g, :i_startVertex);
	-- traverse the graph from the start Vertex, "hooking" into each vertex/edge visit
  -- if a maximum distance is reached, the traversal is stopped
	TRAVERSE BFS(:i_dir) :g FROM :v_start
		ON VISIT VERTEX (Vertex v, BIGINT v_dist) {
			v."DISTANCE" = :v_dist;
			IF (:v_dist >= :i_maxDepth) { END TRAVERSE; }
		}
		ON VISIT EDGE (Edge e, BIGINT e_dist) {
			e."DISTANCE" = :e_dist;
		};
	MULTISET<Vertex> m_vertices = v IN Vertices(:g) WHERE :v."DISTANCE" >= 0L;
	MULTISET<Edge> m_edges = e IN Edges(:g) WHERE :e."DISTANCE" >= 0L;
	o_vertices = SELECT :v."ID", :v."DISTANCE" FOREACH v IN :m_vertices;
	o_edges = SELECT :e."ID", :e."SOURCE", :e."TARGET", :e."DISTANCE" FOREACH e IN :m_edges;
END;

CALL "GRAPHSCRIPT"."GS_BREADTH_FIRST_SEARCH"(i_startVertex => 4, i_dir => 'ANY', i_maxDepth => 1000, o_VERTICES => ?, o_edges => ?);
CALL "GRAPHSCRIPT"."GS_BREADTH_FIRST_SEARCH"(i_startVertex => 4, i_dir => 'OUTGOING', i_maxDepth => 1000, o_VERTICES => ?, o_edges => ?);
