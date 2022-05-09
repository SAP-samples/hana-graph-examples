-- 20220509 "Starter" script for PM Challenge
-- DROP SCHEMA "2022_GRAPH_CHALLENGE" CASCADE;

-- Load the data from https://github.com/SAP-samples/hana-graph-examples/tree/main/2022_GRAPH_CHALLENGE/data
-- using the DBX to upload the catalog objects

-- Inspect what has been imported
-- (1) The street network
SELECT * FROM "2022_GRAPH_CHALLENGE".OSM_EDGES;
SELECT * FROM "2022_GRAPH_CHALLENGE".OSM_VERTICES;
-- (2) The SAP Buildings. The table contains a column "nearest_street_vertex", which references a record in OSM_VERTICES
SELECT * FROM "2022_GRAPH_CHALLENGE".SAP_BUILDINGS;

-- Create a GRAPH WORKSPACE to expose the network to HANA's Graph Engine
CREATE GRAPH WORKSPACE "2022_GRAPH_CHALLENGE"."GRAPH"
	EDGE TABLE 2022_GRAPH_CHALLENGE.OSM_EDGES
		SOURCE COLUMN "u"
		TARGET COLUMN "v"
		KEY COLUMN "ID"
	VERTEX TABLE 2022_GRAPH_CHALLENGE.OSM_VERTICES
		KEY COLUMN "osmid";	

-- How to use Shortest_Path as an example of GraphScript
/*******************************/
-- using a GRAPH procedure
CREATE OR REPLACE PROCEDURE "2022_GRAPH_CHALLENGE"."GS_SPOO"(
	IN i_startVertex BIGINT, 		-- the ID of the start vertex
	IN i_endVertex BIGINT, 			-- the ID of the end vertex
	IN i_dir NVARCHAR(10), 			-- the the direction of the edge traversal: OUTGOING (default), INCOMING, ANY
	OUT o_weight DOUBLE,
	OUT o_vertices TABLE ("osmid" BIGINT, "VERTEX_ORDER" BIGINT), -- the set of vertices returned by the procedure
	OUT o_edges TABLE ("ID" NVARCHAR(255), "u" BIGINT, "v" BIGINT, "EDGE_ORDER" BIGINT) -- the set of edges returned by the procedure
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	-- Create an instance of the graph, refering to the graph workspace object
	GRAPH g = Graph("2022_GRAPH_CHALLENGE", "GRAPH");
	-- Create an instance of the start/end vertex
	VERTEX v_start = Vertex(:g, :i_startVertex);
	VERTEX v_end = Vertex(:g, :i_endVertex);
	-- Running shortest path using the "length" column as cost
	WeightedPath<DOUBLE> p = Shortest_Path(:g, :v_start, :v_end, (Edge e) => DOUBLE{ return :e."length"; }, :i_dir);
	-- Project the results from the path
	o_weight = WEIGHT(:p);
	o_vertices = SELECT :v."osmid", :VERTEX_ORDER FOREACH v IN Vertices(:p) WITH ORDINALITY AS VERTEX_ORDER;
	o_edges = SELECT :e."ID", :e."u", :e."v", :EDGE_ORDER FOREACH e IN Edges(:p) WITH ORDINALITY AS EDGE_ORDER;
END;

-- Finding the shortest path between vertex "1" and "4", traversing edges in any direction
CALL "2022_GRAPH_CHALLENGE"."GS_SPOO"(i_startVertex => 2087434011, i_endVertex => 1574720906, i_dir => 'ANY', o_weight => ?, o_vertices => ?, o_edges => ?);



/*******************************/
-- using a GRAPH function
CREATE OR REPLACE FUNCTION "2022_GRAPH_CHALLENGE"."F_SPOO_EDGES" (
	IN i_startVertex BIGINT, 		-- the ID of the start vertex
	IN i_endVertex BIGINT, 			-- the ID of the end vertex
	IN i_dir NVARCHAR(10) 	-- the the direction of the edge traversal: OUTGOING (default), INCOMING, ANY
	)
	RETURNS TABLE ("ID" NVARCHAR(255), "u" BIGINT, "v" BIGINT, "EDGE_ORDER" BIGINT)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph("2022_GRAPH_CHALLENGE", "GRAPH");
	VERTEX v_start = Vertex(:g, :i_startVertex);
	VERTEX v_end = Vertex(:g, :i_endVertex);
	WeightedPath<DOUBLE> p = Shortest_Path(:g, :v_start, :v_end, (Edge e) => DOUBLE{ return :e."length"; }, :i_dir);
	RETURN SELECT :e."ID", :e."u", :e."v", :EDGE_ORDER FOREACH e IN Edges(:p) WITH ORDINALITY AS EDGE_ORDER;
END;

SELECT G.*, E."SHAPE_3857" FROM "2022_GRAPH_CHALLENGE"."F_SPOO_EDGES"(2087434011, 1574720906, 'ANY') AS G
	LEFT JOIN "2022_GRAPH_CHALLENGE"."OSM_EDGES" AS E
	ON G."ID" = E."ID";



/*******************************/
-- using an anonymous block to orchestrate stuff
DO() 
BEGIN
	DECLARE b1, b2 BIGINT;
	DECLARE o_weight DOUBLE;
	buildings = SELECT "nearest_street_vertex" FROM "2022_GRAPH_CHALLENGE"."SAP_BUILDINGS" WHERE "name" LIKE '%18%' OR "name" LIKE '%53%';
	b1 = :buildings."nearest_street_vertex"[1];
	b2 = :buildings."nearest_street_vertex"[2];	
	CALL "2022_GRAPH_CHALLENGE"."GS_SPOO"(:b1, :b2, 'ANY', o_weight, o_vertices, o_edges);
	SELECT * FROM :o_edges;
	SELECT :o_weight AS "WEIGHT" FROM DUMMY;
END;




	
	
	
	
	
	