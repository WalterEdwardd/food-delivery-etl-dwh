/*
================================================================================
PROJECT : Food Delivery ETL & Data Warehouse
FILE    : 03_verify_ods_load.sql
PURPOSE : Integration and reconciliation tests for RAW -> ODS
================================================================================
TEST SCOPE
================================================================================
This script validates the complete RAW -> ODS loading and standardization process.
It supports batch scoping (filtering by @batch_id or defaulting to latest batch).

Tests:
    01. Environment validation
    02. Schema validation
    03. ODS tables existence (all 8 entities)
    04. Row count reconciliation (RAW vs ODS vs etl_error for @batch_id)
    05. Audit log completeness (Every rejected row is logged in control.etl_error)
    06. Business Key Uniqueness check
    07. Business Key Null / Empty check
    08. Residual whitespace / Trimming validation
    09. Audit metadata completeness (batch_id, lineage)
    10. Final test summary
================================================================================
*/

USE FoodDeliveryDW;
GO

SET NOCOUNT ON;
GO


/*==============================================================================
  0. BATCH CONFIGURATION
==============================================================================*/

-- NULL: Automatically fetch the latest active batch_id from ODS (or RAW if ODS is empty)
-- Or specify an explicit batch_id (e.g., 1) to audit a past execution run
DECLARE @batch_id BIGINT = NULL;

IF @batch_id IS NULL
BEGIN
    SELECT @batch_id = MAX(batch_id) FROM ods.ods_order;

    IF @batch_id IS NULL
        SELECT @batch_id = MAX(batch_id) FROM raw.raw_order;
END;

PRINT CONCAT('>>> [VERIFICATION SCOPE] Executing ODS verification tests for BATCH_ID = ', ISNULL(CAST(@batch_id AS VARCHAR), 'ALL'));


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
    batch_id        BIGINT NULL,
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
    INSERT INTO #test_results (test_name, batch_id, expected_value, actual_value, status)
    VALUES ('Environment validation', @batch_id, 'FoodDeliveryDW', DB_NAME(), 'PASS');
END
ELSE
BEGIN
    INSERT INTO #test_results (test_name, batch_id, expected_value, actual_value, status, error_message)
    VALUES ('Environment validation', @batch_id, 'FoodDeliveryDW', DB_NAME(), 'FAIL', 'Must run on FoodDeliveryDW');
END;


/*==============================================================================
  3. ODS SCHEMA & TABLE EXISTENCE VALIDATION
==============================================================================*/

IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'ods')
BEGIN
    INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status)
    VALUES ('Schema existence', 'ods', @batch_id, 'EXISTS', 'EXISTS', 'PASS');
END
ELSE
BEGIN
    INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
    VALUES ('Schema existence', 'ods', @batch_id, 'EXISTS', 'NOT FOUND', 'FAIL', 'Schema ods missing');
END;

DECLARE @expected_tables TABLE (tbl VARCHAR(100));
INSERT INTO @expected_tables VALUES
    ('ods_customer'),
    ('ods_restaurant'),
    ('ods_menu_item'),
    ('ods_delivery_partner'),
    ('ods_order'),
    ('ods_order_item'),
    ('ods_delivery_performance'),
    ('ods_rating');

DECLARE @missing_tables_count INT = 0;
SELECT @missing_tables_count = COUNT(*)
FROM @expected_tables e
WHERE NOT EXISTS (
    SELECT 1 FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'ods' AND t.name = e.tbl
);

IF @missing_tables_count = 0
BEGIN
    INSERT INTO #test_results (test_name, batch_id, expected_value, actual_value, status)
    VALUES ('ODS tables existence', @batch_id, '8 tables present', '8 tables present', 'PASS');
END
ELSE
BEGIN
    INSERT INTO #test_results (test_name, batch_id, expected_value, actual_value, status, error_message)
    VALUES ('ODS tables existence', @batch_id, '8 tables present', CAST(@missing_tables_count AS VARCHAR) + ' missing', 'FAIL', 'One or more ODS tables missing');
END;


/*==============================================================================
  4. ROW COUNT RECONCILIATION & ERROR LOG AUDITABILITY (BATCH SCOPED)
==============================================================================*/

DECLARE @entities TABLE (entity VARCHAR(100), raw_tbl VARCHAR(100), ods_tbl VARCHAR(100));
INSERT INTO @entities VALUES
    ('customer',             'raw_customer',             'ods_customer'),
    ('restaurant',           'raw_restaurant',           'ods_restaurant'),
    ('menu_item',            'raw_menu_item',            'ods_menu_item'),
    ('delivery_partner',     'raw_delivery_partner',     'ods_delivery_partner'),
    ('order',                'raw_order',                'ods_order'),
    ('order_item',           'raw_order_item',           'ods_order_item'),
    ('delivery_performance', 'raw_delivery_performance', 'ods_delivery_performance'),
    ('rating',               'raw_rating',               'ods_rating');

DECLARE @entity VARCHAR(100), @raw_tbl VARCHAR(100), @ods_tbl VARCHAR(100);
DECLARE @raw_cnt BIGINT, @ods_cnt BIGINT, @rejected_cnt BIGINT;
DECLARE @distinct_err_rows BIGINT, @total_err_violations BIGINT;
DECLARE @sql NVARCHAR(MAX);

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
SELECT entity, raw_tbl, ods_tbl FROM @entities;

OPEN cur;
FETCH NEXT FROM cur INTO @entity, @raw_tbl, @ods_tbl;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
        SELECT @raw_cnt = COUNT(*) FROM raw.' + QUOTENAME(@raw_tbl) + N' WHERE batch_id = @batch_id;
        SELECT @ods_cnt = COUNT(*) FROM ods.' + QUOTENAME(@ods_tbl) + N' WHERE batch_id = @batch_id;
        
        -- Distinct physical rows logged in error table vs Total error violations
        SELECT 
            @distinct_err_rows    = COUNT(DISTINCT source_row_number),
            @total_err_violations = COUNT(*)
        FROM control.etl_error
        WHERE table_name IN (@ods_tbl, @raw_tbl, @entity)
          AND batch_id = @batch_id
          AND source_row_number IS NOT NULL;
    ';

    EXEC sp_executesql @sql,
        N'@ods_tbl VARCHAR(100), @raw_tbl VARCHAR(100), @entity VARCHAR(100), @batch_id BIGINT,
          @raw_cnt BIGINT OUTPUT, @ods_cnt BIGINT OUTPUT, 
          @distinct_err_rows BIGINT OUTPUT, @total_err_violations BIGINT OUTPUT',
        @ods_tbl = @ods_tbl, @raw_tbl = @raw_tbl, @entity = @entity, @batch_id = @batch_id,
        @raw_cnt = @raw_cnt OUTPUT, @ods_cnt = @ods_cnt OUTPUT, 
        @distinct_err_rows = @distinct_err_rows OUTPUT, @total_err_violations = @total_err_violations OUTPUT;

    -- Mathematical reconciliation: Rejected rows = RAW - ODS
    SET @rejected_cnt = @raw_cnt - @ods_cnt;

    -- Test 4.1: Mathematical Balance (RAW = ODS + Rejected)
    IF @raw_cnt >= @ods_cnt
    BEGIN
        INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status)
        VALUES (
            'Row count reconciliation',
            @entity,
            @batch_id,
            CONCAT('RAW = ', @raw_cnt),
            CONCAT('ODS = ', @ods_cnt, ' | Rejected = ', @rejected_cnt),
            'PASS'
        );
    END
    ELSE
    BEGIN
        INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
        VALUES (
            'Row count reconciliation',
            @entity,
            @batch_id,
            CONCAT('RAW = ', @raw_cnt),
            CONCAT('ODS = ', @ods_cnt, ' | Rejected = ', @rejected_cnt),
            'FAIL',
            'ODS row count exceeds RAW row count (row duplication detected)'
        );
    END;

    -- Test 4.2: Error Auditability (Verify that all rejected rows exist in control.etl_error for this batch)
    DECLARE @exp_msg VARCHAR(500), @act_msg VARCHAR(500);

    IF @rejected_cnt = 0
    BEGIN
        SET @exp_msg = '0 rejected rows';
        SET @act_msg = '0 error rows in etl_error';
    END
    ELSE
    BEGIN
        SET @exp_msg = CONCAT(@rejected_cnt, ' rejected rows');
        SET @act_msg = CONCAT(@total_err_violations, ' error rows in etl_error');
    END;

    IF @rejected_cnt = @distinct_err_rows
    BEGIN
        INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status)
        VALUES (
            'Audit log completeness',
            @entity,
            @batch_id,
            @exp_msg,
            @act_msg,
            'PASS'
        );
    END
    ELSE
    BEGIN
        INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
        VALUES (
            'Audit log completeness',
            @entity,
            @batch_id,
            @exp_msg,
            @act_msg,
            'FAIL',
            CONCAT('Mismatch between rejected rows (', @rejected_cnt, ') and logged rows in control.etl_error (', @distinct_err_rows, ')')
        );
    END;

    FETCH NEXT FROM cur INTO @entity, @raw_tbl, @ods_tbl;
END;

CLOSE cur;
DEALLOCATE cur;


/*==============================================================================
  5. BUSINESS KEY UNIQUENESS VALIDATION (ODS DEDUPLICATION)
==============================================================================*/

-- 5.1 Customer
DECLARE @dup_cust INT;
SELECT @dup_cust = COUNT(*)
FROM (
    SELECT customer_id FROM ods.ods_customer WHERE batch_id = @batch_id GROUP BY customer_id HAVING COUNT(*) > 1
) d;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Business Key Uniqueness', 'ods_customer', @batch_id, '0 duplicates', CAST(@dup_cust AS VARCHAR) + ' duplicates',
        CASE WHEN @dup_cust = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @dup_cust = 0 THEN NULL ELSE 'Duplicate customer_id found in ODS' END);

-- 5.2 Restaurant
DECLARE @dup_rest INT;
SELECT @dup_rest = COUNT(*)
FROM (
    SELECT restaurant_id FROM ods.ods_restaurant WHERE batch_id = @batch_id GROUP BY restaurant_id HAVING COUNT(*) > 1
) d;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Business Key Uniqueness', 'ods_restaurant', @batch_id, '0 duplicates', CAST(@dup_rest AS VARCHAR) + ' duplicates',
        CASE WHEN @dup_rest = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @dup_rest = 0 THEN NULL ELSE 'Duplicate restaurant_id found in ODS' END);

-- 5.3 Delivery Partner
DECLARE @dup_dp INT;
SELECT @dup_dp = COUNT(*)
FROM (
    SELECT delivery_partner_id FROM ods.ods_delivery_partner WHERE batch_id = @batch_id GROUP BY delivery_partner_id HAVING COUNT(*) > 1
) d;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Business Key Uniqueness', 'ods_delivery_partner', @batch_id, '0 duplicates', CAST(@dup_dp AS VARCHAR) + ' duplicates',
        CASE WHEN @dup_dp = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @dup_dp = 0 THEN NULL ELSE 'Duplicate delivery_partner_id found in ODS' END);

-- 5.4 Order
DECLARE @dup_ord INT;
SELECT @dup_ord = COUNT(*)
FROM (
    SELECT order_id FROM ods.ods_order WHERE batch_id = @batch_id GROUP BY order_id HAVING COUNT(*) > 1
) d;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Business Key Uniqueness', 'ods_order', @batch_id, '0 duplicates', CAST(@dup_ord AS VARCHAR) + ' duplicates',
        CASE WHEN @dup_ord = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @dup_ord = 0 THEN NULL ELSE 'Duplicate order_id found in ODS' END);

-- 5.5 Order Item
DECLARE @dup_item INT;
SELECT @dup_item = COUNT(*)
FROM (
    SELECT order_line_id FROM ods.ods_order_item WHERE batch_id = @batch_id GROUP BY order_line_id HAVING COUNT(*) > 1
) d;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Business Key Uniqueness', 'ods_order_item', @batch_id, '0 duplicates', CAST(@dup_item AS VARCHAR) + ' duplicates',
        CASE WHEN @dup_item = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @dup_item = 0 THEN NULL ELSE 'Duplicate order_line_id found in ODS' END);


/*==============================================================================
  6. BUSINESS KEY INTEGRITY (NO NULL OR EMPTY KEYS)
==============================================================================*/

DECLARE @null_keys INT;

SELECT @null_keys = 
    (SELECT COUNT(*) FROM ods.ods_customer WHERE batch_id = @batch_id AND (customer_id IS NULL OR LTRIM(RTRIM(customer_id)) = '')) +
    (SELECT COUNT(*) FROM ods.ods_restaurant WHERE batch_id = @batch_id AND (restaurant_id IS NULL OR LTRIM(RTRIM(restaurant_id)) = '')) +
    (SELECT COUNT(*) FROM ods.ods_delivery_partner WHERE batch_id = @batch_id AND (delivery_partner_id IS NULL OR LTRIM(RTRIM(delivery_partner_id)) = '')) +
    (SELECT COUNT(*) FROM ods.ods_menu_item WHERE batch_id = @batch_id AND (menu_item_id IS NULL OR LTRIM(RTRIM(menu_item_id)) = '')) +
    (SELECT COUNT(*) FROM ods.ods_order WHERE batch_id = @batch_id AND (order_id IS NULL OR LTRIM(RTRIM(order_id)) = '')) +
    (SELECT COUNT(*) FROM ods.ods_order_item WHERE batch_id = @batch_id AND (order_line_id IS NULL OR LTRIM(RTRIM(order_line_id)) = '')) +
    (SELECT COUNT(*) FROM ods.ods_delivery_performance WHERE batch_id = @batch_id AND (delivery_id IS NULL OR LTRIM(RTRIM(delivery_id)) = '')) +
    (SELECT COUNT(*) FROM ods.ods_rating WHERE batch_id = @batch_id AND (rating_id IS NULL OR LTRIM(RTRIM(rating_id)) = ''));

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Business Key Integrity', 'ALL ODS Tables', @batch_id, '0 null/empty keys', CAST(@null_keys AS VARCHAR) + ' null/empty keys',
        CASE WHEN @null_keys = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @null_keys = 0 THEN NULL ELSE 'Null or blank business keys found in ODS' END);


/*==============================================================================
  7. RESIDUAL WHITESPACE / TRIMMING VALIDATION
==============================================================================*/

DECLARE @whitespace_count INT;

SELECT @whitespace_count = 
    (SELECT COUNT(*) FROM ods.ods_customer WHERE batch_id = @batch_id AND (customer_id <> LTRIM(RTRIM(customer_id)) OR city <> LTRIM(RTRIM(city)))) +
    (SELECT COUNT(*) FROM ods.ods_restaurant WHERE batch_id = @batch_id AND (restaurant_id <> LTRIM(RTRIM(restaurant_id)) OR city <> LTRIM(RTRIM(city)))) +
    (SELECT COUNT(*) FROM ods.ods_delivery_partner WHERE batch_id = @batch_id AND (delivery_partner_id <> LTRIM(RTRIM(delivery_partner_id)) OR city <> LTRIM(RTRIM(city))));

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Trimming validation', 'Customer, Restaurant, Driver', @batch_id, '0 untrimmed rows', CAST(@whitespace_count AS VARCHAR) + ' untrimmed rows',
        CASE WHEN @whitespace_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @whitespace_count = 0 THEN NULL ELSE 'Leading/trailing whitespace detected in ODS' END);


/*==============================================================================
  8. AUDIT METADATA COMPLETENESS
==============================================================================*/

DECLARE @missing_audit INT;

SELECT @missing_audit = 
    (SELECT COUNT(*) FROM ods.ods_customer WHERE batch_id = @batch_id AND (batch_id IS NULL OR source_file_name IS NULL OR load_timestamp IS NULL)) +
    (SELECT COUNT(*) FROM ods.ods_restaurant WHERE batch_id = @batch_id AND (batch_id IS NULL OR source_file_name IS NULL OR load_timestamp IS NULL)) +
    (SELECT COUNT(*) FROM ods.ods_delivery_partner WHERE batch_id = @batch_id AND (batch_id IS NULL OR source_file_name IS NULL OR load_timestamp IS NULL)) +
    (SELECT COUNT(*) FROM ods.ods_order WHERE batch_id = @batch_id AND (batch_id IS NULL OR source_file_name IS NULL OR load_timestamp IS NULL));

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Audit Metadata completeness', 'ALL ODS Tables', @batch_id, '0 missing audit cols', CAST(@missing_audit AS VARCHAR) + ' missing audit cols',
        CASE WHEN @missing_audit = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @missing_audit = 0 THEN NULL ELSE 'Null audit columns found in ODS' END);


/*==============================================================================
  9. TEST RESULTS SUMMARY
==============================================================================*/

SELECT
    test_id,
    test_name,
    ISNULL(entity_name, '-') AS entity,
    ISNULL(CAST(batch_id AS VARCHAR), 'ALL') AS batch_id,
    expected_value,
    actual_value,
    status,
    ISNULL(error_message, '-') AS error_message
FROM #test_results
ORDER BY test_id;

DECLARE @total_tests INT, @passed_tests INT, @failed_tests INT;
SELECT
    @total_tests  = COUNT(*),
    @passed_tests = COUNT(CASE WHEN status = 'PASS' THEN 1 END),
    @failed_tests = COUNT(CASE WHEN status = 'FAIL' THEN 1 END)
FROM #test_results;

PRINT '================================================================================';
PRINT CONCAT('ODS VERIFICATION TEST SUMMARY [BATCH: ', ISNULL(CAST(@batch_id AS VARCHAR), 'ALL'), ']: Total=', @total_tests, ', Passed=', @passed_tests, ', Failed=', @failed_tests);
PRINT '================================================================================';

SELECT
    @batch_id       AS batch_id,
    @total_tests    AS total_tests,
    @passed_tests   AS passed_tests,
    @failed_tests   AS failed_tests,
    CASE WHEN @failed_tests = 0 THEN 'PASS' ELSE 'FAIL' END AS overall_status;

IF @failed_tests > 0
BEGIN
    THROW 50001, 'One or more ODS verification tests FAILED. Please review #test_results table.', 1;
END;
GO
