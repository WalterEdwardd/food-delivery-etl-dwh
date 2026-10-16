# System Architecture

## High-Level Architecture

```text
CSV
 ↓
Python
 ↓
STG
 ↓
RAW
 ↓
SSIS / Stored Procedures
 ↓
ODS
 ↓
DWH (Single Source of Truth - Physical Storage)
 ↓
BI (Semantic Serving Layer: Schema bi - 15 Views)
 ↓
POWER BI
```

## Control Layer

```text
CONTROL
 ├── etl_batch
 ├── etl_log
 ├── etl_error
 ├── etl_warning
 └── dim_change_log
```

## Design Principles

* RAW is source-preserving.
* Python focuses on source ingestion and orchestration.
* SSIS and SQL Stored Procedures drive reliable transformation.
* ODS contains typed, cleaned, standardized and validated data.
* DWH follows Kimball dimensional modeling principles (10 Dimensions, 5 Facts with Columnstore indexes).
* BI layer (schema `bi`) provides clean, decoupled Semantic Views for Power BI, omitting ETL audit columns and technical SCD2 metadata.
* Data lineage and auditability are mandatory.
* Monetary values use DECIMAL where appropriate.
* Business rules must be explicitly defined or documented as assumptions.
