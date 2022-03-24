/*************************************/
-- SAP HANA Graph examples - How to work with table parameters in GraphScript
-- 2022-03-24
-- This script was developed for SAP HANA Cloud 2021 Q4
-- See also https://help.sap.com/viewer/11afa2e60a5f4192a381df30f94863f9/latest/en-US/0a2875fccc6b4201921e23683d9c3af3.html
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
	"TARGET" BIGINT REFERENCES "GRAPHSCRIPT"."VERTICES"("ID") ON DELETE CASCADE NOT NULL,
	"WEIGHT" DOUBLE
);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (1);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (2);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (3);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (4);
INSERT INTO "GRAPHSCRIPT"."VERTICES" VALUES (5);
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
-- 2 How to use tables as input and output parameter in a GraphScript procedure
-- The procedure loops over a set of source values (i_source) and calulates the shortest path distance to all target values (i_target)

CREATE OR REPLACE PROCEDURE "GRAPHSCRIPT"."GS_MATRIX_SP_SEQUENTIAL" (
	IN i_sources TABLE ("ID" BIGINT), -- table containing the keys of the source vertices
	IN i_targets TABLE ("ID" BIGINT), -- table containing the keys of the target vertices
	IN i_dir NVARCHAR(10), -- edge direction: IN, OUT, ANY
	OUT o_matrix_sp TABLE ("$PATH_ID" BIGINT, "$SOURCE" BIGINT, "$TARGET" BIGINT, "$LENGTH" BIGINT, "$DISTANCE" DOUBLE) -- table containing source/target pairs with length and distance of shortest path
)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph("GRAPHSCRIPT","GRAPHWS");
	BIGINT rowID = 0L; -- row index for MATRIX_SP table
	MULTISET<BIGINT> m_sources = MULTISET<BIGINT>(:i_sources."ID"); -- store the INPUT DATA IN a multiset
	MULTISET<BIGINT> m_targets = MULTISET<BIGINT>(:i_targets."ID");
	
	FOREACH sourceID IN :m_sources{ -- loop over the sources
		VERTEX v_source = Vertex(:g, :sourceID);
		FOREACH targetID IN :m_targets{ -- loop over the targets
			VERTEX v_target = Vertex(:g, :targetID);
			WeightedPath<DOUBLE> p = Shortest_Path(:g, :v_source, :v_target, (Edge e) => DOUBLE{ return :e."WEIGHT"; }, :i_dir);
			rowID = :rowID + 1L;
			o_matrix_sp."$PATH_ID"[:rowID] = :rowID;
			o_matrix_sp."$SOURCE"[:rowID] = :sourceID;
			o_matrix_sp."$TARGET"[:rowID] = :targetID;
			IF ( NOT IS_EMPTY(:p) ) {
				o_matrix_sp."$LENGTH"[:rowID] = LENGTH(:p);
				o_matrix_sp."$DISTANCE"[:rowID] = WEIGHT(:p);
			}
		}
	}
END;

/*************************************/
-- 3 The procedure is called within an "anonymous block"
-- Two tables variables are created - t_sources, t_targets - and handed over to the GraphScript procedure
-- The result is a 4 row table, providing path information for source = 1/2 to target = 4/5

DO()
LANGUAGE SQLSCRIPT
BEGIN
	t_sources = SELECT "ID" FROM "GRAPHSCRIPT"."VERTICES" WHERE "ID" < 3;
	t_targets = SELECT "ID" FROM "GRAPHSCRIPT"."VERTICES" WHERE "ID" > 3;
	CALL "GRAPHSCRIPT"."GS_MATRIX_SP_SEQUENTIAL" (:t_sources, :t_targets, 'OUTGOING', o_matrix_sp);
	SELECT * FROM :o_matrix_sp;
END;

