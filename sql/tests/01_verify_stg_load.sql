USE FoodDeliveryDW;
GO

SET NOCOUNT ON;
GO


/* =========================================================
   PART 1 - STG LOAD VERIFICATION
   Purpose:
       Verify data loaded from CSV source into STG layer.

   Checks:
       1.  Row count
       2.  Batch / source file
       3.  Expected row count reconciliation (latest batch)
       4.  Metadata completeness
       5.  Source row number range
       6.  Source row number gap check
       7.  Duplicate source rows
       8.  Source file consistency
       9.  Sample source data (all 8 tables)
   ========================================================= */


/* =========================================================
   1. VERIFY STG TABLES EXIST
   ========================================================= */

SELECT
    s.name AS schema_name,
    t.name AS table_name
FROM sys.tables t
INNER JOIN sys.schemas s
    ON t.schema_id = s.schema_id
WHERE s.name = 'stg'
ORDER BY t.name;
GO


/* =========================================================
   2. ROW COUNT - ALL STG TABLES
   ========================================================= */

SELECT
    'stg_customer' AS table_name,
    COUNT(*) AS row_count
FROM stg.stg_customer

UNION ALL

SELECT
    'stg_restaurant',
    COUNT(*)
FROM stg.stg_restaurant

UNION ALL

SELECT
    'stg_menu_item',
    COUNT(*)
FROM stg.stg_menu_item

UNION ALL

SELECT
    'stg_delivery_partner',
    COUNT(*)
FROM stg.stg_delivery_partner

UNION ALL

SELECT
    'stg_order',
    COUNT(*)
FROM stg.stg_order

UNION ALL

SELECT
    'stg_order_item',
    COUNT(*)
FROM stg.stg_order_item

UNION ALL

SELECT
    'stg_delivery_performance',
    COUNT(*)
FROM stg.stg_delivery_performance

UNION ALL

SELECT
    'stg_rating',
    COUNT(*)
FROM stg.stg_rating

ORDER BY table_name;
GO


/* =========================================================
   3. EXPECTED ROW COUNT RECONCILIATION
   Filter: latest batch only (multi-batch tables would fail without this)
   ========================================================= */

DECLARE @ExpectedCustomer             BIGINT = 107776;
DECLARE @ExpectedRestaurant           BIGINT = 19995;
DECLARE @ExpectedMenuItem             BIGINT = 342671;
DECLARE @ExpectedDeliveryPartner      BIGINT = 15000;
DECLARE @ExpectedOrder                BIGINT = 149166;
DECLARE @ExpectedOrderItem            BIGINT = 342994;
DECLARE @ExpectedDeliveryPerformance  BIGINT = 149166;
DECLARE @ExpectedRating               BIGINT = 68825;

-- Lấy batch_id lớn nhất trong toàn bộ STG (giả sử mỗi bảng dùng cùng 1 batch)
DECLARE @LatestBatchID BIGINT = (
    SELECT MAX(batch_id) FROM stg.stg_customer
);


SELECT
    v.table_name,
    v.expected_rows,
    v.actual_rows,
    v.actual_rows - v.expected_rows AS difference,
    CASE
        WHEN v.actual_rows = v.expected_rows
            THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM
(
    SELECT
        'stg_customer' AS table_name,
        @ExpectedCustomer AS expected_rows,
        COUNT(*) AS actual_rows
    FROM stg.stg_customer
    WHERE batch_id = @LatestBatchID

    UNION ALL

    SELECT
        'stg_restaurant',
        @ExpectedRestaurant,
        COUNT(*)
    FROM stg.stg_restaurant
    WHERE batch_id = @LatestBatchID

    UNION ALL

    SELECT
        'stg_menu_item',
        @ExpectedMenuItem,
        COUNT(*)
    FROM stg.stg_menu_item
    WHERE batch_id = @LatestBatchID

    UNION ALL

    SELECT
        'stg_delivery_partner',
        @ExpectedDeliveryPartner,
        COUNT(*)
    FROM stg.stg_delivery_partner
    WHERE batch_id = @LatestBatchID

    UNION ALL

    SELECT
        'stg_order',
        @ExpectedOrder,
        COUNT(*)
    FROM stg.stg_order
    WHERE batch_id = @LatestBatchID

    UNION ALL

    SELECT
        'stg_order_item',
        @ExpectedOrderItem,
        COUNT(*)
    FROM stg.stg_order_item
    WHERE batch_id = @LatestBatchID

    UNION ALL

    SELECT
        'stg_delivery_performance',
        @ExpectedDeliveryPerformance,
        COUNT(*)
    FROM stg.stg_delivery_performance
    WHERE batch_id = @LatestBatchID

    UNION ALL

    SELECT
        'stg_rating',
        @ExpectedRating,
        COUNT(*)
    FROM stg.stg_rating
    WHERE batch_id = @LatestBatchID
) v
ORDER BY v.table_name;
GO


/* =========================================================
   4. VERIFY BATCH + SOURCE FILE
   ========================================================= */

SELECT
    'stg_customer' AS table_name,
    batch_id,
    source_file_name,
    COUNT(*) AS row_count,
    MIN(source_row_number) AS min_source_row_number,
    MAX(source_row_number) AS max_source_row_number,
    MIN(load_timestamp) AS min_load_timestamp,
    MAX(load_timestamp) AS max_load_timestamp
FROM stg.stg_customer
GROUP BY
    batch_id,
    source_file_name

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
GROUP BY
    batch_id,
    source_file_name

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
GROUP BY
    batch_id,
    source_file_name

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
GROUP BY
    batch_id,
    source_file_name

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
GROUP BY
    batch_id,
    source_file_name

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
GROUP BY
    batch_id,
    source_file_name

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
GROUP BY
    batch_id,
    source_file_name

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
GROUP BY
    batch_id,
    source_file_name

ORDER BY table_name, min_load_timestamp DESC;
GO


/* =========================================================
   5. METADATA NULL CHECK
   Expected:
       All NULL counts = 0
   ========================================================= */

SELECT
    'stg_customer' AS table_name,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN batch_id IS NULL THEN 1 ELSE 0 END) AS null_batch_id,
    SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END) AS null_source_file_name,
    SUM(CASE WHEN source_row_number IS NULL THEN 1 ELSE 0 END) AS null_source_row_number,
    SUM(CASE WHEN load_timestamp IS NULL THEN 1 ELSE 0 END) AS null_load_timestamp
FROM stg.stg_customer

UNION ALL

SELECT
    'stg_restaurant',
    COUNT(*),
    SUM(CASE WHEN batch_id IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_row_number IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN load_timestamp IS NULL THEN 1 ELSE 0 END)
FROM stg.stg_restaurant

UNION ALL

SELECT
    'stg_menu_item',
    COUNT(*),
    SUM(CASE WHEN batch_id IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_row_number IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN load_timestamp IS NULL THEN 1 ELSE 0 END)
FROM stg.stg_menu_item

UNION ALL

SELECT
    'stg_delivery_partner',
    COUNT(*),
    SUM(CASE WHEN batch_id IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_row_number IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN load_timestamp IS NULL THEN 1 ELSE 0 END)
FROM stg.stg_delivery_partner

UNION ALL

SELECT
    'stg_order',
    COUNT(*),
    SUM(CASE WHEN batch_id IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_row_number IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN load_timestamp IS NULL THEN 1 ELSE 0 END)
FROM stg.stg_order

UNION ALL

SELECT
    'stg_order_item',
    COUNT(*),
    SUM(CASE WHEN batch_id IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_row_number IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN load_timestamp IS NULL THEN 1 ELSE 0 END)
FROM stg.stg_order_item

UNION ALL

SELECT
    'stg_delivery_performance',
    COUNT(*),
    SUM(CASE WHEN batch_id IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_row_number IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN load_timestamp IS NULL THEN 1 ELSE 0 END)
FROM stg.stg_delivery_performance

UNION ALL

SELECT
    'stg_rating',
    COUNT(*),
    SUM(CASE WHEN batch_id IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN source_row_number IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN load_timestamp IS NULL THEN 1 ELSE 0 END)
FROM stg.stg_rating

ORDER BY table_name;
GO


/* =========================================================
   6. SOURCE ROW NUMBER RANGE
   Expected:
       First data row = 2
       Last data row = row_count + 1
   ========================================================= */

SELECT
    'stg_customer' AS table_name,
    MIN(source_row_number) AS min_row_number,
    MAX(source_row_number) AS max_row_number,
    COUNT(*) AS row_count
FROM stg.stg_customer

UNION ALL

SELECT
    'stg_restaurant',
    MIN(source_row_number),
    MAX(source_row_number),
    COUNT(*)
FROM stg.stg_restaurant

UNION ALL

SELECT
    'stg_menu_item',
    MIN(source_row_number),
    MAX(source_row_number),
    COUNT(*)
FROM stg.stg_menu_item

UNION ALL

SELECT
    'stg_delivery_partner',
    MIN(source_row_number),
    MAX(source_row_number),
    COUNT(*)
FROM stg.stg_delivery_partner

UNION ALL

SELECT
    'stg_order',
    MIN(source_row_number),
    MAX(source_row_number),
    COUNT(*)
FROM stg.stg_order

UNION ALL

SELECT
    'stg_order_item',
    MIN(source_row_number),
    MAX(source_row_number),
    COUNT(*)
FROM stg.stg_order_item

UNION ALL

SELECT
    'stg_delivery_performance',
    MIN(source_row_number),
    MAX(source_row_number),
    COUNT(*)
FROM stg.stg_delivery_performance

UNION ALL

SELECT
    'stg_rating',
    MIN(source_row_number),
    MAX(source_row_number),
    COUNT(*)
FROM stg.stg_rating

ORDER BY table_name;
GO


/* =========================================================
   7. SOURCE ROW NUMBER GAP CHECK
   Expected:
       0 rows returned for every table
   Note: PARTITION BY batch_id, source_file_name is required
         to avoid false positives when multiple files/batches
         exist in the same STG table.
   ========================================================= */

WITH numbered AS
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number,
        LAG(source_row_number) OVER (
            PARTITION BY batch_id, source_file_name
            ORDER BY source_row_number
        ) AS previous_row_number
    FROM stg.stg_customer
)
SELECT
    'stg_customer' AS table_name,
    batch_id,
    source_file_name,
    previous_row_number,
    source_row_number
FROM numbered
WHERE previous_row_number IS NOT NULL
  AND source_row_number <> previous_row_number + 1;
GO


WITH numbered AS
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number,
        LAG(source_row_number) OVER (
            PARTITION BY batch_id, source_file_name
            ORDER BY source_row_number
        ) AS previous_row_number
    FROM stg.stg_restaurant
)
SELECT
    'stg_restaurant' AS table_name,
    batch_id,
    source_file_name,
    previous_row_number,
    source_row_number
FROM numbered
WHERE previous_row_number IS NOT NULL
  AND source_row_number <> previous_row_number + 1;
GO


WITH numbered AS
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number,
        LAG(source_row_number) OVER (
            PARTITION BY batch_id, source_file_name
            ORDER BY source_row_number
        ) AS previous_row_number
    FROM stg.stg_menu_item
)
SELECT
    'stg_menu_item' AS table_name,
    batch_id,
    source_file_name,
    previous_row_number,
    source_row_number
FROM numbered
WHERE previous_row_number IS NOT NULL
  AND source_row_number <> previous_row_number + 1;
GO


WITH numbered AS
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number,
        LAG(source_row_number) OVER (
            PARTITION BY batch_id, source_file_name
            ORDER BY source_row_number
        ) AS previous_row_number
    FROM stg.stg_delivery_partner
)
SELECT
    'stg_delivery_partner' AS table_name,
    batch_id,
    source_file_name,
    previous_row_number,
    source_row_number
FROM numbered
WHERE previous_row_number IS NOT NULL
  AND source_row_number <> previous_row_number + 1;
GO


WITH numbered AS
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number,
        LAG(source_row_number) OVER (
            PARTITION BY batch_id, source_file_name
            ORDER BY source_row_number
        ) AS previous_row_number
    FROM stg.stg_order
)
SELECT
    'stg_order' AS table_name,
    batch_id,
    source_file_name,
    previous_row_number,
    source_row_number
FROM numbered
WHERE previous_row_number IS NOT NULL
  AND source_row_number <> previous_row_number + 1;
GO


WITH numbered AS
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number,
        LAG(source_row_number) OVER (
            PARTITION BY batch_id, source_file_name
            ORDER BY source_row_number
        ) AS previous_row_number
    FROM stg.stg_order_item
)
SELECT
    'stg_order_item' AS table_name,
    batch_id,
    source_file_name,
    previous_row_number,
    source_row_number
FROM numbered
WHERE previous_row_number IS NOT NULL
  AND source_row_number <> previous_row_number + 1;
GO


WITH numbered AS
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number,
        LAG(source_row_number) OVER (
            PARTITION BY batch_id, source_file_name
            ORDER BY source_row_number
        ) AS previous_row_number
    FROM stg.stg_delivery_performance
)
SELECT
    'stg_delivery_performance' AS table_name,
    batch_id,
    source_file_name,
    previous_row_number,
    source_row_number
FROM numbered
WHERE previous_row_number IS NOT NULL
  AND source_row_number <> previous_row_number + 1;
GO


WITH numbered AS
(
    SELECT
        batch_id,
        source_file_name,
        source_row_number,
        LAG(source_row_number) OVER (
            PARTITION BY batch_id, source_file_name
            ORDER BY source_row_number
        ) AS previous_row_number
    FROM stg.stg_rating
)
SELECT
    'stg_rating' AS table_name,
    batch_id,
    source_file_name,
    previous_row_number,
    source_row_number
FROM numbered
WHERE previous_row_number IS NOT NULL
  AND source_row_number <> previous_row_number + 1;
GO



/* =========================================================
   8. DUPLICATE SOURCE ROW CHECK
   Expected:
       0 rows returned
   ========================================================= */

SELECT
    'stg_customer' AS table_name,
    batch_id,
    source_file_name,
    source_row_number,
    COUNT(*) AS duplicate_count
FROM stg.stg_customer
GROUP BY
    batch_id,
    source_file_name,
    source_row_number
HAVING COUNT(*) > 1

UNION ALL

SELECT
    'stg_restaurant',
    batch_id,
    source_file_name,
    source_row_number,
    COUNT(*)
FROM stg.stg_restaurant
GROUP BY
    batch_id,
    source_file_name,
    source_row_number
HAVING COUNT(*) > 1

UNION ALL

SELECT
    'stg_menu_item',
    batch_id,
    source_file_name,
    source_row_number,
    COUNT(*)
FROM stg.stg_menu_item
GROUP BY
    batch_id,
    source_file_name,
    source_row_number
HAVING COUNT(*) > 1

UNION ALL

SELECT
    'stg_delivery_partner',
    batch_id,
    source_file_name,
    source_row_number,
    COUNT(*)
FROM stg.stg_delivery_partner
GROUP BY
    batch_id,
    source_file_name,
    source_row_number
HAVING COUNT(*) > 1

UNION ALL

SELECT
    'stg_order',
    batch_id,
    source_file_name,
    source_row_number,
    COUNT(*)
FROM stg.stg_order
GROUP BY
    batch_id,
    source_file_name,
    source_row_number
HAVING COUNT(*) > 1

UNION ALL

SELECT
    'stg_order_item',
    batch_id,
    source_file_name,
    source_row_number,
    COUNT(*)
FROM stg.stg_order_item
GROUP BY
    batch_id,
    source_file_name,
    source_row_number
HAVING COUNT(*) > 1

UNION ALL

SELECT
    'stg_delivery_performance',
    batch_id,
    source_file_name,
    source_row_number,
    COUNT(*)
FROM stg.stg_delivery_performance
GROUP BY
    batch_id,
    source_file_name,
    source_row_number
HAVING COUNT(*) > 1

UNION ALL

SELECT
    'stg_rating',
    batch_id,
    source_file_name,
    source_row_number,
    COUNT(*)
FROM stg.stg_rating
GROUP BY
    batch_id,
    source_file_name,
    source_row_number
HAVING COUNT(*) > 1

ORDER BY table_name;
GO


/* =========================================================
   9. SOURCE FILE CONSISTENCY
   ========================================================= */

SELECT
    'stg_customer' AS table_name,
    source_file_name,
    COUNT(*) AS row_count
FROM stg.stg_customer
GROUP BY source_file_name

UNION ALL

SELECT
    'stg_restaurant',
    source_file_name,
    COUNT(*)
FROM stg.stg_restaurant
GROUP BY source_file_name

UNION ALL

SELECT
    'stg_menu_item',
    source_file_name,
    COUNT(*)
FROM stg.stg_menu_item
GROUP BY source_file_name

UNION ALL

SELECT
    'stg_delivery_partner',
    source_file_name,
    COUNT(*)
FROM stg.stg_delivery_partner
GROUP BY source_file_name

UNION ALL

SELECT
    'stg_order',
    source_file_name,
    COUNT(*)
FROM stg.stg_order
GROUP BY source_file_name

UNION ALL

SELECT
    'stg_order_item',
    source_file_name,
    COUNT(*)
FROM stg.stg_order_item
GROUP BY source_file_name

UNION ALL

SELECT
    'stg_delivery_performance',
    source_file_name,
    COUNT(*)
FROM stg.stg_delivery_performance
GROUP BY source_file_name

UNION ALL

SELECT
    'stg_rating',
    source_file_name,
    COUNT(*)
FROM stg.stg_rating
GROUP BY source_file_name

ORDER BY table_name;
GO


/* =========================================================
   10. SAMPLE DATA - CUSTOMER
   Compare manually with source CSV.
   Purpose:
       Verify source values are preserved.
   ========================================================= */

SELECT TOP (5)
    customer_id,
    signup_date,
    city,
    acquisition_channel,

    batch_id,
    source_file_name,
    source_row_number,
    load_timestamp
FROM stg.stg_customer
ORDER BY source_row_number;
GO


/* =========================================================
   11. SAMPLE DATA - RESTAURANT
   ========================================================= */

SELECT TOP (5)
    restaurant_id,
    restaurant_name,
    city,
    cuisine_type,
    partner_type,
    avg_prep_time_min,
    is_active,

    batch_id,
    source_file_name,
    source_row_number,
    load_timestamp
FROM stg.stg_restaurant
ORDER BY source_row_number;
GO


/* =========================================================
   12. SAMPLE DATA - ORDER
   ========================================================= */

SELECT TOP (5)
    order_id,
    customer_id,
    restaurant_id,
    delivery_partner_id,
    order_timestamp,
    subtotal_amount,
    discount_amount,
    delivery_fee,
    total_amount,
    is_cod,
    is_cancelled,

    batch_id,
    source_file_name,
    source_row_number,
    load_timestamp
FROM stg.stg_order
ORDER BY source_row_number;
GO


/* =========================================================
   13. SAMPLE DATA - MENU ITEM
   ========================================================= */

SELECT TOP (5)
    menu_item_id,
    restaurant_id,
    item_name,
    category,
	is_veg,
    price,

    batch_id,
    source_file_name,
    source_row_number,
    load_timestamp
FROM stg.stg_menu_item
ORDER BY source_row_number;
GO


/* =========================================================
   14. SAMPLE DATA - DELIVERY PARTNER
   ========================================================= */

SELECT TOP (5)
    delivery_partner_id,
    partner_name,
    vehicle_type,
    city,
	employment_type,
    avg_rating,
    is_active,

    batch_id,
    source_file_name,
    source_row_number,
    load_timestamp
FROM stg.stg_delivery_partner
ORDER BY source_row_number;
GO


/* =========================================================
   15. SAMPLE DATA - ORDER ITEM
   ========================================================= */

SELECT TOP (5)
    order_line_id,
    order_id,
    menu_item_id,
	restaurant_id,
    quantity,
    unit_price,
	item_discount,
    line_total,

    batch_id,
    source_file_name,
    source_row_number,
    load_timestamp
FROM stg.stg_order_item
ORDER BY source_row_number;
GO


/* =========================================================
   16. SAMPLE DATA - DELIVERY PERFORMANCE
   ========================================================= */

SELECT TOP (5)
    delivery_id,
	order_id,
	order_item,
	delivery_item,
	expected_delivery_time_min,
	actual_delivery_time_min,
    distance_km,

    batch_id,
    source_file_name,
    source_row_number,
    load_timestamp
FROM stg.stg_delivery_performance
ORDER BY source_row_number;
GO


/* =========================================================
   17. SAMPLE DATA - RATING
   ========================================================= */

SELECT TOP (5)
    rating_id,
    order_id,
    customer_id,
    restaurant_id,
	rating,
	sentiment_score,
    review_text,
    review_timestamp,

    batch_id,
    source_file_name,
    source_row_number,
    load_timestamp
FROM stg.stg_rating
ORDER BY source_row_number;
GO


/* =========================================================
   18. FINAL STG LOAD SUMMARY
   ========================================================= */

SELECT
    'STG LOAD VERIFICATION COMPLETED' AS verification_status,
    SYSDATETIME() AS verification_timestamp;
GO