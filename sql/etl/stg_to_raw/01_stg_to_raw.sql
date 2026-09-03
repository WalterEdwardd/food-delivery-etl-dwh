/*
================================================================================
PROJECT : Food Delivery ETL & Data Warehouse
FILE    : 04_stg_to_raw.sql
PURPOSE : Manual / smoke-test load from STG to RAW

FLOW:
    STG
      |
      v
    RAW

IMPORTANT:
    - RAW must remain source-preserving.
    - No business transformation is performed here.
    - Load is batch-aware.
    - Existing RAW records for the same batch are replaced.
    - Explicit column mapping is mandatory.
    - SELECT * is intentionally not used.

AUTHOR  : FoodDeliveryETL
================================================================================
*/

USE FoodDeliveryDW;
GO


/*==============================================================================
1. IDENTIFY BATCH TO LOAD
==============================================================================*/

DECLARE @batch_id BIGINT;

/*
    Automatically select the latest batch currently available in STG.

    IMPORTANT:
    For production orchestration, the batch_id should normally be supplied
    explicitly by the orchestration layer.

    This automatic selection is intended for manual development / testing.
*/

SELECT
    @batch_id = MAX(batch_id)
FROM stg.stg_restaurant;

IF @batch_id IS NULL
BEGIN
    THROW 50001, 'No batch_id was found in STG.', 1;
END;


/*==============================================================================
2. DISPLAY SELECTED BATCH
==============================================================================*/

SELECT
    @batch_id AS selected_batch_id;


/*==============================================================================
3. LOAD CUSTOMER
==============================================================================*/

BEGIN TRY

    BEGIN TRANSACTION;

    DELETE FROM raw.raw_customer
    WHERE batch_id = @batch_id;

    INSERT INTO raw.raw_customer
    (
        customer_id,
        signup_date,
        city,
        acquisition_channel,
        batch_id,
        source_file_name,
        source_row_number,
        load_timestamp
    )
    SELECT
        customer_id,
        signup_date,
        city,
        acquisition_channel,
        batch_id,
        source_file_name,
        source_row_number,
        load_timestamp
    FROM stg.stg_customer
    WHERE batch_id = @batch_id;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;

END CATCH;


/*==============================================================================
4. LOAD RESTAURANT
==============================================================================*/

BEGIN TRY

    BEGIN TRANSACTION;

    DELETE FROM raw.raw_restaurant
    WHERE batch_id = @batch_id;

    INSERT INTO raw.raw_restaurant
    (
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
    )
    SELECT
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
    WHERE batch_id = @batch_id;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;

END CATCH;


/*==============================================================================
5. LOAD MENU ITEM
==============================================================================*/

BEGIN TRY

    BEGIN TRANSACTION;

    DELETE FROM raw.raw_menu_item
    WHERE batch_id = @batch_id;

    INSERT INTO raw.raw_menu_item
    (
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
    )
    SELECT
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
    WHERE batch_id = @batch_id;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;

END CATCH;


/*==============================================================================
6. LOAD DELIVERY PARTNER
==============================================================================*/

BEGIN TRY

    BEGIN TRANSACTION;

    DELETE FROM raw.raw_delivery_partner
    WHERE batch_id = @batch_id;

    INSERT INTO raw.raw_delivery_partner
    (
        delivery_partner_id,
        partner_name,
        city,
        vehicle_type,
        employment_type,
        avg_rating,
        is_active,
        batch_id,
        source_file_name,
        source_row_number,
        load_timestamp
    )
    SELECT
        delivery_partner_id,
        partner_name,
        city,
        vehicle_type,
        employment_type,
        avg_rating,
        is_active,
        batch_id,
        source_file_name,
        source_row_number,
        load_timestamp
    FROM stg.stg_delivery_partner
    WHERE batch_id = @batch_id;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;

END CATCH;


/*==============================================================================
7. LOAD ORDER
==============================================================================*/

BEGIN TRY

    BEGIN TRANSACTION;

    DELETE FROM raw.raw_order
    WHERE batch_id = @batch_id;

    INSERT INTO raw.raw_order
    (
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
    )
    SELECT
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
    WHERE batch_id = @batch_id;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;

END CATCH;


/*==============================================================================
8. LOAD ORDER ITEM
==============================================================================*/

BEGIN TRY

    BEGIN TRANSACTION;

    DELETE FROM raw.raw_order_item
    WHERE batch_id = @batch_id;

    INSERT INTO raw.raw_order_item
    (
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
    )
    SELECT
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
    WHERE batch_id = @batch_id;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;

END CATCH;


/*==============================================================================
9. LOAD DELIVERY PERFORMANCE
==============================================================================*/

BEGIN TRY

    BEGIN TRANSACTION;

    DELETE FROM raw.raw_delivery_performance
    WHERE batch_id = @batch_id;

    INSERT INTO raw.raw_delivery_performance
    (
        delivery_id,
        order_id,
        order_item,
        expected_delivery_time_min,
        actual_delivery_time_min,
        delivery_item,
        distance_km,
        batch_id,
        source_file_name,
        source_row_number,
        load_timestamp
    )
    SELECT
        delivery_id,
        order_id,
        order_item,
        expected_delivery_time_min,
        actual_delivery_time_min,
        delivery_item,
        distance_km,
        batch_id,
        source_file_name,
        source_row_number,
        load_timestamp
    FROM stg.stg_delivery_performance
    WHERE batch_id = @batch_id;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;

END CATCH;


/*==============================================================================
10. LOAD RATING
==============================================================================*/

BEGIN TRY

    BEGIN TRANSACTION;

    DELETE FROM raw.raw_rating
    WHERE batch_id = @batch_id;

    INSERT INTO raw.raw_rating
    (
        rating_id,
        order_id,
        customer_id,
        restaurant_id,
        rating,
        review_text,
        review_timestamp,
        sentiment_score,
        batch_id,
        source_file_name,
        source_row_number,
        load_timestamp
    )
    SELECT
        rating_id,
        order_id,
        customer_id,
        restaurant_id,
        rating,
        review_text,
        review_timestamp,
        sentiment_score,
        batch_id,
        source_file_name,
        source_row_number,
        load_timestamp
    FROM stg.stg_rating
    WHERE batch_id = @batch_id;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH

    IF XACT_STATE() <> 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;

END CATCH;


/*==============================================================================
11. FINAL RECONCILIATION
==============================================================================*/

SELECT
    @batch_id AS batch_id,

    (
        SELECT COUNT_BIG(*)
        FROM stg.stg_customer
        WHERE batch_id = @batch_id
    ) AS stg_customer_count,

    (
        SELECT COUNT_BIG(*)
        FROM raw.raw_customer
        WHERE batch_id = @batch_id
    ) AS raw_customer_count,

    (
        SELECT COUNT_BIG(*)
        FROM stg.stg_restaurant
        WHERE batch_id = @batch_id
    ) AS stg_restaurant_count,

    (
        SELECT COUNT_BIG(*)
        FROM raw.raw_restaurant
        WHERE batch_id = @batch_id
    ) AS raw_restaurant_count,

    (
        SELECT COUNT_BIG(*)
        FROM stg.stg_menu_item
        WHERE batch_id = @batch_id
    ) AS stg_menu_item_count,

    (
        SELECT COUNT_BIG(*)
        FROM raw.raw_menu_item
        WHERE batch_id = @batch_id
    ) AS raw_menu_item_count,

    (
        SELECT COUNT_BIG(*)
        FROM stg.stg_delivery_partner
        WHERE batch_id = @batch_id
    ) AS stg_delivery_partner_count,

    (
        SELECT COUNT_BIG(*)
        FROM raw.raw_delivery_partner
        WHERE batch_id = @batch_id
    ) AS raw_delivery_partner_count,

    (
        SELECT COUNT_BIG(*)
        FROM stg.stg_order
        WHERE batch_id = @batch_id
    ) AS stg_order_count,

    (
        SELECT COUNT_BIG(*)
        FROM raw.raw_order
        WHERE batch_id = @batch_id
    ) AS raw_order_count,

    (
        SELECT COUNT_BIG(*)
        FROM stg.stg_order_item
        WHERE batch_id = @batch_id
    ) AS stg_order_item_count,

    (
        SELECT COUNT_BIG(*)
        FROM raw.raw_order_item
        WHERE batch_id = @batch_id
    ) AS raw_order_item_count,

    (
        SELECT COUNT_BIG(*)
        FROM stg.stg_delivery_performance
        WHERE batch_id = @batch_id
    ) AS stg_delivery_performance_count,

    (
        SELECT COUNT_BIG(*)
        FROM raw.raw_delivery_performance
        WHERE batch_id = @batch_id
    ) AS raw_delivery_performance_count,

    (
        SELECT COUNT_BIG(*)
        FROM stg.stg_rating
        WHERE batch_id = @batch_id
    ) AS stg_rating_count,

    (
        SELECT COUNT_BIG(*)
        FROM raw.raw_rating
        WHERE batch_id = @batch_id
    ) AS raw_rating_count;
GO