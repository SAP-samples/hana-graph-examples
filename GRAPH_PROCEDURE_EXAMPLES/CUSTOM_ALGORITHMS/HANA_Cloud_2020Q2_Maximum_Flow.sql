/*************************************/
-- SAP HANA Graph examples - Maximum Flow
-- 2020-10-01
-- This script was developed for SAP HANA Cloud 2020 Q3
-- Wikipedia https://en.wikipedia.org/wiki/Maximum_flow_problem
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
-- Maximum flow procedure
-- This procedure implements the "Ford Fulkerson Algorithm" to find a maximum flow in a graph from source i_startVertex to sink i_endVertex.
-- It is assumed that between two vertices u, v there is at most one directed edge.
CREATE TYPE "GRAPHSCRIPT"."TT_EDGES" AS TABLE (
	"ID" BIGINT,
	"SOURCE" BIGINT,
	"TARGET" BIGINT,
	"CAPACITY" DOUBLE,
	"FLOW" DOUBLE,
	"RESIDUAL_CAPACITY" DOUBLE
);

CREATE OR REPLACE PROCEDURE "GRAPHSCRIPT"."GS_MAXIMUM_FLOW"(
	IN i_startVertex BIGINT,
	IN i_endVertex BIGINT,
	IN i_maxIterations INT,
	OUT o_flow "GRAPHSCRIPT"."TT_EDGES",
	OUT o_maxFlow DOUBLE
)
LANGUAGE GRAPH READS SQL DATA AS
BEGIN
	GRAPH g = Graph("GRAPHSCRIPT","GRAPHWS");
	-- Add edge attributes for residual capacity and flow values
	ALTER g ADD TEMPORARY EDGE ATTRIBUTE (DOUBLE flow = 0.0);
	ALTER g ADD TEMPORARY EDGE ATTRIBUTE (DOUBLE residualCapacity = 0.0);
	-- Initialize the residual capacity
  FOREACH e IN EDGES(:g) {
    	e.residualCapacity = :e."CAPACITY";
	}
	VERTEX v_startVertex = Vertex(:g, :i_startVertex);
	VERTEX v_endVertex = Vertex(:g, :i_endVertex);
	MULTISET<Edge> m_edgesWithResidualCapacity = Multiset<Edge>(:g);
  o_maxFlow = 0.0;
  DOUBLE v_increaseFlowBy = 0.0;
  INT v_iteration = 0;

  WHILE (:v_iteration <= :i_maxIterations) {
		m_edgesWithResidualCapacity = e IN Edges(:g) WHERE :e.residualCapacity > 0.0;
    GRAPH g_sub = SubGraph(:g, :m_edgesWithResidualCapacity);
		IF (VERTEX_EXISTS(:g_sub, :i_startVertex) == FALSE OR VERTEX_EXISTS(:g_sub, :i_endVertex) == FALSE) {
			break;
		}
		ELSE {
			-- first, we need to get an arbitrary path. It doesn't have to be the shortest, but Shortest_Path is a convenient function.
      WeightedPath<BIGINT> p_path = Shortest_Path(:g_sub, Vertex(:g_sub, :v_startVertex), Vertex(:g_sub, :v_endVertex));
			-- In case there is no path - I am done
			IF (LENGTH(:p_path) == 0L) {
				break;
			}
      -- There is a path. Now let's check if the is some capacity left, so we can increase the flow.
      ELSE {
				v_increaseFlowBy = 0.0;
        -- Find the maximum amount by which the flow can be increased in this iteration. This is the minimal capacity on all edges an the path p
        FOREACH e_path IN Edges(:p_path){
          IF (:e_path.residualCapacity < :v_increaseFlowBy OR :v_increaseFlowBy == 0.0) {
            v_increaseFlowBy = :e_path.residualCapacity;
          }
				}
				-- Update flow values of the path's edges
				FOREACH e_in_path IN Edges(:p_path) {
					EDGE e_in_g = Edge(:g, :e_in_path.ID);
					e_in_g.flow = :e_in_g.flow + :v_increaseFlowBy;
					e_in_g.residualCapacity = :e_in_g.residualCapacity - :v_increaseFlowBy;
				}
			}
		}
		v_iteration = :v_iteration + 1;
	}
	FOREACH e IN IN_EDGES(:v_endVertex){
		o_maxFlow = :o_maxFlow + :e.flow;
	}
	o_flow = SELECT :e."ID", :e."SOURCE", :e."TARGET", :e.capacity, :e.flow, :e.residualCapacity FOREACH e IN e_g IN edges(:g) WHERE :e_g.flow > 0.0;
END;
CALL "GRAPHSCRIPT"."GS_MAXIMUM_FLOW"(1, 4, 1000, ?, ?);
