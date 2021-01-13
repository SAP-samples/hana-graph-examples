[![REUSE status](https://api.reuse.software/badge/github.com/SAP-samples/hana-graph-examples)](https://api.reuse.software/info/github.com/SAP-samples/hana-graph-examples)

# SAP HANA Graph Examples
SAP HANA includes a graph engine for network analysis. The examples demonstrate the usage of built-in algorithms, e.g. for path finding.

## Description
SAP HANA's built-in graph algorithms, e.g. for shortest path finding, can be invoked within database procedures. The procedures are called from SQL, which is a nice way to integrate graph processing with relational. The sample procedures included in this repository help you understand the power of the language and also provide code snippets and reuse templates.

Self-contained scripts are in the GRAPH_PROCEDURES_EXAMPLES folder. You'll find templates for the built-in algorithms, e.g. [BFS](GRAPH_PROCEDURE_EXAMPLES/BUILTIN_FUNCTIONS_ALGORITHMS/HANA_Cloud_2020Q2_Breadth_First_Search.sql), and templates for common algorithms like [closeness centrality](GRAPH_PROCEDURE_EXAMPLES/CUSTOM_ALGORITHMS/HANA_Cloud_2020Q2_Closeness_Centrality.sql).<br>
A more advanced script, specifically related to different variants of path finding, is based on a flight routes dataset [OPENFLIGHTS](OPENFLIGHTS/OPENFLIGHTS_shortest_paths.sql).<br>
Using the [POKEC](https://snap.stanford.edu/data/soc-Pokec.html) dataset, there is a script we used to benchmark sequential vs. [parallel execution](POKEC/POKEC_1k_SP_pairs_bench_sequential_and_parallel.sql) of 1000 shortest path queries. It serves as a template for using the MAP_MERGE operator to parallelize graph queries.<br>
In October 2020 the [SAP HANA Python Client API](https://pypi.org/project/hana-ml/) was enhanced and now includes functions to leverage HANA's Graph engine. If you are a data scientist working in python take a look at the [Jupyter Notebook](NOTEBOOKS/LONDON/HANA-ML_Graph_demo.ipynb) that demonstrates the use of the graph extensions on the London street network.<br>
Also using London street network data, there is a script that demonstrates [how to calculate isochrones](ISOCHRONES/README.md) using the graph engine's built-in shortest path one-to-all algorithm and some HANA-native spatial post processing.

## Requirements
In order to run the examples yourself you need a SAP HANA Cloud system and a basic understand of SQL. To get a system yourself, just [register for a trial](https://developers.sap.com/tutorials/hana-trial-advanced-analytics.html). Once set up and connected, you just need to open the SQL Editor of the SAP HANA Database Explorer and run the statements in the script.
Some of the examples are self-contained, others are made for external datasets (e.g. https://openflights.org/data.html) which can be downloaded and imported into HANA tables.

## Download and Installation
The .sql scripts can just be copied to a SQL Editor and executed.

## Limitations
Some parts of the scripts may not run on older versions of SAP HANA Cloud - just make sure your system is up-to-date.

## Known Issues
None.

## How to obtain support
This project is provided "as-is" - there is no guarantee that raised issues will be answered or addressed in future releases.

## Contributing
At this point, the repository is maintained by SAP only. External contributions will not be considered. However, you are welcome to open a bug report.

## To-Do (upcoming changes)
We plan to include additional examples and a ready to deploy HANA database module later.

## License
Copyright (c) 2020 SAP SE or an SAP affiliate company. All rights reserved. This project is licensed under the Apache Software License, version 2.0 except as noted otherwise in the [LICENSE](LICENSES/Apache-2.0.txt) file.
