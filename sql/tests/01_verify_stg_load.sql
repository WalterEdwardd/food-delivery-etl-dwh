/* ================================================================================
   PROJECT  : QuickBite Data Platform - Food Delivery ETL & Data Warehouse
   LAYER    : STAGING (STG) VERIFICATION
   FILE     : 01_verify_stg_load.sql
   PURPOSE  : Complete automated verification for CSV to STG data ingestion.

   CHECKS PERFORMED:
       1. STG Tables Existence & Schema Validation
       2. ETL Control Batch Status & Reconciliation
       3. Table-Level Row Count & File Ingestion Summary
       4. Metadata Completeness & NULL Checks
       5. Business Key Integrity & Non-Blank Checks
       6. Source Row Number Range Verification
       7. Source Row Number Gap / Sequence Check (Partition-Aware)
       8. Duplicate Check (Technical Row & Business Key)
       9. Referential Integrity / Orphan Records Check
       10. Sample Data Preview (All 8 STG Tables)
       11. Unified Test Summary Dashboard (PASS / FAIL)

   PLATFORM : Microsoft SQL Server
   DATABASE : FoodDeliveryDW
   ================================================================================ */

USE FoodDeliveryDW;
GO

SET NOCOUNT ON;
GO


/* ================================================================================
   0. PARAMETERS & BATCH IDENTIFICATION
   - Automatically selects the latest batch_id from control.etl_batch if not specified.
   - You can manually override @target_batch_id (e.g., SET @target_batch_id = 5;)
   ================================================================================ */

DECLARE @target_batch_id BIGINT = NULL;

IF @target_batch_id IS NULL
BEGIN
    SELECT @target_batch_id = MAX(batch_id)
    FROM control.etl_batch;
END;

IF @target_batch_id IS NULL
BEGIN
    SELECT @target_batch_id = MAX(batch_id)
    FROM stg.stg_customer;
END;

IF @target_batch_id IS NULL
BEGIN
    RAISERROR('No batch_id found in control.etl_batch or stg tables. Please run ingestion first.', 16, 1);
    RETURN;
END;

PRINT '================================================================================';
PRINT 'RUNNING STG VERIFICATION FOR BATCH_ID: ' + CAST(@target_batch_id AS VARCHAR(20));
PRINT '================================================================================';
GO


/* ================================================================================
   1. VERIFY STG TABLES EXIST
   - Verifies that all 8 required STG tables exist in the database.
   ================================================================================ */

DECLARE @target_batch_id BIGINT;
SELECT @target_batch_id = MAX(batch_id) FROM control.etl_batch;

WITH expected_tables AS
(
    SELECT 'stg_customer' AS table_name UNION ALL
    SELECT 'stg_restaurant' UNION ALL
    SELECT 'stg_menu_item' UNION ALL
    SELECT 'stg_delivery_partner' UNION ALL
    SELECT 'stg_order' UNION ALL
    SELECT 'stg_order_item' UNION ALL
    SELECT 'stg_delivery_performance' UNION ALL
    SELECT 'stg_rating'
)
SELECT
    e.table_name,
    CASE 
        WHEN t.object_id IS NOT NULL THEN 'EXISTS' 
        ELSE 'MISSING' 
    END AS table_status,
    CASE 
        WHEN t.object_id IS NOT NULL THEN 'PASS' 
        ELSE 'FAIL' 
    END AS check_status
FROM expected_tables e
LEFT JOIN sys.tables t
    ON t.name = e.table_name
   AND t.schema_id = SCHEMA_ID('stg')
ORDER BY e.table_name;
GO


/* ================================================================================
   2. CONTROL BATCH STATUS & RECONCILIATION
   - Reconciles total rows loaded across STG tables against control.etl_batch.
   ================================================================================ */

DECLARE @target_batch_id BIGINT;
SELECT @target_batch_id = MAX(batch_id) FROM control.etl_batch;

WITH stg_counts AS
(
    SELECT 'stg_customer' AS table_name, COUNT(*) AS rows_loaded FROM stg.stg_customer WHERE batch_id = @target_batch_id
    UNION ALL
    SELECT 'stg_restaurant', COUNT(*) FROM stg.stg_restaurant WHERE batch_id = @target_batch_id
    UNION ALL
    SELECT 'stg_menu_item', COUNT(*) FROM stg.stg_menu_item WHERE batch_id = @target_batch_id
    UNION ALL
    SELECT 'stg_delivery_partner', COUNT(*) FROM stg.stg_delivery_partner WHERE batch_id = @target_batch_id
    UNION ALL
    SELECT 'stg_order', COUNT(*) FROM stg.stg_order WHERE batch_id = @target_batch_id
    UNION ALL
    SELECT 'stg_order_item', COUNT(*) FROM stg.stg_order_item WHERE batch_id = @target_batch_id
    UNION ALL
    SELECT 'stg_delivery_performance', COUNT(*) FROM stg.stg_delivery_performance WHERE batch_id = @target_batch_id
    UNION ALL
    SELECT 'stg_rating', COUNT(*) FROM stg.stg_rating WHERE batch_id = @target_batch_id
),
stg_total AS
(
    SELECT SUM(rows_loaded) AS total_stg_rows, COUNT(*) AS total_stg_tables FROM stg_counts
)
SELECT
    b.batch_id,
    b.pipeline_name,
    b.source_system,
    b.source_file_count,
    st.total_stg_tables AS active_stg_tables,
    b.status AS batch_status,
    b.total_records AS control_total_records,
    b.success_records AS control_success_records,
    st.total_stg_rows AS actual_stg_rows_loaded,
    b.error_records AS control_error_records,
    b.start_time,
    b.end_time,
    DATEDIFF(SECOND, b.start_time, ISNULL(b.end_time, SYSUTCDATETIME())) AS duration_seconds,
    CASE
        WHEN b.status = 'SUCCESS' AND st.total_stg_rows = b.success_records THEN 'PASS'
        ELSE 'FAIL - RECONCILIATION MISMATCH'
    END AS reconciliation_status
FROM control.etl_batch b
CROSS JOIN stg_total st
WHERE b.batch_id = @target_batch_id;
GO


/* ================================================================================
   3. TABLE-LEVEL ROW COUNT & INGESTION SUMMARY (BATCH-AWARE)
   ================================================================================ */

DECLARE @target_batch_id BIGINT;
SELECT @target_batch_id = MAX(batch_id) FROM control.etl_batch;

SELECT
    'stg_customer' AS table_name,
    batch_id,
    source_file_name,
    COUNT(*) AS row_count,
    MIN(source_row_number) AS min_row_number,
    MAX(source_row_number) AS max_row_number,
    MIN(load_timestamp) AS min_load_timestamp,
    MAX(load_timestamp) AS max_load_timestamp
FROM stg.stg_customer
WHERE batch_id = @target_batch_id
GROUP BY batch_id, source_file_name

UNION ALL

SELECT
    'stg_restaurant',
    batch_id,
    source_file_name,
    COUNT(*),
    MIN(source_row_number),
    MAX(source_row_number),
    MIN(load_timestamp),
    MAX(load_timestamp)
FROM stg.stg_restaurant
WHERE batch_id = @target_batch_id
GROUP BY batch_id, source_file_name

UNION ALL

SELECT
    'stg_menu_item',
    batch_id,
    source_file_name,
    COUNT(*),
    MIN(source_row_number),
    MAX(source_row_number),
    MIN(load_timestamp),
    MAX(load_timestamp)
FROM stg.stg_menu_item
WHERE batch_id = @target_batch_id
GROUP BY batch_id, source_file_name

UNION ALL

SELECT
    'stg_delivery_partner',
    batch_id,
    source_file_name,
    COUNT(*),
    MIN(source_row_number),
    MAX(source_row_number),
    MIN(load_timestamp),
    MAX(load_timestamp)
FROM stg.stg_delivery_partner
WHERE batch_id = @target_batch_id
GROUP BY batch_id, source_file_name

UNION ALL

SELECT
    'stg_order',
    batch_id,
    source_file_name,
    COUNT(*),
    MIN(source_row_number),
    MAX(source_row_number),
    MIN(load_timestamp),
    MAX(load_timestamp)
FROM stg.stg_order
WHERE batch_id = @target_batch_id
GROUP BY batch_id, source_file_name

UNION ALL

SELECT
    'stg_order_item',
    batch_id,
    source_file_name,
    COUNT(*),
    MIN(source_row_number),
    MAX(source_row_number),
    MIN(load_timestamp),
    MAX(load_timestamp)
FROM stg.stg_order_item
WHERE batch_id = @target_batch_id
GROUP BY batch_id, source_file_name

UNION ALL

SELECT
    'stg_delivery_performance',
    batch_id,
    source_file_name,
    COUNT(*),
    MIN(source_row_number),
    MAX(source_row_number),
    MIN(load_timestamp),
    MAX(load_timestamp)
FROM stg.stg_delivery_performance
WHERE batch_id = @target_batch_id
GROUP BY batch_id, source_file_name

UNION ALL

SELECT
    'stg_rating',
    batch_id,
    source_file_name,
    COUNT(*),
    MIN(source_row_number),
    MAX(source_row_number),
    MIN(load_timestamp),
    MAX(load_timestamp)
FROM stg.stg_rating
WHERE batch_id = @target_batch_id
GROUP BY batch_id, source_file_name

ORDER BY table_name;
GO


/* ================================================================================
   4. METADATA COMPLETENESS & NULL CHECKS
   - Technical metadata columns must NEVER be NULL.
   - Expected: All NULL counts = 0
   ================================================================================ */

DECLARE @target_batch_id BIGINT;
SELECT @target_batch_id = MAX(batch_id) FROM control.etl_batch;

SELECT
    'stg_customer' AS table_name,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN batch_id IS NULL THEN 1 ELSE 0 END) AS null_batch_id,
    SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END) AS null_source_file_name,
    SUM(CASE WHEN source_row_number IS NULL THEN 1 ELSE 0 END) AS null_source_row_number,
    SUM(CASE WHEN load_timestamp IS NULL THEN 1 ELSE 0 END) AS null_load_timestamp
FROM stg.stg_customer
WHERE batch_id = @target_batch_id

UNION ALL

SELECT
    'stg_restaurant',
    COUNT(*),
    SUM(CASE WHEN batch_id IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_row_number IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN load_timestamp IS NULL THEN 1 ELSE 0 END)
FROM stg.stg_restaurant
WHERE batch_id = @target_batch_id

UNION ALL

SELECT
    'stg_menu_item',
    COUNT(*),
    SUM(CASE WHEN batch_id IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_row_number IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN load_timestamp IS NULL THEN 1 ELSE 0 END)
FROM stg.stg_menu_item
WHERE batch_id = @target_batch_id

UNION ALL

SELECT
    'stg_delivery_partner',
    COUNT(*),
    SUM(CASE WHEN batch_id IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_row_number IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN load_timestamp IS NULL THEN 1 ELSE 0 END)
FROM stg.stg_delivery_partner
WHERE batch_id = @target_batch_id

UNION ALL

SELECT
    'stg_order',
    COUNT(*),
    SUM(CASE WHEN batch_id IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_row_number IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN load_timestamp IS NULL THEN 1 ELSE 0 END)
FROM stg.stg_order
WHERE batch_id = @target_batch_id

UNION ALL

SELECT
    'stg_order_item',
    COUNT(*),
    SUM(CASE WHEN batch_id IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_row_number IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN load_timestamp IS NULL THEN 1 ELSE 0 END)
FROM stg.stg_order_item
WHERE batch_id = @target_batch_id

UNION ALL

SELECT
    'stg_delivery_performance',
    COUNT(*),
    SUM(CASE WHEN batch_id IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_row_number IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN load_timestamp IS NULL THEN 1 ELSE 0 END)
FROM stg.stg_delivery_performance
WHERE batch_id = @target_batch_id

UNION ALL

SELECT
    'stg_rating',
    COUNT(*),
    SUM(CASE WHEN batch_id IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_row_number IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN load_timestamp IS NULL THEN 1 ELSE 0 END)
FROM stg.stg_rating
WHERE batch_id = @target_batch_id

ORDER BY table_name;
GO


/* ================================================================================
   5. BUSINESS KEY INTEGRITY & NON-BLANK CHECK
   - Key identifier columns must NOT be NULL and NOT be empty string ''.
   - Expected: invalid_key_count = 0 for all tables.
   ================================================================================ */

DECLARE @target_batch_id BIGINT;
SELECT @target_batch_id = MAX(batch_id) FROM control.etl_batch;

SELECT
    'stg_customer' AS table_name,
    'customer_id' AS key_column,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN customer_id IS NULL OR LTRIM(RTRIM(customer_id)) = '' THEN 1 ELSE 0 END) AS invalid_key_count
FROM stg.stg_customer
WHERE batch_id = @target_batch_id

UNION ALL

SELECT
    'stg_restaurant',
    'restaurant_id',
    COUNT(*),
    SUM(CASE WHEN restaurant_id IS NULL OR LTRIM(RTRIM(restaurant_id)) = '' THEN 1 ELSE 0 END)
FROM stg.stg_restaurant
WHERE batch_id = @target_batch_id

UNION ALL

SELECT
    'stg_menu_item',
    'menu_item_id',
    COUNT(*),
    SUM(CASE WHEN menu_item_id IS NULL OR LTRIM(RTRIM(menu_item_id)) = '' THEN 1 ELSE 0 END)
FROM stg.stg_menu_item
WHERE batch_id = @target_batch_id

UNION ALL

SELECT
    'stg_delivery_partner',
    'delivery_partner_id',
    COUNT(*),
    SUM(CASE WHEN delivery_partner_id IS NULL OR LTRIM(RTRIM(delivery_partner_id)) = '' THEN 1 ELSE 0 END)
FROM stg.stg_delivery_partner
WHERE batch_id = @target_batch_id

UNION ALL

SELECT
    'stg_order',
    'order_id',
    COUNT(*),
    SUM(CASE WHEN order_id IS NULL OR LTRIM(RTRIM(order_id)) = '' THEN 1 ELSE 0 END)
FROM stg.stg_order
WHERE batch_id = @target_batch_id

UNION ALL

SELECT
    'stg_order_item',
    'order_line_id',
    COUNT(*),
    SUM(CASE WHEN order_line_id IS NULL OR LTRIM(RTRIM(order_line_id)) = '' THEN 1 ELSE 0 END)
FROM stg.stg_order_item
WHERE batch_id = @target_batch_id

UNION ALL

SELECT
    'stg_delivery_performance',
    'delivery_id',
    COUNT(*),
    SUM(CASE WHEN delivery_id IS NULL OR LTRIM(RTRIM(delivery_id)) = '' THEN 1 ELSE 0 END)
FROM stg.stg_delivery_performance
WHERE batch_id = @target_batch_id

UNION ALL

SELECT
    'stg_rating',
    'rating_id',
    COUNT(*),
    SUM(CASE WHEN rating_id IS NULL OR LTRIM(RTRIM(rating_id)) = '' THEN 1 ELSE 0 END)
FROM stg.stg_rating
WHERE batch_id = @target_batch_id

ORDER BY table_name;
GO


/* ================================================================================
   6. SOURCE ROW NUMBER RANGE VERIFICATION
   - First data row in CSV must start at row 2 (row 1 is CSV header).
   - Last row must equal row_count + 1.
   - Expected status = 'PASS'
   ================================================================================ */

DECLARE @target_batch_id BIGINT;
SELECT @target_batch_id = MAX(batch_id) FROM control.etl_batch;

WITH table_ranges AS
(
    SELECT 'stg_customer' AS table_name, source_file_name, MIN(source_row_number) AS min_row, MAX(source_row_number) AS max_row, COUNT(*) AS row_count FROM stg.stg_customer WHERE batch_id = @target_batch_id GROUP BY source_file_name
    UNION ALL
    SELECT 'stg_restaurant', source_file_name, MIN(source_row_number), MAX(source_row_number), COUNT(*) FROM stg.stg_restaurant WHERE batch_id = @target_batch_id GROUP BY source_file_name
    UNION ALL
    SELECT 'stg_menu_item', source_file_name, MIN(source_row_number), MAX(source_row_number), COUNT(*) FROM stg.stg_menu_item WHERE batch_id = @target_batch_id GROUP BY source_file_name
    UNION ALL
    SELECT 'stg_delivery_partner', source_file_name, MIN(source_row_number), MAX(source_row_number), COUNT(*) FROM stg.stg_delivery_partner WHERE batch_id = @target_batch_id GROUP BY source_file_name
    UNION ALL
    SELECT 'stg_order', source_file_name, MIN(source_row_number), MAX(source_row_number), COUNT(*) FROM stg.stg_order WHERE batch_id = @target_batch_id GROUP BY source_file_name
    UNION ALL
    SELECT 'stg_order_item', source_file_name, MIN(source_row_number), MAX(source_row_number), COUNT(*) FROM stg.stg_order_item WHERE batch_id = @target_batch_id GROUP BY source_file_name
    UNION ALL
    SELECT 'stg_delivery_performance', source_file_name, MIN(source_row_number), MAX(source_row_number), COUNT(*) FROM stg.stg_delivery_performance WHERE batch_id = @target_batch_id GROUP BY source_file_name
    UNION ALL
    SELECT 'stg_rating', source_file_name, MIN(source_row_number), MAX(source_row_number), COUNT(*) FROM stg.stg_rating WHERE batch_id = @target_batch_id GROUP BY source_file_name
)
SELECT
    table_name,
    source_file_name,
    row_count,
    min_row,
    max_row,
    (max_row - min_row + 1) AS calculated_span,
    CASE
        WHEN min_row = 2 AND (max_row - min_row + 1) = row_count THEN 'PASS'
        ELSE 'FAIL - UNEXPECTED ROW NUMBER RANGE'
    END AS range_status
FROM table_ranges
ORDER BY table_name;
GO


/* ================================================================================
   7. SOURCE ROW NUMBER GAP CHECK (PARTITION-AWARE)
   - Checks if any row numbers were skipped during CSV chunk ingestion.
   - Expected: 0 rows returned.
   ================================================================================ */

DECLARE @target_batch_id BIGINT;
SELECT @target_batch_id = MAX(batch_id) FROM control.etl_batch;

WITH numbered AS
(
    SELECT
        'stg_customer' AS table_name,
        source_file_name,
        source_row_number,
        LAG(source_row_number) OVER (
            PARTITION BY batch_id, source_file_name
            ORDER BY source_row_number
        ) AS previous_row_number
    FROM stg.stg_customer
    WHERE batch_id = @target_batch_id

    UNION ALL

    SELECT
        'stg_restaurant',
        source_file_name,
        source_row_number,
        LAG(source_row_number) OVER (
            PARTITION BY batch_id, source_file_name
            ORDER BY source_row_number
        ) AS previous_row_number
    FROM stg.stg_restaurant
    WHERE batch_id = @target_batch_id

    UNION ALL

    SELECT
        'stg_menu_item',
        source_file_name,
        source_row_number,
        LAG(source_row_number) OVER (
            PARTITION BY batch_id, source_file_name
            ORDER BY source_row_number
        ) AS previous_row_number
    FROM stg.stg_menu_item
    WHERE batch_id = @target_batch_id

    UNION ALL

    SELECT
        'stg_delivery_partner',
        source_file_name,
        source_row_number,
        LAG(source_row_number) OVER (
            PARTITION BY batch_id, source_file_name
            ORDER BY source_row_number
        ) AS previous_row_number
    FROM stg.stg_delivery_partner
    WHERE batch_id = @target_batch_id

    UNION ALL

    SELECT
        'stg_order',
        source_file_name,
        source_row_number,
        LAG(source_row_number) OVER (
            PARTITION BY batch_id, source_file_name
            ORDER BY source_row_number
        ) AS previous_row_number
    FROM stg.stg_order
    WHERE batch_id = @target_batch_id

    UNION ALL

    SELECT
        'stg_order_item',
        source_file_name,
        source_row_number,
        LAG(source_row_number) OVER (
            PARTITION BY batch_id, source_file_name
            ORDER BY source_row_number
        ) AS previous_row_number
    FROM stg.stg_order_item
    WHERE batch_id = @target_batch_id

    UNION ALL

    SELECT
        'stg_delivery_performance',
        source_file_name,
        source_row_number,
        LAG(source_row_number) OVER (
            PARTITION BY batch_id, source_file_name
            ORDER BY source_row_number
        ) AS previous_row_number
    FROM stg.stg_delivery_performance
    WHERE batch_id = @target_batch_id

    UNION ALL

    SELECT
        'stg_rating',
        source_file_name,
        source_row_number,
        LAG(source_row_number) OVER (
            PARTITION BY batch_id, source_file_name
            ORDER BY source_row_number
        ) AS previous_row_number
    FROM stg.stg_rating
    WHERE batch_id = @target_batch_id
)
SELECT
    table_name,
    source_file_name,
    previous_row_number,
    source_row_number,
    (source_row_number - previous_row_number - 1) AS missing_rows_count
FROM numbered
WHERE previous_row_number IS NOT NULL
  AND source_row_number <> previous_row_number + 1;
GO


/* ================================================================================
   8. DUPLICATE ROW CHECK
   8.1 Technical Row Duplicate: Same file and row_number loaded twice.
   8.2 Business Key Duplicate: Same business entity key appears multiple times.
   - Expected: 0 rows returned.
   ================================================================================ */

DECLARE @target_batch_id BIGINT;
SELECT @target_batch_id = MAX(batch_id) FROM control.etl_batch;

-- 8.1 Technical Row Number Duplicates
SELECT
    'stg_customer' AS table_name,
    'Technical Row Duplicate' AS check_type,
    source_file_name,
    CAST(source_row_number AS VARCHAR(50)) AS duplicate_identifier,
    COUNT(*) AS duplicate_count
FROM stg.stg_customer
WHERE batch_id = @target_batch_id
GROUP BY source_file_name, source_row_number
HAVING COUNT(*) > 1

UNION ALL

SELECT
    'stg_restaurant',
    'Technical Row Duplicate',
    source_file_name,
    CAST(source_row_number AS VARCHAR(50)),
    COUNT(*)
FROM stg.stg_restaurant
WHERE batch_id = @target_batch_id
GROUP BY source_file_name, source_row_number
HAVING COUNT(*) > 1

UNION ALL

SELECT
    'stg_order',
    'Technical Row Duplicate',
    source_file_name,
    CAST(source_row_number AS VARCHAR(50)),
    COUNT(*)
FROM stg.stg_order
WHERE batch_id = @target_batch_id
GROUP BY source_file_name, source_row_number
HAVING COUNT(*) > 1

UNION ALL

-- 8.2 Business Key Duplicates
SELECT
    'stg_customer',
    'Business Key Duplicate',
    source_file_name,
    customer_id,
    COUNT(*)
FROM stg.stg_customer
WHERE batch_id = @target_batch_id
GROUP BY source_file_name, customer_id
HAVING COUNT(*) > 1

UNION ALL

SELECT
    'stg_restaurant',
    'Business Key Duplicate',
    source_file_name,
    restaurant_id,
    COUNT(*)
FROM stg.stg_restaurant
WHERE batch_id = @target_batch_id
GROUP BY source_file_name, restaurant_id
HAVING COUNT(*) > 1

UNION ALL

SELECT
    'stg_order',
    'Business Key Duplicate',
    source_file_name,
    order_id,
    COUNT(*)
FROM stg.stg_order
WHERE batch_id = @target_batch_id
GROUP BY source_file_name, order_id
HAVING COUNT(*) > 1

ORDER BY table_name, check_type;
GO


/* ================================================================================
   9. REFERENTIAL INTEGRITY / ORPHAN RECORDS CHECK
   - Verifies cross-file consistency within the same batch.
   - Expected: orphan_records_count = 0 for all checks.
   ================================================================================ */

DECLARE @target_batch_id BIGINT;
SELECT @target_batch_id = MAX(batch_id) FROM control.etl_batch;

-- 1. Orders with invalid customer_id
SELECT
    'stg_order -> stg_customer' AS relationship,
    'Orders referencing non-existent customer_id' AS issue_description,
    COUNT(*) AS orphan_records_count
FROM stg.stg_order o
WHERE o.batch_id = @target_batch_id
  AND NOT EXISTS (
      SELECT 1 FROM stg.stg_customer c
      WHERE c.batch_id = @target_batch_id
        AND c.customer_id = o.customer_id
  )

UNION ALL

-- 2. Orders with invalid restaurant_id
SELECT
    'stg_order -> stg_restaurant',
    'Orders referencing non-existent restaurant_id',
    COUNT(*)
FROM stg.stg_order o
WHERE o.batch_id = @target_batch_id
  AND NOT EXISTS (
      SELECT 1 FROM stg.stg_restaurant r
      WHERE r.batch_id = @target_batch_id
        AND r.restaurant_id = o.restaurant_id
  )

UNION ALL

-- 3. Order items with invalid order_id
SELECT
    'stg_order_item -> stg_order',
    'Order items referencing non-existent order_id',
    COUNT(*)
FROM stg.stg_order_item oi
WHERE oi.batch_id = @target_batch_id
  AND NOT EXISTS (
      SELECT 1 FROM stg.stg_order o
      WHERE o.batch_id = @target_batch_id
        AND o.order_id = oi.order_id
  )

UNION ALL

-- 4. Delivery performance with invalid order_id
SELECT
    'stg_delivery_performance -> stg_order',
    'Delivery performance referencing non-existent order_id',
    COUNT(*)
FROM stg.stg_delivery_performance dp
WHERE dp.batch_id = @target_batch_id
  AND NOT EXISTS (
      SELECT 1 FROM stg.stg_order o
      WHERE o.batch_id = @target_batch_id
        AND o.order_id = dp.order_id
  )

UNION ALL

-- 5. Ratings with invalid order_id
SELECT
    'stg_rating -> stg_order',
    'Ratings referencing non-existent order_id',
    COUNT(*)
FROM stg.stg_rating rt
WHERE rt.batch_id = @target_batch_id
  AND NOT EXISTS (
      SELECT 1 FROM stg.stg_order o
      WHERE o.batch_id = @target_batch_id
        AND o.order_id = rt.order_id
  );
GO


/* ================================================================================
   10. SAMPLE DATA PREVIEW (ALL 8 STG TABLES)
   - Visual inspection of raw preserved strings across all tables.
   ================================================================================ */

DECLARE @target_batch_id BIGINT;
SELECT @target_batch_id = MAX(batch_id) FROM control.etl_batch;

PRINT '--- 10.1 SAMPLE: CUSTOMER ---';
SELECT TOP (5) customer_id, signup_date, city, acquisition_channel, batch_id, source_file_name, source_row_number, load_timestamp
FROM stg.stg_customer WHERE batch_id = @target_batch_id ORDER BY source_row_number;

PRINT '--- 10.2 SAMPLE: RESTAURANT ---';
SELECT TOP (5) restaurant_id, restaurant_name, city, cuisine_type, partner_type, avg_prep_time_min, is_active, batch_id, source_file_name, source_row_number, load_timestamp
FROM stg.stg_restaurant WHERE batch_id = @target_batch_id ORDER BY source_row_number;

PRINT '--- 10.3 SAMPLE: MENU ITEM ---';
SELECT TOP (5) menu_item_id, restaurant_id, item_name, category, is_veg, price, batch_id, source_file_name, source_row_number, load_timestamp
FROM stg.stg_menu_item WHERE batch_id = @target_batch_id ORDER BY source_row_number;

PRINT '--- 10.4 SAMPLE: DELIVERY PARTNER ---';
SELECT TOP (5) delivery_partner_id, partner_name, city, vehicle_type, employment_type, avg_rating, is_active, batch_id, source_file_name, source_row_number, load_timestamp
FROM stg.stg_delivery_partner WHERE batch_id = @target_batch_id ORDER BY source_row_number;

PRINT '--- 10.5 SAMPLE: ORDER ---';
SELECT TOP (5) order_id, customer_id, restaurant_id, delivery_partner_id, order_timestamp, subtotal_amount, discount_amount, delivery_fee, total_amount, is_cod, is_cancelled, batch_id, source_file_name, source_row_number, load_timestamp
FROM stg.stg_order WHERE batch_id = @target_batch_id ORDER BY source_row_number;

PRINT '--- 10.6 SAMPLE: ORDER ITEM ---';
SELECT TOP (5) order_line_id, order_id, menu_item_id, restaurant_id, quantity, unit_price, item_discount, line_total, batch_id, source_file_name, source_row_number, load_timestamp
FROM stg.stg_order_item WHERE batch_id = @target_batch_id ORDER BY source_row_number;

PRINT '--- 10.7 SAMPLE: DELIVERY PERFORMANCE ---';
SELECT TOP (5) delivery_id, order_id, order_item, expected_delivery_time_min, actual_delivery_time_min, delivery_item, distance_km, batch_id, source_file_name, source_row_number, load_timestamp
FROM stg.stg_delivery_performance WHERE batch_id = @target_batch_id ORDER BY source_row_number;

PRINT '--- 10.8 SAMPLE: RATING ---';
SELECT TOP (5) rating_id, order_id, customer_id, restaurant_id, rating, sentiment_score, review_text, review_timestamp, batch_id, source_file_name, source_row_number, load_timestamp
FROM stg.stg_rating WHERE batch_id = @target_batch_id ORDER BY source_row_number;
GO


/* ================================================================================
   11. UNIFIED TEST SUMMARY DASHBOARD
   - Aggregates all automated test assertions into a single PASS/FAIL scorecard.
   ================================================================================ */

DECLARE @target_batch_id BIGINT;
SELECT @target_batch_id = MAX(batch_id) FROM control.etl_batch;

WITH stg_counts AS
(
    SELECT 'stg_customer' AS tbl, COUNT(*) AS cnt FROM stg.stg_customer WHERE batch_id = @target_batch_id
    UNION ALL SELECT 'stg_restaurant', COUNT(*) FROM stg.stg_restaurant WHERE batch_id = @target_batch_id
    UNION ALL SELECT 'stg_menu_item', COUNT(*) FROM stg.stg_menu_item WHERE batch_id = @target_batch_id
    UNION ALL SELECT 'stg_delivery_partner', COUNT(*) FROM stg.stg_delivery_partner WHERE batch_id = @target_batch_id
    UNION ALL SELECT 'stg_order', COUNT(*) FROM stg.stg_order WHERE batch_id = @target_batch_id
    UNION ALL SELECT 'stg_order_item', COUNT(*) FROM stg.stg_order_item WHERE batch_id = @target_batch_id
    UNION ALL SELECT 'stg_delivery_performance', COUNT(*) FROM stg.stg_delivery_performance WHERE batch_id = @target_batch_id
    UNION ALL SELECT 'stg_rating', COUNT(*) FROM stg.stg_rating WHERE batch_id = @target_batch_id
),
test_results AS
(
    -- 1. Table existence (Expect 8 tables)
    SELECT
        1 AS test_id,
        'STG Tables Existence' AS test_name,
        CASE WHEN COUNT(*) = 8 THEN 'PASS' ELSE 'FAIL' END AS status,
        CONCAT('Found ', COUNT(*), '/8 STG tables') AS details
    FROM sys.tables
    WHERE schema_id = SCHEMA_ID('stg')

    UNION ALL

    -- 2. Control Batch Status
    SELECT
        2,
        'ETL Batch Status',
        CASE WHEN status = 'SUCCESS' THEN 'PASS' ELSE 'FAIL' END,
        CONCAT('Batch status: ', status, ' (batch_id=', @target_batch_id, ')')
    FROM control.etl_batch
    WHERE batch_id = @target_batch_id

    UNION ALL

    -- 3. Row Count Reconciliation with Control
    SELECT
        3,
        'Row Count Reconciliation',
        CASE WHEN (SELECT SUM(cnt) FROM stg_counts) = b.success_records THEN 'PASS' ELSE 'FAIL' END,
        CONCAT('STG rows: ', (SELECT SUM(cnt) FROM stg_counts), ' | Control success_records: ', b.success_records)
    FROM control.etl_batch b
    WHERE b.batch_id = @target_batch_id

    UNION ALL

    -- 4. Metadata NULL Check
    SELECT
        4,
        'Metadata NULL Check',
        CASE WHEN SUM(null_cnt) = 0 THEN 'PASS' ELSE 'FAIL' END,
        CONCAT('Total NULL metadata occurrences: ', SUM(null_cnt))
    FROM
    (
        SELECT SUM(CASE WHEN batch_id IS NULL OR source_file_name IS NULL OR source_row_number IS NULL OR load_timestamp IS NULL THEN 1 ELSE 0 END) AS null_cnt FROM stg.stg_customer WHERE batch_id = @target_batch_id
        UNION ALL SELECT SUM(CASE WHEN batch_id IS NULL OR source_file_name IS NULL OR source_row_number IS NULL OR load_timestamp IS NULL THEN 1 ELSE 0 END) FROM stg.stg_restaurant WHERE batch_id = @target_batch_id
        UNION ALL SELECT SUM(CASE WHEN batch_id IS NULL OR source_file_name IS NULL OR source_row_number IS NULL OR load_timestamp IS NULL THEN 1 ELSE 0 END) FROM stg.stg_menu_item WHERE batch_id = @target_batch_id
        UNION ALL SELECT SUM(CASE WHEN batch_id IS NULL OR source_file_name IS NULL OR source_row_number IS NULL OR load_timestamp IS NULL THEN 1 ELSE 0 END) FROM stg.stg_delivery_partner WHERE batch_id = @target_batch_id
        UNION ALL SELECT SUM(CASE WHEN batch_id IS NULL OR source_file_name IS NULL OR source_row_number IS NULL OR load_timestamp IS NULL THEN 1 ELSE 0 END) FROM stg.stg_order WHERE batch_id = @target_batch_id
        UNION ALL SELECT SUM(CASE WHEN batch_id IS NULL OR source_file_name IS NULL OR source_row_number IS NULL OR load_timestamp IS NULL THEN 1 ELSE 0 END) FROM stg.stg_order_item WHERE batch_id = @target_batch_id
        UNION ALL SELECT SUM(CASE WHEN batch_id IS NULL OR source_file_name IS NULL OR source_row_number IS NULL OR load_timestamp IS NULL THEN 1 ELSE 0 END) FROM stg.stg_delivery_performance WHERE batch_id = @target_batch_id
        UNION ALL SELECT SUM(CASE WHEN batch_id IS NULL OR source_file_name IS NULL OR source_row_number IS NULL OR load_timestamp IS NULL THEN 1 ELSE 0 END) FROM stg.stg_rating WHERE batch_id = @target_batch_id
    ) m

    UNION ALL

    -- 5. Business Key Blank/NULL Check
    SELECT
        5,
        'Business Key Integrity Check',
        CASE WHEN SUM(bad_keys) = 0 THEN 'PASS' ELSE 'FAIL' END,
        CONCAT('Total blank/null keys: ', SUM(bad_keys))
    FROM
    (
        SELECT SUM(CASE WHEN customer_id IS NULL OR LTRIM(RTRIM(customer_id)) = '' THEN 1 ELSE 0 END) AS bad_keys FROM stg.stg_customer WHERE batch_id = @target_batch_id
        UNION ALL SELECT SUM(CASE WHEN restaurant_id IS NULL OR LTRIM(RTRIM(restaurant_id)) = '' THEN 1 ELSE 0 END) FROM stg.stg_restaurant WHERE batch_id = @target_batch_id
        UNION ALL SELECT SUM(CASE WHEN menu_item_id IS NULL OR LTRIM(RTRIM(menu_item_id)) = '' THEN 1 ELSE 0 END) FROM stg.stg_menu_item WHERE batch_id = @target_batch_id
        UNION ALL SELECT SUM(CASE WHEN delivery_partner_id IS NULL OR LTRIM(RTRIM(delivery_partner_id)) = '' THEN 1 ELSE 0 END) FROM stg.stg_delivery_partner WHERE batch_id = @target_batch_id
        UNION ALL SELECT SUM(CASE WHEN order_id IS NULL OR LTRIM(RTRIM(order_id)) = '' THEN 1 ELSE 0 END) FROM stg.stg_order WHERE batch_id = @target_batch_id
        UNION ALL SELECT SUM(CASE WHEN order_line_id IS NULL OR LTRIM(RTRIM(order_line_id)) = '' THEN 1 ELSE 0 END) FROM stg.stg_order_item WHERE batch_id = @target_batch_id
        UNION ALL SELECT SUM(CASE WHEN delivery_id IS NULL OR LTRIM(RTRIM(delivery_id)) = '' THEN 1 ELSE 0 END) FROM stg.stg_delivery_performance WHERE batch_id = @target_batch_id
        UNION ALL SELECT SUM(CASE WHEN rating_id IS NULL OR LTRIM(RTRIM(rating_id)) = '' THEN 1 ELSE 0 END) FROM stg.stg_rating WHERE batch_id = @target_batch_id
    ) k
)
SELECT
    test_id,
    test_name,
    status,
    details,
    SYSUTCDATETIME() AS evaluated_at
FROM test_results
ORDER BY test_id;
GO
