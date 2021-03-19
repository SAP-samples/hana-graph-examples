/*************************************/
-- SAP HANA Graph examples - How to use the K_SHORTEST_PATH function
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
	"TARGET" BIGINT REFERENCES "GRAPHSCRIPT"."VERTICES"("ID") ON DELETE CASCADE NOT NULL,
	"WEIGHT" DOUBLE
);
INSERT INTO "GRAPHSCRIPT"."VERTICES"("ID", "NAME") VALUES (1, 'one');
INSERT INTO "GRAPHSCRIPT"."VERTICES"("ID", "NAME") VALUES (2, 'two');
INSERT INTO "GRAPHSCRIPT"."VERTICES"("ID", "NAME") VALUES (3, 'three');
INSERT INTO "GRAPHSCRIPT"."VERTICES"("ID", "NAME") VALUES (4, 'four');
INSERT INTO "GRAPHSCRIPT"."VERTICES"("ID", "NAME") VALUES (5, 'five');
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (1, 2, 0.5);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (1, 3, 0.1);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (2, 3, 1.5);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (2, 4, 0.1);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (3, 4, 0.2);
INSERT INTO "GRAPHSCRIPT"."EDGES"("SOURCE", "TARGET", "WEIGHT") VALUES (5, 4, 0.8);

CREATE GRAPH WORKSPACE "GRAPHSCRIPT"."GRAPHWS"
	EDGE TABLE "GRAPHSCRIPT"."EDGES"
		SOURCE COLUMN "SOURCE"
		TARGET COLUMN "TARGET"
		KEY COLUMN "ID"
	VERTEX TABLE "GRAPHSCRIPT"."VERTICES"
		KEY COLUMN "ID";

/*************************************/
-- How to use the K_SHORTEST_PATH function in a GRAPH"Script" procedure
-- The procedure identifies the top k shortest paths, given three input parameters: i_startVertex, i_endVertex, and i_k
-- The procedure returns a table containing up to k paths: each path gets an individual path_id, and contains an ordered set of edges

CREATE TYPE "GRAPHSCRIPT"."TT_PATHS_TKSP" AS TABLE (
	"PATH_ID" INT, "PATH_LENGTH" BIGINT, "PATH_WEIGHT" DOUBLE,
	"EDGE_ID" BIGINT, "EDGE_ORDER" INT);

CREATE OR REPLACE PROCEDURE "GRAPHSCRIPT"."GS_TKSP"(
	IN i_startVertex BIGINT, 	-- the key of the start vertex
	IN i_endVertex BIGINT, 		-- the key of the end vertex
	IN i_k INT, 				-- the number of paths to be returned
	OUT o_paths "GRAPHSCRIPT"."TT_PATHS_TKSP"
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	-- Create an instance of the graph, refering to the graph workspace object
	GRAPH g = Graph("GRAPHSCRIPT", "GRAPHWS");
	-- Create an instance of the start/end vertex
	VERTEX v_start = Vertex(:g, :i_startVertex);
	VERTEX v_end = Vertex(:g, :i_endVertex);
	-- Running top k shortest paths using the WEIGHT column as cost
	SEQUENCE<WeightedPath<DOUBLE>> s_paths = K_Shortest_Paths(:g, :v_start, :v_end, :i_k, (Edge e) => DOUBLE{ return :e."WEIGHT"; });
	-- Project result paths into a table
	BIGINT currentResultRow = 1L;
	FOREACH result_path IN (:s_paths) WITH ORDINALITY AS path_id {
		FOREACH path_edge in EDGES(:result_path) WITH ORDINALITY AS edge_order {
			o_paths."PATH_ID"[:currentResultRow] = INTEGER(:path_id);
			o_paths."PATH_LENGTH"[:currentResultRow] = Length(:result_path);
			o_paths."PATH_WEIGHT"[:currentResultRow] = Weight(:result_path);
			o_paths."EDGE_ID"[:currentResultRow] = :path_edge."ID";
			o_paths."EDGE_ORDER"[:currentResultRow] = INTEGER(:edge_order);
			currentResultRow = :currentResultRow + 1L;
		}
	}
END;

-- Finding the top 2 shortest paths between vertex "1" and "4"
CALL "GRAPHSCRIPT"."GS_TKSP"(i_startVertex => 1, i_endVertex => 4, i_k => 2, o_paths => ?);

-- As an alternative you can also run the Top k Shortest Paths as a so called anonymous block
DO (
	IN i_startVertex BIGINT => 1,
	IN i_endVertex BIGINT => 4,
	IN i_k INT => 2,
	OUT o_paths TABLE ("PATH_ID" INT, "PATH_LENGTH" BIGINT, "PATH_WEIGHT" DOUBLE, "EDGE_ID" BIGINT, "EDGE_ORDER" INT) => ?
	)
LANGUAGE GRAPH
BEGIN
	GRAPH g = Graph("GRAPHSCRIPT", "GRAPHWS");
	VERTEX v_start = Vertex(:g, :i_startVertex);
	VERTEX v_end = Vertex(:g, :i_endVertex);
	SEQUENCE<WeightedPath<DOUBLE>> s_paths = K_Shortest_Paths(:g, :v_start, :v_end, :i_k, (Edge e) => DOUBLE{ return :e."WEIGHT"; });
	BIGINT currentResultRow = 1L;
	FOREACH result_path IN (:s_paths) WITH ORDINALITY AS path_id {
		FOREACH path_edge in EDGES(:result_path) WITH ORDINALITY AS edge_order {
			o_paths."PATH_ID"[:currentResultRow] = INTEGER(:path_id);
			o_paths."PATH_LENGTH"[:currentResultRow] = Length(:result_path);
			o_paths."PATH_WEIGHT"[:currentResultRow] = Weight(:result_path);
			o_paths."EDGE_ID"[:currentResultRow] = :path_edge."ID";
			o_paths."EDGE_ORDER"[:currentResultRow] = INTEGER(:edge_order);
			currentResultRow = :currentResultRow + 1L;
		}
	}
END;