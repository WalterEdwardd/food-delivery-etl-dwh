/*
================================================================================
PROJECT : Food Delivery ETL & Data Warehouse
FILE    : 02_verify_raw_load.sql
PURPOSE : Integration and reconciliation tests for STG -> RAW

================================================================================
TEST SCOPE
================================================================================

This script validates the complete STG -> RAW loading process for ONE batch.

Tests:

01. Environment validation
02. Batch validation
03. Stored procedure validation
04. Execute STG -> RAW batch load
05. Row count reconciliation
06. Duplicate lineage - STG
07. Duplicate lineage - RAW
08. STG -> RAW lineage preservation
09. RAW -> STG lineage preservation
10. Source-value preservation
11. Metadata preservation
12. Rerun / batch-replacement idempotency
13. Final test summary

================================================================================
IMPORTANT
================================================================================

This script is an INTEGRATION TEST.

It intentionally EXECUTES:

    dbo.usp_load_raw_batch

Therefore it modifies RAW data and creates ETL log records.

Do NOT use this as a read-only monitoring query.

For manual smoke testing of individual entities, use:

    04_stg_to_raw.sql

================================================================================
RAW DESIGN CONTRACT
================================================================================

RAW must preserve:

    business/source columns
    batch_id
    source_file_name
    source_row_number
    load_timestamp

RAW must NOT perform:

    trimming
    casting
    normalization
    business transformation
    business validation

================================================================================
PERFORMANCE DESIGN
================================================================================

All tests are scoped to @batch_id.

Lineage comparisons use:

    batch_id
    source_file_name
    source_row_number

The test intentionally avoids SELECT * and avoids unnecessary full-table
comparisons.

================================================================================
*/

USE FoodDeliveryDW;
GO

SET NOCOUNT ON;
GO


/*==============================================================================
  0. TEST CONFIGURATION
==============================================================================*/

DECLARE @batch_id BIGINT = 1;


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
  HELPER CONCEPT
==============================================================================

Every test writes one row to #test_results.

SUCCESS = test passed
FAIL    = test failed

The script continues collecting results whenever possible.

At the end, the script throws if one or more tests failed.
==============================================================================*/


/*==============================================================================
  2. ENVIRONMENT VALIDATION
==============================================================================*/

IF DB_NAME() = 'FoodDeliveryDW'
BEGIN

    INSERT INTO #test_results
    (
        test_name,
        expected_value,
        actual_value,
        status
    )
    VALUES
    (
        'Environment validation',
        'FoodDeliveryDW',
        DB_NAME(),
        'PASS'
    );

END
ELSE
BEGIN

    INSERT INTO #test_results
    (
        test_name,
        expected_value,
        actual_value,
        status,
        error_message
    )
    VALUES
    (
        'Environment validation',
        'FoodDeliveryDW',
        DB_NAME(),
        'FAIL',
        'Script must be executed against FoodDeliveryDW.'
    );

END;


/*==============================================================================
  3. BATCH VALIDATION
==============================================================================*/

IF @batch_id IS NULL
BEGIN

    INSERT INTO #test_results
    (
        test_name,
        status,
        error_message
    )
    VALUES
    (
        'Batch validation',
        'FAIL',
        'batch_id must be supplied.'
    );

END
ELSE
BEGIN

    IF EXISTS
    (
        SELECT 1
        FROM stg.stg_customer
        WHERE batch_id = @batch_id

        UNION ALL

        SELECT 1
        FROM stg.stg_restaurant
        WHERE batch_id = @batch_id

        UNION ALL

        SELECT 1
        FROM stg.stg_menu_item
        WHERE batch_id = @batch_id

        UNION ALL

        SELECT 1
        FROM stg.stg_delivery_partner
        WHERE batch_id = @batch_id

        UNION ALL

        SELECT 1
        FROM stg.stg_order
        WHERE batch_id = @batch_id

        UNION ALL

        SELECT 1
        FROM stg.stg_order_item
        WHERE batch_id = @batch_id

        UNION ALL

        SELECT 1
        FROM stg.stg_delivery_performance
        WHERE batch_id = @batch_id

        UNION ALL

        SELECT 1
        FROM stg.stg_rating
        WHERE batch_id = @batch_id
    )
    BEGIN

        INSERT INTO #test_results
        (
            test_name,
            expected_value,
            actual_value,
            status
        )
        VALUES
        (
            'Batch validation',
            'Batch exists in STG',
            CONCAT('batch_id=', @batch_id),
            'PASS'
        );

    END
    ELSE
    BEGIN

        INSERT INTO #test_results
        (
            test_name,
            expected_value,
            actual_value,
            status,
            error_message
        )
        VALUES
        (
            'Batch validation',
            'Batch exists in STG',
            CONCAT('batch_id=', @batch_id),
            'FAIL',
            'Specified batch_id does not exist in any STG table.'
        );

    END;

END;


/*==============================================================================
  4. STORED PROCEDURE VALIDATION
==============================================================================*/

DECLARE @expected_procedures TABLE
(
    procedure_name SYSNAME
);

INSERT INTO @expected_procedures
(
    procedure_name
)
VALUES
    ('usp_load_raw_customer'),
    ('usp_load_raw_restaurant'),
    ('usp_load_raw_menu_item'),
    ('usp_load_raw_delivery_partner'),
    ('usp_load_raw_order'),
    ('usp_load_raw_order_item'),
    ('usp_load_raw_delivery_performance'),
    ('usp_load_raw_rating'),
    ('usp_load_raw_batch');


INSERT INTO #test_results
(
    test_name,
    entity_name,
    expected_value,
    actual_value,
    status
)
SELECT
    'Stored procedure validation',
    p.procedure_name,
    'Procedure exists',
    CASE
        WHEN sp.object_id IS NOT NULL
            THEN 'Exists'
        ELSE 'Missing'
    END,
    CASE
        WHEN sp.object_id IS NOT NULL
            THEN 'PASS'
        ELSE 'FAIL'
    END
FROM @expected_procedures p
LEFT JOIN sys.procedures sp
    ON sp.name = p.procedure_name
   AND SCHEMA_NAME(sp.schema_id) = 'dbo';


/*==============================================================================
  5. EXECUTE PRODUCTION STG -> RAW ORCHESTRATOR
==============================================================================*/

BEGIN TRY

    EXEC dbo.usp_load_raw_batch
        @batch_id = @batch_id;

    INSERT INTO #test_results
    (
        test_name,
        expected_value,
        actual_value,
        status
    )
    VALUES
    (
        'STG -> RAW batch execution',
        'Procedure completes successfully',
        CONCAT('batch_id=', @batch_id),
        'PASS'
    );

END TRY
BEGIN CATCH

    INSERT INTO #test_results
    (
        test_name,
        expected_value,
        actual_value,
        status,
        error_message
    )
    VALUES
    (
        'STG -> RAW batch execution',
        'Procedure completes successfully',
        CONCAT('batch_id=', @batch_id),
        'FAIL',
        ERROR_MESSAGE()
    );

END CATCH;


/*==============================================================================
  6. ROW COUNT RECONCILIATION
==============================================================================

Expected:

    STG count = RAW count

for each entity and the selected batch.

==============================================================================*/

DECLARE
    @stg_count BIGINT,
    @raw_count BIGINT;


/*------------------------------------------------------------------------------
  CUSTOMER
------------------------------------------------------------------------------*/

SELECT @stg_count = COUNT_BIG(*)
FROM stg.stg_customer
WHERE batch_id = @batch_id;

SELECT @raw_count = COUNT_BIG(*)
FROM raw.raw_customer
WHERE batch_id = @batch_id;

INSERT INTO #test_results
(
    test_name,
    entity_name,
    expected_value,
    actual_value,
    status
)
VALUES
(
    'Row count reconciliation',
    'customer',
    CAST(@stg_count AS VARCHAR(500)),
    CAST(@raw_count AS VARCHAR(500)),
    CASE WHEN @stg_count = @raw_count THEN 'PASS' ELSE 'FAIL' END
);


/*------------------------------------------------------------------------------
  RESTAURANT
------------------------------------------------------------------------------*/

SELECT @stg_count = COUNT_BIG(*)
FROM stg.stg_restaurant
WHERE batch_id = @batch_id;

SELECT @raw_count = COUNT_BIG(*)
FROM raw.raw_restaurant
WHERE batch_id = @batch_id;

INSERT INTO #test_results
VALUES
(
    'Row count reconciliation',
    'restaurant',
    CAST(@stg_count AS VARCHAR(500)),
    CAST(@raw_count AS VARCHAR(500)),
    CASE WHEN @stg_count = @raw_count THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
);


/*------------------------------------------------------------------------------
  MENU ITEM
------------------------------------------------------------------------------*/

SELECT @stg_count = COUNT_BIG(*)
FROM stg.stg_menu_item
WHERE batch_id = @batch_id;

SELECT @raw_count = COUNT_BIG(*)
FROM raw.raw_menu_item
WHERE batch_id = @batch_id;

INSERT INTO #test_results
VALUES
(
    'Row count reconciliation',
    'menu_item',
    CAST(@stg_count AS VARCHAR(500)),
    CAST(@raw_count AS VARCHAR(500)),
    CASE WHEN @stg_count = @raw_count THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
);


/*------------------------------------------------------------------------------
  DELIVERY PARTNER
------------------------------------------------------------------------------*/

SELECT @stg_count = COUNT_BIG(*)
FROM stg.stg_delivery_partner
WHERE batch_id = @batch_id;

SELECT @raw_count = COUNT_BIG(*)
FROM raw.raw_delivery_partner
WHERE batch_id = @batch_id;

INSERT INTO #test_results
VALUES
(
    'Row count reconciliation',
    'delivery_partner',
    CAST(@stg_count AS VARCHAR(500)),
    CAST(@raw_count AS VARCHAR(500)),
    CASE WHEN @stg_count = @raw_count THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
);


/*------------------------------------------------------------------------------
  ORDER
------------------------------------------------------------------------------*/

SELECT @stg_count = COUNT_BIG(*)
FROM stg.stg_order
WHERE batch_id = @batch_id;

SELECT @raw_count = COUNT_BIG(*)
FROM raw.raw_order
WHERE batch_id = @batch_id;

INSERT INTO #test_results
VALUES
(
    'Row count reconciliation',
    'order',
    CAST(@stg_count AS VARCHAR(500)),
    CAST(@raw_count AS VARCHAR(500)),
    CASE WHEN @stg_count = @raw_count THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
);


/*------------------------------------------------------------------------------
  ORDER ITEM
------------------------------------------------------------------------------*/

SELECT @stg_count = COUNT_BIG(*)
FROM stg.stg_order_item
WHERE batch_id = @batch_id;

SELECT @raw_count = COUNT_BIG(*)
FROM raw.raw_order_item
WHERE batch_id = @batch_id;

INSERT INTO #test_results
VALUES
(
    'Row count reconciliation',
    'order_item',
    CAST(@stg_count AS VARCHAR(500)),
    CAST(@raw_count AS VARCHAR(500)),
    CASE WHEN @stg_count = @raw_count THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
);


/*------------------------------------------------------------------------------
  DELIVERY PERFORMANCE
------------------------------------------------------------------------------*/

SELECT @stg_count = COUNT_BIG(*)
FROM stg.stg_delivery_performance
WHERE batch_id = @batch_id;

SELECT @raw_count = COUNT_BIG(*)
FROM raw.raw_delivery_performance
WHERE batch_id = @batch_id;

INSERT INTO #test_results
VALUES
(
    'Row count reconciliation',
    'delivery_performance',
    CAST(@stg_count AS VARCHAR(500)),
    CAST(@raw_count AS VARCHAR(500)),
    CASE WHEN @stg_count = @raw_count THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
);


/*------------------------------------------------------------------------------
  RATING
------------------------------------------------------------------------------*/

SELECT @stg_count = COUNT_BIG(*)
FROM stg.stg_rating
WHERE batch_id = @batch_id;

SELECT @raw_count = COUNT_BIG(*)
FROM raw.raw_rating
WHERE batch_id = @batch_id;

INSERT INTO #test_results
VALUES
(
    'Row count reconciliation',
    'rating',
    CAST(@stg_count AS VARCHAR(500)),
    CAST(@raw_count AS VARCHAR(500)),
    CASE WHEN @stg_count = @raw_count THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
);


/*==============================================================================
  7. DUPLICATE LINEAGE - STG
==============================================================================

Lineage key:

    batch_id
    source_file_name
    source_row_number

Each combination should occur at most once.

==============================================================================*/


/* CUSTOMER */
INSERT INTO #test_results
SELECT
    'Duplicate lineage - STG',
    'customer',
    '0 duplicate lineage groups',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM stg.stg_customer
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
) d;


/* RESTAURANT */
INSERT INTO #test_results
SELECT
    'Duplicate lineage - STG',
    'restaurant',
    '0 duplicate lineage groups',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM stg.stg_restaurant
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
) d;


/* MENU ITEM */
INSERT INTO #test_results
SELECT
    'Duplicate lineage - STG',
    'menu_item',
    '0 duplicate lineage groups',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM stg.stg_menu_item
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
) d;


/* DELIVERY PARTNER */
INSERT INTO #test_results
SELECT
    'Duplicate lineage - STG',
    'delivery_partner',
    '0 duplicate lineage groups',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM stg.stg_delivery_partner
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
) d;


/* ORDER */
INSERT INTO #test_results
SELECT
    'Duplicate lineage - STG',
    'order',
    '0 duplicate lineage groups',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM stg.stg_order
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
) d;


/* ORDER ITEM */
INSERT INTO #test_results
SELECT
    'Duplicate lineage - STG',
    'order_item',
    '0 duplicate lineage groups',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM stg.stg_order_item
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
) d;


/* DELIVERY PERFORMANCE */
INSERT INTO #test_results
SELECT
    'Duplicate lineage - STG',
    'delivery_performance',
    '0 duplicate lineage groups',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM stg.stg_delivery_performance
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
) d;


/* RATING */
INSERT INTO #test_results
SELECT
    'Duplicate lineage - STG',
    'rating',
    '0 duplicate lineage groups',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM stg.stg_rating
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
) d;


/*==============================================================================
  8. DUPLICATE LINEAGE - RAW
==============================================================================*/

/* CUSTOMER */
INSERT INTO #test_results
SELECT
    'Duplicate lineage - RAW',
    'customer',
    '0 duplicate lineage groups',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM raw.raw_customer
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
) d;


/* RESTAURANT */
INSERT INTO #test_results
SELECT
    'Duplicate lineage - RAW',
    'restaurant',
    '0 duplicate lineage groups',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM raw.raw_restaurant
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
) d;


/* MENU ITEM */
INSERT INTO #test_results
SELECT
    'Duplicate lineage - RAW',
    'menu_item',
    '0 duplicate lineage groups',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM raw.raw_menu_item
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
) d;


/* DELIVERY PARTNER */
INSERT INTO #test_results
SELECT
    'Duplicate lineage - RAW',
    'delivery_partner',
    '0 duplicate lineage groups',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM raw.raw_delivery_partner
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
) d;


/* ORDER */
INSERT INTO #test_results
SELECT
    'Duplicate lineage - RAW',
    'order',
    '0 duplicate lineage groups',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM raw.raw_order
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
) d;


/* ORDER ITEM */
INSERT INTO #test_results
SELECT
    'Duplicate lineage - RAW',
    'order_item',
    '0 duplicate lineage groups',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM raw.raw_order_item
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
) d;


/* DELIVERY PERFORMANCE */
INSERT INTO #test_results
SELECT
    'Duplicate lineage - RAW',
    'delivery_performance',
    '0 duplicate lineage groups',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM raw.raw_delivery_performance
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
) d;


/* RATING */
INSERT INTO #test_results
SELECT
    'Duplicate lineage - RAW',
    'rating',
    '0 duplicate lineage groups',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number
    FROM raw.raw_rating
    WHERE batch_id = @batch_id
    GROUP BY
        batch_id,
        source_file_name,
        source_row_number
    HAVING COUNT_BIG(*) > 1
) d;


/*==============================================================================
  9. STG -> RAW LINEAGE PRESERVATION
==============================================================================

For every STG lineage record there must be exactly one corresponding RAW
lineage record.

==============================================================================*/


/* CUSTOMER */
INSERT INTO #test_results
SELECT
    'STG -> RAW lineage',
    'customer',
    '0 missing lineage records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        s.batch_id,
        s.source_file_name,
        s.source_row_number
    FROM stg.stg_customer s
    LEFT JOIN raw.raw_customer r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND r.source_row_number IS NULL
) x;


/* RESTAURANT */
INSERT INTO #test_results
SELECT
    'STG -> RAW lineage',
    'restaurant',
    '0 missing lineage records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        s.batch_id,
        s.source_file_name,
        s.source_row_number
    FROM stg.stg_restaurant s
    LEFT JOIN raw.raw_restaurant r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND r.source_row_number IS NULL
) x;


/* MENU ITEM */
INSERT INTO #test_results
SELECT
    'STG -> RAW lineage',
    'menu_item',
    '0 missing lineage records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        s.batch_id,
        s.source_file_name,
        s.source_row_number
    FROM stg.stg_menu_item s
    LEFT JOIN raw.raw_menu_item r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND r.source_row_number IS NULL
) x;


/* DELIVERY PARTNER */
INSERT INTO #test_results
SELECT
    'STG -> RAW lineage',
    'delivery_partner',
    '0 missing lineage records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        s.batch_id,
        s.source_file_name,
        s.source_row_number
    FROM stg.stg_delivery_partner s
    LEFT JOIN raw.raw_delivery_partner r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND r.source_row_number IS NULL
) x;


/* ORDER */
INSERT INTO #test_results
SELECT
    'STG -> RAW lineage',
    'order',
    '0 missing lineage records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        s.batch_id,
        s.source_file_name,
        s.source_row_number
    FROM stg.stg_order s
    LEFT JOIN raw.raw_order r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND r.source_row_number IS NULL
) x;


/* ORDER ITEM */
INSERT INTO #test_results
SELECT
    'STG -> RAW lineage',
    'order_item',
    '0 missing lineage records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        s.batch_id,
        s.source_file_name,
        s.source_row_number
    FROM stg.stg_order_item s
    LEFT JOIN raw.raw_order_item r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND r.source_row_number IS NULL
) x;


/* DELIVERY PERFORMANCE */
INSERT INTO #test_results
SELECT
    'STG -> RAW lineage',
    'delivery_performance',
    '0 missing lineage records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        s.batch_id,
        s.source_file_name,
        s.source_row_number
    FROM stg.stg_delivery_performance s
    LEFT JOIN raw.raw_delivery_performance r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND r.source_row_number IS NULL
) x;


/* RATING */
INSERT INTO #test_results
SELECT
    'STG -> RAW lineage',
    'rating',
    '0 missing lineage records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        s.batch_id,
        s.source_file_name,
        s.source_row_number
    FROM stg.stg_rating s
    LEFT JOIN raw.raw_rating r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND r.source_row_number IS NULL
) x;


/*==============================================================================
  10. RAW -> STG LINEAGE PRESERVATION
==============================================================================

Reverse direction.

This catches unexpected RAW records that do not exist in STG.

==============================================================================*/


/* CUSTOMER */
INSERT INTO #test_results
SELECT
    'RAW -> STG lineage',
    'customer',
    '0 extra lineage records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        r.batch_id,
        r.source_file_name,
        r.source_row_number
    FROM raw.raw_customer r
    LEFT JOIN stg.stg_customer s
        ON  s.batch_id = r.batch_id
        AND s.source_file_name = r.source_file_name
        AND s.source_row_number = r.source_row_number
    WHERE r.batch_id = @batch_id
      AND s.source_row_number IS NULL
) x;


/* RESTAURANT */
INSERT INTO #test_results
SELECT
    'RAW -> STG lineage',
    'restaurant',
    '0 extra lineage records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        r.batch_id,
        r.source_file_name,
        r.source_row_number
    FROM raw.raw_restaurant r
    LEFT JOIN stg.stg_restaurant s
        ON  s.batch_id = r.batch_id
        AND s.source_file_name = r.source_file_name
        AND s.source_row_number = r.source_row_number
    WHERE r.batch_id = @batch_id
      AND s.source_row_number IS NULL
) x;


/* MENU ITEM */
INSERT INTO #test_results
SELECT
    'RAW -> STG lineage',
    'menu_item',
    '0 extra lineage records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        r.batch_id,
        r.source_file_name,
        r.source_row_number
    FROM raw.raw_menu_item r
    LEFT JOIN stg.stg_menu_item s
        ON  s.batch_id = r.batch_id
        AND s.source_file_name = r.source_file_name
        AND s.source_row_number = r.source_row_number
    WHERE r.batch_id = @batch_id
      AND s.source_row_number IS NULL
) x;


/* DELIVERY PARTNER */
INSERT INTO #test_results
SELECT
    'RAW -> STG lineage',
    'delivery_partner',
    '0 extra lineage records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        r.batch_id,
        r.source_file_name,
        r.source_row_number
    FROM raw.raw_delivery_partner r
    LEFT JOIN stg.stg_delivery_partner s
        ON  s.batch_id = r.batch_id
        AND s.source_file_name = r.source_file_name
        AND s.source_row_number = r.source_row_number
    WHERE r.batch_id = @batch_id
      AND s.source_row_number IS NULL
) x;


/* ORDER */
INSERT INTO #test_results
SELECT
    'RAW -> STG lineage',
    'order',
    '0 extra lineage records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        r.batch_id,
        r.source_file_name,
        r.source_row_number
    FROM raw.raw_order r
    LEFT JOIN stg.stg_order s
        ON  s.batch_id = r.batch_id
        AND s.source_file_name = r.source_file_name
        AND s.source_row_number = r.source_row_number
    WHERE r.batch_id = @batch_id
      AND s.source_row_number IS NULL
) x;


/* ORDER ITEM */
INSERT INTO #test_results
SELECT
    'RAW -> STG lineage',
    'order_item',
    '0 extra lineage records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        r.batch_id,
        r.source_file_name,
        r.source_row_number
    FROM raw.raw_order_item r
    LEFT JOIN stg.stg_order_item s
        ON  s.batch_id = r.batch_id
        AND s.source_file_name = r.source_file_name
        AND s.source_row_number = r.source_row_number
    WHERE r.batch_id = @batch_id
      AND s.source_row_number IS NULL
) x;


/* DELIVERY PERFORMANCE */
INSERT INTO #test_results
SELECT
    'RAW -> STG lineage',
    'delivery_performance',
    '0 extra lineage records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        r.batch_id,
        r.source_file_name,
        r.source_row_number
    FROM raw.raw_delivery_performance r
    LEFT JOIN stg.stg_delivery_performance s
        ON  s.batch_id = r.batch_id
        AND s.source_file_name = r.source_file_name
        AND s.source_row_number = r.source_row_number
    WHERE r.batch_id = @batch_id
      AND s.source_row_number IS NULL
) x;


/* RATING */
INSERT INTO #test_results
SELECT
    'RAW -> STG lineage',
    'rating',
    '0 extra lineage records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        r.batch_id,
        r.source_file_name,
        r.source_row_number
    FROM raw.raw_rating r
    LEFT JOIN stg.stg_rating s
        ON  s.batch_id = r.batch_id
        AND s.source_file_name = r.source_file_name
        AND s.source_row_number = r.source_row_number
    WHERE r.batch_id = @batch_id
      AND s.source_row_number IS NULL
) x;


/*==============================================================================
  11. SOURCE-VALUE PRESERVATION
==============================================================================

RAW must contain the same source values as STG.

No:

    TRIM
    CAST
    NORMALIZATION
    BUSINESS TRANSFORMATION

is allowed at this stage.

The test compares source columns through lineage.

==============================================================================*/


/* CUSTOMER */
INSERT INTO #test_results
SELECT
    'Source-value preservation',
    'customer',
    '0 mismatched records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT 1 AS mismatch
    FROM stg.stg_customer s
    INNER JOIN raw.raw_customer r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND
      (
           ISNULL(s.customer_id, '') <> ISNULL(r.customer_id, '')
        OR ISNULL(s.signup_date, '') <> ISNULL(r.signup_date, '')
        OR ISNULL(s.city, '') <> ISNULL(r.city, '')
        OR ISNULL(s.acquisition_channel, '')
           <> ISNULL(r.acquisition_channel, '')
      )
) x;


/* RESTAURANT */
INSERT INTO #test_results
SELECT
    'Source-value preservation',
    'restaurant',
    '0 mismatched records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT 1 AS mismatch
    FROM stg.stg_restaurant s
    INNER JOIN raw.raw_restaurant r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND
      (
           ISNULL(s.restaurant_id, '') <> ISNULL(r.restaurant_id, '')
        OR ISNULL(s.restaurant_name, '') <> ISNULL(r.restaurant_name, '')
        OR ISNULL(s.city, '') <> ISNULL(r.city, '')
        OR ISNULL(s.cuisine_type, '') <> ISNULL(r.cuisine_type, '')
        OR ISNULL(s.partner_type, '') <> ISNULL(r.partner_type, '')
        OR ISNULL(s.avg_prep_time_min, '') <> ISNULL(r.avg_prep_time_min, '')
        OR ISNULL(s.is_active, '') <> ISNULL(r.is_active, '')
      )
) x;


/* MENU ITEM */
INSERT INTO #test_results
SELECT
    'Source-value preservation',
    'menu_item',
    '0 mismatched records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT 1 AS mismatch
    FROM stg.stg_menu_item s
    INNER JOIN raw.raw_menu_item r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND
      (
           ISNULL(s.menu_item_id, '') <> ISNULL(r.menu_item_id, '')
        OR ISNULL(s.restaurant_id, '') <> ISNULL(r.restaurant_id, '')
        OR ISNULL(s.item_name, '') <> ISNULL(r.item_name, '')
        OR ISNULL(s.category, '') <> ISNULL(r.category, '')
        OR ISNULL(s.is_veg, '') <> ISNULL(r.is_veg, '')
        OR ISNULL(s.price, '') <> ISNULL(r.price, '')
      )
) x;


/* DELIVERY PARTNER */
INSERT INTO #test_results
SELECT
    'Source-value preservation',
    'delivery_partner',
    '0 mismatched records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT 1 AS mismatch
    FROM stg.stg_delivery_partner s
    INNER JOIN raw.raw_delivery_partner r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND
      (
           ISNULL(s.delivery_partner_id, '') <> ISNULL(r.delivery_partner_id, '')
        OR ISNULL(s.partner_name, '') <> ISNULL(r.partner_name, '')
        OR ISNULL(s.city, '') <> ISNULL(r.city, '')
        OR ISNULL(s.vehicle_type, '') <> ISNULL(r.vehicle_type, '')
        OR ISNULL(s.employment_type, '') <> ISNULL(r.employment_type, '')
        OR ISNULL(s.avg_rating, '') <> ISNULL(r.avg_rating, '')
        OR ISNULL(s.is_active, '') <> ISNULL(r.is_active, '')
      )
) x;


/* ORDER */
INSERT INTO #test_results
SELECT
    'Source-value preservation',
    'order',
    '0 mismatched records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT 1 AS mismatch
    FROM stg.stg_order s
    INNER JOIN raw.raw_order r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND
      (
           ISNULL(s.order_id, '') <> ISNULL(r.order_id, '')
        OR ISNULL(s.customer_id, '') <> ISNULL(r.customer_id, '')
        OR ISNULL(s.restaurant_id, '') <> ISNULL(r.restaurant_id, '')
        OR ISNULL(s.delivery_partner_id, '') <> ISNULL(r.delivery_partner_id, '')
        OR ISNULL(s.order_timestamp, '') <> ISNULL(r.order_timestamp, '')
        OR ISNULL(s.subtotal_amount, '') <> ISNULL(r.subtotal_amount, '')
        OR ISNULL(s.discount_amount, '') <> ISNULL(r.discount_amount, '')
        OR ISNULL(s.delivery_fee, '') <> ISNULL(r.delivery_fee, '')
        OR ISNULL(s.total_amount, '') <> ISNULL(r.total_amount, '')
        OR ISNULL(s.is_cod, '') <> ISNULL(r.is_cod, '')
        OR ISNULL(s.is_cancelled, '') <> ISNULL(r.is_cancelled, '')
      )
) x;


/* ORDER ITEM */
INSERT INTO #test_results
SELECT
    'Source-value preservation',
    'order_item',
    '0 mismatched records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT 1 AS mismatch
    FROM stg.stg_order_item s
    INNER JOIN raw.raw_order_item r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND
      (
           ISNULL(s.order_line_id, '') <> ISNULL(r.order_line_id, '')
        OR ISNULL(s.order_id, '') <> ISNULL(r.order_id, '')
        OR ISNULL(s.menu_item_id, '') <> ISNULL(r.menu_item_id, '')
        OR ISNULL(s.restaurant_id, '') <> ISNULL(r.restaurant_id, '')
        OR ISNULL(s.quantity, '') <> ISNULL(r.quantity, '')
        OR ISNULL(s.unit_price, '') <> ISNULL(r.unit_price, '')
        OR ISNULL(s.item_discount, '') <> ISNULL(r.item_discount, '')
        OR ISNULL(s.line_total, '') <> ISNULL(r.line_total, '')
      )
) x;


/* DELIVERY PERFORMANCE */
INSERT INTO #test_results
SELECT
    'Source-value preservation',
    'delivery_performance',
    '0 mismatched records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT 1 AS mismatch
    FROM stg.stg_delivery_performance s
    INNER JOIN raw.raw_delivery_performance r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND
      (
           ISNULL(s.delivery_id, '') <> ISNULL(r.delivery_id, '')
        OR ISNULL(s.order_id, '') <> ISNULL(r.order_id, '')
        OR ISNULL(s.order_item, '') <> ISNULL(r.order_item, '')
        OR ISNULL(s.expected_delivery_time_min, '')
           <> ISNULL(r.expected_delivery_time_min, '')
        OR ISNULL(s.actual_delivery_time_min, '')
           <> ISNULL(r.actual_delivery_time_min, '')
        OR ISNULL(s.delivery_item, '') <> ISNULL(r.delivery_item, '')
        OR ISNULL(s.distance_km, '') <> ISNULL(r.distance_km, '')
      )
) x;


/* RATING */
INSERT INTO #test_results
SELECT
    'Source-value preservation',
    'rating',
    '0 mismatched records',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT 1 AS mismatch
    FROM stg.stg_rating s
    INNER JOIN raw.raw_rating r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND
      (
           ISNULL(s.rating_id, '') <> ISNULL(r.rating_id, '')
        OR ISNULL(s.order_id, '') <> ISNULL(r.order_id, '')
        OR ISNULL(s.customer_id, '') <> ISNULL(r.customer_id, '')
        OR ISNULL(s.restaurant_id, '') <> ISNULL(r.restaurant_id, '')
        OR ISNULL(s.rating, '') <> ISNULL(r.rating, '')
        OR ISNULL(s.review_text, '') <> ISNULL(r.review_text, '')
        OR ISNULL(s.review_timestamp, '') <> ISNULL(r.review_timestamp, '')
        OR ISNULL(s.sentiment_score, '') <> ISNULL(r.sentiment_score, '')
      )
) x;


/*==============================================================================
  12. METADATA PRESERVATION
==============================================================================

Check:

    batch_id
    source_file_name
    source_row_number

must match between STG and RAW.

==============================================================================*/

INSERT INTO #test_results
SELECT
    'Metadata preservation',
    'ALL 8 ENTITIES',
    '0 metadata mismatches',
    CAST(COUNT_BIG(*) AS VARCHAR(500)),
    CASE WHEN COUNT_BIG(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
    NULL,
    SYSDATETIME()
FROM
(
    SELECT
        s.batch_id,
        s.source_file_name,
        s.source_row_number
    FROM stg.stg_customer s
    LEFT JOIN raw.raw_customer r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND r.source_row_number IS NULL

    UNION ALL

    SELECT
        s.batch_id,
        s.source_file_name,
        s.source_row_number
    FROM stg.stg_restaurant s
    LEFT JOIN raw.raw_restaurant r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND r.source_row_number IS NULL

    UNION ALL

    SELECT
        s.batch_id,
        s.source_file_name,
        s.source_row_number
    FROM stg.stg_menu_item s
    LEFT JOIN raw.raw_menu_item r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND r.source_row_number IS NULL

    UNION ALL

    SELECT
        s.batch_id,
        s.source_file_name,
        s.source_row_number
    FROM stg.stg_delivery_partner s
    LEFT JOIN raw.raw_delivery_partner r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND r.source_row_number IS NULL

    UNION ALL

    SELECT
        s.batch_id,
        s.source_file_name,
        s.source_row_number
    FROM stg.stg_order s
    LEFT JOIN raw.raw_order r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND r.source_row_number IS NULL

    UNION ALL

    SELECT
        s.batch_id,
        s.source_file_name,
        s.source_row_number
    FROM stg.stg_order_item s
    LEFT JOIN raw.raw_order_item r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND r.source_row_number IS NULL

    UNION ALL

    SELECT
        s.batch_id,
        s.source_file_name,
        s.source_row_number
    FROM stg.stg_delivery_performance s
    LEFT JOIN raw.raw_delivery_performance r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND r.source_row_number IS NULL

    UNION ALL

    SELECT
        s.batch_id,
        s.source_file_name,
        s.source_row_number
    FROM stg.stg_rating s
    LEFT JOIN raw.raw_rating r
        ON  r.batch_id = s.batch_id
        AND r.source_file_name = s.source_file_name
        AND r.source_row_number = s.source_row_number
    WHERE s.batch_id = @batch_id
      AND r.source_row_number IS NULL
) x;


/*==============================================================================
  13. RERUN / BATCH-REPLACEMENT IDEMPOTENCY
==============================================================================

The production procedure uses:

    DELETE FROM RAW WHERE batch_id = @batch_id
    INSERT FROM STG WHERE batch_id = @batch_id

Therefore running the same batch again should NOT increase the final RAW
row count.

We capture RAW counts before rerun, execute the batch again, then compare.

==============================================================================*/

DECLARE
    @before_customer BIGINT,
    @before_restaurant BIGINT,
    @before_menu_item BIGINT,
    @before_delivery_partner BIGINT,
    @before_order BIGINT,
    @before_order_item BIGINT,
    @before_delivery_performance BIGINT,
    @before_rating BIGINT;

SELECT @before_customer =
    COUNT_BIG(*)
FROM raw.raw_customer
WHERE batch_id = @batch_id;

SELECT @before_restaurant =
    COUNT_BIG(*)
FROM raw.raw_restaurant
WHERE batch_id = @batch_id;

SELECT @before_menu_item =
    COUNT_BIG(*)
FROM raw.raw_menu_item
WHERE batch_id = @batch_id;

SELECT @before_delivery_partner =
    COUNT_BIG(*)
FROM raw.raw_delivery_partner
WHERE batch_id = @batch_id;

SELECT @before_order =
    COUNT_BIG(*)
FROM raw.raw_order
WHERE batch_id = @batch_id;

SELECT @before_order_item =
    COUNT_BIG(*)
FROM raw.raw_order_item
WHERE batch_id = @batch_id;

SELECT @before_delivery_performance =
    COUNT_BIG(*)
FROM raw.raw_delivery_performance
WHERE batch_id = @batch_id;

SELECT @before_rating =
    COUNT_BIG(*)
FROM raw.raw_rating
WHERE batch_id = @batch_id;


/*------------------------------------------------------------------------------
  Execute second run
------------------------------------------------------------------------------*/

BEGIN TRY

    EXEC dbo.usp_load_raw_batch
        @batch_id = @batch_id;

END TRY
BEGIN CATCH

    INSERT INTO #test_results
    (
        test_name,
        entity_name,
        expected_value,
        actual_value,
        status,
        error_message
    )
    VALUES
    (
        'Rerun / idempotency',
        'ALL 8 ENTITIES',
        'Second execution succeeds',
        'Second execution failed',
        'FAIL',
        ERROR_MESSAGE()
    );

END CATCH;


/*------------------------------------------------------------------------------
  Compare final counts
------------------------------------------------------------------------------*/

DECLARE
    @after_customer BIGINT,
    @after_restaurant BIGINT,
    @after_menu_item BIGINT,
    @after_delivery_partner BIGINT,
    @after_order BIGINT,
    @after_order_item BIGINT,
    @after_delivery_performance BIGINT,
    @after_rating BIGINT;

SELECT @after_customer =
    COUNT_BIG(*)
FROM raw.raw_customer
WHERE batch_id = @batch_id;

SELECT @after_restaurant =
    COUNT_BIG(*)
FROM raw.raw_restaurant
WHERE batch_id = @batch_id;

SELECT @after_menu_item =
    COUNT_BIG(*)
FROM raw.raw_menu_item
WHERE batch_id = @batch_id;

SELECT @after_delivery_partner =
    COUNT_BIG(*)
FROM raw.raw_delivery_partner
WHERE batch_id = @batch_id;

SELECT @after_order =
    COUNT_BIG(*)
FROM raw.raw_order
WHERE batch_id = @batch_id;

SELECT @after_order_item =
    COUNT_BIG(*)
FROM raw.raw_order_item
WHERE batch_id = @batch_id;

SELECT @after_delivery_performance =
    COUNT_BIG(*)
FROM raw.raw_delivery_performance
WHERE batch_id = @batch_id;

SELECT @after_rating =
    COUNT_BIG(*)
FROM raw.raw_rating
WHERE batch_id = @batch_id;


INSERT INTO #test_results
(
    test_name,
    entity_name,
    expected_value,
    actual_value,
    status
)
VALUES
(
    'Rerun / idempotency',
    'customer',
    CAST(@before_customer AS VARCHAR(500)),
    CAST(@after_customer AS VARCHAR(500)),
    CASE WHEN @before_customer = @after_customer THEN 'PASS' ELSE 'FAIL' END
),
(
    'Rerun / idempotency',
    'restaurant',
    CAST(@before_restaurant AS VARCHAR(500)),
    CAST(@after_restaurant AS VARCHAR(500)),
    CASE WHEN @before_restaurant = @after_restaurant THEN 'PASS' ELSE 'FAIL' END
),
(
    'Rerun / idempotency',
    'menu_item',
    CAST(@before_menu_item AS VARCHAR(500)),
    CAST(@after_menu_item AS VARCHAR(500)),
    CASE WHEN @before_menu_item = @after_menu_item THEN 'PASS' ELSE 'FAIL' END
),
(
    'Rerun / idempotency',
    'delivery_partner',
    CAST(@before_delivery_partner AS VARCHAR(500)),
    CAST(@after_delivery_partner AS VARCHAR(500)),
    CASE WHEN @before_delivery_partner = @after_delivery_partner THEN 'PASS' ELSE 'FAIL' END
),
(
    'Rerun / idempotency',
    'order',
    CAST(@before_order AS VARCHAR(500)),
    CAST(@after_order AS VARCHAR(500)),
    CASE WHEN @before_order = @after_order THEN 'PASS' ELSE 'FAIL' END
),
(
    'Rerun / idempotency',
    'order_item',
    CAST(@before_order_item AS VARCHAR(500)),
    CAST(@after_order_item AS VARCHAR(500)),
    CASE WHEN @before_order_item = @after_order_item THEN 'PASS' ELSE 'FAIL' END
),
(
    'Rerun / idempotency',
    'delivery_performance',
    CAST(@before_delivery_performance AS VARCHAR(500)),
    CAST(@after_delivery_performance AS VARCHAR(500)),
    CASE WHEN @before_delivery_performance = @after_delivery_performance THEN 'PASS' ELSE 'FAIL' END
),
(
    'Rerun / idempotency',
    'rating',
    CAST(@before_rating AS VARCHAR(500)),
    CAST(@after_rating AS VARCHAR(500)),
    CASE WHEN @before_rating = @after_rating THEN 'PASS' ELSE 'FAIL' END
);


/*==============================================================================
  14. FINAL TEST RESULT DETAIL
==============================================================================*/

SELECT
    test_id,
    test_name,
    entity_name,
    expected_value,
    actual_value,
    status,
    error_message,
    test_timestamp
FROM #test_results
ORDER BY
    test_id;


/*==============================================================================
  15. FINAL SUMMARY
==============================================================================*/

DECLARE
    @total_tests  INT,
    @passed_tests INT,
    @failed_tests INT;

SELECT
    @total_tests = COUNT(*),
    @passed_tests = SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END),
    @failed_tests = SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END)
FROM #test_results;


SELECT
    @batch_id       AS batch_id,
    @total_tests    AS total_tests,
    @passed_tests   AS passed_tests,
    @failed_tests   AS failed_tests,
    CASE
        WHEN @failed_tests = 0
            THEN 'PASS'
        ELSE 'FAIL'
    END AS overall_status;


/*==============================================================================
  16. FAIL THE SCRIPT IF ANY TEST FAILED
==============================================================================*/

IF @failed_tests > 0
BEGIN

    THROW 50010,
          'STG -> RAW verification failed. Review #test_results and the test detail output.',
          1;

END;


/*==============================================================================
  END OF VERIFICATION
==============================================================================*/
