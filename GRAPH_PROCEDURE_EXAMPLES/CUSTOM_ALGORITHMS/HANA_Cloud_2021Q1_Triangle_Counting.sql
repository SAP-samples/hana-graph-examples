/*************************************/
-- SAP HANA Graph examples - Triangle Counting
-- 2021-04-15
-- This script was developed for SAP HANA Cloud 2021 Q1
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
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (1, 4);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (2, 3);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (2, 4);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (3, 4);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (5, 1);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET") VALUES (4, 5);

CREATE GRAPH WORKSPACE "GRAPHSCRIPT"."GRAPHWS"
	EDGE TABLE "GRAPHSCRIPT"."EDGES"
		SOURCE COLUMN "SOURCE"
		TARGET COLUMN "TARGET"
		KEY COLUMN "ID"
	VERTEX TABLE "GRAPHSCRIPT"."VERTICES"
		KEY COLUMN "ID";

/*************************************/
--  Procedure to count trinagles in a graph
CREATE OR REPLACE PROCEDURE "GRAPHSCRIPT"."GS_TRIANGLES"(
	OUT o_triangleCount BIGINT
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph("GRAPHSCRIPT","GRAPHWS");
	MULTISET<Vertex> m_n = Multiset<Vertex>(:g);
	BIGINT triangleCount = 0L;
	FOREACH v IN Vertices(:g){
		-- get all the 1 hop neighbors of v (v is not in this set)
		m_n = Neighbors(:g, :v, 1, 1, 'ANY');
		--  now, count all the edges that connected these neighbors to each other
		triangleCount = :triangleCount + COUNT(EDGES(:g, :m_n, :m_n));
	}
	-- Since every triangle is counted three times, the final number of triangles is:
	o_triangleCount = :triangleCount / 3L;
END;

CALL "GRAPHSCRIPT"."GS_TRIANGLES"(?);



/*************************************/
--  Triangle count as anonymous block
DO(
	OUT o_triangleCount BIGINT => ?
	)
LANGUAGE GRAPH
BEGIN
	GRAPH g = Graph("GRAPHSCRIPT","GRAPHWS");
	MULTISET<Vertex> m_n = Multiset<Vertex>(:g);
	BIGINT triangleCount = 0L;
	FOREACH v IN Vertices(:g){
		-- get all the 1 hop neighbors of v (v is not in this set)
		m_n = Neighbors(:g, :v, 1, 1, 'ANY');
		--  now, count all the edges that connected these neighbors to each other
		triangleCount = :triangleCount + COUNT(EDGES(:g, :m_n, :m_n));
	}
	-- Since every triangle is counted three times, the final number of triangles is:
	o_triangleCount = :triangleCount / 3L;
END;

