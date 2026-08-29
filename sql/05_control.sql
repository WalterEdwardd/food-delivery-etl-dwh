/* =========================================================
   QUICKBITE DATA PLATFORM
   Food Delivery ETL & Data Warehouse

   PART 6 - CONTROL LAYER SETUP

   Purpose:
   Create and validate the CONTROL tables
   used for ETL batch tracking, process logging,
   and error tracking.

   Database : FoodDeliveryDW
   Schema   : control
   Platform : Microsoft SQL Server
   ========================================================= */


-- 1. CHECK DATABASE

USE FoodDeliveryDW;
GO

SELECT
    DB_NAME() AS current_database;
GO

-- Verify CONTROL schema exists

SELECT
    name AS schema_name
FROM sys.schemas
WHERE name = N'control';
GO


-- 2. CREATE CONTROL TABLES

-- 2.1 CONTROL ETL BATCH

IF OBJECT_ID(N'control.etl_batch', N'U') IS NULL
BEGIN
    CREATE TABLE control.etl_batch
    (
        batch_id            BIGINT IDENTITY(1,1) NOT NULL,
        pipeline_name       VARCHAR(100) NOT NULL,
        source_system       VARCHAR(100) NULL,
        source_file_count   INT NULL,

        start_time          DATETIME2(3) NOT NULL,
        end_time            DATETIME2(3) NULL,

        status              VARCHAR(20) NOT NULL,

        total_records       BIGINT NULL,
        success_records     BIGINT NULL,
        error_records       BIGINT NULL,

        created_at          DATETIME2(3) NOT NULL
            CONSTRAINT DF_etl_batch_created_at
            DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_etl_batch
            PRIMARY KEY CLUSTERED (batch_id),

        CONSTRAINT CK_etl_batch_status
            CHECK
            (
                status IN
                (
                    'RUNNING',
                    'SUCCESS',
                    'FAILED',
                    'PARTIAL'
                )
            )
    );
END;
GO


-- 2.2 CONTROL ETL LOG

IF OBJECT_ID(N'control.etl_log', N'U') IS NULL
BEGIN
    CREATE TABLE control.etl_log
    (
        log_id              BIGINT IDENTITY(1,1) NOT NULL,
        batch_id            BIGINT NOT NULL,

        process_name        VARCHAR(100) NOT NULL,
        step_name           VARCHAR(200) NOT NULL,

        start_time          DATETIME2(3) NOT NULL,
        end_time            DATETIME2(3) NULL,

        status              VARCHAR(20) NOT NULL,

        rows_processed      BIGINT NULL,
        rows_inserted       BIGINT NULL,
        rows_rejected       BIGINT NULL,

        message             VARCHAR(4000) NULL,

        created_at          DATETIME2(3) NOT NULL
            CONSTRAINT DF_etl_log_created_at
            DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_etl_log
            PRIMARY KEY CLUSTERED (log_id),

        CONSTRAINT FK_etl_log_batch
            FOREIGN KEY (batch_id)
            REFERENCES control.etl_batch(batch_id),

        CONSTRAINT CK_etl_log_status
            CHECK
            (
                status IN
                (
                    'RUNNING',
                    'SUCCESS',
                    'FAILED',
                    'PARTIAL'
                )
            )
    );
END;
GO


-- 2.3 CONTROL ETL ERROR

IF OBJECT_ID(N'control.etl_error', N'U') IS NULL
BEGIN
    CREATE TABLE control.etl_error
    (
        error_id             BIGINT IDENTITY(1,1) NOT NULL,
        batch_id             BIGINT NOT NULL,

        source_file_name     VARCHAR(500) NULL,
        source_row_number    BIGINT NULL,

        table_name           VARCHAR(200) NULL,
        column_name          VARCHAR(200) NULL,

        error_type           VARCHAR(100) NOT NULL,
        error_message        VARCHAR(4000) NOT NULL,

        raw_value             VARCHAR(4000) NULL,

        error_timestamp      DATETIME2(3) NOT NULL
            CONSTRAINT DF_etl_error_timestamp
            DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_etl_error
            PRIMARY KEY CLUSTERED (error_id),

        CONSTRAINT FK_etl_error_batch
            FOREIGN KEY (batch_id)
            REFERENCES control.etl_batch(batch_id)
    );
END;
GO


-- 3. CREATE INDEXES

-- 3.1 INDEX ON ETL LOG

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_etl_log_batch_id'
      AND object_id = OBJECT_ID(N'control.etl_log')
)
BEGIN
    CREATE INDEX IX_etl_log_batch_id
    ON control.etl_log(batch_id);
END;
GO


-- 3.1 INDEX ON ETL ERROR

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_etl_error_batch_id'
      AND object_id = OBJECT_ID(N'control.etl_error')
)
BEGIN
    CREATE INDEX IX_etl_error_batch_id
    ON control.etl_error(batch_id);
END;
GO


-- 4. VALIDATE CONTROL TABLES

-- 4.1 VERIFY CONTROL TABLE EXISTENCE

SELECT
    s.name AS schema_name,
    t.name AS table_name
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'control'
ORDER BY
    t.name;
GO


-- 4.2 VERIFY CONTROL TABLE COLUMNS

SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    NUMERIC_PRECISION,
    NUMERIC_SCALE,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = N'control'
ORDER BY
    TABLE_NAME,
    ORDINAL_POSITION;
GO


-- 4.3 VERIFY PRIMARY KEY CONSTRAINTS

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    kc.name AS constraint_name,
    kc.type_desc AS constraint_type
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
INNER JOIN sys.key_constraints AS kc
    ON t.object_id = kc.parent_object_id
WHERE s.name = N'control'
ORDER BY
    t.name,
    kc.name;
GO


-- 4.4 VERIFY FOREIGN KEY CONSTRAINTS

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    fk.name AS foreign_key_name,
    OBJECT_SCHEMA_NAME(fk.referenced_object_id)
        AS referenced_schema_name,
    OBJECT_NAME(fk.referenced_object_id)
        AS referenced_table_name
FROM sys.foreign_keys AS fk
INNER JOIN sys.tables AS t
    ON fk.parent_object_id = t.object_id
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'control'
ORDER BY
    t.name,
    fk.name;
GO


-- 4.5 VERIFY CHECK CONSTRAINTS

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    cc.name AS constraint_name,
    cc.definition AS check_definition
FROM sys.check_constraints AS cc
INNER JOIN sys.tables AS t
    ON cc.parent_object_id = t.object_id
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'control'
ORDER BY
    t.name,
    cc.name;
GO


-- 4.6 VERIFY DEFAULT CONSTRAINTS

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    c.name AS column_name,
    dc.name AS constraint_name,
    dc.definition AS default_definition
FROM sys.default_constraints AS dc
INNER JOIN sys.columns AS c
    ON dc.parent_object_id = c.object_id
   AND dc.parent_column_id = c.column_id
INNER JOIN sys.tables AS t
    ON c.object_id = t.object_id
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'control'
ORDER BY
    t.name,
    c.column_id;
GO


-- 4.7 VERIFY INDEXES

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    i.name AS index_name,
    i.type_desc AS index_type,
    i.is_primary_key,
    i.is_unique
FROM sys.indexes AS i
INNER JOIN sys.tables AS t
    ON i.object_id = t.object_id
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'control'
  AND i.name IS NOT NULL
ORDER BY
    t.name,
    i.name;
GO


-- 4.8 VERIFY CONTROL TABLES HAVE NO DATA

SELECT
    'etl_batch' AS table_name,
    COUNT(*) AS row_count
FROM control.etl_batch

UNION ALL

SELECT
    'etl_log',
    COUNT(*)
FROM control.etl_log

UNION ALL

SELECT
    'etl_error',
    COUNT(*)
FROM control.etl_error;
GO


-- 4.9 VERIFY CONTROL TABLE CONVENTION

SELECT
    s.name AS schema_name,
    t.name AS table_name
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'control'
  AND t.name NOT IN
  (
      N'etl_batch',
      N'etl_log',
      N'etl_error'
  )
ORDER BY
    t.name;
GO


-- 5. VERIFY ETL LINEAGE

-- 5.1 BATCH → LOG →  ERROR LINEAGE

SELECT
    b.batch_id,

    b.pipeline_name,
    b.status AS batch_status,

    l.log_id,
    l.process_name,
    l.step_name,
    l.status AS step_status,

    e.error_id,
    e.source_file_name,
    e.source_row_number,
    e.table_name,
    e.column_name,
    e.error_type,
    e.raw_value

FROM control.etl_batch AS b

LEFT JOIN control.etl_log AS l
    ON b.batch_id = l.batch_id

LEFT JOIN control.etl_error AS e
    ON b.batch_id = e.batch_id

ORDER BY
    b.batch_id,
    l.log_id,
    e.error_id;
GO


-- 6. FINAL CONTROL LAYER SUMMARY

SELECT
    'CONTROL TABLE COUNT' AS validation_name,
    COUNT(*) AS actual_count,
    3 AS expected_count,
    CASE
        WHEN COUNT(*) = 3 THEN 'PASS'
        ELSE 'FAIL'
    END AS validation_status
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'control'
  AND t.name IN
  (
      N'etl_batch',
      N'etl_log',
      N'etl_error'
  );
GO