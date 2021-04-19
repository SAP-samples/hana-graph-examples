/*************************************/
-- SAP HANA Graph examples - How to use the Strongly Connected Components algorithm
-- 2021-04-15
-- This script was developed for SAP HANA Cloud 2021 Q1
-- see also https://help.sap.com/viewer/11afa2e60a5f4192a381df30f94863f9/cloud/en-US/3b0a971b129c446c9e40a797bdb29c2b.html
-- Wikipedia https://en.wikipedia.org/wiki/Strongly_connected_component#:~:text=7%20External%20links-,Definitions,second%20vertex%20to%20the%20first. 
/*************************************/

/*************************************/
-- 1 create schema, tables, graph workspace, and load some sample data
DROP SCHEMA "GRAPHSCRIPT" CASCADE;
CREATE SCHEMA "GRAPHSCRIPT";
CREATE COLUMN TABLE "GRAPHSCRIPT"."NODES" (
	"ID" BIGINT PRIMARY KEY
);
CREATE COLUMN TABLE "GRAPHSCRIPT"."EDGES" (
	"ID" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	"SOURCE" BIGINT REFERENCES "GRAPHSCRIPT"."NODES"("ID") ON DELETE CASCADE NOT NULL,
	"TARGET" BIGINT REFERENCES "GRAPHSCRIPT"."NODES"("ID") ON DELETE CASCADE NOT NULL
);
INSERT INTO "GRAPHSCRIPT"."NODES" VALUES (1);
INSERT INTO "GRAPHSCRIPT"."NODES" VALUES (2);
INSERT INTO "GRAPHSCRIPT"."NODES" VALUES (3);
INSERT INTO "GRAPHSCRIPT"."NODES" VALUES (4);
INSERT INTO "GRAPHSCRIPT"."NODES" VALUES (5);
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
	VERTEX TABLE "GRAPHSCRIPT"."NODES" 
		KEY COLUMN "ID";

/*************************************/
-- 2 How to use the SCC algorithm in a GRAPH"Script" procedure
-- The procedure identifies the strongly Connected Components of a graph
-- The procedure returns a table containing vertex keys and a COMPONENT attribute identifiying which vertices belong to the same SCC. The procedure returns also th number of SCCs

CREATE TYPE "GRAPHSCRIPT"."TT_SCC" AS TABLE ("ID" BIGINT, "COMPONENT" BIGINT);

CREATE OR REPLACE PROCEDURE "GRAPHSCRIPT"."GS_STRONGLY_CONNECTED_COMPONENTS"(
	OUT o_scc "GRAPHSCRIPT"."TT_SCC",
	OUT o_componentsCount BIGINT
)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	-- create an insatnce of the graph
	Graph g = Graph("GRAPHSCRIPT", "GRAPHWS");
	-- add a temporary attribute to store the component number for each node
	ALTER g ADD TEMPORARY VERTEX ATTRIBUTE(BIGINT "COMPONENT");
	BIGINT componentCounter = 0L;
	-- run SCC which returns a sequence of sequences of vertices
	Sequence<Sequence<Vertex>> m_scc = STRONGLY_CONNECTED_COMPONENTS(:g);
	-- loop over the individual component and store the component number in each vertex' COMPONENT attribute
	FOREACH m_component IN :m_scc {
		componentCounter = :componentCounter + 1L;
		FOREACH v IN :m_component {
			v."COMPONENT" = :componentCounter;
		}
	}
	o_scc = SELECT :v."ID", :v."COMPONENT" FOREACH v in Vertices(:g);
	o_componentsCount = COUNT(:m_scc);
END;

CALL "GRAPHSCRIPT"."GS_STRONGLY_CONNECTED_COMPONENTS"(o_scc => ?, o_componentsCount => ?);


/*************************************/
-- 4 How to use the SCC in a GRAPH"Script" anonymous block.
-- The code between BEGIN and END is the same as in the procedure.
DO (
	OUT o_scc TABLE ("ID" BIGINT, "COMPONENT" BIGINT) => ?,
	OUT o_componentsCount BIGINT => ?
)
LANGUAGE GRAPH
BEGIN
	Graph g = Graph("GRAPHSCRIPT", "GRAPHWS");
	ALTER g ADD TEMPORARY VERTEX ATTRIBUTE(BIGINT "COMPONENT");
	BIGINT componentCounter = 0L;
	Sequence<Sequence<Vertex>> m_scc = STRONGLY_CONNECTED_COMPONENTS(:g);
	FOREACH m_component IN :m_scc {
		componentCounter = :componentCounter + 1L;
		FOREACH v IN :m_component {
			v."COMPONENT" = :componentCounter;
		}
	}
	o_scc = SELECT :v."ID", :v."COMPONENT" FOREACH v in Vertices(:g);
	o_componentsCount = COUNT(:m_scc);
END;
