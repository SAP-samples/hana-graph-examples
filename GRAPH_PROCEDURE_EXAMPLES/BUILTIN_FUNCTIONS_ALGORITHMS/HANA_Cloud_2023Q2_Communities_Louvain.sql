/*************************************/
-- SAP HANA Graph examples - How to use the Community Detection algorithm
-- 2023-08-09
-- This script was developed for SAP HANA Cloud 2023 Q2
-- see also https://help.sap.com/docs/hana-cloud-database/sap-hana-cloud-sap-hana-database-graph-reference/built-in-graph-algorithms#community-detection
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
-- 2 How to use the community detection algorithm in a GRAPH"Script" procedure
-- The procedure identifies the communities of a graph
-- The procedure returns
	-- the number of communities
	-- the community histogram
	-- a table with vertex keys and the community IID

CREATE OR REPLACE PROCEDURE "GRAPHSCRIPT"."GS_COMMUNITY" (
	IN i_runs INT DEFAULT 1,
	OUT o_numberOfCommunities BIGINT,
	OUT o_communityHistogram TABLE("$COMMUNITY_ID" BIGINT, "$COUNT" BIGINT),
	OUT o_res TABLE("ID" BIGINT, "$COMMUNITY_ID" BIGINT)
)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	Graph g = Graph("GRAPHSCRIPT","GRAPHWS");
	SEQUENCE<MULTISET<VERTEX>> communities = COMMUNITIES_LOUVAIN(:g, :i_runs);
	--SEQUENCE<MULTISET<VERTEX>> communities = COMMUNITIES_LOUVAIN(:g, :i_runs, (Edge e) => DOUBLE{ return 1.0/:e."LENGTH"; } );
	-- counting the elements in the communites SEQUENCE provides the number of communities found
	o_numberOfCommunities = COUNT(:communities);
	-- to get the number of vertices in each community, we count the elements in each community MULTISET, and write the results in the output table
	BIGINT i = 0L;
	FOREACH community IN :communities {
		i = :i + 1L;
		o_communityHistogram."$COMMUNITY_ID"[:i] = :i - 1L;
		o_communityHistogram."$COUNT"[:i] = COUNT(:community);
	}
	-- and finally project the result: return the community id for each vertex
	MAP<VERTEX, BIGINT> m_vertexCommunity = TO_ORDINALITY_MAP(:communities);
	o_res = SELECT :v."ID", :m_vertexCommunity[:v] FOREACH v in VERTICES(:g);
END;

CALL "GRAPHSCRIPT"."GS_COMMUNITY"(i_runs => 1, o_numberOfCommunities => ?, o_communityHistogram => ?, o_res => ?);




/*************************************/
-- 4 How to use the Community Detection in a GRAPH"Script" anonymous block.
-- The code between BEGIN and END is the same as in the procedure.
DO (
	IN i_runs INT => 1,
	OUT o_scalars TABLE ("NUMBER_OF_COMMUNITIES" BIGINT) => ?,
	OUT o_communityHistogram TABLE("$COMMUNITY_ID" BIGINT, "$COUNT" BIGINT) => ?,
	OUT o_res TABLE("ID" BIGINT, "$COMMUNITY_ID" BIGINT) => ?
)
LANGUAGE GRAPH
BEGIN
	Graph g = Graph("GRAPHSCRIPT","GRAPHWS");
	SEQUENCE<MULTISET<VERTEX>> communities = COMMUNITIES_LOUVAIN(:g, :i_runs);
	--SEQUENCE<MULTISET<VERTEX>> communities = COMMUNITIES_LOUVAIN(:g, :i_runs, (Edge e) => DOUBLE{ return 1.0/:e."LENGTH"; } );
	-- counting the elements in the communites SEQUENCE provides the number of communities found
	o_scalars."NUMBER_OF_COMMUNITIES"[1L] = COUNT(:communities);
	-- to get the number of vertices in each community, we count the elements in each community MULTISET, and write the results in the output table
	BIGINT i = 0L;
	FOREACH community IN :communities {
		i = :i + 1L;
		o_communityHistogram."$COMMUNITY_ID"[:i] = :i - 1L;
		o_communityHistogram."$COUNT"[:i] = COUNT(:community);
	}
	-- and finally project the result: return the community id for each vertex
	MAP<VERTEX, BIGINT> m_vertexCommunity = TO_ORDINALITY_MAP(:communities);
	o_res = SELECT :v."ID", :m_vertexCommunity[:v] FOREACH v in VERTICES(:g);
END;
