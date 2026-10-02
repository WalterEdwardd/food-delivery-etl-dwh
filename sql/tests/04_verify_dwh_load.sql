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

-- NULL: Automatically fetch the latest active batch_id from ODS (or RAW if ODS is empty)
-- Or specify an explicit batch_id (e.g., 1) to audit a past execution run
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
    ('dim_life_cycles',            'Dimension'),
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
VALUES ('DWH tables completeness', '15 Core Tables', @batch_id, '15 tables present', 
        CAST(15 - @missing_dwh_tables AS VARCHAR) + ' tables present',
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

-- 9.1 Customer Reconciliation
DECLARE @ods_cust BIGINT, @dwh_cust BIGINT;
SELECT @ods_cust = COUNT(*) FROM ods.ods_customer WHERE batch_id = @batch_id;
SELECT @dwh_cust = COUNT(*) FROM dwh.dim_customer WHERE batch_id = @batch_id AND customer_key <> -1;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Customer Reconciliation', 'ods_customer -> dim_customer', @batch_id,
        CONCAT('ODS = ', @ods_cust),
        CONCAT('DWH = ', @dwh_cust),
        CASE WHEN @dwh_cust = @ods_cust THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @dwh_cust = @ods_cust THEN NULL ELSE 'DWH customer count does not match ODS' END);

-- 9.2 Delivery Partner Reconciliation
DECLARE @ods_dp BIGINT, @dwh_dp BIGINT;
SELECT @ods_dp = COUNT(*) FROM ods.ods_delivery_partner WHERE batch_id = @batch_id;
SELECT @dwh_dp = COUNT(*) FROM dwh.dim_delivery_partner WHERE batch_id = @batch_id AND delivery_partner_key <> -1;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Delivery Partner Reconciliation', 'ods_delivery_partner -> dim_delivery_partner', @batch_id,
        CONCAT('ODS = ', @ods_dp),
        CONCAT('DWH = ', @dwh_dp),
        CASE WHEN @dwh_dp = @ods_dp THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @dwh_dp = @ods_dp THEN NULL ELSE 'DWH delivery partner count does not match ODS' END);

-- 9.3 Restaurant Reconciliation
DECLARE @ods_rest BIGINT, @dwh_rest BIGINT;
SELECT @ods_rest = COUNT(*) FROM ods.ods_restaurant WHERE batch_id = @batch_id;
SELECT @dwh_rest = COUNT(*) FROM dwh.dim_restaurant WHERE batch_id = @batch_id AND restaurant_key <> -1;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Restaurant Reconciliation', 'ods_restaurant -> dim_restaurant', @batch_id,
        CONCAT('ODS = ', @ods_rest),
        CONCAT('DWH = ', @dwh_rest),
        CASE WHEN @dwh_rest = @ods_rest THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @dwh_rest = @ods_rest THEN NULL ELSE 'DWH restaurant count does not match ODS' END);

-- 9.4 Menu Item Reconciliation
DECLARE @ods_item BIGINT, @dwh_item BIGINT;
SELECT @ods_item = COUNT(*) FROM ods.ods_menu_item WHERE batch_id = @batch_id;
SELECT @dwh_item = COUNT(*) FROM dwh.dim_menu_item WHERE batch_id = @batch_id AND menu_item_key <> -1;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Menu Item Reconciliation', 'ods_menu_item -> dim_menu_item', @batch_id,
        CONCAT('ODS = ', @ods_item),
        CONCAT('DWH = ', @dwh_item),
        CASE WHEN @dwh_item = @ods_item THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @dwh_item = @ods_item THEN NULL ELSE 'DWH menu item count does not match ODS' END);

-- 9.5 Fact Order Reconciliation
DECLARE @ods_ord BIGINT, @dwh_ord BIGINT;
SELECT @ods_ord = COUNT(*) FROM ods.ods_order WHERE batch_id = @batch_id;
SELECT @dwh_ord = COUNT(*) FROM dwh.fact_order WHERE batch_id = @batch_id;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Fact Order Reconciliation', 'ods_order -> fact_order', @batch_id,
        CONCAT('ODS = ', @ods_ord),
        CONCAT('DWH = ', @dwh_ord),
        CASE WHEN @dwh_ord = @ods_ord THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @dwh_ord = @ods_ord THEN NULL ELSE 'DWH fact order count does not match ODS' END);

-- 9.6 Fact Order Item Reconciliation
DECLARE @ods_oi BIGINT, @dwh_oi BIGINT;
SELECT @ods_oi = COUNT(*) FROM ods.ods_order_item WHERE batch_id = @batch_id;
SELECT @dwh_oi = COUNT(*) FROM dwh.fact_order_item WHERE batch_id = @batch_id;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Fact Order Item Reconciliation', 'ods_order_item -> fact_order_item', @batch_id,
        CONCAT('ODS = ', @ods_oi),
        CONCAT('DWH = ', @dwh_oi),
        CASE WHEN @dwh_oi = @ods_oi THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @dwh_oi = @ods_oi THEN NULL ELSE 'DWH fact order item count does not match ODS' END);

-- 9.7 Fact Delivery Performance Reconciliation
DECLARE @ods_deliv BIGINT, @dwh_deliv BIGINT;
SELECT @ods_deliv = COUNT(*) FROM ods.ods_delivery_performance WHERE batch_id = @batch_id;
SELECT @dwh_deliv = COUNT(*) FROM dwh.fact_delivery_performance WHERE batch_id = @batch_id;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Delivery Performance Reconciliation', 'ods_delivery_performance -> fact_delivery_performance', @batch_id,
        CONCAT('ODS = ', @ods_deliv),
        CONCAT('DWH = ', @dwh_deliv),
        CASE WHEN @dwh_deliv = @ods_deliv THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @dwh_deliv = @ods_deliv THEN NULL ELSE 'DWH delivery performance count does not match ODS' END);

-- 9.8 Cross-Table: Delivery Performance order_item vs Order Item quantity
DECLARE @mismatched_item_quantities INT = 0;
SELECT @mismatched_item_quantities = COUNT(*)
FROM dwh.fact_delivery_performance dp
JOIN (
    SELECT order_id, SUM(quantity) AS sum_qty
    FROM dwh.fact_order_item
    GROUP BY order_id
) oi ON dp.order_id = oi.order_id
WHERE dp.order_item <> oi.sum_qty;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Cross-Table Item Quantity Check', 'delivery_performance.order_item vs sum(order_item.quantity)', @batch_id,
        '0 mismatches',
        CONCAT(@mismatched_item_quantities, ' mismatches'),
        CASE WHEN @mismatched_item_quantities = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @mismatched_item_quantities = 0 THEN NULL ELSE 'Delivery performance order_item does not match sum of order items quantity' END);

-- 9.9 Fact Rating Reconciliation
DECLARE @ods_rat BIGINT, @dwh_rat BIGINT;
SELECT @ods_rat = COUNT(*) FROM ods.ods_rating WHERE batch_id = @batch_id;
SELECT @dwh_rat = COUNT(*) FROM dwh.fact_rating WHERE batch_id = @batch_id;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Fact Rating Reconciliation', 'ods_rating -> fact_rating', @batch_id,
        CONCAT('ODS = ', @ods_rat),
        CONCAT('DWH = ', @dwh_rat),
        CASE WHEN @dwh_rat = @ods_rat THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @dwh_rat = @ods_rat THEN NULL ELSE 'DWH fact rating count does not match ODS' END);

-- 9.10 Cross-Table: Order Subtotal vs Order Item Gross Sum
DECLARE @mismatched_subtotals INT = 0;
SELECT @mismatched_subtotals = COUNT(*)
FROM dwh.fact_order fo
JOIN (
    SELECT order_id, SUM(gross_line_total) AS sum_gross
    FROM dwh.fact_order_item
    GROUP BY order_id
) oi ON fo.order_id = oi.order_id
WHERE fo.is_cancelled = 0
  AND ABS(fo.subtotal_amount - oi.sum_gross) > 0.01;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Cross-Table Subtotal vs Gross Check', 'order.subtotal_amount vs sum(order_item.gross_line_total)', @batch_id,
        '0 mismatches',
        CONCAT(@mismatched_subtotals, ' mismatches'),
        CASE WHEN @mismatched_subtotals = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @mismatched_subtotals = 0 THEN NULL ELSE 'Order subtotal does not match sum of gross line totals' END);

-- 9.11 Cross-Table: Order Discount vs Order Item Discount Sum
DECLARE @mismatched_discounts INT = 0;
SELECT @mismatched_discounts = COUNT(*)
FROM dwh.fact_order fo
JOIN (
    SELECT order_id, SUM(item_discount) AS sum_discount
    FROM dwh.fact_order_item
    GROUP BY order_id
) oi ON fo.order_id = oi.order_id
WHERE fo.is_cancelled = 0
  AND ABS(fo.discount_amount - oi.sum_discount) > 0.01;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Cross-Table Discount Check', 'order.discount_amount vs sum(order_item.item_discount)', @batch_id,
        '0 mismatches',
        CONCAT(@mismatched_discounts, ' mismatches'),
        CASE WHEN @mismatched_discounts = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @mismatched_discounts = 0 THEN NULL ELSE 'Order discount does not match sum of item discounts' END);

-- 9.12 Cross-Table: Order Net Amount vs Order Item Net Sum
DECLARE @mismatched_net_amounts INT = 0;
SELECT @mismatched_net_amounts = COUNT(*)
FROM dwh.fact_order fo
JOIN (
    SELECT order_id, SUM(net_line_total) AS sum_net
    FROM dwh.fact_order_item
    GROUP BY order_id
) oi ON fo.order_id = oi.order_id
WHERE fo.is_cancelled = 0
  AND ABS((fo.subtotal_amount - fo.discount_amount) - oi.sum_net) > 0.01;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Cross-Table Net Amount Check', '(subtotal - discount) vs sum(order_item.net_line_total)', @batch_id,
        '0 mismatches',
        CONCAT(@mismatched_net_amounts, ' mismatches'),
        CASE WHEN @mismatched_net_amounts = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @mismatched_net_amounts = 0 THEN NULL ELSE 'Order net amount does not match sum of net line totals' END);


-- 9.13 Fact Review Aspect Row Count Check
DECLARE @fra_count INT = 0;
SELECT @fra_count = COUNT(*) FROM dwh.fact_review_aspect;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Fact Review Aspect Row Count', 'dwh.fact_review_aspect', @batch_id,
        '> 0 rows',
        CONCAT(@fra_count, ' rows'),
        CASE WHEN @fra_count > 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @fra_count > 0 THEN NULL ELSE 'fact_review_aspect is empty' END);

-- 9.14 Fact Review Aspect Referential Integrity (Rating Key)
DECLARE @orphan_fra_ratings INT = 0;
SELECT @orphan_fra_ratings = COUNT(*)
FROM dwh.fact_review_aspect fra
LEFT JOIN dwh.fact_rating fr ON fra.rating_key = fr.rating_key
WHERE fr.rating_key IS NULL;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Review Aspect Rating FK Integrity', 'fra.rating_key -> fact_rating', @batch_id,
        '0 orphaned rows',
        CONCAT(@orphan_fra_ratings, ' orphaned rows'),
        CASE WHEN @orphan_fra_ratings = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @orphan_fra_ratings = 0 THEN NULL ELSE 'fact_review_aspect has orphaned rating_key values' END);

-- 9.15 Fact Review Aspect Referential Integrity (Aspect & Sentiment)
DECLARE @invalid_fra_dimensions INT = 0;
SELECT @invalid_fra_dimensions = COUNT(*)
FROM dwh.fact_review_aspect fra
LEFT JOIN dwh.dim_aspect da ON fra.aspect_id = da.aspect_id
LEFT JOIN dwh.dim_sentiment_type ds ON fra.sentiment_type_id = ds.sentiment_type_id
WHERE da.aspect_id IS NULL OR ds.sentiment_type_id IS NULL;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Review Aspect Dimension FK Integrity', 'fra.aspect_id & sentiment_type_id', @batch_id,
        '0 invalid foreign keys',
        CONCAT(@invalid_fra_dimensions, ' invalid foreign keys'),
        CASE WHEN @invalid_fra_dimensions = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @invalid_fra_dimensions = 0 THEN NULL ELSE 'Invalid aspect_id or sentiment_type_id in fact_review_aspect' END);

-- 9.16 Fact Review Aspect Uniqueness Check
DECLARE @fra_duplicates INT = 0;
SELECT @fra_duplicates = COUNT(*)
FROM (
    SELECT rating_id, aspect_id, sentiment_type_id, COUNT(*) AS dup_cnt
    FROM dwh.fact_review_aspect
    GROUP BY rating_id, aspect_id, sentiment_type_id
    HAVING COUNT(*) > 1
) d;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Review Aspect Uniqueness Check', 'rating_id + aspect_id + sentiment_type_id', @batch_id,
        '0 duplicate records',
        CONCAT(@fra_duplicates, ' duplicate records'),
        CASE WHEN @fra_duplicates = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @fra_duplicates = 0 THEN NULL ELSE 'Duplicate aspect extractions found for same rating' END);

-- 9.17 Fact Review Aspect Multi-Aspect Separation Check (Tasty but a bit late)
DECLARE @multi_aspect_anomalies INT = 0;
SELECT @multi_aspect_anomalies = COUNT(*)
FROM (
    SELECT fra.rating_id, COUNT(DISTINCT fra.aspect_id) AS distinct_aspects
    FROM dwh.fact_review_aspect fra
    JOIN dwh.fact_rating fr ON fra.rating_key = fr.rating_key
    WHERE fr.review_text = 'Tasty but a bit late'
    GROUP BY fra.rating_id
    HAVING COUNT(DISTINCT fra.aspect_id) <> 2
) a;

INSERT INTO #test_results (test_name, entity_name, batch_id, expected_value, actual_value, status, error_message)
VALUES ('Multi-Aspect Separation Check', 'Tasty but a bit late -> 2 aspects', @batch_id,
        '0 anomalies (all have 2 aspects)',
        CONCAT(@multi_aspect_anomalies, ' anomalies'),
        CASE WHEN @multi_aspect_anomalies = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @multi_aspect_anomalies = 0 THEN NULL ELSE 'Multi-aspect separation failed for Tasty but a bit late' END);



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
