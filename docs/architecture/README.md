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
SSIS
 ↓
ODS
 ↓
DWH
 ↓
DATA MART
 ↓
POWER BI
```

## Control Layer

```text
CONTROL
 ├── etl_batch
 ├── etl_log
 └── etl_error
```

## Design Principles

* RAW is source-preserving.
* Python focuses on source ingestion and orchestration.
* SSIS is the primary transformation engine.
* ODS contains typed, cleaned, standardized and validated data.
* DWH follows dimensional modeling principles.
* Data lineage and auditability are mandatory.
* Monetary values use DECIMAL where appropriate.
* Business rules must be explicitly defined or documented as assumptions.
