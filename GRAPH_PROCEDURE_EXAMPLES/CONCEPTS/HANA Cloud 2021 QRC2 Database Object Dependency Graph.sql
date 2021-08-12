-- 2021 Q3 Database object lineage using SAP HANA Graph
-- This script runs on SAP HANA Cloud QRC2

-- SAP HANA database objects like tables, views, procedures etc. form a dependency graph:
-- a view depends on tables, procedures depend on views and/or tables etc.
-- The dependencies of the core database objects are exposed via SYS.OBJECT_DEPENDENCIES.
-- We use SYS.OBJECT_DEPENDENCIES as edge data for a graph workspace.
-- On the graph workspace, we can use graph functions and algorithms.
-- For getting object dependencies plus hop distance, we use the built-in algorithm "shortest paths one to all".

DROP SCHEMA "DEP_ANALYSIS_HANA" CASCADE;
CREATE SCHEMA "DEP_ANALYSIS_HANA";
-- The edges of the object dependency graph are in the OBJECT_DEPENDENCIES system view
CREATE OR REPLACE VIEW "DEP_ANALYSIS_HANA"."V_EDGES" AS (
	SELECT N2."OBJECT_OID"||'-'||N1."OBJECT_OID"||'-'||"DEPENDENCY_TYPE" AS "KEY", 
	N2."OBJECT_OID" AS "SOURCE", "DEPENDENT_SCHEMA_NAME", "DEPENDENT_OBJECT_NAME", "DEPENDENT_OBJECT_TYPE", 
	N1."OBJECT_OID" AS "TARGET", "BASE_SCHEMA_NAME", "BASE_OBJECT_NAME", "BASE_OBJECT_TYPE", 
	"DEPENDENCY_TYPE", 'DEPENDS_ON' AS "DEPENDENCY_LABEL"
	FROM "SYS"."OBJECT_DEPENDENCIES" AS E
	INNER JOIN "SYS"."OBJECTS" AS N1 ON E."BASE_SCHEMA_NAME" = N1."SCHEMA_NAME" AND E."BASE_OBJECT_NAME" = N1."OBJECT_NAME" AND E."BASE_OBJECT_TYPE" = N1."OBJECT_TYPE"
	INNER JOIN "SYS"."OBJECTS" AS N2 ON E."DEPENDENT_SCHEMA_NAME" = N2."SCHEMA_NAME" AND E."DEPENDENT_OBJECT_NAME" = N2."OBJECT_NAME" AND E."DEPENDENT_OBJECT_TYPE" = N2."OBJECT_TYPE"
	WHERE "DEPENDENCY_TYPE" IN (1, 5) AND N1."OBJECT_TYPE" != 'TRIGGER' AND N2."OBJECT_TYPE" != 'TRIGGER'
		AND N1."SCHEMA_NAME" NOT IN ('PUBLIC', '_SYS_STATISTICS', '_SYS_AFL', '_SYS_DI', '_SYS_BI', '_SYS_SQL_ANALYZER', '_SYS_TASK')
		AND N2."SCHEMA_NAME" NOT IN ('PUBLIC', '_SYS_STATISTICS', '_SYS_AFL', 'SYS','_SYS_DI', '_SYS_BI', '_SYS_SQL_ANALYZER', '_SYS_TASK')
);
-- Vertices
CREATE OR REPLACE VIEW "DEP_ANALYSIS_HANA"."V_VERTICES" AS (
	SELECT * FROM "SYS"."OBJECTS" WHERE "OBJECT_OID" IN (
		SELECT "SOURCE" FROM "DEP_ANALYSIS_HANA"."V_EDGES") OR "OBJECT_OID" IN (SELECT "TARGET" FROM "DEP_ANALYSIS_HANA"."V_EDGES")
);
-- Optionally: persist the data
CREATE COLUMN TABLE "DEP_ANALYSIS_HANA"."T_VERTICES" AS (SELECT * FROM "DEP_ANALYSIS_HANA"."V_VERTICES");
ALTER TABLE "DEP_ANALYSIS_HANA"."T_VERTICES" ADD PRIMARY KEY ("OBJECT_OID");
CREATE COLUMN TABLE "DEP_ANALYSIS_HANA"."T_EDGES" AS (SELECT * FROM "DEP_ANALYSIS_HANA"."V_EDGES");
ALTER TABLE "DEP_ANALYSIS_HANA"."T_EDGES" ADD PRIMARY KEY ("KEY");
ALTER TABLE "DEP_ANALYSIS_HANA"."T_EDGES" ALTER ("SOURCE" BIGINT NOT NULL);
ALTER TABLE "DEP_ANALYSIS_HANA"."T_EDGES" ALTER ("TARGET" BIGINT NOT NULL);

-- Graph Workspace
CREATE GRAPH WORKSPACE "DEP_ANALYSIS_HANA"."T_OBJECT_GRAPH"
	EDGE TABLE "DEP_ANALYSIS_HANA"."T_EDGES"
		SOURCE COLUMN "SOURCE"
		TARGET COLUMN "TARGET"
		KEY COLUMN "KEY"
	VERTEX TABLE "DEP_ANALYSIS_HANA"."T_VERTICES" 
		KEY COLUMN "OBJECT_OID";


/****************************************/
-- We use shortest paths one to all (SPOA) to identify all dependent objects in one traversal direction (INCOMING or OUTGOING), and to get the spanning tree
/****************************************/
-- get the OBJECT_OID of one of your vertices 
SELECT * FROM "DEP_ANALYSIS_HANA"."V_VERTICES";
-- the logic runs as "anonymous block" (SAP HANA Coud only)
DO(
	IN i_start BIGINT => [put an OBJECT_OID here],			-- the key of the start vertex
	IN i_dir VARCHAR(10) => 'INCOMING', 	-- the the direction of the edge traversal: OUTGOING (default), INCOMING
	OUT o_vertices TABLE ("OBJECT_OID" BIGINT, "SCHEMA_NAME" NVARCHAR(5000), "OBJECT_NAME" NVARCHAR(5000), "OBJECT_TYPE" VARCHAR(5000), "DISTANCE" BIGINT) => ?,
	OUT o_edges TABLE ("KEY" VARCHAR(100), "SOURCE" BIGINT, "TARGET" BIGINT, "DEPENDENCY_TYPE" INTEGER, "DEPENDENCY_LABEL" VARCHAR(10)) => ?
	)
LANGUAGE GRAPH
BEGIN
	GRAPH g = Graph("DEP_ANALYSIS_HANA","T_OBJECT_GRAPH");
	VERTEX v_start = Vertex(:g, :i_start);
	GRAPH g_spoa = SHORTEST_PATHS_ONE_TO_ALL(:g, :v_start, "DISTANCE", :i_dir);
	o_vertices = SELECT :v."OBJECT_OID", :v."SCHEMA_NAME", :v."OBJECT_NAME", :v."OBJECT_TYPE", :v."DISTANCE" FOREACH v IN Vertices(:g_spoa);
	o_edges = SELECT :e."KEY", :e."SOURCE", :e."TARGET", :e."DEPENDENCY_TYPE", :e."DEPENDENCY_LABEL" FOREACH e IN Edges(:g_spoa);
END;



-- the same logic runs as procedure (SAP HANA Cloud and on-premise)
-- create table types
CREATE TYPE "DEP_ANALYSIS_HANA"."TT_EDGES" AS TABLE ("KEY" VARCHAR(100), "SOURCE" BIGINT, "TARGET" BIGINT, "DEPENDENCY_TYPE" INTEGER, "DEPENDENCY_LABEL" VARCHAR(10));
CREATE TYPE "DEP_ANALYSIS_HANA"."TT_VERTICES" AS TABLE ("OBJECT_OID" BIGINT, "SCHEMA_NAME" NVARCHAR(5000), "OBJECT_NAME" NVARCHAR(5000), "OBJECT_TYPE"  VARCHAR(5000), "DISTANCE" BIGINT);

CREATE OR REPLACE PROCEDURE "DEP_ANALYSIS_HANA"."GS_SPOA" (
	IN i_start BIGINT,		-- the key of the start vertex
	IN i_dir VARCHAR(10), 	-- the the direction of the edge traversal: OUTGOING (default), INCOMING
	OUT o_vertices "DEP_ANALYSIS_HANA"."TT_VERTICES",
	OUT o_edges "DEP_ANALYSIS_HANA"."TT_EDGES"
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph("DEP_ANALYSIS_HANA","T_OBJECT_GRAPH");
	VERTEX v_start = Vertex(:g, :i_start);
	GRAPH g_spoa = SHORTEST_PATHS_ONE_TO_ALL(:g, :v_start, "DISTANCE", :i_dir);
	o_vertices = SELECT :v."OBJECT_OID", :v."SCHEMA_NAME", :v."OBJECT_NAME", :v."OBJECT_TYPE", :v."DISTANCE" FOREACH v IN Vertices(:g_spoa);
	o_edges = SELECT :e."KEY", :e."SOURCE", :e."TARGET", :e."DEPENDENCY_TYPE", :e."DEPENDENCY_LABEL" FOREACH e IN Edges(:g_spoa);
END;

-- get the OBJECT_OID of one of your vertices 
SELECT * FROM "DEP_ANALYSIS_HANA"."V_VERTICES";

-- call the procedure
CALL "DEP_ANALYSIS_HANA"."GS_SPOA"([put an OBJECT_OID here], 'OUTGOING', ?, ?);
CALL "DEP_ANALYSIS_HANA"."GS_SPOA"([put an OBJECT_OID here], 'INCOMING', ?, ?);