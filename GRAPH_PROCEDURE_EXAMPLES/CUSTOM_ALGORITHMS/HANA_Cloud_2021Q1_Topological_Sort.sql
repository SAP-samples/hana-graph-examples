/*************************************/
-- SAP HANA Graph examples - Topological Sort
-- 2021-04-01
-- This script was developed for SAP HANA Cloud 2020 Q4
-- Wikipedia https://en.wikipedia.org/wiki/Topological_sorting
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
INSERT INTO "GRAPHSCRIPT"."VERTICES" ("ID") VALUES (20);
INSERT INTO "GRAPHSCRIPT"."VERTICES" ("ID") VALUES (30);
INSERT INTO "GRAPHSCRIPT"."VERTICES" ("ID") VALUES (40);
INSERT INTO "GRAPHSCRIPT"."VERTICES" ("ID") VALUES (300);
INSERT INTO "GRAPHSCRIPT"."VERTICES" ("ID") VALUES (400);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET", "WEIGHT") VALUES (1, 2, 0.0);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET", "WEIGHT") VALUES (1, 3, 0.0);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET", "WEIGHT") VALUES (3, 4, 0.0);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET", "WEIGHT") VALUES (4, 5, 0.0);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET", "WEIGHT") VALUES (3, 20, 0.0);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET", "WEIGHT") VALUES (20, 30, 0.0);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET", "WEIGHT") VALUES (30, 40, 0.0);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET", "WEIGHT") VALUES (3, 300, 0.0);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET", "WEIGHT") VALUES (300, 400, 0.0);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET", "WEIGHT") VALUES (300, 2, 0.0);
INSERT INTO "GRAPHSCRIPT"."EDGES" ("SOURCE", "TARGET", "WEIGHT") VALUES (4, 20, 0.0);

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
-- procedure Topologial Sort
CREATE TYPE "GRAPHSCRIPT"."TT_VERTICES" AS TABLE ("ID" BIGINT, "EXIT_ORDER" BIGINT, "DEPTH" BIGINT);

CREATE OR REPLACE PROCEDURE "GRAPHSCRIPT"."GS_TOPOLOGICAL_SORT" (
    OUT o_vertices "GRAPHSCRIPT"."TT_VERTICES",
    OUT o_isSortable INT
)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
    GRAPH g = Graph("GRAPHSCRIPT", "GRAPHWS");
    ALTER g ADD TEMPORARY VERTEX ATTRIBUTE (BIGINT "IN_DEGREE");
    ALTER g ADD TEMPORARY VERTEX ATTRIBUTE (BIGINT "VISIT_ORDER");
    ALTER g ADD TEMPORARY VERTEX ATTRIBUTE (BIGINT "EXIT_ORDER");
    ALTER g ADD TEMPORARY VERTEX ATTRIBUTE (BIGINT "DEPTH");
    o_isSortable = 1;
    BIGINT c_visit = 0L;
    BIGINT c_exit = 0L;
    FOREACH v IN VERTICES(:G) {
        v."IN_DEGREE" = IN_DEGREE(:v);
    }
    MULTISET<VERTEX> m_nodes = v IN VERTICES(:G) WHERE :v."IN_DEGREE" == 0L;
    IF (COUNT(:m_nodes) == 0L) { 
        o_isSortable = 0;
        RETURN; 
    }
    FOREACH v_start in :m_nodes {
        TRAVERSE DFS('OUTGOING') :g FROM :v_start
            ON VISIT VERTEX (VERTEX v_visited, BIGINT lvl) {
                IF (:v_visited."VISIT_ORDER" IS NULL) {
                    c_visit = :c_visit + 1L;
                    v_visited."VISIT_ORDER" = :c_visit;
                    v_visited."DEPTH" = :lvl;
                }
                ELSE { END TRAVERSE; }
            }
            ON EXIT VERTEX (VERTEX v_exited) {
                IF (:v_exited."EXIT_ORDER" IS NULL) {
                    c_exit = :c_exit + 1L;
                    v_exited."EXIT_ORDER" = :c_exit;
                }
            }
            ON VISIT EDGE (EDGE e_visited) {
                VERTEX S = SOURCE(:e_visited);
                VERTEX T = TARGET(:e_visited);
                IF (:T."VISIT_ORDER" IS NOT NULL AND :T."EXIT_ORDER" IS NULL) {
                    o_isSortable = 0;
                    END TRAVERSE ALL;
                }
            };
    }
    IF ( :o_isSortable == 1 ) {
        SEQUENCE<VERTEX> s_ordered_vertices = SEQUENCE<VERTEX>(Vertices(:g)) ORDER BY "EXIT_ORDER" DESC;
        o_vertices = SELECT :v."ID", :v."EXIT_ORDER", :v."DEPTH" FOREACH v IN :s_ordered_vertices;
    }
END;

CALL "GRAPHSCRIPT"."GS_TOPOLOGICAL_SORT"(?, ?);

-- Optional: wrap the procedure in a function
CREATE OR REPLACE FUNCTION "GRAPHSCRIPT"."F_TOPOLOGICAL_SORT" ()
    RETURNS "GRAPHSCRIPT"."TT_VERTICES"
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
	DECLARE o_isSortable INT;
    CALL "GRAPHSCRIPT"."GS_TOPOLOGICAL_SORT"(o_res, o_isSortable);
    RETURN :o_res;
END;

SELECT * FROM "GRAPHSCRIPT"."F_TOPOLOGICAL_SORT"() ORDER BY "EXIT_ORDER" DESC;
