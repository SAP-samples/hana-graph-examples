/*************************************/
-- SAP HANA Graph examples - Closeness Centrality
-- 2020-10-01
-- This script was developed for SAP HANA Cloud 2020 Q2
-- Wikipedia https://en.wikipedia.org/wiki/Closeness_centrality
/*************************************/

/*************************************/
-- 1 Create schema, tables, graph workspace, and load some sample data
DROP SCHEMA "GRAPHSCRIPT" CASCADE;
CREATE SCHEMA "GRAPHSCRIPT";
CREATE COLUMN TABLE "GRAPHSCRIPT"."VERTICES" (
    "ID" BIGINT PRIMARY KEY
);

CREATE COLUMN TABLE "GRAPHSCRIPT"."EDGES" (
    "ID" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY NOT NULL,
    "SOURCE" BIGINT NOT NULL REFERENCES "GRAPHSCRIPT"."VERTICES" ("ID") ON UPDATE CASCADE ON DELETE CASCADE,
    "TARGET" BIGINT NOT NULL REFERENCES "GRAPHSCRIPT"."VERTICES" ("ID") ON UPDATE CASCADE ON DELETE CASCADE
);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (0);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (1);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (2);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (3);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (4);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (5);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (6);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (7);

INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET") VALUES (0, 1);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET") VALUES (0, 2);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET") VALUES (0, 3);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET") VALUES (0, 4);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET") VALUES (4, 5);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET") VALUES (4, 6);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET") VALUES (6, 0);

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
-- Closeness Centrality procedure
-- The procedure takes direction parameter i_dir.
-- The procedure returns a table including raw closeness centrality, normalized closeness centrality, harmonic centrality, normalized harmonic centrality.

CREATE TYPE "GRAPHSCRIPT"."TT_RESULT_CC" AS TABLE (
	"ID" BIGINT, "CLOSENESS_CENTRALITY" DOUBLE, "NORMALIZED_CLOSENESS_CENTRALITY" DOUBLE,
	"HARMONIC_CENTRALITY" DOUBLE, "NORMALIZED_HARMONIC_CENTRALITY" DOUBLE);

CREATE OR REPLACE PROCEDURE "GRAPHSCRIPT"."GS_CLOSENESS_CENTRALITY"(
	IN i_dir NVARCHAR(10),
	OUT o_res "GRAPHSCRIPT"."TT_RESULT_CC"
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph("GRAPHSCRIPT","GRAPHWS");
	BIGINT v_sumVertices = 0L;
	BIGINT v_sumCost = 0L;
	DOUBLE v_sumReciprocCost = 0.0;
	BIGINT v_i = 1L;
	FOREACH v_start IN Vertices(:g) {
		v_sumVertices = 0L;
		v_sumCost = 0L;
		v_sumReciprocCost = 0.0;
		TRAVERSE BFS (:i_dir) :g FROM :v_start ON VISIT VERTEX (Vertex v_visited, BIGINT lvl) {
		    IF (:lvl > 0L){
		    	v_sumVertices = :v_sumVertices + 1L;
			    v_sumCost = :v_sumCost + :lvl;
			    v_sumReciprocCost = :v_sumReciprocCost + 1.0/DOUBLE(:lvl);
			}
		};
		IF (:v_sumCost > 0L AND :v_sumReciprocCost > 0.0 AND :v_sumVertices > 1L){
			o_res."ID"[:v_i] = :v_start."ID";
			o_res."CLOSENESS_CENTRALITY"[:v_i] = 1.0/DOUBLE(:v_sumCost);
			o_res."NORMALIZED_CLOSENESS_CENTRALITY"[:v_i] = DOUBLE(:v_sumVertices)/DOUBLE(:v_sumCost);
			o_res."HARMONIC_CENTRALITY"[:v_i] = :v_sumReciprocCost;
			o_res."NORMALIZED_HARMONIC_CENTRALITY"[:v_i] =  :v_sumReciprocCost/DOUBLE(:v_sumVertices);
			v_i = :v_i + 1L;
		}
	}
END;
CALL "GRAPHSCRIPT"."GS_CLOSENESS_CENTRALITY"('OUTGOING', ?);