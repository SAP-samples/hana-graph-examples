-- a possible solution to the PM Graph Challenge 2022:
-- 1 a graph procedure calculating the paths from BLDG1 and BLDG2 to any other building
-- output is a set of paths (for post-processing), and the edges that make up the paths (for display)
CREATE OR REPLACE PROCEDURE 2022_GRAPH_CHALLENGE.GS_SPOO_BUILDING_IN_THE_MIDDLE (
	IN i_buildings TABLE ("nearest_street_vertex" BIGINT), -- a TABLE containing ALL SAP buildings
	IN i_bldg1 BIGINT,
	IN i_bldg2 BIGINT,
	IN i_direction NVARCHAR(20),
	OUT o_edges TABLE ("nearest_street_vertex" BIGINT, "PATH" INT, "ORD" BIGINT, "EDGE_ID" NVARCHAR(5000)),
	OUT o_paths TABLE ("nearest_street_vertex" BIGINT, "p1" DOUBLE, "p2" DOUBLE)	
)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph("2022_GRAPH_CHALLENGE","GRAPH");
	VERTEX v_bldg1 = Vertex(:g, :i_bldg1);
	VERTEX v_bldg2 = Vertex(:g, :i_bldg2);
	BIGINT cnt = 0L;
	BIGINT cnt2 = 0L;
	-- put the buildings into a multiset to run a loop
	MULTISET<BIGINT> m_buildings = MULTISET<BIGINT>(:i_buildings."nearest_street_vertex");
	FOREACH building IN :m_buildings {
		WeightedPath<DOUBLE> p1 = Shortest_Path(:g, :v_bldg1, Vertex(:g, :building), (Edge e) => DOUBLE{ return :e."length"; }, :i_direction);
		WeightedPath<DOUBLE> p2 = Shortest_Path(:g, :v_bldg2, Vertex(:g, :building), (Edge e) => DOUBLE{ return :e."length"; }, :i_direction);
		cnt = :cnt + 1L;
		o_paths."nearest_street_vertex"[:cnt] = :building;
		o_paths."p1"[:cnt] = WEIGHT(:p1);
		o_paths."p2"[:cnt] = WEIGHT(:p2);
		FOREACH e IN EDGES(:p1) WITH ORDINALITY AS ord{
			cnt2 = :cnt2 + 1L;
			o_edges."nearest_street_vertex"[:cnt2] = :building;
			o_edges."PATH"[:cnt2] = 1;
			o_edges."ORD"[:cnt2] = :ord;
			o_edges."EDGE_ID"[:cnt2] = :e."ID";
		}
		FOREACH e IN EDGES(:p2) WITH ORDINALITY AS ord{
			cnt2 = :cnt2 + 1L;
			o_edges."nearest_street_vertex"[:cnt2] = :building;
			o_edges."PATH"[:cnt2] = 2;
			o_edges."ORD"[:cnt2] = :ord;
			o_edges."EDGE_ID"[:cnt2] = :e."ID";
		}
	}
END;
CALL "2022_GRAPH_CHALLENGE"."GS_SPOO_BUILDING_IN_THE_MIDDLE"("2022_GRAPH_CHALLENGE"."SAP_BUILDINGS", 7848508645, 1574720906, 'ANY', ?, ?);

-- 2 post-processing logic in a block, joining some attributes and aggregation
DO() BEGIN
	-- get the requried data to run the procedure
	DECLARE bldg1 BIGINT;
	DECLARE bldg2 BIGINT;
	SELECT "nearest_street_vertex" INTO bldg1 FROM "2022_GRAPH_CHALLENGE"."SAP_BUILDINGS" WHERE "name" = 'SAP WDF13';
	SELECT "nearest_street_vertex" INTO bldg2 FROM "2022_GRAPH_CHALLENGE"."SAP_BUILDINGS" WHERE "name" = 'SAP WDF53';
	buildings = SELECT "nearest_street_vertex" FROM "2022_GRAPH_CHALLENGE"."SAP_BUILDINGS";
	-- call the procedure
	CALL "2022_GRAPH_CHALLENGE"."GS_SPOO_BUILDING_IN_THE_MIDDLE"(:buildings, :bldg1, :bldg2, 'ANY', o_edges, o_paths);
	-- massage the two output tables
	paths = SELECT PAT.*, DAT."name" AS "BITM_NAME", DAT."shape_3857" AS "BITM_SHAPE_3857" 
		FROM :o_paths AS PAT, "2022_GRAPH_CHALLENGE"."SAP_BUILDINGS" AS DAT
		WHERE PAT."nearest_street_vertex" = DAT."nearest_street_vertex";
	edges = SELECT "NSV", "PATH", SUM("length") AS "SUM_LENGTH", ST_UNIONAGGR("SHAPE_3857") AS "SHAPE_3857" FROM (
		SELECT EDG."nearest_street_vertex" AS NSV, EDG."PATH", DAT."length", DAT."SHAPE_3857"
		FROM :o_edges AS EDG, "2022_GRAPH_CHALLENGE"."OSM_EDGES" AS DAT
		WHERE EDG."EDGE_ID" = DAT."ID"
	) GROUP BY "NSV", "PATH";
	-- ... and join
	SELECT PAT.BITM_NAME, PAT."p1", PAT."p2", "p1"+"p2" AS "P1+P2", GREATEST("p1", "p2") AS "GREA P1, P2", abs("p1"-"p2") AS "DIFF P1,P2", PAT.BITM_SHAPE_3857, E1."SHAPE_3857" AS "PATH1", E2."SHAPE_3857" AS "PATH2" 
		FROM :paths AS PAT, :edges AS E1, :edges AS E2
		WHERE PAT."nearest_street_vertex" = E1."NSV" AND E1."PATH" = 1 AND PAT."nearest_street_vertex" = E2."NSV" AND E2."PATH" = 2
		ORDER BY GREATEST("p1", "p2") ASC;
		--ORDER BY abs("p1"-"p2") ASC;
		--ORDER BY ("p1"+"p2") ASC;
END;

/**********************************************/










/*****************************************/
-- Working with table parameters
-- IN parameters:  1 convert a column to multiset, 2 convert two columns to a map
	-- use case: provide multi values for evaluating an IN clause ... v in vertices(g) where v.color in multiset
	-- count and index access
	-- here... checking against a map
-- OUT parameters:
	-- write to the out structure (procedure/block only) (instead of projecting)
	-- looping through a multiset/map and storing the values in the out table 
-- Using TRAVERSE DIJKSTRA
/*******************/
-- Using the values in an IN table to filter the graph
DO (
	IN i_buildings TABLE ("nearest_street_vertex" BIGINT, "name" NVARCHAR(5000)) => "2022_GRAPH_CHALLENGE"."SAP_BUILDINGS",
	OUT o_vertices TABLE ("osmid" BIGINT, "street_count" BIGINT) => ?
	)
LANGUAGE GRAPH
BEGIN
	GRAPH g = Graph("2022_GRAPH_CHALLENGE", "GRAPH");
	-- put the values in a table column into a multiset:
	MULTISET<BIGINT> m_buildings = MULTISET<BIGINT>(:i_buildings."nearest_street_vertex");
	-- use the multiset in a where clause:
	MULTISET<VERTEX> m_vertices = v IN Vertices(:g) WHERE :v."osmid" IN :m_buildings;
	o_vertices = SELECT :v."osmid", :v."street_count" FOREACH v IN :m_vertices;
END;	

-- Looping over an IN table
-- 1 create a multiset from table and FOREACH loop over multiset
DO (
	IN i_buildings TABLE ("nearest_street_vertex" BIGINT, "name" NVARCHAR(5000)) => "2022_GRAPH_CHALLENGE"."SAP_BUILDINGS",
	OUT o_vertices TABLE ("osmid" BIGINT, "buildings_near" BIGINT) => ?
	)
LANGUAGE GRAPH
BEGIN
	GRAPH g = Graph("2022_GRAPH_CHALLENGE", "GRAPH") WITH TEMPORARY ATTRIBUTES (VERTEX BIGINT "$buildings_near" = 0L);
	MULTISET<BIGINT> m_buildings = MULTISET<BIGINT>(:i_buildings."nearest_street_vertex");
	FOREACH building IN :m_buildings{
		VERTEX v = Vertex(:g, :building);
		v."$buildings_near" = :v."$buildings_near" + 1L; 
	}
	MULTISET<VERTEX> m_vertices = v IN Vertices(:g) WHERE :v."$buildings_near" > 0L;
	o_vertices = SELECT :v."osmid", :v."$buildings_near" FOREACH v IN :m_vertices;
END;
-- 2 WHILE LOOP over the table
DO (
	IN i_buildings TABLE ("nearest_street_vertex" BIGINT, "name" NVARCHAR(5000)) => "2022_GRAPH_CHALLENGE"."SAP_BUILDINGS",
	OUT o_vertices TABLE ("osmid" BIGINT, "buildings_near" BIGINT) => ?
	)
LANGUAGE GRAPH
BEGIN
	GRAPH g = Graph("2022_GRAPH_CHALLENGE", "GRAPH") WITH TEMPORARY ATTRIBUTES (VERTEX BIGINT "$buildings_near" = 0L);
	BIGINT i = 1L;
	WHILE (:i <= COUNT(:i_buildings)) {
		VERTEX v = Vertex(:g, :i_buildings."nearest_street_vertex"[:i]);
		v."$buildings_near" = :v."$buildings_near" + 1L; 
	  	i = :i + 1L;
	}
	MULTISET<VERTEX> m_vertices = v IN Vertices(:g) WHERE :v."$buildings_near" > 0L;
	o_vertices = SELECT :v."osmid", :v."$buildings_near" FOREACH v IN :m_vertices;
END;


-- Creating a MAP from two columns of an IN table, looping over the key/value pair of the map
DO (
	IN i_buildings TABLE ("nearest_street_vertex" BIGINT, "name" NVARCHAR(5000)) => "2022_GRAPH_CHALLENGE"."SAP_BUILDINGS",
	OUT o_vertices TABLE ("osmid" BIGINT, "name" NVARCHAR(5000)) => ?
	)
LANGUAGE GRAPH
BEGIN
	GRAPH g = Graph("2022_GRAPH_CHALLENGE", "GRAPH");
	BIGINT i1 = 1L;
	BIGINT i2 = 1L;
	MAP<VERTEX, NVARCHAR> map_buildings = MAP<VERTEX, NVARCHAR>(:g, 100L);
	WHILE (:i1 <= COUNT(:i_buildings)) {
		map_buildings[Vertex(:g, :i_buildings."nearest_street_vertex"[:i1])] = :i_buildings."name"[:i1];
	  	i1 = :i1 + 1L;
	}
	FOREACH (v, nam) IN :map_buildings {
    	o_vertices."osmid"[:i2] = :v."osmid";
    	o_vertices."name"[:i2] = :nam;
    	i2 = :i2 + 1L;
    }
END;



-- TRAVERSE DIJKSTRA
-- the to friends are at building 4 but the coffee machine is broken.
-- show me the top 5 nearest buildings.
-- traversing the street network in a "shortest path manner", detecting the buildings as we traverse
-- SELECT "nearest_street_vertex", * FROM "2022_GRAPH_CHALLENGE"."SAP_BUILDINGS" WHERE "name" = 'SAP WDF04';
-- version where map contains bigint/nvarchar
DO (
	IN i_startVertex BIGINT => 2861722132, -- WDF04
	IN i_buildings TABLE ("nearest_street_vertex" BIGINT, "name" NVARCHAR(5000)) => "2022_GRAPH_CHALLENGE"."SAP_BUILDINGS",
	IN i_k BIGINT => 5,
	OUT o_paths TABLE ("osmid" BIGINT, "ID" NVARCHAR(5000), "u" BIGINT, "v" BIGINT, "length" DOUBLE) => ?,
	OUT o_vertices TABLE ("name" NVARCHAR(5000), "$DISTANCE" DOUBLE) => ?
	)
LANGUAGE GRAPH
BEGIN
	GRAPH g = Graph("2022_GRAPH_CHALLENGE", "GRAPH");
	-- converting the buildings IN table tp a map
	MAP<BIGINT, NVARCHAR> m_buildings = MAP<BIGINT, NVARCHAR>(100L);
	BIGINT i = 1L;
	WHILE (:i <= COUNT(:i_buildings)) {
		m_buildings[:i_buildings."nearest_street_vertex"[:i]] = :i_buildings."name"[:i];
	  	i = :i + 1L;
	}
	VERTEX v_start = Vertex(:g, :i_startVertex);
	BIGINT cnt = 1L;
	TRAVERSERESULT<DOUBLE> shortest_path_tree = TRAVERSERESULT<DOUBLE>(:g);
	
	TRAVERSE DIJKSTRA :g FROM :v_start
		WITH RESULT :shortest_path_tree
		WITH WEIGHT (EDGE e) => DOUBLE { return :e."length"; }
		ON VISIT VERTEX (Vertex v, DOUBLE v_dist) {
			-- check if there is a building at this traversed vertex - search the MAP for the vertex key
			IF (:m_buildings[:v."osmid"] IS NOT NULL) {
				o_vertices."name"[:cnt] = :m_buildings[:v."osmid"];
				o_vertices."$DISTANCE"[:cnt] = :v_dist;
				cnt = :cnt + 1L;
				-- if we found what we need, let's stop the traversal
				IF (:cnt > :i_k) { END TRAVERSE ALL; }
			}
		};
	cnt = 1L;
	FOREACH (o, n) IN :m_buildings {
    	WEIGHTEDPATH<DOUBLE> p = GET_PATH(:shortest_path_tree, Vertex(:g, :o));
    	FOREACH e IN Edges(:p) {
    		o_paths."osmid"[:cnt] = :o;
    		o_paths."ID"[:cnt] = :e."ID";
    		o_paths."u"[:cnt] = :e."u";
    		o_paths."v"[:cnt] = :e."v";
    		o_paths."length"[:cnt] = :e."length";
    		cnt = :cnt + 1L;
    	}
    }
END;



-- alternative version where map contains vertex, nvarchar
DO (
	IN i_startVertex BIGINT => 2861722132, -- WDF04
	IN i_buildings TABLE ("nearest_street_vertex" BIGINT, "name" NVARCHAR(5000)) => "2022_GRAPH_CHALLENGE"."SAP_BUILDINGS",
	IN i_k BIGINT => 5,
	OUT o_vertices TABLE ("name" NVARCHAR(5000), "$DISTANCE" DOUBLE) => ?,
	OUT o_paths TABLE ("osmid" BIGINT, "ID" NVARCHAR(5000), "u" BIGINT, "v" BIGINT, "length" DOUBLE) => ?
	)
LANGUAGE GRAPH
BEGIN
	GRAPH g = Graph("2022_GRAPH_CHALLENGE", "GRAPH");
	-- create a map from i_buildings table
	MAP<VERTEX, NVARCHAR> m_buildings = MAP<VERTEX, NVARCHAR>(:g, 100L);
	BIGINT i = 1L;
	WHILE (:i <= COUNT(:i_buildings)) {
		VERTEX v = Vertex(:g, :i_buildings."nearest_street_vertex"[:i]);
		m_buildings[:v] = :i_buildings."name"[:i];
	  	i = :i + 1L;
	}
	-- define otehr requreid objects
	VERTEX v_start = Vertex(:g, :i_startVertex);
	BIGINT cnt = 1L;
	TRAVERSERESULT<DOUBLE> shortest_path_tree = TRAVERSERESULT<DOUBLE>(:g);
	-- traverse from the start vertex
	TRAVERSE DIJKSTRA :g FROM :v_start
		WITH RESULT :shortest_path_tree
		WITH WEIGHT (EDGE e) => DOUBLE { return :e."length"; }
		ON VISIT VERTEX (Vertex v, DOUBLE v_dist) {
			-- check if there is a building at this street vertex
			IF (:m_buildings[:v] IS NOT NULL) {
				-- record the building's name and distance
				o_vertices."name"[:cnt] = :m_buildings[:v];
				o_vertices."$DISTANCE"[:cnt] = :v_dist;
				cnt = :cnt + 1L;
				-- if k buildings found - stop
				IF (:cnt > :i_k) { END TRAVERSE ALL; }
			}
		};
	cnt = 1L;
	-- get the path from the startpoint to each of the k buildings found
	FOREACH (v, n) IN :m_buildings {
    	WEIGHTEDPATH<DOUBLE> p = GET_PATH(:shortest_path_tree, :v);
    	FOREACH e IN Edges(:p) {
    		o_paths."osmid"[:cnt] = :v."osmid";
    		o_paths."ID"[:cnt] = :e."ID";
    		o_paths."u"[:cnt] = :e."u";
    		o_paths."v"[:cnt] = :e."v";
    		o_paths."length"[:cnt] = :e."length";
    		cnt = :cnt + 1L;
    	}
    }
END;