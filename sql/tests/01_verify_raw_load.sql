/*
================================================================================
PROJECT : Food Delivery ETL & Data Warehouse
FILE    : 01_verify_raw_load.sql
PURPOSE : Production Post-load Verification & Audit for the RAW Layer
================================================================================
TEST SCOPE
================================================================================
This script performs a STRICTLY READ-ONLY audit and verification on the RAW layer
for a completed batch. It does NOT modify or delete data, and does NOT depend on
transient STG tables (which are purged post-load in production).

Audit Checks:
    01. Environment validation (FoodDeliveryDW)
    02. Batch existence and SUCCESS status in control.etl_batch
    03. RAW table existence (all 8 tables in schema 'raw')
    04. Row count reconciliation (raw.* vs control.etl_log rows_inserted)
    05. Lineage key uniqueness in RAW (batch_id + source_file_name + source_row_number)
    06. Metadata completeness (batch_id, file name, row number, load timestamp)
    07. Business Key completeness (no NULL or blank business keys)
    08. Schema drift verification (new columns: onboard_date, prep_time...)
    09. Final test summary and assertion
================================================================================
*/

USE FoodDeliveryDW;
GO

SET NOCOUNT ON;
GO


/*==============================================================================
  0. BATCH CONFIGURATION
==============================================================================*/

-- Set @batch_id to a specific batch number, or leave NULL to auto-select the latest batch
DECLARE @batch_id BIGINT = NULL;

IF @batch_id IS NULL
BEGIN
    SELECT @batch_id = MAX(batch_id)
    FROM control.etl_batch
    WHERE status = 'SUCCESS';

    IF @batch_id IS NULL
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM raw.raw_order;
    END;
END;

PRINT CONCAT('>>> [AUDIT SCOPE] Running RAW Verification Tests for BATCH_ID = ', ISNULL(CAST(@batch_id AS VARCHAR), 'NONE'));


/*==============================================================================
  1. TEST RESULT TABLE
==============================================================================*/

IF OBJECT_ID('tempdb..#test_results') IS NOT NULL
    DROP TABLE #test_results;

CREATE TABLE #test_results
(
    test_id         INT IDENTITY(1,1),
    test_name       VARCHAR(200) NOT NULL,
    entity_name     VARCHAR(100) NULL,
    expected_value  VARCHAR(500) NULL,
    actual_value    VARCHAR(500) NULL,
    status          VARCHAR(20) NOT NULL,
    error_message   VARCHAR(1000) NULL,
    test_timestamp  DATETIME2(3) NOT NULL DEFAULT SYSDATETIME()
);


/*==============================================================================
  2. ENVIRONMENT VALIDATION
==============================================================================*/

IF DB_NAME() = 'FoodDeliveryDW'
BEGIN
    INSERT INTO #test_results (test_name, expected_value, actual_value, status)
    VALUES ('Environment validation', 'FoodDeliveryDW', DB_NAME(), 'PASS');
END
ELSE
BEGIN
    INSERT INTO #test_results (test_name, expected_value, actual_value, status, error_message)
    VALUES ('Environment validation', 'FoodDeliveryDW', DB_NAME(), 'FAIL', 'Script must be executed against FoodDeliveryDW.');
END;


/*==============================================================================
  3. BATCH STATUS VALIDATION
==============================================================================*/

IF EXISTS (
    SELECT 1 
    FROM control.etl_batch 
    WHERE batch_id = @batch_id 
      AND status = 'SUCCESS'
)
BEGIN
    INSERT INTO #test_results (test_name, expected_value, actual_value, status)
    SELECT 
        'Batch status check',
        'SUCCESS',
        status,
        'PASS'
    FROM control.etl_batch
    WHERE batch_id = @batch_id;
END
ELSE
BEGIN
    INSERT INTO #test_results (test_name, expected_value, actual_value, status, error_message)
    VALUES (
        'Batch status check',
        'SUCCESS',
        ISNULL((SELECT status FROM control.etl_batch WHERE batch_id = @batch_id), 'NOT_FOUND'),
        'FAIL',
        'Batch does not exist or did not finish with SUCCESS status.'
    );
END;


/*==============================================================================
  4. RAW SCHEMA & TABLES EXISTENCE (8 ENTITIES)
==============================================================================*/

DECLARE @expected_raw_tables TABLE (table_name VARCHAR(100));
INSERT INTO @expected_raw_tables (table_name)
VALUES 
    ('raw_customer'),
    ('raw_restaurant'),
    ('raw_menu_item'),
    ('raw_delivery_partner'),
    ('raw_order'),
    ('raw_order_item'),
    ('raw_delivery_performance'),
    ('raw_rating');

INSERT INTO #test_results (test_name, entity_name, expected_value, actual_value, status, error_message)
SELECT 
    'Table existence - RAW',
    e.table_name,
    'EXISTS',
    CASE WHEN t.name IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END,
    CASE WHEN t.name IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
    CASE WHEN t.name IS NULL THEN CONCAT('Table raw.', e.table_name, ' is missing.') ELSE NULL END
FROM @expected_raw_tables e
LEFT JOIN sys.tables t 
    ON t.name = e.table_name 
   AND t.schema_id = SCHEMA_ID('raw');


/*==============================================================================
  5. ROW COUNT RECONCILIATION: RAW VS CONTROL.ETL_LOG
==============================================================================*/

DECLARE @raw_reconciliation TABLE
(
    entity_name VARCHAR(100),
    step_name   VARCHAR(100),
    raw_table   VARCHAR(100)
);

INSERT INTO @raw_reconciliation VALUES
    ('customer',             'LOAD_CUSTOMER',             'raw_customer'),
    ('restaurant',           'LOAD_RESTAURANT',           'raw_restaurant'),
    ('menu_item',            'LOAD_MENU_ITEM',            'raw_menu_item'),
    ('delivery_partner',     'LOAD_DELIVERY_PARTNER',     'raw_delivery_partner'),
    ('order',                'LOAD_ORDER',                'raw_order'),
    ('order_item',           'LOAD_ORDER_ITEM',           'raw_order_item'),
    ('delivery_performance', 'LOAD_DELIVERY_PERFORMANCE', 'raw_delivery_performance'),
    ('rating',               'LOAD_RATING',               'raw_rating');

DECLARE @cur_entity VARCHAR(100), @cur_step VARCHAR(100), @cur_table VARCHAR(100);
DECLARE @cur_raw_cnt BIGINT, @cur_log_cnt BIGINT;
DECLARE @sql_cnt NVARCHAR(1000);

DECLARE rec_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT entity_name, step_name, raw_table FROM @raw_reconciliation;

OPEN rec_cursor;
FETCH NEXT FROM rec_cursor INTO @cur_entity, @cur_step, @cur_table;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Query raw count for this batch
    SET @sql_cnt = N'SELECT @cnt = COUNT_BIG(*) FROM raw.' + QUOTENAME(@cur_table) + N' WHERE batch_id = @b_id;';
    EXEC sp_executesql @sql_cnt, N'@b_id BIGINT, @cnt BIGINT OUTPUT', @b_id = @batch_id, @cnt = @cur_raw_cnt OUTPUT;

    -- Query logged rows_inserted from control.etl_log
    SELECT @cur_log_cnt = rows_inserted
    FROM control.etl_log
    WHERE batch_id = @batch_id
      AND step_name = @cur_step
      AND status = 'SUCCESS';

    INSERT INTO #test_results (test_name, entity_name, expected_value, actual_value, status, error_message)
    VALUES
    (
        'Row count reconciliation (RAW vs Log)',
        @cur_entity,
        CONCAT('Logged rows = ', ISNULL(CAST(@cur_log_cnt AS VARCHAR), 'NULL')),
        CONCAT('RAW rows = ', ISNULL(CAST(@cur_raw_cnt AS VARCHAR), '0')),
        CASE 
            WHEN @cur_raw_cnt > 0 AND @cur_raw_cnt = @cur_log_cnt THEN 'PASS'
            ELSE 'FAIL'
        END,
        CASE 
            WHEN @cur_raw_cnt = 0 THEN 'RAW table has 0 rows for this batch.'
            WHEN @cur_raw_cnt <> @cur_log_cnt THEN 'Mismatch between actual RAW count and logged count.'
            ELSE NULL
        END
    );

    FETCH NEXT FROM rec_cursor INTO @cur_entity, @cur_step, @cur_table;
END;

CLOSE rec_cursor;
DEALLOCATE rec_cursor;


/*==============================================================================
  6. LINEAGE KEY UNIQUENESS IN RAW (batch_id + source_file_name + source_row_number)
==============================================================================*/

DECLARE line_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT entity_name, raw_table FROM @raw_reconciliation;

OPEN line_cursor;
FETCH NEXT FROM line_cursor INTO @cur_entity, @cur_table;

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @dup_cnt BIGINT = 0;
    SET @sql_cnt = N'
        SELECT @cnt = COUNT_BIG(*)
        FROM (
            SELECT batch_id, source_file_name, source_row_number
            FROM raw.' + QUOTENAME(@cur_table) + N'
            WHERE batch_id = @b_id
            GROUP BY batch_id, source_file_name, source_row_number
            HAVING COUNT_BIG(*) > 1
        ) d;';
    EXEC sp_executesql @sql_cnt, N'@b_id BIGINT, @cnt BIGINT OUTPUT', @b_id = @batch_id, @cnt = @dup_cnt OUTPUT;

    INSERT INTO #test_results (test_name, entity_name, expected_value, actual_value, status, error_message)
    VALUES
    (
        'Lineage key uniqueness in RAW',
        @cur_entity,
        '0 duplicates',
        CONCAT(@dup_cnt, ' duplicates'),
        CASE WHEN @dup_cnt = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @dup_cnt > 0 THEN CONCAT('Found ', @dup_cnt, ' duplicate lineage records.') ELSE NULL END
    );

    FETCH NEXT FROM line_cursor INTO @cur_entity, @cur_table;
END;

CLOSE line_cursor;
DEALLOCATE line_cursor;


/*==============================================================================
  7. METADATA COMPLETENESS (NO NULL OR EMPTY METADATA IN RAW)
==============================================================================*/

DECLARE meta_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT entity_name, raw_table FROM @raw_reconciliation;

OPEN meta_cursor;
FETCH NEXT FROM meta_cursor INTO @cur_entity, @cur_table;

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @invalid_meta_cnt BIGINT = 0;
    SET @sql_cnt = N'
        SELECT @cnt = COUNT_BIG(*)
        FROM raw.' + QUOTENAME(@cur_table) + N'
        WHERE batch_id = @b_id
          AND (
               source_file_name IS NULL 
            OR LTRIM(RTRIM(source_file_name)) = ''''
            OR source_row_number IS NULL 
            OR source_row_number < 2
            OR load_timestamp IS NULL
          );';
    EXEC sp_executesql @sql_cnt, N'@b_id BIGINT, @cnt BIGINT OUTPUT', @b_id = @batch_id, @cnt = @invalid_meta_cnt OUTPUT;

    INSERT INTO #test_results (test_name, entity_name, expected_value, actual_value, status, error_message)
    VALUES
    (
        'Metadata completeness in RAW',
        @cur_entity,
        '0 invalid records',
        CONCAT(@invalid_meta_cnt, ' invalid records'),
        CASE WHEN @invalid_meta_cnt = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @invalid_meta_cnt > 0 THEN 'Found records with NULL or invalid audit metadata.' ELSE NULL END
    );

    FETCH NEXT FROM meta_cursor INTO @cur_entity, @cur_table;
END;

CLOSE meta_cursor;
DEALLOCATE meta_cursor;


/*==============================================================================
  8. NATURAL BUSINESS KEY COMPLETENESS
==============================================================================*/

-- 8.1 Customer
INSERT INTO #test_results (test_name, entity_name, expected_value, actual_value, status, error_message)
SELECT
    'Business Key completeness',
    'customer',
    '0 NULL/empty customer_id',
    CONCAT(COUNT_BIG(*), ' invalid'),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL
FROM raw.raw_customer
WHERE batch_id = @batch_id AND (customer_id IS NULL OR LTRIM(RTRIM(customer_id)) = '');

-- 8.2 Restaurant
INSERT INTO #test_results (test_name, entity_name, expected_value, actual_value, status, error_message)
SELECT
    'Business Key completeness',
    'restaurant',
    '0 NULL/empty restaurant_id',
    CONCAT(COUNT_BIG(*), ' invalid'),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL
FROM raw.raw_restaurant
WHERE batch_id = @batch_id AND (restaurant_id IS NULL OR LTRIM(RTRIM(restaurant_id)) = '');

-- 8.3 Menu Item
INSERT INTO #test_results (test_name, entity_name, expected_value, actual_value, status, error_message)
SELECT
    'Business Key completeness',
    'menu_item',
    '0 NULL/empty menu_item_id',
    CONCAT(COUNT_BIG(*), ' invalid'),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL
FROM raw.raw_menu_item
WHERE batch_id = @batch_id AND (menu_item_id IS NULL OR LTRIM(RTRIM(menu_item_id)) = '');

-- 8.4 Delivery Partner
INSERT INTO #test_results (test_name, entity_name, expected_value, actual_value, status, error_message)
SELECT
    'Business Key completeness',
    'delivery_partner',
    '0 NULL/empty delivery_partner_id',
    CONCAT(COUNT_BIG(*), ' invalid'),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL
FROM raw.raw_delivery_partner
WHERE batch_id = @batch_id AND (delivery_partner_id IS NULL OR LTRIM(RTRIM(delivery_partner_id)) = '');

-- 8.5 Order
INSERT INTO #test_results (test_name, entity_name, expected_value, actual_value, status, error_message)
SELECT
    'Business Key completeness',
    'order',
    '0 NULL/empty order_id',
    CONCAT(COUNT_BIG(*), ' invalid'),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL
FROM raw.raw_order
WHERE batch_id = @batch_id AND (order_id IS NULL OR LTRIM(RTRIM(order_id)) = '');

-- 8.6 Order Item
INSERT INTO #test_results (test_name, entity_name, expected_value, actual_value, status, error_message)
SELECT
    'Business Key completeness',
    'order_item',
    '0 NULL/empty order_item_id',
    CONCAT(COUNT_BIG(*), ' invalid'),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL
FROM raw.raw_order_item
WHERE batch_id = @batch_id AND (order_item_id IS NULL OR LTRIM(RTRIM(order_item_id)) = '');

-- 8.7 Delivery Performance
INSERT INTO #test_results (test_name, entity_name, expected_value, actual_value, status, error_message)
SELECT
    'Business Key completeness',
    'delivery_performance',
    '0 NULL/empty delivery_id',
    CONCAT(COUNT_BIG(*), ' invalid'),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL
FROM raw.raw_delivery_performance
WHERE batch_id = @batch_id AND (delivery_id IS NULL OR LTRIM(RTRIM(delivery_id)) = '');

-- 8.8 Rating
INSERT INTO #test_results (test_name, entity_name, expected_value, actual_value, status, error_message)
SELECT
    'Business Key completeness',
    'rating',
    '0 NULL/empty rating_id',
    CONCAT(COUNT_BIG(*), ' invalid'),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL
FROM raw.raw_rating
WHERE batch_id = @batch_id AND (rating_id IS NULL OR LTRIM(RTRIM(rating_id)) = '');


/*==============================================================================
  9. SCHEMA DRIFT & NEW COLUMNS VALIDATION
==============================================================================*/

-- 9.1 Restaurant: onboard_date
DECLARE @null_onboard_date_rest BIGINT;
SELECT @null_onboard_date_rest = COUNT_BIG(*)
FROM raw.raw_restaurant
WHERE batch_id = @batch_id AND (onboard_date IS NULL OR LTRIM(RTRIM(onboard_date)) = '');

INSERT INTO #test_results (test_name, entity_name, expected_value, actual_value, status, error_message)
VALUES
(
    'New column presence: onboard_date',
    'restaurant',
    '0 NULL/empty onboard_date',
    CONCAT(@null_onboard_date_rest, ' NULL/empty'),
    CASE WHEN @null_onboard_date_rest = 0 THEN 'PASS' ELSE 'FAIL' END,
    CASE WHEN @null_onboard_date_rest > 0 THEN 'Column onboard_date has missing values.' ELSE NULL END
);

-- 9.2 Delivery Partner: onboard_date
DECLARE @null_onboard_date BIGINT;
SELECT @null_onboard_date = COUNT_BIG(*)
FROM raw.raw_delivery_partner
WHERE batch_id = @batch_id AND (onboard_date IS NULL OR LTRIM(RTRIM(onboard_date)) = '');

INSERT INTO #test_results (test_name, entity_name, expected_value, actual_value, status, error_message)
VALUES
(
    'New column presence: onboard_date',
    'delivery_partner',
    '0 NULL/empty onboard_date',
    CONCAT(@null_onboard_date, ' NULL/empty'),
    CASE WHEN @null_onboard_date = 0 THEN 'PASS' ELSE 'FAIL' END,
    CASE WHEN @null_onboard_date > 0 THEN 'Column onboard_date has missing values.' ELSE NULL END
);

-- 9.3 Delivery Performance: prep_time, rider_wait_time, travel_time populated check
DECLARE @valid_timing_metrics BIGINT;
SELECT @valid_timing_metrics = COUNT_BIG(*)
FROM raw.raw_delivery_performance
WHERE batch_id = @batch_id 
  AND prep_time IS NOT NULL 
  AND rider_wait_time IS NOT NULL 
  AND travel_time IS NOT NULL;

INSERT INTO #test_results (test_name, entity_name, expected_value, actual_value, status, error_message)
VALUES
(
    'New timing metrics populated',
    'delivery_performance',
    '> 100000 populated rows',
    CONCAT(@valid_timing_metrics, ' populated rows'),
    CASE WHEN @valid_timing_metrics > 100000 THEN 'PASS' ELSE 'FAIL' END,
    CASE WHEN @valid_timing_metrics <= 100000 THEN 'Delivery timing metrics are not properly populated.' ELSE NULL END
);


/*==============================================================================
  10. FINAL TEST RESULT DETAIL
==============================================================================*/

SELECT
    test_id,
    test_name,
    ISNULL(entity_name, '-') AS entity_name,
    expected_value,
    actual_value,
    status,
    ISNULL(error_message, '-') AS error_message,
    test_timestamp
FROM #test_results
ORDER BY test_id;


/*==============================================================================
  11. FINAL TEST SUMMARY & ASSERTION
==============================================================================*/

DECLARE
    @total_tests  INT,
    @passed_tests INT,
    @failed_tests INT;

SELECT
    @total_tests  = COUNT(*),
    @passed_tests = SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END),
    @failed_tests = SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END)
FROM #test_results;

SELECT
    @batch_id       AS batch_id,
    @total_tests    AS total_tests,
    @passed_tests   AS passed_tests,
    @failed_tests   AS failed_tests,
    CASE
        WHEN @failed_tests = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS overall_status;

IF @failed_tests > 0
BEGIN
    THROW 50010, 'RAW verification failed. Review #test_results for details.', 1;
END;
ELSE
BEGIN
    PRINT '>>> [PASS] All RAW layer verification and audit checks passed successfully!';
END;
GO
