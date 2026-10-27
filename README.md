# Food Delivery ETL & Data Warehouse

## Overview

This project implements a real-world end-to-end ETL pipeline for a food delivery platform.

The project demonstrates a Microsoft Data Platform architecture covering source ingestion, data transformation, operational data storage, dimensional data warehousing, and BI consumption.

## Architecture

```text
CSV Source Files
  ↓
Python Ingestion (STG Loader)
  ↓
STG (Staging Layer)
  ↓
RAW (Audit & Source-Preserving Layer)
  ↓
[ RAW -> ODS ]
  ├── Production Engine  : Native T-SQL Stored Procedure (ods.usp_load_raw_to_ods_batch)
  └── Reference Engine   : SSIS Packages (ssis/FoodDeliveryETL/*.dtsx in Visual Studio)
  ↓
ODS (Operational Data Store: Cleansed & Typed)
  ↓
DWH (Dimensional Warehouse: Star Schema, SCD 1/2, Columnstore Indexes)
  ↓
BI (Semantic Serving Layer: Schema bi Views)
  ↓
POWER BI (Dashboards & Pipeline Observability)
```

> [!NOTE]
> **Dual-Engine Architecture Note:**
> * **Production Pipeline (Active):** Uses Python (`run_monthly_pipeline.py`) orchestrating Native T-SQL stored procedures (`ods.usp_load_raw_to_ods_batch` and `dwh.usp_run_ods_to_dwh_pipeline`). This enables 100% automated CLI/CI/CD execution with zero SSIS licensing or runtime dependencies.
> * **Enterprise Reference Implementation (`ssis/`):** Preserved in the repository as a graphical ETL reference implementation designed in Visual Studio SSDT for Microsoft BI Enterprise environments utilizing SSISDB Catalog and SQL Server Agent.

A dedicated control layer provides batch tracking, logging, error handling, and auditability.

```text
CONTROL
 ├── etl_batch
 ├── etl_log
 ├── etl_error
 ├── etl_warning
 └── dim_change_log
```

## Technology Stack

* Python
* Pandas
* SQL Server
* SQL Server Management Studio
* SQL Server Integration Services (SSIS)
* Visual Studio
* Power BI

## Data Architecture

### STG

Source ingestion layer.

The staging layer receives data from source files before loading it into the RAW layer.

### RAW

Source-preserving layer.

RAW maintains source-aligned data and includes audit metadata such as:

* batch_id
* source_file_name
* source_row_number
* load_timestamp

### ODS

Operational Data Store.

Data in ODS is:

* Typed
* Cleaned
* Standardized
* Validated
* Business-transformed where applicable

### DWH

Dimensional Data Warehouse containing:

* Dimensions
* Facts
* Surrogate keys
* Business keys
* Dimensional relationships

### BI Serving Layer (Schema `bi`)

The dedicated `bi` schema provides clean, consumer-ready Semantic Views (10 Dimensions, 5 Facts) directly feeding Power BI. It completely decouples reporting from internal physical DWH tables:
* 100% of ETL technical audit metadata (`batch_id`, `load_timestamp`) is omitted.
* SCD Type 2 metadata (`valid_from`, `valid_to`, `is_current`) is omitted; dimension views are pre-filtered to current records (`is_current = 1`).
* Dynamic behavioral metrics (`days_since_last_active`, `is_churned`, `churned_date`, `last_status_id`, `churn_risk`) are computed on-read via `GETDATE()`.
* DWH physical tables remain isolated, clean, and secure.
### Control

ETL operational control layer:

* etl_batch (batch execution status and high-level record counters)
* etl_log (granular step and table execution metrics)
* etl_error (quarantine for malformed records and schema failures)
* etl_warning (observability for orphan foreign keys and non-fatal business discrepancies)
* dim_change_log (audit trail for dimension SCD Type 1/2 changes)

### Pipeline Observability & Control Views (`bi.v_monitor_*`)

Dedicated Semantic Views for the **Power BI Pipeline Monitoring Dashboard**, replacing manual SSMS operational queries:
* `bi.v_monitor_pipeline_overview`: Executive status, duration, total volume, error count, and dynamic SLA freshness.
* `bi.v_monitor_step_performance`: Step execution time (seconds), throughput (rows/sec), and bottleneck detection.
* `bi.v_monitor_data_quality_errors`: Categorized quarantined errors by table, column, and error type.
* `bi.v_monitor_warnings_anomalies`: Orphan anomalies and non-fatal operational warnings.
* `bi.v_monitor_layer_reconciliation`: End-to-end record reconciliation (RAW -> ODS -> DWH) and retention rate audit.
* `bi.v_monitor_scd2_audit`: Dimension SCD Type 1 & 2 historical change audit log.

For setup details, DAX measures, and visual layout, see: [docs/runbook/powerbi_pipeline_monitoring_dashboard.md](docs/runbook/powerbi_pipeline_monitoring_dashboard.md).

## Source Data

The project currently contains 8 CSV source datasets:

1. Customer
2. Restaurant
3. Menu Item
4. Delivery Partner
5. Delivery Performance
6. Order
7. Order Item
8. Rating

## Project Structure

```text
food-delivery-etl-dwh/
│
├── data/
│   ├── incoming/
│   ├── processed/
│   ├── archive/
│   └── rejected/
│
├── python/
│   ├── src/
│   │   ├── ingestion/
│   │   ├── validation/
│   │   ├── orchestration/
│   │   ├── config/
│   │   └── utils/
│   │
│   └── tests/
│
├── sql/
│
├── ssis/
│
├── powerbi/
│   └── pipeline_monitoring/
│       ├── Pipeline_Monitoring.pbix
│       ├── tmdl/
│       └── data_dictionary.md
│
├── tests/
│   ├── data_quality/
│   ├── integration/
│   └── reconciliation/
│
└── docs/
    ├── architecture/
    ├── data_dictionary/
    ├── data_lineage/
    └── runbook/
```

## Project Goals

The pipeline is designed with production-oriented principles:

* Layered data architecture
* Batch processing
* Data lineage
* Data quality
* Error handling
* Logging
* Auditability
* Incremental processing
* Idempotency
* Restartability
* Monitoring
* Dimensional modeling

## Project Status

### Phase 1 — Foundation

* [x] Project initialization
* [x] SQL Server database setup
* [x] Schema creation (`stg`, `raw`, `ods`, `dwh`, `bi`, `control`, `ref`, `temp`)
* [x] Source data contract
* [x] STG design
* [x] RAW design
* [x] Control layer
* [x] Python ingestion
* [x] SSIS / SQL Stored Procedure ETL
* [x] ODS

### Phase 2 — Data Warehouse

* [x] Grain definition
* [x] Dimensions (10 dimensions)
* [x] Facts (5 facts with Columnstore indexes)
* [x] Surrogate keys
* [x] SCD (Hybrid Type 1 & Type 2 with change logging)
* [x] DWH ETL

### Phase 3 — BI Serving Layer & Metrics

* [x] Dedicated BI Serving Views (10 Dimensions, 5 Facts in schema `bi`)
* [x] Business KPIs, Dynamic Behavioral Metrics & Aggregations

### Phase 4 — Power BI

* [x] Semantic model
* [x] Relationships (Star Schema)
* [x] DAX
* [x] Dashboard
* [x] Deployment

### Phase 5 — Productionization

* [x] Incremental loading
* [x] Idempotency
* [x] Restartability
* [x] Monitoring & Alerting
* [x] Performance (Columnstore, Partitioning-ready)
* [x] Scheduling (SQL Agent / Orchestration)

---

## Running the Pipeline

### 1. Run a Monthly Batch (Production CLI)
Execute end-to-end ingestion, cleansing, and dimensional loading for any monthly dataset:
```bash
# Run monthly batch (e.g. 2026_01)
python run_monthly_pipeline.py --month 2026_01

# Or run sequentially across multiple batches
python run_monthly_pipeline.py --month 2026_02
```

### 2. Run Comprehensive Audit & Integration Tests
Verify data integrity across all layers (RAW, ODS, DWH) after loading:
```bash
# Verify RAW Ingestion
sqlcmd -S localhost\SQLEXPRESS -d FoodDeliveryDW -E -i sql/tests/01_verify_raw_load.sql

# Verify ODS Cleansing & Typing
sqlcmd -S localhost\SQLEXPRESS -d FoodDeliveryDW -E -i sql/tests/02_verify_ods_load.sql

# Verify DWH Dimensional Modeling & Zero Orphan Facts
sqlcmd -S localhost\SQLEXPRESS -d FoodDeliveryDW -E -i sql/tests/03_verify_dwh_load.sql
```
