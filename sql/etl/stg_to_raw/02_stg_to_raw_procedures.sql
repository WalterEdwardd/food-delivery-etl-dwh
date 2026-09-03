/*
================================================================================
PROJECT : Food Delivery ETL & Data Warehouse
FILE    : 05_stg_to_raw_procedures.sql
PURPOSE : Stored procedures for STG -> RAW loading

FLOW:
    STG
      |
      v
    RAW

DESIGN:
    - Batch-aware
    - Source-preserving
    - Explicit column mapping
    - Idempotent batch replacement
    - Transactional
    - TRY/CATCH
    - XACT_ABORT
    - THROW

AUTHOR  : FoodDeliveryETL
================================================================================
*/

USE FoodDeliveryDW;
GO


/*==============================================================================
1. CUSTOMER
==============================================================================*/

CREATE OR ALTER PROCEDURE dbo.usp_load_raw_customer
    @batch_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

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
END;
GO


/*==============================================================================
2. RESTAURANT
==============================================================================*/

CREATE OR ALTER PROCEDURE dbo.usp_load_raw_restaurant
    @batch_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

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
END;
GO


/*==============================================================================
3. MENU ITEM
==============================================================================*/

CREATE OR ALTER PROCEDURE dbo.usp_load_raw_menu_item
    @batch_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

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
END;
GO


/*==============================================================================
4. DELIVERY PARTNER
==============================================================================*/

CREATE OR ALTER PROCEDURE dbo.usp_load_raw_delivery_partner
    @batch_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

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
END;
GO


/*==============================================================================
5. ORDER
==============================================================================*/

CREATE OR ALTER PROCEDURE dbo.usp_load_raw_order
    @batch_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

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
END;
GO


/*==============================================================================
6. ORDER ITEM
==============================================================================*/

CREATE OR ALTER PROCEDURE dbo.usp_load_raw_order_item
    @batch_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

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
END;
GO


/*==============================================================================
7. DELIVERY PERFORMANCE
==============================================================================*/

CREATE OR ALTER PROCEDURE dbo.usp_load_raw_delivery_performance
    @batch_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

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
END;
GO


/*==============================================================================
8. RATING
==============================================================================*/

CREATE OR ALTER PROCEDURE dbo.usp_load_raw_rating
    @batch_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

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
END;
GO