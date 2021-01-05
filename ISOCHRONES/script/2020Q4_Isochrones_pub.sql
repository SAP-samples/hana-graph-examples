/*
 * This script shows how to calclulate isochrones on the London street network. It runs on HANA Cloud Q3.
 * The data was optained from Open Street Map using osmx and hana-ml.
 * A HANA database export is the ../data folder.
 * Before you import the data, you need to create the spatial reference system in which the geometries are stored.
 * Just run the below statement
*/
CREATE PREDEFINED SPATIAL REFERENCE SYSTEM IDENTIFIED BY 32630;
/*
 * Once the data is imported, you can run the below script which is organized in 4 steps:
 * 1 shortest paths one-to-all SPOA
 * 2 joining the SPOA result to add geometries to the output
 * 3 applying spatial aggregations on the result: concave hull and hexagon clustering
 * 4 running isochrones calcluation for multiple start points
*/

-- Inspect the data - edges are road segments, vertices are road junctions
SELECT * FROM "ISOCHRONES"."LONDON_EDGES";
SELECT * FROM "ISOCHRONES"."LONDON_VERTICES";

CREATE GRAPH WORKSPACE "ISOCHRONES"."LONDON_GRAPH"
	EDGE TABLE "ISOCHRONES"."LONDON_EDGES"
		SOURCE COLUMN "SOURCE"
		TARGET COLUMN "TARGET"
		KEY COLUMN "ID"
	VERTEX TABLE "ISOCHRONES"."LONDON_VERTICES"
		KEY COLUMN "osmid";

-- 1 shortest paths one-to-all is a built-in graph algorithm.
-- The below procedure returns all vertex keys that can be reached given a time limit.
CREATE TYPE "ISOCHRONES"."TT_SPOA_VERTICES" AS TABLE ("osmid" BIGINT, "CALCULATED_COST" DOUBLE);

CREATE OR REPLACE PROCEDURE "ISOCHRONES"."GS_SPOA"(
    IN i_startID BIGINT,		-- the key of the start vertex, i.e. a road junction in the street network
    IN i_maxSeconds DOUBLE,		-- the maximum drive time distance in seconds
    OUT o_vertices "ISOCHRONES"."TT_SPOA_VERTICES"
)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
    GRAPH g = Graph("ISOCHRONES", "LONDON_GRAPH");
    VERTEX v_start = Vertex(:g, :i_startID);
    -- Running shortest paths one-to-all, which returns a subgraph.
    -- The WEIGHT based path length to a vertex is stored in the attribute CALCULATED_COST
    GRAPH g_spoa = SHORTEST_PATHS_ONE_TO_ALL(:g, :v_start, "CALCULATED_COST",
        (EDGE e, DOUBLE currentPathCost) => DOUBLE{
        	-- length is in meter, speed is in mph, 1 mile/h = 0.44704 m/s, so the expression should return seconds
					IF(:currentPathCost < :i_maxSeconds) { RETURN :e."length"/(DOUBLE(:e."SPEED_MPH")*0.44704); }
					ELSE { END TRAVERSE; }
        });
	-- The procedure returns "osmid" and "CALCULATED_COST" from all vertices in the SPOA graph
    o_vertices = SELECT :v."osmid", :v."CALCULATED_COST" FOREACH v IN Vertices(:g_spoa);
END;
-- Where can we go within 60 seconds starting at a road junction near a swimming pool in Forest Hill (1275065419)
CALL "ISOCHRONES"."GS_SPOA" (1275065419, 60, ?);



-- 2 joining the SPOA result to the LONDON_VERTICES table to add geometries to the output
CREATE OR REPLACE FUNCTION "ISOCHRONES"."F_SPOA"(
    IN i_startID BIGINT,		-- the key of the start vertex
    IN i_maxSeconds DOUBLE		-- the maximum distance/cost
)
RETURNS TABLE("START_ID" BIGINT, "osmid" BIGINT, "CALCULATED_COST" DOUBLE, "SHAPE" ST_GEOMETRY(32630))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
	-- call the SPOA procedure and store the results in o_vertices
  CALL "ISOCHRONES"."GS_SPOA"(:i_startID, :i_maxSeconds, o_vertices);
	-- join o_vertices to the LONDON_VERICES table to add geometries to the result
	RETURN SELECT :i_startID AS "START_ID", V."osmid", V."CALCULATED_COST", T."SHAPE"
		FROM :o_vertices AS V
		LEFT JOIN "ISOCHRONES"."LONDON_VERTICES" AS T
		ON V."osmid" = T."osmid";
END;
-- Where can we go within 60 seconds starting at 1275065419.
-- The function also returns the spatial location of the reachable vertices.
SELECT * FROM "ISOCHRONES"."F_SPOA"(1275065419, 60);



-- 3 applying two spatial aggregations on the result: concave hull and hexagon clustering
CREATE OR REPLACE FUNCTION "ISOCHRONES"."F_ISOCHRONE_SINGLE"(
    IN i_startID BIGINT,			-- the key of the start vertex
    IN i_maxSeconds DOUBLE,			-- the maximum distance/cost
    IN i_resultType NVARCHAR(20)	-- indicates if the result should be CONCAVEHULL or HEXAGON, defaults to POINTS
)
RETURNS TABLE("START_ID" BIGINT, "ID" BIGINT, "SHAPE" ST_GEOMETRY(32630), "CALCULATED_COST" DOUBLE)
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
	-- call the SPOA procedure and store the results in o_vertices
	CALL "ISOCHRONES"."GS_SPOA"(:i_startID, :i_maxSeconds, o_vertices);
	-- join o_vertices to the LONDON_VERICES table to add geometries to the result
	spoaPoints = SELECT V."osmid" AS "ID", V."CALCULATED_COST", T."SHAPE"
		FROM :o_vertices AS V
		LEFT JOIN "ISOCHRONES"."LONDON_VERTICES" AS T
		ON V."osmid" = T."osmid";
	-- apply CONCAVEHULL_AGGR on the point set
	IF (:i_resultType = 'CONCAVEHULL') THEN
    RETURN SELECT :i_startID AS "START_ID", :i_startID AS "ID", ST_CONCAVEHULLAGGR("SHAPE") AS "SHAPE", :i_maxSeconds AS "CALCULATED_COST"
      FROM :spoaPoints;
	-- apply HEXAGON CLUSTERING on the point set
	ELSEIF (:i_resultType = 'HEXAGON') THEN
    RETURN SELECT :i_startID AS "START_ID", ST_CLUSTERID() AS "ID", ST_CLUSTERCELL() AS "SHAPE", CAST(AVG("CALCULATED_COST") AS DOUBLE) AS "CALCULATED_COST"
    	FROM :spoaPoints
      GROUP CLUSTER BY "SHAPE" USING HEXAGON CELL AREA 10000 'meter';
	-- default: just return the point
	ELSE RETURN SELECT :i_startID AS "START_ID", "ID", "SHAPE", "CALCULATED_COST" FROM :spoaPoints;
  END IF;
END;
-- The first query returns a single geometry: the concave hull covering the vertices that can be reached within 90 seconds.
SELECT * FROM "ISOCHRONES"."F_ISOCHRONE_SINGLE"(1275065419, 90, 'CONCAVEHULL');
-- The seconds query applies hexagon clustering on the result set. The CALCULATED_COST for each grid cell is the average of the drive times to the points in the cell.
SELECT * FROM "ISOCHRONES"."F_ISOCHRONE_SINGLE"(1275065419, 90, 'HEXAGON');



-- 4 running isochrones calculation for multiple start points in parallel.
-- The function below filters data in the Points-of-Interest data table and calls the SPOA algorithm for each record.
-- The results are merged and for each vertex the minimum travel time is identified.
-- The final output is clustered using hexagons.
CREATE OR REPLACE FUNCTION "ISOCHRONES"."F_ISOCHRONE_MULTI" (
	IN i_filter NVARCHAR(5000),		-- a SQL WHERE clause to filter the data
	IN i_maxSeconds DOUBLE,			-- the maximum distance/cost
	IN i_cells INT					-- a parameter to configure the number of cells for hexagon clustering
)
RETURNS TABLE ("START_ID" BIGINT, "ID" BIGINT, "SHAPE" ST_GEOMETRY(32630), "CALCULATED_COST" DOUBLE)
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
	-- apply the incoming filter clause on the LONDON_POI table
	startPOIs = APPLY_FILTER("ISOCHRONES"."LONDON_POI", :i_filter);
	-- call the function F_SPOA for all records in startPOIs and merge the result into spoaPoints
	spoaPoints = MAP_MERGE(:startPOIs, "ISOCHRONES"."F_SPOA"(:startPOIs."VERTEX_OSMID", :i_maxSeconds));
	-- for each vertex, calculate the minimum distance and START_ID, then apply hexagon clustering
   RETURN SELECT MAX("START_ID") AS "START_ID", ST_CLUSTERID() AS "ID", ST_CLUSTERCELL() AS "SHAPE", AVG("CALCULATED_COST") AS "CALCULATED_COST" FROM (
	  	SELECT "START_ID", "ID", "SHAPE", "CALCULATED_COST" FROM (
				SELECT "START_ID", "osmid" AS "ID", "SHAPE", "CALCULATED_COST", RANK() OVER (PARTITION BY "osmid" ORDER BY "CALCULATED_COST" ASC) AS "RANK"
				FROM :spoaPoints
			) WHERE "RANK" = 1
		) GROUP CLUSTER BY "SHAPE" USING HEXAGON X CELLS :i_cells;
END;
-- This query returns the combined isochrones for all swimming pools in London, given a maximum drive time of 10 min=1200 sec.
-- The isochrones are the result of hexagon clustering using 110 cells in X direction.
SELECT * FROM "ISOCHRONES"."F_ISOCHRONE_MULTI"(' "amenity" = ''swimming_pool'' ', 1200 , 110);
