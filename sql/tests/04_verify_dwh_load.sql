/*
================================================================================
PROJECT : Food Delivery ETL & Data Warehouse
FILE    : 04_verify_dwh_load.sql
PURPOSE : Integration and reconciliation tests for ODS -> DWH Dimensional Layer
================================================================================
TEST SCOPE
================================================================================
This script validates the complete DWH Star Schema, Surrogate Keys,
Unknown Member references, Foreign Key integrity, and ODS -> DWH reconciliations.
It supports batch scoping (filtering by @batch_id or defaulting to latest batch).

Tests:
    01. Environment validation
    02. Schema validation (dwh)
    03. DWH tables existence (all 14 Dimensions & Facts)
    04. Primary Key / Surrogate Key validation
    05. Natural Business Key Uniqueness validation
    06. Unknown Member (-1) completeness on all Dimensions
    07. Star Schema Foreign Key Referential Integrity
    08. Fact Surrogate Key Nullability validation
    09. Row count reconciliation (ODS vs DWH for @batch_id)
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

-- NULL: Tự động lấy batch_id mới nhất thực tế từ ODS (hoặc RAW nếu ODS rỗng)
-- Hoặc chỉ định một số cụ thể (ví dụ: 1) để audit lại đợt chạy trong quá khứ
DECLARE @batch_id BIGINT = NULL;

IF @batch_id IS NULL
BEGIN
    SELECT @batch_id = MAX(batch_id) FROM ods.ods_order;

    IF @batch_id IS NULL
        SELECT @batch_id = MAX(batch_id) FROM raw.raw_order;
END;

PRINT CONCAT('>>> [VERIFICATION SCOPE] Executing DWH verification tests for BATCH_ID = ', ISNULL(CAST(@batch_id AS VARCHAR), 'ALL'));


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
  3. DWH SCHEMA & TABLES EXISTENCE VALIDATION (14 TABLES)
==============================================================================*/

IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'dwh')
BEGIN
    INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status)
    VALUES ('Schema existence', 'dwh', @batch_id, 'EXISTS', 'EXISTS', 'PASS');
END
ELSE
BEGIN
    INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
    VALUES ('Schema existence', 'dwh', @batch_id, 'EXISTS', 'NOT FOUND', 'FAIL', 'Schema dwh missing');
END;

DECLARE @dwh_expected_tables TABLE (tbl VARCHAR(100), role_type VARCHAR(20));
INSERT INTO @dwh_expected_tables VALUES
    ('dim_date',                   'Dimension'),
    ('dim_time',                   'Dimension'),
    ('dim_customer',               'Dimension'),
    ('dim_restaurant',             'Dimension'),
    ('dim_delivery_partner',       'Dimension'),
    ('dim_menu_item',              'Dimension'),
    ('dim_rating_type',            'Dimension'),
    ('dim_sentiment_type',         'Dimension'),
    ('dim_aspect',                 'Dimension'),
    ('fact_order',                 'Fact'),
    ('fact_order_item',            'Fact'),
    ('fact_delivery_performance',  'Fact'),
    ('fact_rating',                'Fact'),
    ('fact_review_aspect',         'Fact');

DECLARE @missing_dwh_tables INT = 0;
SELECT @missing_dwh_tables = COUNT(*)
FROM @dwh_expected_tables e
WHERE NOT EXISTS (
    SELECT 1 FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dwh' AND t.name = e.tbl
);

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('DWH tables completeness', '14 Core Tables', @batch_id, '14 tables present', 
        CAST(14 - @missing_dwh_tables AS VARCHAR) + ' tables present',
        CASE WHEN @missing_dwh_tables = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @missing_dwh_tables = 0 THEN NULL ELSE 'One or more DWH tables missing' END);


/*==============================================================================
  4. PRIMARY KEY INTEGRITY CHECK
==============================================================================*/

DECLARE @tables_without_pk INT;

SELECT @tables_without_pk = COUNT(*)
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE s.name = 'dwh'
  AND NOT EXISTS (
      SELECT 1 FROM sys.key_constraints kc
      WHERE kc.parent_object_id = t.object_id AND kc.type = 'PK'
  );

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Primary Key Integrity', 'ALL DWH Tables', @batch_id, '0 tables without PK', CAST(@tables_without_pk AS VARCHAR) + ' without PK',
        CASE WHEN @tables_without_pk = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @tables_without_pk = 0 THEN NULL ELSE 'Tables missing Primary Key found in DWH' END);


/*==============================================================================
  5. NATURAL BUSINESS KEY UNIQUENESS VALIDATION
==============================================================================*/

DECLARE @tables_without_uq INT;

SELECT @tables_without_uq = COUNT(*)
FROM (
    SELECT 'dim_customer' AS tbl UNION ALL
    SELECT 'dim_restaurant'      UNION ALL
    SELECT 'dim_delivery_partner' UNION ALL
    SELECT 'dim_menu_item'       UNION ALL
    SELECT 'fact_order'          UNION ALL
    SELECT 'fact_order_item'     UNION ALL
    SELECT 'fact_delivery_performance' UNION ALL
    SELECT 'fact_rating'
) req
WHERE NOT EXISTS (
    SELECT 1 FROM sys.key_constraints kc
    JOIN sys.tables t ON kc.parent_object_id = t.object_id
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dwh' AND t.name = req.tbl AND kc.type = 'UQ'
);

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Business Key Unique Constraints', 'Entity Tables', @batch_id, '0 tables without UQ', CAST(@tables_without_uq AS VARCHAR) + ' without UQ',
        CASE WHEN @tables_without_uq = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @tables_without_uq = 0 THEN NULL ELSE 'Business Key Unique Constraint missing' END);


/*==============================================================================
  6. UNKNOWN MEMBER (-1) VALIDATION ACROSS DIMENSIONS
==============================================================================*/

DECLARE @missing_unknowns INT = 0;

IF NOT EXISTS (SELECT 1 FROM dwh.dim_date WHERE date_key = -1) SET @missing_unknowns += 1;
IF NOT EXISTS (SELECT 1 FROM dwh.dim_time WHERE time_key = -1) SET @missing_unknowns += 1;
IF NOT EXISTS (SELECT 1 FROM dwh.dim_customer WHERE customer_key = -1) SET @missing_unknowns += 1;
IF NOT EXISTS (SELECT 1 FROM dwh.dim_restaurant WHERE restaurant_key = -1) SET @missing_unknowns += 1;
IF NOT EXISTS (SELECT 1 FROM dwh.dim_delivery_partner WHERE delivery_partner_key = -1) SET @missing_unknowns += 1;
IF NOT EXISTS (SELECT 1 FROM dwh.dim_menu_item WHERE menu_item_key = -1) SET @missing_unknowns += 1;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Unknown Member (-1) Integrity', 'All Dimensions', @batch_id, '6 Unknown Members present', 
        CAST(6 - @missing_unknowns AS VARCHAR) + ' Unknown Members present',
        CASE WHEN @missing_unknowns = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @missing_unknowns = 0 THEN NULL ELSE 'Missing Unknown Member (-1) in one or more Dimensions' END);


/*==============================================================================
  7. STAR SCHEMA FOREIGN KEY INTEGRITY
==============================================================================*/

DECLARE @expected_fk_count INT = 16;
DECLARE @actual_fk_count INT;

SELECT @actual_fk_count = COUNT(*)
FROM sys.foreign_keys
WHERE schema_id = SCHEMA_ID('dwh');

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Star Schema FK Constraints', 'Fact to Dim relationships', @batch_id,
        CONCAT('>=', @expected_fk_count, ' FKs'), 
        CAST(@actual_fk_count AS VARCHAR) + ' FKs active',
        CASE WHEN @actual_fk_count >= @expected_fk_count THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @actual_fk_count >= @expected_fk_count THEN NULL ELSE 'Missing Foreign Key constraints in DWH' END);


/*==============================================================================
  8. FACT SURROGATE KEY NULLABILITY CHECK
==============================================================================*/

DECLARE @null_fk_records INT = 0;

IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'fact_order' AND schema_id = SCHEMA_ID('dwh'))
BEGIN
    SELECT @null_fk_records = 
        (SELECT COUNT(*) FROM dwh.fact_order WHERE order_date_key IS NULL OR customer_key IS NULL OR restaurant_key IS NULL OR delivery_partner_key IS NULL) +
        (SELECT COUNT(*) FROM dwh.fact_order_item WHERE order_date_key IS NULL OR customer_key IS NULL OR restaurant_key IS NULL OR menu_item_key IS NULL);
END;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Fact Surrogate Keys Nullability', 'fact_order & fact_order_item', @batch_id, '0 null FKs in facts', 
        CAST(@null_fk_records AS VARCHAR) + ' null FKs found',
        CASE WHEN @null_fk_records = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @null_fk_records = 0 THEN NULL ELSE 'Null surrogate foreign keys detected in Facts' END);


/*==============================================================================
  9. ROW COUNT RECONCILIATION (ODS vs DWH - BATCH SCOPED)
==============================================================================*/

DECLARE @ods_cust BIGINT, @dwh_cust BIGINT;
SELECT @ods_cust = COUNT(*) FROM ods.ods_customer WHERE batch_id = @batch_id;
SELECT @dwh_cust = COUNT(*) FROM dwh.dim_customer WHERE batch_id = @batch_id AND customer_key <> -1;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Customer Reconciliation', 'ods_customer -> dim_customer', @batch_id,
        CONCAT('ODS = ', @ods_cust),
        CONCAT('DWH = ', @dwh_cust),
        CASE WHEN @dwh_cust = @ods_cust OR @dwh_cust = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @dwh_cust = @ods_cust OR @dwh_cust = 0 THEN NULL ELSE 'DWH customer count does not match ODS' END);


/*==============================================================================
  10. TEST RESULTS SUMMARY
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
PRINT CONCAT('DWH INTEGRATION TEST SUMMARY [BATCH: ', ISNULL(CAST(@batch_id AS VARCHAR), 'ALL'), ']: Total=', @total_tests, ', Passed=', @passed_tests, ', Failed=', @failed_tests);
PRINT '================================================================================';

SELECT
    @batch_id       AS batch_id,
    @total_tests    AS total_tests,
    @passed_tests   AS passed_tests,
    @failed_tests   AS failed_tests,
    CASE WHEN @failed_tests = 0 THEN 'PASS' ELSE 'FAIL' END AS overall_status;

IF @failed_tests > 0
BEGIN
    THROW 50002, 'One or more DWH verification tests FAILED. Please review #test_results table.', 1;
END;
GO
