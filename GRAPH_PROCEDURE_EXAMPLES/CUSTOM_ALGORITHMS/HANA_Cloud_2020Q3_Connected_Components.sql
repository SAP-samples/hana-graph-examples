/*************************************/
-- SAP HANA Graph examples - (weakly) connected components and connectivity check
-- 2020-10-01
-- This script was developed for SAP HANA Cloud 2020 Q3
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
-- Procedure Connected Components
CREATE TYPE "GRAPHSCRIPT"."TT_OUT_VERTICES" AS TABLE ("ID" BIGINT, "COMPONENT" BIGINT);

CREATE OR REPLACE PROCEDURE "GRAPHSCRIPT"."GS_CONNECTED_COMPONENTS" (
	OUT o_comps BIGINT,
	OUT o_res "GRAPHSCRIPT"."TT_OUT_VERTICES"
)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph("GRAPHSCRIPT", "GRAPHWS");
	-- add a temporary attribute to store the component number
	ALTER g ADD TEMPORARY VERTEX ATTRIBUTE (BIGINT "COMPONENT" = 0L);
	BIGINT i = 0L;
	FOREACH v_s IN Vertices(:g){
		IF(:v_s."COMPONENT" == 0L) {
			i = :i + 1L;
			-- all reachable neighbors are assigned the same component number > 0
			FOREACH v_visited IN NEIGHBORS(:g, :v_s, -1000000, 1000000, 'ANY') {
    			v_visited."COMPONENT" = :i;
    		}
		}
	}
	o_comps = :i;
	o_res = SELECT :v."ID", :v."COMPONENT" FOREACH v IN Vertices(:g);
END;
CALL "GRAPHSCRIPT"."GS_CONNECTED_COMPONENTS"(?, ?);

-- Optional: wrap procedure in SQLScript function for easy post-processing
CREATE OR REPLACE FUNCTION "GRAPHSCRIPT"."F_CONNECTED_COMPONENTS"()
    RETURNS "GRAPHSCRIPT"."TT_OUT_VERTICES"
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
	DECLARE o_comps BIGINT;
    CALL "GRAPHSCRIPT"."GS_CONNECTED_COMPONENTS"(o_comps, o_res);
    RETURN :O_RES;
END;
SELECT "COMPONENT", COUNT(*) AS C FROM "GRAPHSCRIPT"."F_CONNECTED_COMPONENTS"() GROUP BY "COMPONENT" ORDER BY C DESC;


/****************************************************/
-- Ad-hoc procedure Connectivity Check
DO (OUT o_connected BOOLEAN => ?) LANGUAGE GRAPH
BEGIN
	GRAPH g = Graph("GRAPHSCRIPT", "GRAPHWS");
	BIGINT number_of_nodes = COUNT(VERTICES(:g));
	IF (:number_of_nodes == 0L) { return; }
	SEQUENCE<Vertex> s_v = Sequence<Vertex>(Vertices(:g));
	o_connected = FALSE;
	IF (COUNT(NEIGHBORS(:g, :s_v[1L], -1000000, 1000000, 'ANY')) == :number_of_nodes) {
			o_connected = TRUE;
		}
END;
