USE FoodDeliveryDW;
GO

/* =========================================================
   PART 13 - VERIFY RAW -> ODS CUSTOMER
   ========================================================= */


/* ---------------------------------------------------------
   1. RAW row count
   --------------------------------------------------------- */

SELECT
    COUNT(*) AS raw_customer_count
FROM raw.raw_customer;


/* ---------------------------------------------------------
   2. ODS row count
   --------------------------------------------------------- */

SELECT
    COUNT(*) AS ods_customer_count
FROM ods.ods_customer;


/* ---------------------------------------------------------
   3. Customer error count
   --------------------------------------------------------- */

SELECT
    COUNT(*) AS customer_error_count
FROM control.etl_error
WHERE table_name = 'ods_customer';


/* ---------------------------------------------------------
   4. Preview ODS
   --------------------------------------------------------- */

SELECT TOP (5)
    customer_id,
    signup_date,
    city,
    acquisition_channel,
    batch_id,
    source_file_name,
    source_row_number,
    load_timestamp
FROM ods.ods_customer
ORDER BY source_row_number;


/* ---------------------------------------------------------
   5. Check missing customer_id
   --------------------------------------------------------- */

SELECT
    COUNT(*) AS invalid_customer_id_count
FROM ods.ods_customer
WHERE customer_id IS NULL
   OR LTRIM(RTRIM(customer_id)) = '';


/* ---------------------------------------------------------
   6. Check residual whitespace
   --------------------------------------------------------- */

SELECT
    customer_id,
    city,
    acquisition_channel
FROM ods.ods_customer
WHERE
       customer_id <> LTRIM(RTRIM(customer_id))
    OR city <> LTRIM(RTRIM(city))
    OR acquisition_channel <> LTRIM(RTRIM(acquisition_channel));


/* ---------------------------------------------------------
   7. Profile duplicate business keys
   --------------------------------------------------------- */

SELECT
    customer_id,
    COUNT(*) AS row_count
FROM ods.ods_customer
GROUP BY customer_id
HAVING COUNT(*) > 1
ORDER BY row_count DESC;


/* ---------------------------------------------------------
   8. View Customer ETL errors
   --------------------------------------------------------- */

SELECT TOP (5)
    batch_id,
    source_file_name,
    source_row_number,
    table_name,
    column_name,
    error_type,
    error_message,
    raw_value,
    error_timestamp
FROM control.etl_error
WHERE table_name = 'ods_customer'
ORDER BY error_timestamp DESC;


/* ---------------------------------------------------------
   9. Reconciliation using unique rejected records
   --------------------------------------------------------- */

WITH rejected_rows AS
(
    SELECT DISTINCT
        batch_id,
        source_file_name,
        source_row_number
    FROM control.etl_error
    WHERE table_name = 'ods_customer'
)
SELECT
    (SELECT COUNT(*)
     FROM raw.raw_customer) AS raw_rows,

    (SELECT COUNT(*)
     FROM ods.ods_customer) AS ods_rows,

    (SELECT COUNT(*)
     FROM rejected_rows) AS rejected_rows;


/* ---------------------------------------------------------
   10. Verify ODS schema
   --------------------------------------------------------- */

SELECT
    c.column_id,
    c.name AS column_name,
    t.name AS data_type,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable
FROM sys.columns AS c
INNER JOIN sys.types AS t
    ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID(N'ods.ods_customer')
ORDER BY c.column_id;
GO