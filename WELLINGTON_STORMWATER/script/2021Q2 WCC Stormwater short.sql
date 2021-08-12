-- 20210812 this code runs on SAP HANA Cloud QRC2

-- This script complements and extends the Jupyter Notebook showcasing the hana-ml python client:
-- see: https://github.com/SAP-samples/hana-graph-examples/tree/main/NOTEBOOKS/WELLINGTON_STORMWATER

-- We will demonstrate how to use some advanced spatial and graph features via SQL to analyze a water network.
-- Stormwater network data was downloaded from the Wellington Water Open Data Portal
-- See: https://data-wellingtonwater.opendata.arcgis.com/datasets/d70eead642bf49e393a3b199f0c63e8c_15/explore?location=-41.309742%2C174.802830%2C13.35

-- In essence, we will calculate Voronoi cells to estimate the catchment area and thus the amount of water pushing into each vertex individually.
-- Then, we use a Graph procedure to propagate and accumulate the load to the "downstream" parts of the network.
-- Last, we will compare the load to the pipe's cross-section to identify the network sections which might get "under pressure" first.

-- 1 Load and inspect the data and create the Graph Workspace
-- 2 Identify weakly connected components 
-- 3 Calcluate the catchment area for each stormwater node to estimate the water load
-- 4 Estimate the potential water load for each network vertex/edge



/******************************************/
-- Install the spatial reference system in which the data is defined
CREATE PREDEFINED SPATIAL REFERENCE SYSTEM IDENTIFIED BY 2193;



/******************************************/
-- 1 Load and inspect the data and create the Graph Workspace
-- Use a HANA Database Explorer, right-click on your HANA Cloud system and choose import catalogue objects to import
-- 2021Q3_HANA_CLOUD_EXPORT_STORMWATER_NETWORK.tar.gz

-- The file contains two tables:  
SELECT * FROM "STORMWATER"."STORMWATER_VERTICES";
SELECT * FROM "STORMWATER"."STORMWATER_EDGES";

-- The stormwater network is a directed (mostly acyclic) graph
CREATE GRAPH WORKSPACE "STORMWATER"."STORMWATER"
	EDGE TABLE "STORMWATER"."STORMWATER_EDGES"
		SOURCE COLUMN "SOURCE"
		TARGET COLUMN "TARGET"
		KEY COLUMN "ID"
	VERTEX TABLE "STORMWATER"."STORMWATER_VERTICES"
		KEY COLUMN "ID";

	

/**********************************************/
-- 2 Identify weakly connected components
-- The stormwater network is not connected, i.e. there are multiple "components".
-- Let's identify these components using a GRAPH procedure.
-- Create a table type for the result of the procedure:
CREATE TYPE "STORMWATER"."TT_OUT_VERTICES" AS TABLE ("ID" NVARCHAR(20), "$COMPONENT" BIGINT);

-- The procedure returns the number of components and assigns each vertex a component number.
CREATE OR REPLACE PROCEDURE "STORMWATER"."GS_CONNECTED_COMPONENTS" (
	OUT o_components BIGINT,
	OUT o_res "STORMWATER"."TT_OUT_VERTICES"
)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph("STORMWATER", "STORMWATER");
	-- add a temporary attribute to store the component number
	ALTER g ADD TEMPORARY VERTEX ATTRIBUTE (BIGINT "$COMPONENT" = 0L);
	BIGINT i = 0L;
	-- For each vertes we'll check if it is alerady assigned to a component.
	-- If not, we'll assign the vertex and all of it's neighbors/reachable vertices.
	FOREACH v_start IN Vertices(:g){
		IF(:v_start."$COMPONENT" == 0L) {
			i = :i + 1L;
			-- all reachable neighbors are assigned the same component number > 0
			FOREACH v_reachable IN REACHABLE_VERTICES(:g, :v_start, 'ANY') {
    			v_reachable."$COMPONENT" = :i;
    		}
		}
	}
	o_components = :i;
	o_res = SELECT :v."ID", :v."$COMPONENT" FOREACH v IN Vertices(:g);
END;
-- Call the procedure:
CALL "STORMWATER"."GS_CONNECTED_COMPONENTS"(?, ?);

-- Let' store the result of the procedure. We will add the component numerb to both vertices and edges.
-- Add a new column to both tables:
ALTER TABLE "STORMWATER"."STORMWATER_VERTICES" ADD ("COMPONENT" BIGINT);
ALTER TABLE "STORMWATER"."STORMWATER_EDGES" ADD ("COMPONENT" BIGINT);

-- Call the procedure and update the tables with the procedure's result. We'll use a so called anonymous block for this:
DO ()
LANGUAGE SQLSCRIPT
BEGIN
	DECLARE o_components BIGINT;
    CALL "STORMWATER"."GS_CONNECTED_COMPONENTS"(o_components, o_res);
    MERGE INTO "STORMWATER"."STORMWATER_VERTICES" AS SV
		USING :o_res AS WCC
		ON SV."ID" = WCC."ID"
		WHEN MATCHED THEN UPDATE SET SV."COMPONENT" = WCC."$COMPONENT";
	MERGE INTO "STORMWATER"."STORMWATER_EDGES" AS SE
		USING :o_res AS WCC
		ON SE."SOURCE" = WCC."ID"
		WHEN MATCHED THEN UPDATE SET SE."COMPONENT" = WCC."$COMPONENT";
END;

-- Inspect the data: which are the biggest weakly connected components?
SELECT "COMPONENT", COUNT(*) AS C FROM "STORMWATER"."STORMWATER_VERTICES" GROUP BY "COMPONENT" ORDER BY C DESC;



/**********************************************/
-- 3 Calcluate the catchment area for each stormwater node to estimate the water load
-- 3.1 For each component, we calculate its alphashape which serves as a bounding polygon
-- 3.2 for each node, we calculate the voronoi cell (=catchment area for each node) and intersect with the components' alphashape

/**********************************************/
-- Alphashapes (bounding polygons for each network component)
-- Let's create a table to store the alpha shapes
CREATE COLUMN TABLE "STORMWATER"."STORMWATER_ALPHASHAPES"(
	"COMPONENT" BIGINT,
	"ALPHA_SHAPE" ST_GEOMETRY(2193),
	"CONCAVE_HULL" ST_GEOMETRY(2193),
	"NUM_POINTS" BIGINT
);

-- We'll calculate the alpha shapes for the components with more than 500 vertices
SELECT "COMPONENT", ST_AlphaShapeAggr("SHAPE", 500) AS "ALPHA_SHAPE", ST_ConcaveHullAggr("SHAPE") AS "CONCAVE_HULL", COUNT(*) AS "NUM_POINTS"
	FROM "STORMWATER"."STORMWATER_VERTICES" 
	GROUP BY "COMPONENT"
	HAVING COUNT(*) > 500
	INTO "STORMWATER"."STORMWATER_ALPHASHAPES";

-- Inspect the data
SELECT * FROM "STORMWATER"."STORMWATER_ALPHASHAPES";

/**********************************************/
-- Voronoi cells (catchment area for each individual vertex)
SELECT "ID", "SHAPE", ST_VoronoiCell("SHAPE", 10.0) OVER () AS "VORONOI_CELL" 
	FROM "STORMWATER"."STORMWATER_VERTICES"
	WHERE "COMPONENT" = 2;

-- Now we intersect the voronoi cells with the component's alpha shape
-- We'll wrap this logic in a view:
CREATE OR REPLACE VIEW "STORMWATER"."V_STORMWATER_VERTICES_COVERED_AREA" AS (
	-- Calculate the cutted cells area
	SELECT "ID", "CUTTED_VORONOI_CELL" AS "VORONOI_CELL", "CUTTED_VORONOI_CELL".ST_AREA('meter') AS "AREA_M2" FROM (
		-- Calculate the intersection
		SELECT V."ID", "VORONOI_CELL".ST_Intersection("ALPHA_SHAPE") AS "CUTTED_VORONOI_CELL" FROM
			-- The voronoi cells:
			(SELECT "ID", "COMPONENT", ST_VoronoiCell("SHAPE", 10.0) OVER () AS "VORONOI_CELL" 
				FROM "STORMWATER"."STORMWATER_VERTICES" 
				WHERE "COMPONENT" IN (SELECT "COMPONENT" FROM "STORMWATER"."STORMWATER_ALPHASHAPES")) AS V
			LEFT JOIN 
			-- The alpha shapes:
			(SELECT "COMPONENT", "ALPHA_SHAPE" 
				FROM "STORMWATER"."STORMWATER_ALPHASHAPES") AS A
			ON V."COMPONENT" = A."COMPONENT" AND V."VORONOI_CELL".ST_Intersects(A."ALPHA_SHAPE") = 1 
	)
);

-- Persist the voronoi polygons in a separate table
CREATE COLUMN TABLE "STORMWATER"."STORMWATER_VERTICES_COVERED_AREA" (
	"ID" NVARCHAR(20), "VORONOI_CELL" ST_GEOMETRY(2193), "AREA_M2" DOUBLE
);
SELECT * FROM "STORMWATER"."V_STORMWATER_VERTICES_COVERED_AREA" INTO "STORMWATER"."STORMWATER_VERTICES_COVERED_AREA";

-- For the calculation of the load later, we just need the catchment area in the vertices table
ALTER TABLE "STORMWATER"."STORMWATER_VERTICES" ADD ("AREA_M2" DOUBLE);
MERGE INTO "STORMWATER"."STORMWATER_VERTICES" AS SV
	USING "STORMWATER"."V_STORMWATER_VERTICES_COVERED_AREA" AS CA
	ON SV."ID" = CA."ID"
	WHEN MATCHED THEN UPDATE SET SV."AREA_M2" = CA."AREA_M2";



/**********************************************/
-- 4 Estimate the poential water load for each network vertex/edge
-- The water load for each vertex/edge depends on the catchment area of all upstream nodes.
-- We'll use a Graph procedure for this.

-- Creat table types first.
CREATE TYPE "STORMWATER"."TT_LOAD_EDGES" AS TABLE (
	"ID" INT, "SOURCE" NVARCHAR(20), "TARGET" NVARCHAR(20), 
	"$LOAD" DOUBLE, "$DIAMETER_M" DOUBLE, "$LOAD_PER_DIAMETER" DOUBLE, "$LOAD_PER_CROSSSECTION" DOUBLE
);
CREATE TYPE "STORMWATER"."TT_LOAD_VERTICES" AS TABLE (
	"ID" NVARCHAR(20), "$SUM_COVERED_AREA_M2_UPSTREAM" DOUBLE, "$OUT_DEG" BIGINT
);

-- The Graph procedure
CREATE OR REPLACE PROCEDURE "STORMWATER"."P_CALC_LOAD" (
	OUT o_vertices "STORMWATER"."TT_LOAD_VERTICES",
	OUT o_edges "STORMWATER"."TT_LOAD_EDGES"
)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN 
	GRAPH g = Graph("STORMWATER", "STORMWATER");
	ALTER g ADD TEMPORARY VERTEX ATTRIBUTE(DOUBLE "$SUM_COVERED_AREA_M2_UPSTREAM"); -- to store the sum of the catchment area of all upstream nodes, same as the load
	ALTER g ADD TEMPORARY VERTEX ATTRIBUTE(BIGINT "$OUT_DEG"); -- TO store the number OF outgoing edges
	ALTER g ADD TEMPORARY EDGE ATTRIBUTE(DOUBLE "$LOAD"); -- TO store the load provided BY the vertex AND fed INTO this pipe
	ALTER g ADD TEMPORARY EDGE ATTRIBUTE(DOUBLE "$LOAD_PER_DIAMETER"); 
	ALTER g ADD TEMPORARY EDGE ATTRIBUTE(DOUBLE "$LOAD_PER_CROSSSECTION");
	DOUBLE sum_area_m2 = 0.0;
	DOUBLE sum_dia_m = 0.0;
	DOUBLE sum_cs_m2 = 0.0;
	DOUBLE pipe_load = 0.0;
	MULTISET<Edge> ms_e = MULTISET<Edge>(:g);
-- we'll just loop over all vertices
	FOREACH v IN Vertices(:g){
		sum_area_m2 = 0.0;
		sum_dia_m = 0.0;
		sum_cs_m2 = 0.0;
		v."$OUT_DEG" = OUT_DEGREE(:v);
-- and sum up the area(=load) of all upstream vertices
		FOREACH v_upstream IN REACHABLE_VERTICES(:g, :v, 'INCOMING'){
			sum_area_m2 = :sum_area_m2 + :v_upstream."AREA_M2";
		}
		v."$SUM_COVERED_AREA_M2_UPSTREAM" = :sum_area_m2;
-- from each vertex, we will distrubte the load into downstream edges proportially
		ms_e = OUT_EDGES(:v);
		FOREACH e_out IN :ms_e {
			sum_dia_m = :sum_dia_m + :e_out."DIAMETER_M";
			sum_cs_m2 = :sum_cs_m2 + (:e_out."DIAMETER_M"*:e_out."DIAMETER_M");
		}
		FOREACH e_out IN :ms_e {
			pipe_load = :sum_area_m2 * ((:e_out."DIAMETER_M" * :e_out."DIAMETER_M") / :sum_cs_m2);
			e_out."$LOAD" = :pipe_load;
			e_out."$LOAD_PER_DIAMETER" = :pipe_load / :e_out."DIAMETER_M" ;
			e_out."$LOAD_PER_CROSSSECTION" = :pipe_load / (:e_out."DIAMETER_M" * :e_out."DIAMETER_M") ;
		}
	}
	o_vertices = SELECT :v."ID", :v."$SUM_COVERED_AREA_M2_UPSTREAM", :v."$OUT_DEG" FOREACH v IN Vertices(:g);
	o_edges = SELECT :e."ID", :e."SOURCE", :e."TARGET", :e."$LOAD", :e."DIAMETER_M", :e."$LOAD_PER_DIAMETER", :e."$LOAD_PER_CROSSSECTION" FOREACH e IN Edges(:g);
END;
-- Call the procedure. It returns load information for edges and vertices.
CALL "STORMWATER"."P_CALC_LOAD"(?,?);

-- Next, we need to store the graph procedure's results in the tables.
ALTER TABLE "STORMWATER"."STORMWATER_VERTICES" ADD("SUM_COVERED_AREA_M2_UPSTREAM" DOUBLE);
ALTER TABLE "STORMWATER"."STORMWATER_VERTICES" ADD("OUT_DEG" DOUBLE);
ALTER TABLE "STORMWATER"."STORMWATER_EDGES" ADD("LOAD" DOUBLE);
ALTER TABLE "STORMWATER"."STORMWATER_EDGES" ADD("LOAD_PER_DIAMETER" DOUBLE);
ALTER TABLE "STORMWATER"."STORMWATER_EDGES" ADD("LOAD_PER_CROSSSECTION" DOUBLE);

DO ()
LANGUAGE SQLSCRIPT
BEGIN
	CALL "STORMWATER"."P_CALC_LOAD"(o_vertices, o_edges);
	MERGE INTO "STORMWATER"."STORMWATER_VERTICES" AS v
		USING :o_vertices AS l
		ON v."ID" = l."ID"
		WHEN MATCHED THEN UPDATE SET v."SUM_COVERED_AREA_M2_UPSTREAM" = l."$SUM_COVERED_AREA_M2_UPSTREAM", v."OUT_DEG" = l."$OUT_DEG";
	MERGE INTO "STORMWATER"."STORMWATER_EDGES" AS e
		USING :o_edges AS l
		ON e."ID" = l."ID"
		WHEN MATCHED THEN UPDATE SET e."LOAD" = l."$LOAD", e."LOAD_PER_DIAMETER" = l."$LOAD_PER_DIAMETER", e."LOAD_PER_CROSSSECTION" = l."$LOAD_PER_CROSSSECTION";
END;

-- The edges with the highest risk are the ones with the worst load/crosssection ratio.
SELECT * FROM "STORMWATER"."STORMWATER_EDGES" ORDER BY "LOAD_PER_CROSSSECTION" DESC;

