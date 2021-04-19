/*************************************/
-- SAP HANA Graph examples - (weakly) connected components and connectivity check
-- 2021-03-01
-- This script was developed for SAP HANA Cloud 2020 Q4
-- Wikipedia https://en.wikipedia.org/wiki/Component_(graph_theory)
/*************************************/

/*************************************/
-- 1 Create schema, tables, graph workspace, and load some sample data
DROP SCHEMA "GRAPHSCRIPT" CASCADE;
CREATE SCHEMA "GRAPHSCRIPT";
CREATE COLUMN TABLE "GRAPHSCRIPT"."VERTICES" (
    "ID" BIGINT PRIMARY KEY,
    "NAME" NVARCHAR(5000),
    "ORDER"	BIGINT DEFAULT NULL
);
CREATE COLUMN TABLE "GRAPHSCRIPT"."EDGES" (
    "ID" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY NOT NULL,
    "SOURCE" BIGINT NOT NULL REFERENCES "GRAPHSCRIPT"."VERTICES" ("ID") ON UPDATE CASCADE ON DELETE CASCADE,
    "TARGET" BIGINT NOT NULL REFERENCES "GRAPHSCRIPT"."VERTICES" ("ID") ON UPDATE CASCADE ON DELETE CASCADE,
    "WEIGHT" DOUBLE
);

INSERT INTO "GRAPHSCRIPT"."VERTICES" ("ID") VALUES (1);
INSERT INTO "GRAPHSCRIPT"."VERTICES" ("ID") VALUES (2);
INSERT INTO "GRAPHSCRIPT"."VERTICES" ("ID") VALUES (3);
INSERT INTO "GRAPHSCRIPT"."VERTICES" ("ID") VALUES (4);
INSERT INTO "GRAPHSCRIPT"."VERTICES" ("ID") VALUES (5);
INSERT INTO "GRAPHSCRIPT"."VERTICES" ("ID") VALUES (10);

INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET", "WEIGHT") VALUES (1, 2, 0.0);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET", "WEIGHT") VALUES (1, 3, 0.0);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET", "WEIGHT") VALUES (3, 4, 0.0);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET", "WEIGHT") VALUES (4, 5, 0.0);

/****************************************************/
-- create workspace
CREATE GRAPH WORKSPACE "GRAPHSCRIPT"."GRAPHWS"
	EDGE TABLE "GRAPHSCRIPT"."EDGES"
		SOURCE COLUMN "SOURCE"
		TARGET COLUMN "TARGET"
		KEY COLUMN "ID"
	VERTEX TABLE "GRAPHSCRIPT"."VERTICES"
		KEY COLUMN "ID";


/****************************************************/
-- 2 Procedure Connected Components
CREATE TYPE "GRAPHSCRIPT"."TT_OUT_VERTICES" AS TABLE ("ID" BIGINT, "COMPONENT" BIGINT);

CREATE OR REPLACE PROCEDURE "GRAPHSCRIPT"."GS_CONNECTED_COMPONENTS" (
	OUT o_components BIGINT,
	OUT o_res "GRAPHSCRIPT"."TT_OUT_VERTICES"
)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph("GRAPHSCRIPT", "GRAPHWS");
	-- add a temporary attribute to store the component number
	ALTER g ADD TEMPORARY VERTEX ATTRIBUTE (BIGINT "COMPONENT" = 0L);
	BIGINT i = 0L;
	FOREACH v_start IN Vertices(:g){
		IF(:v_start."COMPONENT" == 0L) {
			i = :i + 1L;
			-- all reachable neighbors are assigned the same component number > 0
			FOREACH v_reachable IN REACHABLE_VERTICES(:g, :v_start, 'ANY') {
    			v_reachable."COMPONENT" = :i;
    		}
		}
	}
	o_components = :i;
	o_res = SELECT :v."ID", :v."COMPONENT" FOREACH v IN Vertices(:g);
END;

CALL "GRAPHSCRIPT"."GS_CONNECTED_COMPONENTS"(?, ?);



/*************************************/
-- 3 Connected Components wrapped in a table funciton
CREATE OR REPLACE FUNCTION "GRAPHSCRIPT"."F_CONNECTED_COMPONENTS"()
    RETURNS "GRAPHSCRIPT"."TT_OUT_VERTICES"
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
	DECLARE o_components BIGINT;
    CALL "GRAPHSCRIPT"."GS_CONNECTED_COMPONENTS"(o_components, o_res);
    RETURN :o_res;
END;

SELECT "COMPONENT", COUNT(*) AS "COUNT" FROM "GRAPHSCRIPT"."F_CONNECTED_COMPONENTS"() GROUP BY "COMPONENT" ORDER BY "COUNT" DESC;



/*************************************/
-- 4 Connected Components as anonymous block
DO (
	OUT o_components BIGINT => ?,
	OUT o_res TABLE ("ID" BIGINT, "COMPONENT" BIGINT) => ?
)
LANGUAGE GRAPH
BEGIN
	GRAPH g = Graph("GRAPHSCRIPT", "GRAPHWS");
	ALTER g ADD TEMPORARY VERTEX ATTRIBUTE (BIGINT "COMPONENT" = 0L);
	BIGINT i = 0L;
	FOREACH v_start IN Vertices(:g){
		IF(:v_start."COMPONENT" == 0L) {
			i = :i + 1L;
			FOREACH v_reachable IN REACHABLE_VERTICES(:g, :v_start, 'ANY') {
    			v_reachable."COMPONENT" = :i;
    		}
		}
	}
	o_components = :i;
	o_res = SELECT :v."ID", :v."COMPONENT" FOREACH v IN Vertices(:g);
END;




/****************************************************/
-- 5 Connected Components histogramm as ad-hoc SQL Function
SELECT * FROM SQL FUNCTION () RETURNS TABLE ("COMPONENT" BIGINT, "COUNT" BIGINT) 
BEGIN
	DECLARE o_components BIGINT;
    CALL "GRAPHSCRIPT"."GS_CONNECTED_COMPONENTS"(o_components, o_res);
    RETURN SELECT "COMPONENT", COUNT(*) AS "COUNT" FROM :o_res GROUP BY "COMPONENT" ORDER BY "COUNT" DESC;		
END;



/****************************************************/
-- 6 Ad-hoc procedure Connectivity Check
DO (OUT o_isConnected BOOLEAN => ?) LANGUAGE GRAPH
BEGIN
	GRAPH g = Graph("GRAPHSCRIPT", "GRAPHWS");
	BIGINT number_of_nodes = COUNT(VERTICES(:g));
	IF (:number_of_nodes == 0L) { return; }
	SEQUENCE<Vertex> s_v = Sequence<Vertex>(Vertices(:g));
	o_isConnected = FALSE;
	IF (COUNT(REACHABLE_VERTICES(:g, :s_v[1L], 'ANY')) == :number_of_nodes) {
			o_isConnected = TRUE;
		}
END;
