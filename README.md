# hana-graph-shortest-paths
SAP HANA includes a graph engine for network analysis. The shortest path examples demonstrate the usage of built-in algorithms for path finding.

## Description
SAP HANA's built-in graph algorithms, e.g. for shortest path finding, can be invoked within database procedures. The procedures are called from SQL, which is a nice way to integrate graph processing with relational. The ["GRAPH"](link to folder) procedure examples included in this repository help you understand the power of the language and also provide code snippets and reuse templates.

Some self-contained examples are in the [GRAPH_PROCEDURES_EXAMPLES](https://github.com/SAP-samples/hana-graph-shortest-paths/tree/main/GRAPH_PROCEDURE_EXAMPLES) folder. Some more advanced samples are based on a flight routes dataset [OPENFLIGHTS](OPENFLIGHTS/OPENFLIGHTS_shortest_paths.sql).

## Requirements
In order to run the examples yourself you need a SAP HANA Cloud system and a basic understand of SQL. To get a system you can register for a trial https://developers.sap.com/tutorials/hana-trial-advanced-analytics.html. Once set up and connected, you just need to open the SQL Editor in the SAP HANA Database Explorer and run the statements in the script.
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
Details on how external developers can contribute to your code should be posted here. See Setting guidelines for repository contributors on GitHub.com about adding a Contributing.md file.
If your project is only updated by SAP employees or only accepting bug reports but no other contributions, then please state this in this section to avoid externals to open pull requests which will not be considered.

## To-Do (upcoming changes)
We plan to include additional examples and a ready to deploy HANA database module later.

## License
Copyright (c) 2020 SAP SE or an SAP affiliate company. All rights reserved. This file is licensed under the Apache Software License, version 2.0 except as noted otherwise in the [LICENSE](LICENSES/Apache-2.0.txt) file.
