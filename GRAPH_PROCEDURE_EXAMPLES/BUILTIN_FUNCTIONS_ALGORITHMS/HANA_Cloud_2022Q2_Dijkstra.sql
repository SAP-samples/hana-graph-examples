/*************************************/
-- SAP HANA Graph examples - How to use TRAVERSE DIJKSTA statement
-- 2022-05-19
-- This script was developed for SAP HANA Cloud 2022 Q1
-- See also https://help.sap.com/docs/HANA_CLOUD_DATABASE/11afa2e60a5f4192a381df30f94863f9/2bd40d9848124781b27a37ce66344730.html?state=DRAFT

/*************************************/

/*************************************/
-- 1 Create schema, tables, graph workspace, and load some sample data
DROP SCHEMA "GRAPHSCRIPT" CASCADE;
CREATE SCHEMA "GRAPHSCRIPT";
CREATE COLUMN TABLE "GRAPHSCRIPT"."VERTICES" (
	"ID" BIGINT PRIMARY KEY,
	"TYPE" NVARCHAR(100)
);

CREATE COLUMN TABLE "GRAPHSCRIPT"."EDGES" (
	"ID" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	"SOURCE" BIGINT REFERENCES "GRAPHSCRIPT"."VERTICES"("ID") ON DELETE CASCADE NOT NULL,
	"TARGET" BIGINT REFERENCES "GRAPHSCRIPT"."VERTICES"("ID") ON DELETE CASCADE NOT NULL
);

INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (1, '');
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (2, 'Pizza');
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (3, '');
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (4, 'Pizza');
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (5, '');
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
-- 2 How to use the DIJKSTRA traversal statement in a GRAPH"Script" procedure.
-- The procedure traverses the graph in a shortest path search manner.
-- The network is explored starting with vertex i_startVertex. If the two nearest "Pizza" vertices are found, it stops. 
-- The procedure returns a table containing the found Pizza vertices, including the (hop) distance information.
-- It is also possible to get the shortest paths to each Pizza vertex. (todo, see documentation)

CREATE OR REPLACE PROCEDURE "GRAPHSCRIPT"."GS_DIJKSTRA"(
	IN i_startVertex BIGINT,
	OUT o_vertices TABLE ("ID" BIGINT, "TYPE" NVARCHAR(100), "DISTANCE" BIGINT)
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph("GRAPHSCRIPT","GRAPHWS") WITH TEMPORARY ATTRIBUTES (
		VERTEX BIGINT "$DISTANCE"
	);
	VERTEX v_start = Vertex(:g, :i_startVertex);
	BIGINT pizzas_found = 0L;
	-- traverse the graph from the start Vertex, "hooking" into each vertex/edge visit
	-- if a two "Pizza" vertices are found, the traversal is stopped
	TRAVERSE DIJKSTRA :g FROM :v_start
		WITH WEIGHT (EDGE e) => BIGINT { return 1L; }
		ON VISIT VERTEX (Vertex v, BIGINT v_dist) {
			IF(:v."TYPE" == 'Pizza') {
				v."$DISTANCE" = :v_dist;
				pizzas_found = :pizzas_found + 1L;
				IF (:pizzas_found >= 2L) { END TRAVERSE; }
			}
		};
	MULTISET<Vertex> m_vertices = v IN Vertices(:g) WHERE :v."$DISTANCE" >= 0L;
	o_vertices = SELECT :v."ID", :v."TYPE", :v."$DISTANCE" FOREACH v IN :m_vertices;
END;

CALL "GRAPHSCRIPT"."GS_DIJKSTRA"(i_startVertex => 3, o_vertices => ?);



