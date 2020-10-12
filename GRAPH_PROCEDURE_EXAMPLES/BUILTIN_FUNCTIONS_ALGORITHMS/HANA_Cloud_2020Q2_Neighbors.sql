/*************************************/
-- SAP HANA Graph examples - How to use the NEIGHBORS function
-- 2020-10-01
-- This script was developed for SAP HANA Cloud 2020 Q2
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
	"TARGET" BIGINT REFERENCES "GRAPHSCRIPT"."VERTICES"("ID") ON DELETE CASCADE NOT NULL
);
INSERT INTO "GRAPHSCRIPT"."VERTICES"("ID", "NAME") VALUES (1, 'one');
INSERT INTO "GRAPHSCRIPT"."VERTICES"("ID", "NAME") VALUES (2, 'two');
INSERT INTO "GRAPHSCRIPT"."VERTICES"("ID", "NAME") VALUES (3, 'three');
INSERT INTO "GRAPHSCRIPT"."VERTICES"("ID", "NAME") VALUES (4, 'four');
INSERT INTO "GRAPHSCRIPT"."VERTICES"("ID", "NAME") VALUES (5, 'five');
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (1, 2);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (1, 3);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (2, 3);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (2, 4);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (3, 4);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (5, 4);

CREATE GRAPH WORKSPACE "GRAPHSCRIPT"."GRAPHWS"
	EDGE TABLE "GRAPHSCRIPT"."EDGES"
		SOURCE COLUMN "SOURCE"
		TARGET COLUMN "TARGET"
		KEY COLUMN "ID"
	VERTEX TABLE "GRAPHSCRIPT"."VERTICES"
		KEY COLUMN "ID";

/*************************************/
-- How to use the NEIGHBORS function in a GRAPH"Script" procedure.
-- The procedure identifies the neighbors, given four input parameters: i_startVertex, with a hop distance between i_minDepth and i_maxDepth, traversing edges in i_dir direction.
-- The procedure returns a table containing vertex keys, the number of vertices, and the edge keys of the neighbor node-induced subgraph.

CREATE TYPE "GRAPHSCRIPT"."TT_VERTICES_NEI" AS TABLE ("ID" BIGINT, "NAME" VARCHAR(100));
CREATE TYPE "GRAPHSCRIPT"."TT_EDGES_NEI" AS TABLE ("ID" BIGINT, "SOURCE" BIGINT, "TARGET" BIGINT);

CREATE OR REPLACE PROCEDURE "GRAPHSCRIPT"."GS_NEIGHBORS"(
	IN i_startVertex BIGINT,	-- the key of the start vertex
	IN i_minDepth BIGINT, 		-- the minimum hop distance
	IN i_maxDepth BIGINT, 		-- the maximum hop distance
	IN i_dir VARCHAR(10),		-- the direction the edges are traversed: OUTGOING, INCOMING, ANY
	OUT o_vertices "GRAPHSCRIPT"."TT_VERTICES_NEI",
	OUT o_verticesCount BIGINT,
	OUT o_edges "GRAPHSCRIPT"."TT_EDGES_NEI"
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	-- Create an instance of the graph, referring to the graph workspace object
	GRAPH g = Graph("GRAPHSCRIPT", "GRAPHWS");
	-- Create an instance of the start vertex
	VERTEX v_start = Vertex(:g, :i_startVertex);
	-- Create a multiset of all neighbor vertices of the start vertex
	MULTISET<Vertex> m_neighbors = Neighbors(:g, :v_start, :i_minDepth, :i_maxDepth, :i_dir);
	-- Project the result from the multiset
	o_vertices = SELECT :v."ID", :v."NAME" FOREACH v IN :m_neighbors;
	o_verticesCount = COUNT(:m_neighbors);
	-- Find all edges between the vertices in m_neighbors
	MULTISET<Edge> m_edges = EDGES(:g, :m_neighbors, :m_neighbors);
	o_edges = SELECT :e."ID", :e."SOURCE", :e."TARGET" FOREACH e IN :m_edges;
END;

-- Get one hop neighbors of the vertex "2", traversing outgoing edges.
CALL "GRAPHSCRIPT"."GS_NEIGHBORS"(i_startVertex => 2, i_minDepth => 1, i_maxDepth => 1, i_dir => 'OUTGOING', o_vertices => ?, o_verticesCount => ?, o_edges => ?);
-- Get neighbors reachable from vertex "2" with max. 2 hops, following edges in any direction.
CALL "GRAPHSCRIPT"."GS_NEIGHBORS"(i_startVertex => 2, i_minDepth => 0, i_maxDepth => 2, i_dir => 'ANY', o_vertices => ?, o_verticesCount => ?, o_edges => ?);


-- Optional post-processing step: wrap a function around the GRAPH"Script" procedure that joins the result vertices to the edges
CREATE OR REPLACE FUNCTION "GRAPHSCRIPT"."F_NEIGHBORS"(
	IN i_startVertex BIGINT,	-- the ID of the start vertex
	IN i_minDepth BIGINT, 		-- the minimum hop distance
	IN i_maxDepth BIGINT, 		-- the maximum hop distance
	IN i_dir VARCHAR(10)		-- the direction the edges are traversed: OUTGOING, INCOMING, ANY
	)
    RETURNS TABLE("ID" BIGINT, "SOURCE" BIGINT, "TARGET" BIGINT, "SOURCE_NAME" VARCHAR(100), "TARGET_NAME" VARCHAR(100))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
	DECLARE o_verticesCount BIGINT;
	CALL "GRAPHSCRIPT"."GS_NEIGHBORS"(:i_startVertex, :i_minDepth, :i_maxDepth, :i_dir, o_vertices, o_verticesCount, o_edges);
    RETURN SELECT E."ID", E."SOURCE", E."TARGET", N1."NAME" AS "SOURCE_NAME", N2."NAME" AS "TARGET_NAME"
    	FROM :o_edges AS E, :o_vertices AS N1, :o_vertices AS N2
    	WHERE E."SOURCE" = N1."ID" AND E."TARGET" = N2."ID";
  END;

SELECT * FROM "GRAPHSCRIPT"."F_NEIGHBORS"(i_startVertex => 1, i_minDepth => 0, i_maxDepth => 2, i_dir => 'ANY');
