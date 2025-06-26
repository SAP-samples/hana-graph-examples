/*************************************/
-- SAP HANA Graph examples - Maximum Flow
-- 2025-06-26
-- This script was developed for SAP HANA Cloud 2025 Q2
-- https://help.sap.com/docs/hana-cloud-database/sap-hana-cloud-sap-hana-database-property-graph-engine-reference/built-in-graph-algorithms#max-flow
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
    "TARGET" BIGINT NOT NULL REFERENCES "GRAPHSCRIPT"."VERTICES" ("ID") ON UPDATE CASCADE ON DELETE CASCADE,
    "CAPACITY" DOUBLE
);
INSERT INTO GRAPHSCRIPT.VERTICES ("ID") VALUES (1);
INSERT INTO GRAPHSCRIPT.VERTICES ("ID") VALUES (2);
INSERT INTO GRAPHSCRIPT.VERTICES ("ID") VALUES (3);
INSERT INTO GRAPHSCRIPT.VERTICES ("ID") VALUES (4);

INSERT INTO GRAPHSCRIPT.EDGES ("SOURCE", "TARGET", "CAPACITY") VALUES (1, 2, 2);
INSERT INTO GRAPHSCRIPT.EDGES ("SOURCE", "TARGET", "CAPACITY") VALUES (1, 3, 1);
INSERT INTO GRAPHSCRIPT.EDGES ("SOURCE", "TARGET", "CAPACITY") VALUES (2, 3, 1.5);
INSERT INTO GRAPHSCRIPT.EDGES ("SOURCE", "TARGET", "CAPACITY") VALUES (2, 4, 0);
INSERT INTO GRAPHSCRIPT.EDGES ("SOURCE", "TARGET", "CAPACITY") VALUES (3, 4, 2.5);

CREATE GRAPH WORKSPACE "GRAPHSCRIPT"."GRAPHWS"
	EDGE TABLE "GRAPHSCRIPT"."EDGES"
		SOURCE COLUMN "SOURCE"
		TARGET COLUMN "TARGET"
		KEY COLUMN "ID"
	VERTEX TABLE "GRAPHSCRIPT"."VERTICES"
		KEY COLUMN "ID";

/****************************************************/
CREATE OR REPLACE PROCEDURE "GRAPHSCRIPT"."GS_MAXIMUM_FLOW"(
	IN i_source BIGINT,
	IN i_sink BIGINT,
	OUT o_flow TABLE("EDGE" BIGINT, "FLOW" DOUBLE, "MAX_FLOW" DOUBLE),
	OUT o_paths TABLE("PATH" BIGINT, "PATH_LENGTH" BIGINT, "PATH_WEIGHT" DOUBLE, "EDGE" BIGINT, "FLOW" DOUBLE, "MAX_FLOW" DOUBLE)
)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph("GRAPHSCRIPT","GRAPHWS");
	VERTEX v_source(:g, :i_source);
	VERTEX v_sink(:g, :i_sink);
	DOUBLE flow_max = 0.0;
	BIGINT p_counter = 1L;
	BIGINT e_counter = 1L;
	SEQUENCE<WEIGHTEDPATH<DOUBLE>> flow_paths(:g);
	CLOSURE capacityFct(:g, (EDGE e) => DOUBLE {
    	RETURN :e."CAPACITY";
	});
	MAP<EDGE, DOUBLE> flow_map = MAX_FLOW(:g, :v_source, :v_sink, :capacityFct, :flow_max, :flow_paths);
	o_flow = SELECT :e."ID", :flow, :flow_max FOREACH (e, flow) IN :flow_map;
	FOREACH p IN :flow_paths {
    	BIGINT l = LENGTH(:p);
    	DOUBLE w = WEIGHT(:p);
    	FOREACH e in EDGES(:p) {
        	o_paths."PATH"[:e_counter] = :p_counter;
			o_paths."PATH_LENGTH"[:e_counter] = :l;
			o_paths."PATH_WEIGHT"[:e_counter] = :w;
			o_paths."EDGE"[:e_counter] = :e."ID";
			o_paths."FLOW"[:e_counter] = :flow_map[EDGE(:g, :e)];
			o_paths."MAX_FLOW"[:e_counter] = :flow_max;
			e_counter = :e_counter + 1L;
    	}
    	p_counter = :p_counter + 1L;
	}
END;

CALL "GRAPHSCRIPT"."GS_MAXIMUM_FLOW"(1, 4, ?, ?);