/***********************************/
-- 2021 Q2
-- This script provides some template code for doing dependency analysis.
-- The scenario is described in this blog post: []
/***********************************/
 
/***********************************/
-- To run this script, you need a SAP HANA Cloud instance.
-- You can get your own trial instance via https://www.sap.com/cmp/td/sap-hana-cloud-trial.html
-- Using the Database Explorer, upload the demo data from github []
/***********************************/

/***********************************/
-- inspect the data
SELECT * FROM "DEPENDENCY_ANALYSIS"."VERTICES";
SELECT * FROM "DEPENDENCY_ANALYSIS"."EDGES";

-- create a graph workspace which exposes the data to the graph engine
CREATE GRAPH WORKSPACE "DEPENDENCY_ANALYSIS"."PACKAGE_GRAPH"
	EDGE TABLE "DEPENDENCY_ANALYSIS"."EDGES"
		SOURCE COLUMN "SOURCE"
		TARGET COLUMN "TARGET"
		KEY COLUMN "ID"
	VERTEX TABLE "DEPENDENCY_ANALYSIS"."VERTICES" 
		KEY COLUMN "PACKAGE_NAME";


	
/****************************************/
-- 1 Basic reachability using REACHABLE_VERTICES
/****************************************/
-- first we need to define a table type which describes the structure of the output
CREATE TYPE "DEPENDENCY_ANALYSIS"."TT_VERTICES" AS TABLE ("PACKAGE_NAME"  NVARCHAR(5000));

-- create a database procedure for reachability
CREATE OR REPLACE PROCEDURE "DEPENDENCY_ANALYSIS"."GS_REACHABLE_VERTICES"(
	IN i_start NVARCHAR(5000),	-- the key of the start vertex, which is its package name
	IN i_dir VARCHAR(10),		-- the direction of the traversal: OUTGOING, INCOMING, ANY
	OUT o_vertices "DEPENDENCY_ANALYSIS"."TT_VERTICES" -- the output structure
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	-- create an instance of the graph, referring to the graph workspace object
	GRAPH g = Graph( "DEPENDENCY_ANALYSIS", "PACKAGE_GRAPH");
	-- create an instance of the start vertex
	VERTEX v_start = Vertex(:g, :i_start);
	-- create a multiset of all vertices reachable from the start node
	MULTISET<Vertex> m_reachableVertices = REACHABLE_VERTICES(:g, :v_start, :i_dir);
	-- create the result from the multiset
	o_vertices = SELECT :v."PACKAGE_NAME" FOREACH v IN :m_reachableVertices;
END;

-- call the procedure: packages that networkx depends upon
CALL "DEPENDENCY_ANALYSIS"."GS_REACHABLE_VERTICES"('networkx', 'OUTGOING', ?);
-- call the procedure: packages which depend on networkx
CALL "DEPENDENCY_ANALYSIS"."GS_REACHABLE_VERTICES"('networkx', 'INCOMING', ?);


-- alternative: the same logic can also run as an "anonymous block"
DO (IN i_start NVARCHAR(5000) => 'networkx', IN i_dir VARCHAR(10) => 'OUTGOING',
	OUT o_vertices "DEPENDENCY_ANALYSIS"."TT_VERTICES" => ? )
LANGUAGE GRAPH BEGIN
	GRAPH g = Graph("DEPENDENCY_ANALYSIS","PACKAGE_GRAPH");
	o_vertices = SELECT :v."PACKAGE_NAME" FOREACH v IN REACHABLE_VERTICES(:g, Vertex(:g, :i_start), :i_dir);
END;


-- extension: the rpocedure can also be wrapped in a function, so you can call it via a SQL SELECT statement
CREATE OR REPLACE FUNCTION "DEPENDENCY_ANALYSIS"."F_REACHABLE_VERTICES" ( IN i_start NVARCHAR(5000), IN i_dir VARCHAR(10)	) 
	RETURNS "DEPENDENCY_ANALYSIS"."TT_VERTICES"
LANGUAGE SQLSCRIPT AS
BEGIN
	CALL "DEPENDENCY_ANALYSIS"."GS_REACHABLE_VERTICES"(:i_start, :i_dir, o_vertices);
	RETURN :o_vertices;
END;

SELECT * FROM "DEPENDENCY_ANALYSIS"."F_REACHABLE_VERTICES"('networkx', 'OUTGOING');
SELECT COUNT(*) FROM "DEPENDENCY_ANALYSIS"."F_REACHABLE_VERTICES"('networkx', 'INCOMING');



/****************************************/
-- 2 Limit traversal depth using the NEIGHBORS function
/****************************************/
CREATE TYPE "DEPENDENCY_ANALYSIS"."TT_EDGES" AS TABLE ("ID" BIGINT, "SOURCE" NVARCHAR(5000), "TARGET" NVARCHAR(5000));

CREATE OR REPLACE PROCEDURE "DEPENDENCY_ANALYSIS"."GS_NEIGHBORS"(
	IN i_start NVARCHAR(5000),	-- the key of the start vertex, which is its package name
	IN i_dir VARCHAR(10),		-- the direction of the traversal: OUTGOING, INCOMING, ANY
	IN i_min BIGINT, 			-- the minimum hop distance 
	IN i_max BIGINT, 			-- the maximum hop distance
	OUT o_vertices "DEPENDENCY_ANALYSIS"."TT_VERTICES", -- the output STRUCTURE
	OUT o_edges "DEPENDENCY_ANALYSIS"."TT_EDGES" -- the output structure
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph("DEPENDENCY_ANALYSIS","PACKAGE_GRAPH");
	VERTEX v_start = Vertex(:g, :i_start);
	MULTISET<Vertex> m_neighbors = MULTISET<Vertex>(:g);
	-- if the direction parameter is not provided, the direction defaults to OUTGOIGN and the NEIGHBORS function accept negative min/max parameters
	IF (:i_dir IS NULL) {
		m_neighbors = NEIGHBORS(:g, :v_start, :i_min, :i_max);
	}
	ELSE {
		m_neighbors = NEIGHBORS(:g, :v_start, :i_min, :i_max, :i_dir);
	}
	o_vertices = SELECT :v."PACKAGE_NAME" FOREACH v IN :m_neighbors;
	-- to get the "ego graph", we identify all edges between the vertices in the neighbors multiset
	o_edges = SELECT :e."ID", :e."SOURCE", :e."TARGET" FOREACH e IN EDGES(:g, :m_neighbors, :m_neighbors);
END;

-- call the procedure: 2-hop ego graph of networkx' dependencies. The procedure returns two result sets - vertices and edges.
CALL "DEPENDENCY_ANALYSIS"."GS_NEIGHBORS"('networkx', 'OUTGOING', 0, 2, ?, ?);
-- call the procedure: 2-hop ego graph of networkx' dependants
CALL "DEPENDENCY_ANALYSIS"."GS_NEIGHBORS"('networkx', 'INCOMING', 0, 2, ?, ?);
-- call the procedure: 2-hop ego graph of networkx. Essentially this is the UNION of the two above statements.
CALL "DEPENDENCY_ANALYSIS"."GS_NEIGHBORS"('networkx', NULL, -2, 2, ?, ?);
-- if we traverse the graph in any direction, we'll get the complete weakly connected component
CALL "DEPENDENCY_ANALYSIS"."GS_NEIGHBORS"('networkx', 'ANY', 0, 1000, ?, ?);



/****************************************/
-- 3 Hop distance and spanning tree using SHORTEST PATHS ONE TO ALL
/****************************************/
CREATE TYPE "DEPENDENCY_ANALYSIS"."TT_VERTICES_DISTANCE" AS TABLE ("PACKAGE_NAME" NVARCHAR(5000), "DISTANCE" BIGINT);

CREATE OR REPLACE PROCEDURE "DEPENDENCY_ANALYSIS"."GS_SPOA"(
	IN i_start NVARCHAR(5000),	-- the key of the start vertex
	IN i_dir NVARCHAR(10), 		-- the the direction of the edge traversal: OUTGOING (default), INCOMING, ANY
	OUT o_vertices "DEPENDENCY_ANALYSIS"."TT_VERTICES_DISTANCE",
	OUT o_edges "DEPENDENCY_ANALYSIS"."TT_EDGES"
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph("DEPENDENCY_ANALYSIS","PACKAGE_GRAPH");
	VERTEX v_start = Vertex(:g, :i_start);
	-- Shortest paths one to all returns a subgraph. The hop distance based path length to a vertex is stored in the attribute DISTANCE
	GRAPH g_spoa = SHORTEST_PATHS_ONE_TO_ALL(:g, :v_start, "DISTANCE", :i_dir);
	o_vertices = SELECT :v."PACKAGE_NAME", :v."DISTANCE" FOREACH v IN Vertices(:g_spoa);
	o_edges = SELECT :e."ID", :e."SOURCE", :e."TARGET" FOREACH e IN Edges(:g_spoa);
END;

-- call the procedure: the vertices result contains a DISTANCE attribute. The edges form a spanning tree.
CALL "DEPENDENCY_ANALYSIS"."GS_SPOA"('networkx', 'OUTGOING', ?, ?);



/****************************************/
-- 4 Filter and stop conditions using BREADTH FIRST SEARCH
/****************************************/
CREATE TYPE "DEPENDENCY_ANALYSIS"."TT_VERTICES_DISTANCE_INOUT" AS TABLE ("PACKAGE_NAME" NVARCHAR(5000), "VERSION" NVARCHAR(5000), "DISTANCE" BIGINT, "IN_DEGREE" BIGINT, "OUT_DEGREE" BIGINT);

CREATE OR REPLACE PROCEDURE "DEPENDENCY_ANALYSIS"."GS_BFS"(
	IN i_start NVARCHAR(5000),
	IN i_dir VARCHAR(10),
	OUT o_vertices "DEPENDENCY_ANALYSIS"."TT_VERTICES_DISTANCE_INOUT"
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph("DEPENDENCY_ANALYSIS","PACKAGE_GRAPH");
	-- add vertex attributes to store data:
	ALTER g ADD TEMPORARY VERTEX ATTRIBUTE (BIGINT "DISTANCE");
	ALTER g ADD TEMPORARY VERTEX ATTRIBUTE (BIGINT "IN_DEGREE");
	ALTER g ADD TEMPORARY VERTEX ATTRIBUTE (BIGINT "OUT_DEGREE");
	VERTEX v_start = Vertex(:g, :i_start);
	-- create a sequence to store the output set of vertices
	SEQUENCE<Vertex> s_o_vertices = Sequence<Vertex> (:g);
	-- traverse the graph from the start node, "hooking" into each vertex visit to run "local" checks for filtering and traversal stop.
	-- We will stop the traversal if the version is <= 1 and will add a vertex to the "output" container if in-degree or out-degree is 0.
	TRAVERSE BFS (:i_dir) :g FROM :v_start ON VISIT VERTEX (Vertex v_visited, BIGINT tmp_distance) {
		v_visited."DISTANCE" = :tmp_distance;
		v_visited."IN_DEGREE" = IN_DEGREE(:v_visited);
		v_visited."OUT_DEGREE" = OUT_DEGREE(:v_visited);
		IF (:v_visited."VERSION" > '1' OR :v_visited."PACKAGE_NAME" == :i_start) {
			IF ( OUT_DEGREE(:v_visited) == 0L OR IN_DEGREE(:v_visited) == 0L ) {
				s_o_vertices = :s_o_vertices || :v_visited;		
			}
		}
		ELSE { END TRAVERSE; }
	};
	o_vertices = SELECT :v."PACKAGE_NAME", :v."VERSION", :v."DISTANCE", :v."IN_DEGREE", :v."OUT_DEGREE" FOREACH v IN :s_o_vertices;
END;

-- networkx' "root" package dependencies:
CALL "DEPENDENCY_ANALYSIS"."GS_BFS"('networkx', 'OUTGOING', ?);
-- top-level packages depending on networkx
CALL "DEPENDENCY_ANALYSIS"."GS_BFS"('networkx', 'INCOMING', ?);

-- alternative: you can also remove simple "stop" vertices from the graph
DO (IN i_start NVARCHAR(5000) => 'networkx', IN i_dir VARCHAR(10) => 'OUTGOING',
	OUT o_vertices "DEPENDENCY_ANALYSIS"."TT_VERTICES" => ? )
LANGUAGE GRAPH BEGIN
	GRAPH g = Graph("DEPENDENCY_ANALYSIS","PACKAGE_GRAPH");
	GRAPH g_sub = Subgraph(:g, v IN Vertices(:g) WHERE :v."VERSION" > '1' OR :v."PACKAGE_NAME" == :i_start);
	o_vertices = SELECT :v."PACKAGE_NAME" FOREACH v IN REACHABLE_VERTICES(:g_sub, Vertex(:g_sub, :i_start), :i_dir);
END;



/****************************************/
-- 5 set operations
/****************************************/
CREATE OR REPLACE PROCEDURE "DEPENDENCY_ANALYSIS"."GS_REACHABLE_VERTICES_INTERSECTION"(
	IN i_startVertices "DEPENDENCY_ANALYSIS"."TT_VERTICES", -- table parameter that provides a set of start packages
	IN i_dir VARCHAR(10),
	OUT o_vertices "DEPENDENCY_ANALYSIS"."TT_VERTICES"
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph( "DEPENDENCY_ANALYSIS", "PACKAGE_GRAPH");
	-- create a multiset of start vertices based on the IN table parameter
	MULTISET<NVARCHAR> m_startVertices = Multiset<NVARCHAR> (:i_startVertices."PACKAGE_NAME");
	-- create an empty container to store the common neighbors
	MULTISET<Vertex> m_commonNeighbors = Multiset<Vertex>(:g);
	-- loop over all start vertices
	FOREACH package IN :m_startVertices {
		-- get all neighbors...
		MULTISET<Vertex> m_reachableVertices = REACHABLE_VERTICES(:g, Vertex(:g, :package), :i_dir);
		IF (IS_EMPTY(:m_commonNeighbors)) { m_commonNeighbors = :m_reachableVertices; }
		-- and calculate the intersections
		ELSE { m_commonNeighbors = :m_commonNeighbors INTERSECT :m_reachableVertices; }
	}
	o_vertices = SELECT :v."PACKAGE_NAME" FOREACH v IN :m_commonNeighbors;
END;

-- to select the multiple start vertices, it is convenient to use the APPLY_FILTER operator in SQLScript
CREATE OR REPLACE FUNCTION "DEPENDENCY_ANALYSIS"."F_REACHABLE_VERTICES_INTERSECTION" (
	IN v_filter NVARCHAR(5000), IN i_dir VARCHAR(10)
	) 
	RETURNS "DEPENDENCY_ANALYSIS"."TT_VERTICES" 
LANGUAGE SQLSCRIPT AS
BEGIN
	selectedVertices = APPLY_FILTER("DEPENDENCY_ANALYSIS"."VERTICES", :v_filter);
	CALL "DEPENDENCY_ANALYSIS"."GS_REACHABLE_VERTICES_INTERSECTION"(:selectedVertices, :i_dir, o_vertices);
	RETURN :o_vertices;
END;

-- get the intersection(common neighbors) of networkx and weihnachtsgurke
SELECT * FROM "DEPENDENCY_ANALYSIS"."F_REACHABLE_VERTICES_INTERSECTION"(' "PACKAGE_NAME" IN (''networkx'', ''weihnachtsgurke'') ', 'OUTGOING');


/****************************************/
-- 5 basic aggregation
/****************************************/ 
CREATE TYPE "DEPENDENCY_ANALYSIS"."TT_VERTICES_COU" AS TABLE ("PACKAGE_NAME" NVARCHAR(5000), "UPSTREAM_TOP_LEVEL_PACKAGES" BIGINT, "DOWNSTREAM_ROOT_PACKAGES" BIGINT);

CREATE OR REPLACE PROCEDURE "DEPENDENCY_ANALYSIS"."GS_DEPENDENCY_COUNT"(
	OUT o_vertices "DEPENDENCY_ANALYSIS"."TT_VERTICES_COU"
	)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph( "DEPENDENCY_ANALYSIS", "PACKAGE_GRAPH");
	BIGINT i = 1L;
	MULTISET<Vertex> m_v = Vertices(:g);
	MULTISET<Vertex> m_reach = MULTISET<Vertex>(:g);
	-- loop over all vertices
	FOREACH v_start IN :m_v {
		-- get the up- and downstream neighbors
		m_reach = NEIGHBORS(:g, :v_start, -1000, 1000);
		o_vertices."PACKAGE_NAME"[:i] = :v_start."PACKAGE_NAME";
		-- and store the count of top-level and root packages
		o_vertices."UPSTREAM_TOP_LEVEL_PACKAGES"[:i] = COUNT(v_reach IN :m_reach WHERE IN_DEGREE(:v_reach) == 0L);
		o_vertices."DOWNSTREAM_ROOT_PACKAGES"[:i] = COUNT(v_reach IN :m_reach WHERE OUT_DEGREE(:v_reach) == 0L);
		i = :i + 1L;
	}
END;

-- wrap the procedure in a function to have full SQL available
CREATE OR REPLACE FUNCTION "DEPENDENCY_ANALYSIS"."F_DEPENDENCY_COUNT"( ) 
	RETURNS "DEPENDENCY_ANALYSIS"."TT_VERTICES_COU" 
LANGUAGE SQLSCRIPT AS
BEGIN
	CALL "DEPENDENCY_ANALYSIS"."GS_DEPENDENCY_COUNT"(o_vertices);
	RETURN :o_vertices;
END;

-- get the packages that are required by most other top-level packages
SELECT * FROM "DEPENDENCY_ANALYSIS"."F_DEPENDENCY_COUNT"() ORDER BY UPSTREAM_TOP_LEVEL_PACKAGES desc;
-- get the packages that require most root packages
SELECT * FROM "DEPENDENCY_ANALYSIS"."F_DEPENDENCY_COUNT"() ORDER BY DOWNSTREAM_ROOT_PACKAGES desc;
