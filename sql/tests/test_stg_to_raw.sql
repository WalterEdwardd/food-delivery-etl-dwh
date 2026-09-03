/*
================================================================================
PROJECT : Food Delivery ETL & Data Warehouse
FILE    : test_stg_to_raw.sql
PURPOSE : Automated test suite for STG -> RAW

TEST COVERAGE
-------------
1. Row Count Reconciliation
2. Idempotency
3. Duplicate Source Lineage
4. Metadata / Lineage Preservation

TABLES
------
1. customer
2. restaurant
3. menu_item
4. delivery_partner
5. order
6. order_item
7. delivery_performance
8. rating

IMPORTANT
---------
- This script is intended for DEV / TEST environments.
- The script executes STG -> RAW stored procedures.
- No business transformation is expected between STG and RAW.
- RAW should remain source-preserving.
- Existing RAW data for the selected batch may be replaced by the
  idempotent load procedures.

AUTHOR : FoodDeliveryETL
================================================================================
*/

USE FoodDeliveryDW;
GO

/*==============================================================================
0. TEST CONFIGURATION
==============================================================================*/

DECLARE @batch_id BIGINT;

/*
    Select the latest batch available in STG.

    For development/testing this is convenient.

    In production, the orchestration layer should pass the exact batch_id
    explicitly instead of relying on MAX(batch_id).
*/

SELECT
    @batch_id =	MAX(batch_id)
FROM stg.stg_restaurant;

IF @batch_id IS NULL
BEGIN
	PRINT '';
	THROW 99999,
		'TEST FAILED: No batch_id was found in STG.',
		1;
END;

PRINT '------------------------------------------------------------';
PRINT 'STG -> RAW TEST SUITE';
PRINT '------------------------------------------------------------';
PRINT 'Database : FoodDeliveryDW';
PRINT 'Batch ID : ' + CAST(@batch_id AS VARCHAR(50));
PRINT '------------------------------------------------------------';


/*==============================================================================
1. TEST RESULT TABLE
==============================================================================*/

IF OBJECT_ID('tempdb..#test_results') IS NOT NULL
BEGIN
    DROP TABLE #test_results;
END;

CREATE TABLE #test_results
(
    test_id              INT IDENTITY(1,1),
    test_category        VARCHAR(100) NOT NULL,
    table_name           VARCHAR(100) NOT NULL,
    status               VARCHAR(10) NOT NULL,
    expected_value       VARCHAR(500) NULL,
    actual_value         VARCHAR(500) NULL,
    error_message        VARCHAR(1000) NULL,
    test_timestamp       DATETIME2(3) NOT NULL
        DEFAULT SYSDATETIME()
);


/*==============================================================================
2. TEST 1 — ROW COUNT RECONCILIATION
==============================================================================*/

PRINT '';
PRINT '------------------------------------------------------------';
PRINT 'TEST 1 — ROW COUNT RECONCILIATION';
PRINT '------------------------------------------------------------';


-- 2.1 CUSTOMER

DECLARE @stg_customer_count BIGINT;
DECLARE @raw_customer_count BIGINT;

SELECT
    @stg_customer_count = COUNT_BIG(*)
FROM stg.stg_customer
WHERE batch_id = @batch_id;

SELECT
    @raw_customer_count = COUNT_BIG(*)
FROM raw.raw_customer
WHERE batch_id = @batch_id;

IF @stg_customer_count = @raw_customer_count
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'ROW_COUNT',
        'customer',
        'PASS',
        CAST(@stg_customer_count AS VARCHAR(100)),
        CAST(@raw_customer_count AS VARCHAR(100)),
        NULL
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'ROW_COUNT',
        'customer',
        'FAIL',
        CAST(@stg_customer_count AS VARCHAR(100)),
        CAST(@raw_customer_count AS VARCHAR(100)),
        'STG and RAW row counts do not match.'
    );

END;


-- 2.2 RESTAURANT

DECLARE @stg_restaurant_count BIGINT;
DECLARE @raw_restaurant_count BIGINT;

SELECT
    @stg_restaurant_count = COUNT_BIG(*)
FROM stg.stg_restaurant
WHERE batch_id = @batch_id;

SELECT
    @raw_restaurant_count = COUNT_BIG(*)
FROM raw.raw_restaurant
WHERE batch_id = @batch_id;

IF @stg_restaurant_count = @raw_restaurant_count
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'ROW_COUNT',
        'restaurant',
        'PASS',
        CAST(@stg_restaurant_count AS VARCHAR(100)),
        CAST(@raw_restaurant_count AS VARCHAR(100))
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'ROW_COUNT',
        'restaurant',
        'FAIL',
        CAST(@stg_restaurant_count AS VARCHAR(100)),
        CAST(@raw_restaurant_count AS VARCHAR(100)),
        'STG and RAW row counts do not match.'
    );

END;


-- 2.3 MENU ITEM

DECLARE @stg_menu_item_count BIGINT;
DECLARE @raw_menu_item_count BIGINT;

SELECT
    @stg_menu_item_count = COUNT_BIG(*)
FROM stg.stg_menu_item
WHERE batch_id = @batch_id;

SELECT
    @raw_menu_item_count = COUNT_BIG(*)
FROM raw.raw_menu_item
WHERE batch_id = @batch_id;

IF @stg_menu_item_count = @raw_menu_item_count
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'ROW_COUNT',
        'menu_item',
        'PASS',
        CAST(@stg_menu_item_count AS VARCHAR(100)),
        CAST(@raw_menu_item_count AS VARCHAR(100))
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'ROW_COUNT',
        'menu_item',
        'FAIL',
        CAST(@stg_menu_item_count AS VARCHAR(100)),
        CAST(@raw_menu_item_count AS VARCHAR(100)),
        'STG and RAW row counts do not match.'
    );

END;


-- 2.4 DELIVERY PARTNER

DECLARE @stg_delivery_partner_count BIGINT;
DECLARE @raw_delivery_partner_count BIGINT;

SELECT
    @stg_delivery_partner_count = COUNT_BIG(*)
FROM stg.stg_delivery_partner
WHERE batch_id = @batch_id;

SELECT
    @raw_delivery_partner_count = COUNT_BIG(*)
FROM raw.raw_delivery_partner
WHERE batch_id = @batch_id;

IF @stg_delivery_partner_count = @raw_delivery_partner_count
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'ROW_COUNT',
        'delivery_partner',
        'PASS',
        CAST(@stg_delivery_partner_count AS VARCHAR(100)),
        CAST(@raw_delivery_partner_count AS VARCHAR(100))
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'ROW_COUNT',
        'delivery_partner',
        'FAIL',
        CAST(@stg_delivery_partner_count AS VARCHAR(100)),
        CAST(@raw_delivery_partner_count AS VARCHAR(100)),
        'STG and RAW row counts do not match.'
    );

END;


-- 2.5 ORDER

DECLARE @stg_order_count BIGINT;
DECLARE @raw_order_count BIGINT;

SELECT
    @stg_order_count = COUNT_BIG(*)
FROM stg.stg_order
WHERE batch_id = @batch_id;

SELECT
    @raw_order_count = COUNT_BIG(*)
FROM raw.raw_order
WHERE batch_id = @batch_id;

IF @stg_order_count = @raw_order_count
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'ROW_COUNT',
        'order',
        'PASS',
        CAST(@stg_order_count AS VARCHAR(100)),
        CAST(@raw_order_count AS VARCHAR(100))
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'ROW_COUNT',
        'order',
        'FAIL',
        CAST(@stg_order_count AS VARCHAR(100)),
        CAST(@raw_order_count AS VARCHAR(100)),
        'STG and RAW row counts do not match.'
    );

END;


-- 2.6 ORDER ITEM

DECLARE @stg_order_item_count BIGINT;
DECLARE @raw_order_item_count BIGINT;

SELECT
    @stg_order_item_count = COUNT_BIG(*)
FROM stg.stg_order_item
WHERE batch_id = @batch_id;

SELECT
    @raw_order_item_count = COUNT_BIG(*)
FROM raw.raw_order_item
WHERE batch_id = @batch_id;

IF @stg_order_item_count = @raw_order_item_count
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'ROW_COUNT',
        'order_item',
        'PASS',
        CAST(@stg_order_item_count AS VARCHAR(100)),
        CAST(@raw_order_item_count AS VARCHAR(100))
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'ROW_COUNT',
        'order_item',
        'FAIL',
        CAST(@stg_order_item_count AS VARCHAR(100)),
        CAST(@raw_order_item_count AS VARCHAR(100)),
        'STG and RAW row counts do not match.'
    );

END;


-- 2.7 DELIVERY PERFORMANCE

DECLARE @stg_delivery_performance_count BIGINT;
DECLARE @raw_delivery_performance_count BIGINT;

SELECT
    @stg_delivery_performance_count = COUNT_BIG(*)
FROM stg.stg_delivery_performance
WHERE batch_id = @batch_id;

SELECT
    @raw_delivery_performance_count = COUNT_BIG(*)
FROM raw.raw_delivery_performance
WHERE batch_id = @batch_id;

IF @stg_delivery_performance_count = @raw_delivery_performance_count
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'ROW_COUNT',
        'delivery_performance',
        'PASS',
        CAST(@stg_delivery_performance_count AS VARCHAR(100)),
        CAST(@raw_delivery_performance_count AS VARCHAR(100))
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'ROW_COUNT',
        'delivery_performance',
        'FAIL',
        CAST(@stg_delivery_performance_count AS VARCHAR(100)),
        CAST(@raw_delivery_performance_count AS VARCHAR(100)),
        'STG and RAW row counts do not match.'
    );

END;


-- 2.8 RATING

DECLARE @stg_rating_count BIGINT;
DECLARE @raw_rating_count BIGINT;

SELECT
    @stg_rating_count = COUNT_BIG(*)
FROM stg.stg_rating
WHERE batch_id = @batch_id;

SELECT
    @raw_rating_count = COUNT_BIG(*)
FROM raw.raw_rating
WHERE batch_id = @batch_id;

IF @stg_rating_count = @raw_rating_count
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'ROW_COUNT',
        'rating',
        'PASS',
        CAST(@stg_rating_count AS VARCHAR(100)),
        CAST(@raw_rating_count AS VARCHAR(100))
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'ROW_COUNT',
        'rating',
        'FAIL',
        CAST(@stg_rating_count AS VARCHAR(100)),
        CAST(@raw_rating_count AS VARCHAR(100)),
        'STG and RAW row counts do not match.'
    );

END;


/*==============================================================================
3. TEST 2 — IDEMPOTENCY
==============================================================================*/

PRINT '';
PRINT '------------------------------------------------------------';
PRINT 'TEST 2 — IDEMPOTENCY';
PRINT '------------------------------------------------------------';

/*
    Definition used in this project:

    Running the same batch twice must NOT create additional RAW records.

    Expected:

        First execution count
                    =
        Second execution count
                    =
        STG count
*/


-- 3.1 CUSTOMER

DECLARE @customer_first_count BIGINT;
DECLARE @customer_second_count BIGINT;

EXEC dbo.usp_load_raw_customer
    @batch_id = @batch_id;

SELECT
    @customer_first_count = COUNT_BIG(*)
FROM raw.raw_customer
WHERE batch_id = @batch_id;

EXEC dbo.usp_load_raw_customer
    @batch_id = @batch_id;

SELECT
    @customer_second_count = COUNT_BIG(*)
FROM raw.raw_customer
WHERE batch_id = @batch_id;

IF
    @customer_first_count = @customer_second_count
    AND @customer_second_count = @stg_customer_count
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'IDEMPOTENCY',
        'customer',
        'PASS',
        CAST(@customer_first_count AS VARCHAR(100)),
        CAST(@customer_second_count AS VARCHAR(100))
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'IDEMPOTENCY',
        'customer',
        'FAIL',
        CAST(@customer_first_count AS VARCHAR(100)),
        CAST(@customer_second_count AS VARCHAR(100)),
        'Repeated execution changed RAW row count.'
    );

END;


-- 3.2 RESTAURANT

DECLARE @restaurant_first_count BIGINT;
DECLARE @restaurant_second_count BIGINT;

EXEC dbo.usp_load_raw_restaurant
    @batch_id = @batch_id;

SELECT
    @restaurant_first_count = COUNT_BIG(*)
FROM raw.raw_restaurant
WHERE batch_id = @batch_id;

EXEC dbo.usp_load_raw_restaurant
    @batch_id = @batch_id;

SELECT
    @restaurant_second_count = COUNT_BIG(*)
FROM raw.raw_restaurant
WHERE batch_id = @batch_id;

IF
    @restaurant_first_count = @restaurant_second_count
    AND @restaurant_second_count = @stg_restaurant_count
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'IDEMPOTENCY',
        'restaurant',
        'PASS',
        CAST(@restaurant_first_count AS VARCHAR(100)),
        CAST(@restaurant_second_count AS VARCHAR(100))
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'IDEMPOTENCY',
        'restaurant',
        'FAIL',
        CAST(@restaurant_first_count AS VARCHAR(100)),
        CAST(@restaurant_second_count AS VARCHAR(100)),
        'Repeated execution changed RAW row count.'
    );

END;


-- 3.3 MENU ITEM

DECLARE @menu_item_first_count BIGINT;
DECLARE @menu_item_second_count BIGINT;

EXEC dbo.usp_load_raw_menu_item
    @batch_id = @batch_id;

SELECT
    @menu_item_first_count = COUNT_BIG(*)
FROM raw.raw_menu_item
WHERE batch_id = @batch_id;

EXEC dbo.usp_load_raw_menu_item
    @batch_id = @batch_id;

SELECT
    @menu_item_second_count = COUNT_BIG(*)
FROM raw.raw_menu_item
WHERE batch_id = @batch_id;

IF
    @menu_item_first_count = @menu_item_second_count
    AND @menu_item_second_count = @stg_menu_item_count
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'IDEMPOTENCY',
        'menu_item',
        'PASS',
        CAST(@menu_item_first_count AS VARCHAR(100)),
        CAST(@menu_item_second_count AS VARCHAR(100))
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'IDEMPOTENCY',
        'menu_item',
        'FAIL',
        CAST(@menu_item_first_count AS VARCHAR(100)),
        CAST(@menu_item_second_count AS VARCHAR(100)),
        'Repeated execution changed RAW row count.'
    );

END;


-- 3.4 DELIVERY PARTNER

DECLARE @delivery_partner_first_count BIGINT;
DECLARE @delivery_partner_second_count BIGINT;

EXEC dbo.usp_load_raw_delivery_partner
    @batch_id = @batch_id;

SELECT
    @delivery_partner_first_count = COUNT_BIG(*)
FROM raw.raw_delivery_partner
WHERE batch_id = @batch_id;

EXEC dbo.usp_load_raw_delivery_partner
    @batch_id = @batch_id;

SELECT
    @delivery_partner_second_count = COUNT_BIG(*)
FROM raw.raw_delivery_partner
WHERE batch_id = @batch_id;

IF
    @delivery_partner_first_count = @delivery_partner_second_count
    AND @delivery_partner_second_count = @stg_delivery_partner_count
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'IDEMPOTENCY',
        'delivery_partner',
        'PASS',
        CAST(@delivery_partner_first_count AS VARCHAR(100)),
        CAST(@delivery_partner_second_count AS VARCHAR(100))
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'IDEMPOTENCY',
        'delivery_partner',
        'FAIL',
        CAST(@delivery_partner_first_count AS VARCHAR(100)),
        CAST(@delivery_partner_second_count AS VARCHAR(100)),
        'Repeated execution changed RAW row count.'
    );

END;


-- 3.5 ORDER

DECLARE @order_first_count BIGINT;
DECLARE @order_second_count BIGINT;

EXEC dbo.usp_load_raw_order
    @batch_id = @batch_id;

SELECT
    @order_first_count = COUNT_BIG(*)
FROM raw.raw_order
WHERE batch_id = @batch_id;

EXEC dbo.usp_load_raw_order
    @batch_id = @batch_id;

SELECT
    @order_second_count = COUNT_BIG(*)
FROM raw.raw_order
WHERE batch_id = @batch_id;

IF
    @order_first_count = @order_second_count
    AND @order_second_count = @stg_order_count
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'IDEMPOTENCY',
        'order',
        'PASS',
        CAST(@order_first_count AS VARCHAR(100)),
        CAST(@order_second_count AS VARCHAR(100))
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'IDEMPOTENCY',
        'order',
        'FAIL',
        CAST(@order_first_count AS VARCHAR(100)),
        CAST(@order_second_count AS VARCHAR(100)),
        'Repeated execution changed RAW row count.'
    );

END;


-- 3.6 ORDER ITEM

DECLARE @order_item_first_count BIGINT;
DECLARE @order_item_second_count BIGINT;

EXEC dbo.usp_load_raw_order_item
    @batch_id = @batch_id;

SELECT
    @order_item_first_count = COUNT_BIG(*)
FROM raw.raw_order_item
WHERE batch_id = @batch_id;

EXEC dbo.usp_load_raw_order_item
    @batch_id = @batch_id;

SELECT
    @order_item_second_count = COUNT_BIG(*)
FROM raw.raw_order_item
WHERE batch_id = @batch_id;

IF
    @order_item_first_count = @order_item_second_count
    AND @order_item_second_count = @stg_order_item_count
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'IDEMPOTENCY',
        'order_item',
        'PASS',
        CAST(@order_item_first_count AS VARCHAR(100)),
        CAST(@order_item_second_count AS VARCHAR(100))
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'IDEMPOTENCY',
        'order_item',
        'FAIL',
        CAST(@order_item_first_count AS VARCHAR(100)),
        CAST(@order_item_second_count AS VARCHAR(100)),
        'Repeated execution changed RAW row count.'
    );

END;


-- 3.7 DELIVERY PERFORMANCE

DECLARE @delivery_performance_first_count BIGINT;
DECLARE @delivery_performance_second_count BIGINT;

EXEC dbo.usp_load_raw_delivery_performance
    @batch_id = @batch_id;

SELECT
    @delivery_performance_first_count = COUNT_BIG(*)
FROM raw.raw_delivery_performance
WHERE batch_id = @batch_id;

EXEC dbo.usp_load_raw_delivery_performance
    @batch_id = @batch_id;

SELECT
    @delivery_performance_second_count = COUNT_BIG(*)
FROM raw.raw_delivery_performance
WHERE batch_id = @batch_id;

IF
    @delivery_performance_first_count = @delivery_performance_second_count
    AND @delivery_performance_second_count = @stg_delivery_performance_count
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'IDEMPOTENCY',
        'delivery_performance',
        'PASS',
        CAST(@delivery_performance_first_count AS VARCHAR(100)),
        CAST(@delivery_performance_second_count AS VARCHAR(100))
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'IDEMPOTENCY',
        'delivery_performance',
        'FAIL',
        CAST(@delivery_performance_first_count AS VARCHAR(100)),
        CAST(@delivery_performance_second_count AS VARCHAR(100)),
        'Repeated execution changed RAW row count.'
    );

END;


-- 3.8 RATING

DECLARE @rating_first_count BIGINT;
DECLARE @rating_second_count BIGINT;


EXEC dbo.usp_load_raw_rating
    @batch_id = @batch_id;

SELECT
    @rating_first_count = COUNT_BIG(*)
FROM raw.raw_rating
WHERE batch_id = @batch_id;

EXEC dbo.usp_load_raw_rating
    @batch_id = @batch_id;

SELECT
    @rating_second_count = COUNT_BIG(*)
FROM raw.raw_rating
WHERE batch_id = @batch_id;

IF
    @rating_first_count = @rating_second_count
    AND @rating_second_count = @stg_rating_count
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'IDEMPOTENCY',
        'rating',
        'PASS',
        CAST(@rating_first_count AS VARCHAR(100)),
        CAST(@rating_second_count AS VARCHAR(100))
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'IDEMPOTENCY',
        'rating',
        'FAIL',
        CAST(@rating_first_count AS VARCHAR(100)),
        CAST(@rating_second_count AS VARCHAR(100)),
        'Repeated execution changed RAW row count.'
    );

END;


/*==============================================================================
4. TEST 3 — DUPLICATE SOURCE LINEAGE
==============================================================================*/

PRINT '';
PRINT '------------------------------------------------------------';
PRINT 'TEST 3 — DUPLICATE SOURCE LINEAGE';
PRINT '------------------------------------------------------------';

/*
    A source row is identified by:

        batch_id
        source_file_name
        source_row_number

    RAW must not contain multiple records representing the same source row.
*/


-- 4.1 CUSTOMER

IF EXISTS
(
    SELECT
        1
    FROM raw.raw_customer
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
)
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'DUPLICATE_LINEAGE',
        'customer',
        'FAIL',
        '0 duplicate source rows',
        'Duplicate source rows found',
        'Duplicate source lineage detected in raw_customer.'
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'DUPLICATE_LINEAGE',
        'customer',
        'PASS',
        '0 duplicate source rows',
        '0 duplicate source rows'
    );

END;


-- 4.2 RESTAURANT

IF EXISTS
(
    SELECT
        1
    FROM raw.raw_restaurant
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
)
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'DUPLICATE_LINEAGE',
        'restaurant',
        'FAIL',
        '0 duplicate source rows',
        'Duplicate source rows found',
        'Duplicate source lineage detected in raw_restaurant.'
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'DUPLICATE_LINEAGE',
        'restaurant',
        'PASS',
        '0 duplicate source rows',
        '0 duplicate source rows'
    );

END;


-- 4.3 MENU ITEM

IF EXISTS
(
    SELECT
        1
    FROM raw.raw_menu_item
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
)
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'DUPLICATE_LINEAGE',
        'menu_item',
        'FAIL',
        '0 duplicate source rows',
        'Duplicate source rows found',
        'Duplicate source lineage detected in raw_menu_item.'
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'DUPLICATE_LINEAGE',
        'menu_item',
        'PASS',
        '0 duplicate source rows',
        '0 duplicate source rows'
    );

END;


-- 4.4 DELIVERY PARTNER

IF EXISTS
(
    SELECT
        1
    FROM raw.raw_delivery_partner
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
)
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'DUPLICATE_LINEAGE',
        'delivery_partner',
        'FAIL',
        '0 duplicate source rows',
        'Duplicate source rows found',
        'Duplicate source lineage detected in raw_delivery_partner.'
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'DUPLICATE_LINEAGE',
        'delivery_partner',
        'PASS',
        '0 duplicate source rows',
        '0 duplicate source rows'
    );

END;


-- 4.5 ORDER

IF EXISTS
(
    SELECT
        1
    FROM raw.raw_order
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
)
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'DUPLICATE_LINEAGE',
        'order',
        'FAIL',
        '0 duplicate source rows',
        'Duplicate source rows found',
        'Duplicate source lineage detected in raw_order.'
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'DUPLICATE_LINEAGE',
        'order',
        'PASS',
        '0 duplicate source rows',
        '0 duplicate source rows'
    );

END;


-- 4.6 ORDER ITEM

IF EXISTS
(
    SELECT
        1
    FROM raw.raw_order_item
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
)
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'DUPLICATE_LINEAGE',
        'order_item',
        'FAIL',
        '0 duplicate source rows',
        'Duplicate source rows found',
        'Duplicate source lineage detected in raw_order_item.'
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'DUPLICATE_LINEAGE',
        'order_item',
        'PASS',
        '0 duplicate source rows',
        '0 duplicate source rows'
    );

END;


-- 4.7 DELIVERY PERFORMANCE

IF EXISTS
(
    SELECT
        1
    FROM raw.raw_delivery_performance
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
)
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'DUPLICATE_LINEAGE',
        'delivery_performance',
        'FAIL',
        '0 duplicate source rows',
        'Duplicate source rows found',
        'Duplicate source lineage detected in raw_delivery_performance.'
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'DUPLICATE_LINEAGE',
        'delivery_performance',
        'PASS',
        '0 duplicate source rows',
        '0 duplicate source rows'
    );

END;


-- 4.8 RATING

IF EXISTS
(
    SELECT
        1
    FROM raw.raw_rating
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
)
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'DUPLICATE_LINEAGE',
        'rating',
        'FAIL',
        '0 duplicate source rows',
        'Duplicate source rows found',
        'Duplicate source lineage detected in raw_rating.'
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'DUPLICATE_LINEAGE',
        'rating',
        'PASS',
        '0 duplicate source rows',
        '0 duplicate source rows'
    );

END;


/*==============================================================================
5. TEST 4 — METADATA / LINEAGE PRESERVATION
==============================================================================*/

PRINT '';
PRINT '------------------------------------------------------------';
PRINT 'TEST 4 — METADATA / LINEAGE PRESERVATION';
PRINT '------------------------------------------------------------';

/*
    For STG -> RAW, the following metadata must be preserved:

        batch_id
        source_file_name
        source_row_number

    load_timestamp is also carried from STG to RAW.

    We validate the source lineage using:

        batch_id
        source_file_name
        source_row_number

    The test ensures every STG source row has exactly one corresponding RAW row.
*/


-- 5.1 CUSTOMER

DECLARE @customer_lineage_mismatch BIGINT;

SELECT
    @customer_lineage_mismatch = COUNT_BIG(*)
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM stg.stg_customer
    WHERE batch_id = @batch_id

    EXCEPT

    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM raw.raw_customer
    WHERE batch_id = @batch_id
) AS x;

IF @customer_lineage_mismatch = 0
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'LINEAGE',
        'customer',
        'PASS',
        '0 mismatched source rows',
        '0 mismatched source rows'
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'LINEAGE',
        'customer',
        'FAIL',
        '0 mismatched source rows',
        CAST(@customer_lineage_mismatch AS VARCHAR(100)),
        'STG source lineage was not fully preserved in RAW.'
    );

END;


-- 5.2 RESTAURANT

DECLARE @restaurant_lineage_mismatch BIGINT;

SELECT
    @restaurant_lineage_mismatch = COUNT_BIG(*)
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM stg.stg_restaurant
    WHERE batch_id = @batch_id

    EXCEPT

    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM raw.raw_restaurant
    WHERE batch_id = @batch_id
) AS x;

IF @restaurant_lineage_mismatch = 0
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'LINEAGE',
        'restaurant',
        'PASS',
        '0 mismatched source rows',
        '0 mismatched source rows'
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'LINEAGE',
        'restaurant',
        'FAIL',
        '0 mismatched source rows',
        CAST(@restaurant_lineage_mismatch AS VARCHAR(100)),
        'STG source lineage was not fully preserved in RAW.'
    );

END;


-- 5.3 MENU ITEM

DECLARE @menu_item_lineage_mismatch BIGINT;

SELECT
    @menu_item_lineage_mismatch = COUNT_BIG(*)
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM stg.stg_menu_item
    WHERE batch_id = @batch_id

    EXCEPT

    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM raw.raw_menu_item
    WHERE batch_id = @batch_id
) AS x;

IF @menu_item_lineage_mismatch = 0
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'LINEAGE',
        'menu_item',
        'PASS',
        '0 mismatched source rows',
        '0 mismatched source rows'
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'LINEAGE',
        'menu_item',
        'FAIL',
        '0 mismatched source rows',
        CAST(@menu_item_lineage_mismatch AS VARCHAR(100)),
        'STG source lineage was not fully preserved in RAW.'
    );

END;


-- 5.4 DELIVERY PARTNER

DECLARE @delivery_partner_lineage_mismatch BIGINT;

SELECT
    @delivery_partner_lineage_mismatch = COUNT_BIG(*)
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM stg.stg_delivery_partner
    WHERE batch_id = @batch_id

    EXCEPT

    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM raw.raw_delivery_partner
    WHERE batch_id = @batch_id
) AS x;

IF @delivery_partner_lineage_mismatch = 0
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'LINEAGE',
        'delivery_partner',
        'PASS',
        '0 mismatched source rows',
        '0 mismatched source rows'
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'LINEAGE',
        'delivery_partner',
        'FAIL',
        '0 mismatched source rows',
        CAST(@delivery_partner_lineage_mismatch AS VARCHAR(100)),
        'STG source lineage was not fully preserved in RAW.'
    );

END;


-- 5.5 ORDER

DECLARE @order_lineage_mismatch BIGINT;

SELECT
    @order_lineage_mismatch = COUNT_BIG(*)
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM stg.stg_order
    WHERE batch_id = @batch_id

    EXCEPT

    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM raw.raw_order
    WHERE batch_id = @batch_id
) AS x;

IF @order_lineage_mismatch = 0
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'LINEAGE',
        'order',
        'PASS',
        '0 mismatched source rows',
        '0 mismatched source rows'
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'LINEAGE',
        'order',
        'FAIL',
        '0 mismatched source rows',
        CAST(@order_lineage_mismatch AS VARCHAR(100)),
        'STG source lineage was not fully preserved in RAW.'
    );

END;


-- 5.6 ORDER ITEM

DECLARE @order_item_lineage_mismatch BIGINT;

SELECT
    @order_item_lineage_mismatch = COUNT_BIG(*)
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM stg.stg_order_item
    WHERE batch_id = @batch_id

    EXCEPT

    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM raw.raw_order_item
    WHERE batch_id = @batch_id
) AS x;

IF @order_item_lineage_mismatch = 0
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'LINEAGE',
        'order_item',
        'PASS',
        '0 mismatched source rows',
        '0 mismatched source rows'
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'LINEAGE',
        'order_item',
        'FAIL',
        '0 mismatched source rows',
        CAST(@order_item_lineage_mismatch AS VARCHAR(100)),
        'STG source lineage was not fully preserved in RAW.'
    );

END;


-- 5.7 DELIVERY PERFORMANCE

DECLARE @delivery_performance_lineage_mismatch BIGINT;

SELECT
    @delivery_performance_lineage_mismatch = COUNT_BIG(*)
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM stg.stg_delivery_performance
    WHERE batch_id = @batch_id

    EXCEPT

    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM raw.raw_delivery_performance
    WHERE batch_id = @batch_id
) AS x;

IF @delivery_performance_lineage_mismatch = 0
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'LINEAGE',
        'delivery_performance',
        'PASS',
        '0 mismatched source rows',
        '0 mismatched source rows'
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'LINEAGE',
        'delivery_performance',
        'FAIL',
        '0 mismatched source rows',
        CAST(@delivery_performance_lineage_mismatch AS VARCHAR(100)),
        'STG source lineage was not fully preserved in RAW.'
    );

END;


-- 5.8 RATING

DECLARE @rating_lineage_mismatch BIGINT;

SELECT
    @rating_lineage_mismatch = COUNT_BIG(*)
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM stg.stg_rating
    WHERE batch_id = @batch_id

    EXCEPT

    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM raw.raw_rating
    WHERE batch_id = @batch_id
) AS x;

IF @rating_lineage_mismatch = 0
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value
    )
    VALUES
    (
        'LINEAGE',
        'rating',
        'PASS',
        '0 mismatched source rows',
        '0 mismatched source rows'
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_category,
        table_name,
        status,
        expected_value,
        actual_value,
        error_message
    )
    VALUES
    (
        'LINEAGE',
        'rating',
        'FAIL',
        '0 mismatched source rows',
        CAST(@rating_lineage_mismatch AS VARCHAR(100)),
        'STG source lineage was not fully preserved in RAW.'
    );

END;


/*==============================================================================
6. TEST RESULT DETAIL
==============================================================================*/

PRINT '';
PRINT '------------------------------------------------------------';
PRINT 'TEST RESULT DETAIL';
PRINT '------------------------------------------------------------';


SELECT
    test_id,
    test_category,
    table_name,
    status,
    expected_value,
    actual_value,
    error_message,
    test_timestamp
FROM #test_results
ORDER BY
    test_id;


/*==============================================================================
7. TEST SUMMARY
==============================================================================*/

PRINT '';
PRINT '------------------------------------------------------------';
PRINT 'TEST SUMMARY';
PRINT '------------------------------------------------------------';

SELECT
    test_category,
    COUNT(*) AS total_tests,
    SUM
    (
        CASE
            WHEN status = 'PASS' THEN 1
            ELSE 0
        END
    ) AS passed_tests,
    SUM
    (
        CASE
            WHEN status = 'FAIL' THEN 1
            ELSE 0
        END
    ) AS failed_tests
FROM #test_results
GROUP BY
    test_category
ORDER BY
    test_category;


/*==============================================================================
8. GLOBAL TEST RESULT
==============================================================================*/

DECLARE @total_tests INT;
DECLARE @passed_tests INT;
DECLARE @failed_tests INT;

SELECT
    @total_tests = COUNT(*),
    @passed_tests =
        SUM
        (
            CASE
                WHEN status = 'PASS' THEN 1
                ELSE 0
            END
        ),
    @failed_tests =
        SUM
        (
            CASE
                WHEN status = 'FAIL' THEN 1
                ELSE 0
            END
        )
FROM #test_results;

PRINT '';
PRINT '------------------------------------------------------------';
PRINT 'FINAL RESULT';
PRINT '------------------------------------------------------------';

PRINT 'Total tests : ' + CAST(@total_tests AS VARCHAR(20));
PRINT 'Passed      : ' + CAST(@passed_tests AS VARCHAR(20));
PRINT 'Failed      : ' + CAST(@failed_tests AS VARCHAR(20));

IF @failed_tests = 0
BEGIN

    PRINT '';
    PRINT '------------------------------------------------------------';
    PRINT 'STG -> RAW TEST SUITE PASSED';
    PRINT '------------------------------------------------------------';

END
ELSE
BEGIN

    PRINT '';
    PRINT '------------------------------------------------------------';
    PRINT 'STG -> RAW TEST SUITE FAILED';
    PRINT '------------------------------------------------------------';

    /*
        Throw an error so that automated execution environments
        can detect the failed test.
    */

    THROW 51001,
          'STG -> RAW test suite failed. Check #test_results for details.',
          1;

END;
GO