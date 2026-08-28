# Food Delivery ETL & Data Warehouse

## Overview

This project implements a real-world end-to-end ETL pipeline for a food delivery platform.

The project demonstrates a Microsoft Data Platform architecture covering source ingestion, data transformation, operational data storage, dimensional data warehousing, data marts, and BI consumption.

## Architecture

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

A dedicated control layer provides batch tracking, logging, error handling, and auditability.

```text
CONTROL
 ├── etl_batch
 ├── etl_log
 └── etl_error
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

### Data Mart

Business-oriented analytical layer.

Planned marts include:

* Sales Mart
* Customer Mart

### Control

ETL operational control layer:

* etl_batch
* etl_log
* etl_error

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
* [ ] SQL Server database setup
* [ ] Schema creation
* [ ] Source data contract
* [ ] STG design
* [ ] RAW design
* [ ] Control layer
* [ ] Python ingestion
* [ ] SSIS ETL
* [ ] ODS

### Phase 2 — Data Warehouse

* [ ] Grain definition
* [ ] Dimensions
* [ ] Facts
* [ ] Surrogate keys
* [ ] SCD
* [ ] DWH ETL

### Phase 3 — Data Mart

* [ ] Sales Mart
* [ ] Customer Mart
* [ ] Business metrics

### Phase 4 — Power BI

* [ ] Semantic model
* [ ] Relationships
* [ ] DAX
* [ ] Dashboard
* [ ] Deployment

### Phase 5 — Productionization

* [ ] Incremental loading
* [ ] Idempotency
* [ ] Restartability
* [ ] Monitoring
* [ ] Performance
* [ ] Scheduling
