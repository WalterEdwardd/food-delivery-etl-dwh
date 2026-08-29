# Food Delivery ETL — Python

Python component for the **Food Delivery ETL & Data Warehouse Platform**.

This component is responsible primarily for **source ingestion and high-level orchestration**. It prepares source data for the SQL Server staging layer and provides the foundation for the downstream SSIS-based ETL pipeline.

---

## 1. Purpose

The Python component is responsible for ingesting source CSV files into the SQL Server staging process.

The main objectives are:

* Discover source files.
* Validate source filenames.
* Validate source file structure.
* Validate source columns.
* Perform basic source-level data validation.
* Create and track ETL batches.
* Read CSV files.
* Load source data into the STG layer.
* Support high-level ETL orchestration.
* Trigger downstream SSIS processing when required.

Python is intentionally kept focused on **source ingestion and orchestration**.

Business transformation is handled by downstream ETL components, primarily SSIS.

---

## 2. Responsibilities

Python is responsible for the following activities.

### 2.1. File Discovery

Identify source files available in the configured source directory.

Example:

```text
data/incoming/

customer_20250930.csv
order_20250930.csv
order_item_20250930.csv
restaurant_20251030.csv
```

The ingestion process should be able to discover files without requiring every individual file to be manually specified.

---

### 2.2. Filename Validation

Validate whether the source filename follows the expected naming convention.

Example:

```text
customer_20250930.csv
```

The filename contains:

```text
entity      = customer
snapshot    = 20250930
extension   = csv
```

Invalid filenames should be rejected before loading.

---

### 2.3. Source Schema Validation

Validate the structure of each CSV file before loading.

Validation includes:

* Required columns.
* Missing columns.
* Unexpected columns.
* Column names.
* Basic source data types where applicable.

Example:

```text
customer_20250930.csv
```

Expected columns:

```text
customer_id
signup_date
city
acquisition_channel
```

If a required column is missing, the file should not continue through the normal ingestion process.

---

### 2.4. ETL Batch Creation

Each ingestion execution should be associated with an ETL batch.

The batch provides a common identifier for tracking the execution across the pipeline.

Example:

```text
batch_id = 202608290001
```

The batch can later be associated with:

```text
STG
RAW
ODS
DWH
ETL_LOG
ETL_ERROR
```

This provides the foundation for auditability and data lineage.

---

### 2.5. CSV Reading

Python uses Pandas to read source CSV files.

Example:

```python
import pandas as pd

df = pd.read_csv(file_path)
```

The ingestion layer should preserve source information rather than applying major business transformations.

---

### 2.6. STG Loading

Python prepares and loads source data into the SQL Server staging layer.

The staging layer is the first database landing area for the ingestion process.

Example:

```text
CSV
 │
 ▼
Python
 │
 ▼
STG
```

The STG layer is intended to support the ingestion process before data is moved into the RAW layer.

---

### 2.7. High-Level Orchestration

Python may coordinate high-level pipeline execution.

For example:

```text
Discover Files
      │
      ▼
Validate Files
      │
      ▼
Create Batch
      │
      ▼
Load STG
      │
      ▼
Load RAW
      │
      ▼
Trigger SSIS
```

Python should not become the primary transformation engine for the entire platform.

---

## 3. Responsibilities Outside Python

Python is **not** the primary layer for business transformation.

The following responsibilities belong to downstream ETL layers.

### 3.1. Main Data Type Transformation

Examples:

```text
string → DATE
string → DATETIME2
string → DECIMAL
string → INT
```

These transformations are primarily handled in SSIS during the RAW → ODS process.

---

### 3.2. Data Standardization

Examples:

```text
' Hanoi ' → 'Hanoi'
'Y'       → 1
'N'       → 0
```

Business-oriented standardization belongs to the downstream transformation layer.

---

### 3.3. Business Validation

Examples:

```text
rating between 1 and 5

quantity > 0

price >= 0

distance_km >= 0
```

These rules are handled as part of the SSIS transformation and validation process.

---

### 3.4. Business Transformation

Python should not contain the main business transformation logic.

For example, Python should not become the place where we implement all business calculations such as:

```text
Order revenue
Customer classification
Restaurant performance
Delivery performance
Business KPIs
```

These transformations belong to the appropriate downstream data layer.

---

### 3.5. ODS Transformation

The main transformation from:

```text
RAW → ODS
```

is implemented using SSIS.

SSIS is responsible for:

```text
Typed
   ↓
Cleaned
   ↓
Standardized
   ↓
Validated
   ↓
Transformed
   ↓
ODS
```

---

### 3.6. Data Warehouse Transformation

The dimensional transformation from:

```text
ODS → DWH
```

is handled by the SQL Server / DWH ETL layer.

This includes:

* Dimension loading.
* Surrogate key generation.
* Fact loading.
* Grain management.
* Slowly Changing Dimensions where applicable.
* Referential integrity.

---

### 3.7. Data Mart Transformation

The Data Mart layer is built from the DWH.

Example:

```text
DWH
 │
 ├── Sales Mart
 │
 └── Customer Mart
```

Data Mart logic should not be implemented inside the source ingestion Python layer.

---

## 4. Project Structure

```text
python/
│
├── .env
├── .env.example
├── README.md
├── requirements.txt
├── requirements-lock.txt
│
├── src/
│   ├── __init__.py
│   ├── main.py
│   │
│   ├── config/
│   │   ├── __init__.py
│   │   └── settings.py
│   │
│   ├── ingestion/
│   │   └── __init__.py
│   │
│   ├── validation/
│   │   └── __init__.py
│   │
│   ├── orchestration/
│   │   └── __init__.py
│   │
│   └── utils/
│       ├── __init__.py
│       └── logger.py
│
└── tests/
    └── test_application.py
```

### Directory Responsibilities

| Directory            | Responsibility                            |
| -------------------- | ----------------------------------------- |
| `src/`               | Main Python application                   |
| `src/config/`        | Environment and application configuration |
| `src/ingestion/`     | Source file ingestion                     |
| `src/validation/`    | Source validation                         |
| `src/orchestration/` | Pipeline orchestration                    |
| `src/utils/`         | Shared utilities                          |
| `tests/`             | Automated tests                           |

---

## 5. Environment Setup

Create a Python virtual environment:

```bash
python -m venv .venv
```

Activate the virtual environment on Windows PowerShell:

```powershell
.\.venv\Scripts\Activate.ps1
```

The terminal should display the active environment:

```text
(.venv)
```

Install project dependencies:

```bash
pip install -r requirements.txt
```

---

## 6. Configuration

Environment-specific configuration is stored in:

```text
.env
```

Example:

```text
DB_SERVER=YOUR_SQL_SERVER
DB_DATABASE=FoodDeliveryDW
DB_DRIVER=ODBC Driver 18 for SQL Server
DB_TRUSTED_CONNECTION=yes
```

The `.env` file is intended for local environment configuration.

It must **not** be committed to Git.

Use:

```text
.env.example
```

as the configuration template.

Example:

```text
.env.example
```

contains:

```text
DB_SERVER=YOUR_SQL_SERVER
DB_DATABASE=FoodDeliveryDW
DB_DRIVER=ODBC Driver 18 for SQL Server
DB_TRUSTED_CONNECTION=yes
```

---

## 7. Running the Application

From the `python` directory:

```bash
python src/main.py
```

The application should initialize successfully and display basic application and database configuration information.

Example:

```text
Food Delivery ETL pipeline initialized.
Database: FoodDeliveryDW
Server: localhost
```

---

## 8. Running Tests

The project uses `pytest` for automated testing.

Run the test suite:

```bash
python -m pytest
```

Example:

```text
1 passed
```

All tests should pass before changes are committed.

---

## 9. Logging

The application uses Python's `logging` framework instead of relying primarily on `print()` statements.

Logging is used to provide information about:

* Application initialization.
* Pipeline execution.
* Processing steps.
* Warnings.
* Errors.
* Development and debugging information.

Example:

```text
2026-08-29 09:30:00 | INFO | __main__ | Food Delivery ETL pipeline initialized.
```

---

### ETL Audit Logging

Application logging and ETL audit logging are different concerns.

Python application logs provide technical execution information.

The SQL Server Control Layer provides ETL audit information such as:

```text
batch_id
step
status
rows_processed
rows_inserted
rows_rejected
start_time
end_time
message
```

The Control Layer contains:

```text
control.etl_batch
control.etl_log
control.etl_error
```

---

## 10. ETL Architecture

The Python component is part of the overall Food Delivery ETL architecture.

```text
CSV Files
    │
    ▼
Python
    │
    ├── File Discovery
    ├── Filename Validation
    ├── Schema Validation
    ├── Batch Creation
    └── CSV Reading
    │
    ▼
STG
    │
    ▼
RAW
    │
    ▼
SSIS
    │
    ├── Typed
    ├── Cleaned
    ├── Standardized
    ├── Validated
    └── Transformed
    │
    ▼
ODS
    │
    ▼
DWH
    │
    ├── Dimensions
    └── Facts
    │
    ▼
DATA MART
    │
    ├── Sales Mart
    └── Customer Mart
    │
    ▼
Power BI
```

---

## 11. Development Principles

The Python component follows the following development principles.

### 11.1. Separation of Responsibilities

Each component should have a clear responsibility.

```text
Python
    → Source ingestion

SSIS
    → RAW → ODS transformation

SQL Server
    → Data storage and database processing

DWH
    → Dimensional modeling

Data Mart
    → BI-oriented business datasets

Power BI
    → Analytics and visualization
```

---

### 11.2. Avoid Hard-Coded Configuration

Environment-specific settings should not be hard-coded into application code.

Avoid:

```python
server = "localhost"
database = "FoodDeliveryDW"
```

Prefer environment configuration:

```text
.env
```

and access the values through the configuration layer.

---

### 11.3. Validate Before Loading

Source files should be validated before entering the ingestion process.

The general flow is:

```text
Discover
   ↓
Validate
   ↓
Process
   ↓
Load
```

rather than:

```text
Discover
   ↓
Load
   ↓
Discover errors later
```

---

### 11.4. Explicit Column Mapping

Production ETL should avoid relying blindly on:

```python
SELECT *
```

or implicit column ordering.

The source-to-target mapping should be explicit.

This becomes particularly important when source schemas change.

---

### 11.5. Logging

Important pipeline events should be logged.

Examples:

```text
File discovered
File validated
Batch created
File loaded
Rows processed
Rows rejected
Pipeline completed
Pipeline failed
```

---

### 11.6. Exception Handling

Expected failures should be handled explicitly.

For example:

```text
File not found
Invalid filename
Missing column
Invalid CSV
Database connection failure
Duplicate file
```

The pipeline should provide useful error information rather than failing with an unexplained exception.

---

### 11.7. Testability

Business-independent components should be designed so they can be tested individually.

For example:

```text
filename validation
schema validation
file discovery
configuration
database connection
```

---

### 11.8. Data Lineage

Source metadata should be preserved throughout ingestion.

Important metadata includes:

```text
batch_id
source_file_name
source_row_number
load_timestamp
```

This allows downstream users to trace a record back to the source file and ETL batch.

---

## 12. Source Data

The current project contains eight source CSV files.

```text
customer_20250930.csv

delivery_partner_20251030.csv

delivery_performance_20251030.csv

menu_item_20251030.csv

order_20250930.csv

order_item_20250930.csv

rating_20250930.csv

restaurant_20251030.csv
```

The corresponding business entities are:

```text
customer
delivery_partner
delivery_performance
menu_item
order
order_item
rating
restaurant
```

---

### Source Entities

| Entity                 | Description                     |
| ---------------------- | ------------------------------- |
| `customer`             | Customer master data            |
| `restaurant`           | Restaurant master data          |
| `menu_item`            | Restaurant menu item data       |
| `delivery_partner`     | Delivery partner data           |
| `order`                | Order header data               |
| `order_item`           | Order line-level data           |
| `delivery_performance` | Delivery performance data       |
| `rating`               | Customer rating and review data |

---

## 13. Data Lineage

The ingestion process preserves source-level metadata.

Important metadata includes:

```text
batch_id
source_file_name
source_row_number
load_timestamp
```

Example:

```text
Source File
    │
    ▼
customer_20250930.csv
    │
    ▼
batch_id = 202608290001
    │
    ▼
STG
    │
    ▼
RAW
    │
    ▼
ODS
```

A record should be traceable back to its original source file and ETL batch whenever possible.

This provides the foundation for:

* Auditability.
* Troubleshooting.
* Data quality investigation.
* ETL monitoring.
* Root-cause analysis.

---

## 14. ETL Batch Processing

Each ETL execution is associated with a batch.

Example:

```text
Batch ID
202608290001
```

A batch can contain multiple source files:

```text
Batch 202608290001
│
├── customer_20250930.csv
├── order_20250930.csv
├── order_item_20250930.csv
├── rating_20250930.csv
└── restaurant_20251030.csv
```

Batch tracking allows the pipeline to answer questions such as:

```text
Which files were processed?

When did the batch start?

When did the batch finish?

How many records were processed?

How many records failed?

Which step failed?
```

---

## 15. Data Quality

Source validation will gradually be expanded to cover:

### Completeness

```text
NULL values
Empty strings
Missing business keys
```

### Validity

```text
Invalid dates
Invalid numeric values
Invalid data types
Invalid ranges
```

### Consistency

```text
Foreign key relationships
Order / Order Item relationship
Restaurant / Menu Item relationship
```

### Business Validation

Examples:

```text
rating between 1 and 5

quantity > 0

price >= 0

distance_km >= 0
```

Invalid records should be handled through the ETL error mechanism where possible.

They should not unnecessarily cause the entire pipeline to fail.

---

## 16. Error Handling

The ingestion process should distinguish between different types of errors.

Examples:

```text
File-level error
    │
    ├── File does not exist
    ├── Invalid filename
    ├── Invalid extension
    └── Invalid schema

Record-level error
    │
    ├── Invalid date
    ├── Invalid numeric value
    ├── Invalid business value
    └── Missing required value
```

Record-level errors should be captured whenever possible without rejecting the entire source file.

Downstream ETL errors are recorded in:

```text
control.etl_error
```

Important information includes:

```text
batch_id
source_file_name
source_row_number
table_name
column_name
error_type
error_message
raw_value
error_timestamp
```

---

## 17. Testing Strategy

Testing will gradually cover the ingestion pipeline.

### File-Level Tests

* Filename validation.
* File extension validation.
* File existence.
* Duplicate file detection.

### Schema Tests

* Required columns.
* Unexpected columns.
* Column names.
* Source schema structure.

### Data Validation Tests

* Required values.
* Numeric validation.
* Date validation.
* Business range validation.

### Database Tests

* SQL Server connectivity.
* STG loading.
* Row counts.
* Batch tracking.

### Pipeline Tests

* Error handling.
* Restartability.
* Batch execution.
* Pipeline orchestration.

Unit tests are maintained under:

```text
tests/
```

---

## 18. Dependencies

The main Python dependencies currently include:

```text
pandas
SQLAlchemy
pyodbc
python-dotenv
pytest
```

The high-level purpose of each dependency is:

| Package         | Purpose                              |
| --------------- | ------------------------------------ |
| `pandas`        | CSV reading and source data handling |
| `SQLAlchemy`    | Database interaction abstraction     |
| `pyodbc`        | SQL Server connectivity              |
| `python-dotenv` | Environment configuration            |
| `pytest`        | Automated testing                    |

---

## 19. Git Development

The Python component is version-controlled together with the overall ETL project.

Changes should be committed in small, logical units.

Example:

```bash
git add python/
git commit -m "feat: implement source file discovery"
```

Examples of appropriate commits:

```text
feat: initialize Python ETL project

feat: implement source file discovery

feat: add filename validation

feat: implement source schema validation

feat: implement CSV ingestion

test: add source validation tests

fix: handle invalid source filename
```

---

### Files That Must Not Be Committed

The following files should not be committed:

```text
.env
.venv/
__pycache__/
*.pyc
```

These files should be excluded through the project's `.gitignore`.

---

## 20. Development Workflow

The expected development workflow is:

```text
1. Modify code
      │
      ▼
2. Run tests
      │
      ▼
3. Review changes
      │
      ▼
4. git diff
      │
      ▼
5. git add
      │
      ▼
6. git diff --cached
      │
      ▼
7. git commit
      │
      ▼
8. git push
```

Example:

```powershell
python -m pytest

git status

git diff

git add python/

git diff --cached

git commit -m "feat: implement source file discovery"

git push origin main
```

---

## 21. Current Development Status

The Python project is currently being developed incrementally.

### Foundation

```text
[✓] Python project structure
[✓] Virtual environment
[✓] Configuration layer
[✓] Environment variables
[✓] Logging foundation
[✓] Testing foundation
[✓] README documentation
```

### Ingestion

```text
[ ] File discovery
[ ] Filename validation
[ ] Source schema validation
[ ] Source data validation
[ ] ETL batch creation
[ ] CSV ingestion
[ ] STG loading
```

### Orchestration

```text
[ ] RAW loading
[ ] SSIS triggering
[ ] Pipeline orchestration
[ ] Error handling
```

These components will be implemented incrementally as the project progresses.

---

## 22. Future Enhancements

The Python component may later be extended with:

* Metadata-driven ingestion.
* Incremental processing.
* Duplicate file detection.
* Idempotent loading.
* Retry mechanisms.
* Structured logging.
* Configuration management by environment.
* Automated pipeline orchestration.
* SSIS execution integration.
* Monitoring integration.
* Automated data quality reporting.

These capabilities will be introduced only when the corresponding ETL layers are implemented.

---

## 23. Architecture Boundary

The most important architectural boundary is:

```text
                    SOURCE
                       │
                       ▼
                    PYTHON
                       │
        ┌──────────────┼──────────────┐
        │              │              │
   Discovery       Validation     Batch
        │              │              │
        └──────────────┼──────────────┘
                       │
                       ▼
                      STG
                       │
                       ▼
                      RAW
                       │
                       ▼
                     SSIS
                       │
        ┌──────────────┼──────────────┐
        │              │              │
      Typed         Cleaned      Standardized
        │              │              │
        └──────────────┼──────────────┘
                       │
                 Transformation
                       │
                   Validation
                       │
                       ▼
                      ODS
                       │
                       ▼
                      DWH
                       │
                       ▼
                  DATA MART
                       │
                       ▼
                    POWER BI
```

Python should remain focused on the left side of the pipeline.

The primary transformation responsibility begins downstream with SSIS.

This separation keeps the architecture maintainable, testable, and scalable.
