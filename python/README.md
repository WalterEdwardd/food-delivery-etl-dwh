# Python Ingestion Layer

The Python layer is responsible primarily for source ingestion and high-level orchestration.

## Responsibilities

* File discovery
* Filename validation
* File existence validation
* Source schema validation
* Basic source data validation
* ETL batch creation
* CSV reading
* STG loading
* High-level orchestration

## Non-Responsibilities

Python is not the primary engine for business transformation.

The main transformation logic is implemented in SSIS.

Python should not become responsible for:

* Main data typing
* Main business transformations
* Main data standardization
* DWH transformation
