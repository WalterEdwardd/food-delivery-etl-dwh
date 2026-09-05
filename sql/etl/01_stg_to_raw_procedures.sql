/*
================================================================================
PROJECT : Food Delivery ETL & Data Warehouse
FILE    : 01_stg_to_raw_procedures.sql
PURPOSE : Production stored procedures for STG -> RAW loading

================================================================================
ARCHITECTURE
================================================================================

    STG
     |
     |  Source-preserving load
     |  Batch-aware
     |  Explicit column mapping
     v
    RAW

================================================================================
DESIGN PRINCIPLES
================================================================================

1. RAW is source-preserving.
   - No business transformation
   - No trimming
   - No casting
   - No normalization
   - No business rules

2. Loading is batch-aware.
   - Every procedure requires @batch_id.
   - Only records belonging to the specified batch are loaded.

3. Batch replacement / replayability.
   - Existing RAW records for the same batch are deleted first.
   - STG records for the batch are then inserted.
   - Re-running the same batch produces the same RAW data set.

4. Explicit column mapping.
   - Never use SELECT *.

5. Transaction isolation.
   - Each entity is processed in its own transaction.
   - Failure of one entity does not rollback previously successful entities.

6. Error handling.
   - TRY/CATCH
   - XACT_ABORT
   - ROLLBACK when required
   - THROW original error after logging

7. Operational logging.
   - Every entity load writes SUCCESS or FAILED to control.etl_log.
   - rows_processed = number of STG rows selected for the batch.
   - rows_inserted  = number of rows inserted into RAW.
   - rows_rejected  = 0 at STG -> RAW because no business validation occurs here.

8. Batch orchestration.
   - usp_load_raw_batch executes all 8 entity procedures.
   - Processing continues when an individual entity fails.
   - If one or more entities fail, the batch is marked FAILED.
   - The batch procedure then THROWs so external orchestrators detect failure.

================================================================================
ENTITY ORDER
================================================================================

1. customer
2. restaurant
3. menu_item
4. delivery_partner
5. order
6. order_item
7. delivery_performance
8. rating

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

    DECLARE
        @start_time      DATETIME2(3) = SYSDATETIME(),
        @end_time        DATETIME2(3),
        @rows_processed  BIGINT = 0,
        @rows_inserted   BIGINT = 0;

    /*----------------------------------------------------------------------
      Validate input
    ----------------------------------------------------------------------*/
    IF @batch_id IS NULL
    BEGIN
        THROW 50001, 'batch_id must be supplied.', 1;
    END;


    BEGIN TRY

        /*------------------------------------------------------------------
          Count source rows
        ------------------------------------------------------------------*/
        SELECT
            @rows_processed = COUNT_BIG(*)
        FROM stg.stg_customer
        WHERE batch_id = @batch_id;


        /*------------------------------------------------------------------
          Replace RAW data for this batch
        ------------------------------------------------------------------*/
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

            SET @rows_inserted = @@ROWCOUNT;

        COMMIT TRANSACTION;


        /*------------------------------------------------------------------
          SUCCESS log
        ------------------------------------------------------------------*/
        SET @end_time = SYSDATETIME();

        INSERT INTO control.etl_log
        (
            batch_id,
            process_name,
            step_name,
            start_time,
            end_time,
            status,
            rows_processed,
            rows_inserted,
            rows_rejected,
            message,
            created_at
        )
        VALUES
        (
            @batch_id,
            'STG_TO_RAW',
            'LOAD_CUSTOMER',
            @start_time,
            @end_time,
            'SUCCESS',
            @rows_processed,
            @rows_inserted,
            0,
            NULL,
            SYSDATETIME()
        );


        /*------------------------------------------------------------------
          Return result
        ------------------------------------------------------------------*/
        SELECT
            @batch_id       AS batch_id,
            'customer'      AS entity_name,
            @rows_processed AS rows_processed,
            @rows_inserted  AS rows_inserted,
            0               AS rows_rejected,
            'SUCCESS'       AS status;

    END TRY

    BEGIN CATCH

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @end_time = SYSDATETIME();

        /*------------------------------------------------------------------
          FAILED log
        ------------------------------------------------------------------*/
        INSERT INTO control.etl_log
        (
            batch_id,
            process_name,
            step_name,
            start_time,
            end_time,
            status,
            rows_processed,
            rows_inserted,
            rows_rejected,
            message,
            created_at
        )
        VALUES
        (
            @batch_id,
            'STG_TO_RAW',
            'LOAD_CUSTOMER',
            @start_time,
            @end_time,
            'FAILED',
            @rows_processed,
            @rows_inserted,
            0,
            ERROR_MESSAGE(),
            SYSDATETIME()
        );

        THROW;

    END CATCH
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

    DECLARE
        @start_time      DATETIME2(3) = SYSDATETIME(),
        @end_time        DATETIME2(3),
        @rows_processed  BIGINT = 0,
        @rows_inserted   BIGINT = 0;

    IF @batch_id IS NULL
    BEGIN
        THROW 50001, 'batch_id must be supplied.', 1;
    END;


    BEGIN TRY

        SELECT
            @rows_processed = COUNT_BIG(*)
        FROM stg.stg_restaurant
        WHERE batch_id = @batch_id;


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

            SET @rows_inserted = @@ROWCOUNT;

        COMMIT TRANSACTION;


        SET @end_time = SYSDATETIME();

        INSERT INTO control.etl_log
        (
            batch_id,
            process_name,
            step_name,
            start_time,
            end_time,
            status,
            rows_processed,
            rows_inserted,
            rows_rejected,
            message,
            created_at
        )
        VALUES
        (
            @batch_id,
            'STG_TO_RAW',
            'LOAD_RESTAURANT',
            @start_time,
            @end_time,
            'SUCCESS',
            @rows_processed,
            @rows_inserted,
            0,
            NULL,
            SYSDATETIME()
        );


        SELECT
            @batch_id       AS batch_id,
            'restaurant'    AS entity_name,
            @rows_processed AS rows_processed,
            @rows_inserted  AS rows_inserted,
            0               AS rows_rejected,
            'SUCCESS'       AS status;

    END TRY

    BEGIN CATCH

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @end_time = SYSDATETIME();

        INSERT INTO control.etl_log
        (
            batch_id,
            process_name,
            step_name,
            start_time,
            end_time,
            status,
            rows_processed,
            rows_inserted,
            rows_rejected,
            message,
            created_at
        )
        VALUES
        (
            @batch_id,
            'STG_TO_RAW',
            'LOAD_RESTAURANT',
            @start_time,
            @end_time,
            'FAILED',
            @rows_processed,
            @rows_inserted,
            0,
            ERROR_MESSAGE(),
            SYSDATETIME()
        );

        THROW;

    END CATCH
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

    DECLARE
        @start_time      DATETIME2(3) = SYSDATETIME(),
        @end_time        DATETIME2(3),
        @rows_processed  BIGINT = 0,
        @rows_inserted   BIGINT = 0;

    IF @batch_id IS NULL
    BEGIN
        THROW 50001, 'batch_id must be supplied.', 1;
    END;


    BEGIN TRY

        SELECT
            @rows_processed = COUNT_BIG(*)
        FROM stg.stg_menu_item
        WHERE batch_id = @batch_id;


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

            SET @rows_inserted = @@ROWCOUNT;

        COMMIT TRANSACTION;


        SET @end_time = SYSDATETIME();

        INSERT INTO control.etl_log
        (
            batch_id,
            process_name,
            step_name,
            start_time,
            end_time,
            status,
            rows_processed,
            rows_inserted,
            rows_rejected,
            message,
            created_at
        )
        VALUES
        (
            @batch_id,
            'STG_TO_RAW',
            'LOAD_MENU_ITEM',
            @start_time,
            @end_time,
            'SUCCESS',
            @rows_processed,
            @rows_inserted,
            0,
            NULL,
            SYSDATETIME()
        );


        SELECT
            @batch_id       AS batch_id,
            'menu_item'     AS entity_name,
            @rows_processed AS rows_processed,
            @rows_inserted  AS rows_inserted,
            0               AS rows_rejected,
            'SUCCESS'       AS status;

    END TRY

    BEGIN CATCH

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @end_time = SYSDATETIME();

        INSERT INTO control.etl_log
        (
            batch_id,
            process_name,
            step_name,
            start_time,
            end_time,
            status,
            rows_processed,
            rows_inserted,
            rows_rejected,
            message,
            created_at
        )
        VALUES
        (
            @batch_id,
            'STG_TO_RAW',
            'LOAD_MENU_ITEM',
            @start_time,
            @end_time,
            'FAILED',
            @rows_processed,
            @rows_inserted,
            0,
            ERROR_MESSAGE(),
            SYSDATETIME()
        );

        THROW;

    END CATCH
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

    DECLARE
        @start_time      DATETIME2(3) = SYSDATETIME(),
        @end_time        DATETIME2(3),
        @rows_processed  BIGINT = 0,
        @rows_inserted   BIGINT = 0;

    IF @batch_id IS NULL
    BEGIN
        THROW 50001, 'batch_id must be supplied.', 1;
    END;


    BEGIN TRY

        SELECT
            @rows_processed = COUNT_BIG(*)
        FROM stg.stg_delivery_partner
        WHERE batch_id = @batch_id;


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

            SET @rows_inserted = @@ROWCOUNT;

        COMMIT TRANSACTION;


        SET @end_time = SYSDATETIME();

        INSERT INTO control.etl_log
        (
            batch_id,
            process_name,
            step_name,
            start_time,
            end_time,
            status,
            rows_processed,
            rows_inserted,
            rows_rejected,
            message,
            created_at
        )
        VALUES
        (
            @batch_id,
            'STG_TO_RAW',
            'LOAD_DELIVERY_PARTNER',
            @start_time,
            @end_time,
            'SUCCESS',
            @rows_processed,
            @rows_inserted,
            0,
            NULL,
            SYSDATETIME()
        );


        SELECT
            @batch_id       AS batch_id,
            'delivery_partner' AS entity_name,
            @rows_processed AS rows_processed,
            @rows_inserted  AS rows_inserted,
            0               AS rows_rejected,
            'SUCCESS'       AS status;

    END TRY

    BEGIN CATCH

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @end_time = SYSDATETIME();

        INSERT INTO control.etl_log
        (
            batch_id,
            process_name,
            step_name,
            start_time,
            end_time,
            status,
            rows_processed,
            rows_inserted,
            rows_rejected,
            message,
            created_at
        )
        VALUES
        (
            @batch_id,
            'STG_TO_RAW',
            'LOAD_DELIVERY_PARTNER',
            @start_time,
            @end_time,
            'FAILED',
            @rows_processed,
            @rows_inserted,
            0,
            ERROR_MESSAGE(),
            SYSDATETIME()
        );

        THROW;

    END CATCH
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

    DECLARE
        @start_time      DATETIME2(3) = SYSDATETIME(),
        @end_time        DATETIME2(3),
        @rows_processed  BIGINT = 0,
        @rows_inserted   BIGINT = 0;

    IF @batch_id IS NULL
    BEGIN
        THROW 50001, 'batch_id must be supplied.', 1;
    END;


    BEGIN TRY

        SELECT
            @rows_processed = COUNT_BIG(*)
        FROM stg.stg_order
        WHERE batch_id = @batch_id;


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

            SET @rows_inserted = @@ROWCOUNT;

        COMMIT TRANSACTION;


        SET @end_time = SYSDATETIME();

        INSERT INTO control.etl_log
        (
            batch_id,
            process_name,
            step_name,
            start_time,
            end_time,
            status,
            rows_processed,
            rows_inserted,
            rows_rejected,
            message,
            created_at
        )
        VALUES
        (
            @batch_id,
            'STG_TO_RAW',
            'LOAD_ORDER',
            @start_time,
            @end_time,
            'SUCCESS',
            @rows_processed,
            @rows_inserted,
            0,
            NULL,
            SYSDATETIME()
        );


        SELECT
            @batch_id       AS batch_id,
            'order'         AS entity_name,
            @rows_processed AS rows_processed,
            @rows_inserted  AS rows_inserted,
            0               AS rows_rejected,
            'SUCCESS'       AS status;

    END TRY

    BEGIN CATCH

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @end_time = SYSDATETIME();

        INSERT INTO control.etl_log
        (
            batch_id,
            process_name,
            step_name,
            start_time,
            end_time,
            status,
            rows_processed,
            rows_inserted,
            rows_rejected,
            message,
            created_at
        )
        VALUES
        (
            @batch_id,
            'STG_TO_RAW',
            'LOAD_ORDER',
            @start_time,
            @end_time,
            'FAILED',
            @rows_processed,
            @rows_inserted,
            0,
            ERROR_MESSAGE(),
            SYSDATETIME()
        );

        THROW;

    END CATCH
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

    DECLARE
        @start_time      DATETIME2(3) = SYSDATETIME(),
        @end_time        DATETIME2(3),
        @rows_processed  BIGINT = 0,
        @rows_inserted   BIGINT = 0;

    IF @batch_id IS NULL
    BEGIN
        THROW 50001, 'batch_id must be supplied.', 1;
    END;


    BEGIN TRY

        SELECT
            @rows_processed = COUNT_BIG(*)
        FROM stg.stg_order_item
        WHERE batch_id = @batch_id;


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

            SET @rows_inserted = @@ROWCOUNT;

        COMMIT TRANSACTION;


        SET @end_time = SYSDATETIME();

        INSERT INTO control.etl_log
        (
            batch_id,
            process_name,
            step_name,
            start_time,
            end_time,
            status,
            rows_processed,
            rows_inserted,
            rows_rejected,
            message,
            created_at
        )
        VALUES
        (
            @batch_id,
            'STG_TO_RAW',
            'LOAD_ORDER_ITEM',
            @start_time,
            @end_time,
            'SUCCESS',
            @rows_processed,
            @rows_inserted,
            0,
            NULL,
            SYSDATETIME()
        );


        SELECT
            @batch_id       AS batch_id,
            'order_item'    AS entity_name,
            @rows_processed AS rows_processed,
            @rows_inserted  AS rows_inserted,
            0               AS rows_rejected,
            'SUCCESS'       AS status;

    END TRY

    BEGIN CATCH

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @end_time = SYSDATETIME();

        INSERT INTO control.etl_log
        (
            batch_id,
            process_name,
            step_name,
            start_time,
            end_time,
            status,
            rows_processed,
            rows_inserted,
            rows_rejected,
            message,
            created_at
        )
        VALUES
        (
            @batch_id,
            'STG_TO_RAW',
            'LOAD_ORDER_ITEM',
            @start_time,
            @end_time,
            'FAILED',
            @rows_processed,
            @rows_inserted,
            0,
            ERROR_MESSAGE(),
            SYSDATETIME()
        );

        THROW;

    END CATCH
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

    DECLARE
        @start_time      DATETIME2(3) = SYSDATETIME(),
        @end_time        DATETIME2(3),
        @rows_processed  BIGINT = 0,
        @rows_inserted   BIGINT = 0;

    IF @batch_id IS NULL
    BEGIN
        THROW 50001, 'batch_id must be supplied.', 1;
    END;


    BEGIN TRY

        SELECT
            @rows_processed = COUNT_BIG(*)
        FROM stg.stg_delivery_performance
        WHERE batch_id = @batch_id;


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

            SET @rows_inserted = @@ROWCOUNT;

        COMMIT TRANSACTION;


        SET @end_time = SYSDATETIME();

        INSERT INTO control.etl_log
        (
            batch_id,
            process_name,
            step_name,
            start_time,
            end_time,
            status,
            rows_processed,
            rows_inserted,
            rows_rejected,
            message,
            created_at
        )
        VALUES
        (
            @batch_id,
            'STG_TO_RAW',
            'LOAD_DELIVERY_PERFORMANCE',
            @start_time,
            @end_time,
            'SUCCESS',
            @rows_processed,
            @rows_inserted,
            0,
            NULL,
            SYSDATETIME()
        );


        SELECT
            @batch_id       AS batch_id,
            'delivery_performance' AS entity_name,
            @rows_processed AS rows_processed,
            @rows_inserted  AS rows_inserted,
            0               AS rows_rejected,
            'SUCCESS'       AS status;

    END TRY

    BEGIN CATCH

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @end_time = SYSDATETIME();

        INSERT INTO control.etl_log
        (
            batch_id,
            process_name,
            step_name,
            start_time,
            end_time,
            status,
            rows_processed,
            rows_inserted,
            rows_rejected,
            message,
            created_at
        )
        VALUES
        (
            @batch_id,
            'STG_TO_RAW',
            'LOAD_DELIVERY_PERFORMANCE',
            @start_time,
            @end_time,
            'FAILED',
            @rows_processed,
            @rows_inserted,
            0,
            ERROR_MESSAGE(),
            SYSDATETIME()
        );

        THROW;

    END CATCH
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

    DECLARE
        @start_time      DATETIME2(3) = SYSDATETIME(),
        @end_time        DATETIME2(3),
        @rows_processed  BIGINT = 0,
        @rows_inserted   BIGINT = 0;

    IF @batch_id IS NULL
    BEGIN
        THROW 50001, 'batch_id must be supplied.', 1;
    END;


    BEGIN TRY

        SELECT
            @rows_processed = COUNT_BIG(*)
        FROM stg.stg_rating
        WHERE batch_id = @batch_id;


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

            SET @rows_inserted = @@ROWCOUNT;

        COMMIT TRANSACTION;


        SET @end_time = SYSDATETIME();

        INSERT INTO control.etl_log
        (
            batch_id,
            process_name,
            step_name,
            start_time,
            end_time,
            status,
            rows_processed,
            rows_inserted,
            rows_rejected,
            message,
            created_at
        )
        VALUES
        (
            @batch_id,
            'STG_TO_RAW',
            'LOAD_RATING',
            @start_time,
            @end_time,
            'SUCCESS',
            @rows_processed,
            @rows_inserted,
            0,
            NULL,
            SYSDATETIME()
        );


        SELECT
            @batch_id       AS batch_id,
            'rating'        AS entity_name,
            @rows_processed AS rows_processed,
            @rows_inserted  AS rows_inserted,
            0               AS rows_rejected,
            'SUCCESS'       AS status;

    END TRY

    BEGIN CATCH

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @end_time = SYSDATETIME();

        INSERT INTO control.etl_log
        (
            batch_id,
            process_name,
            step_name,
            start_time,
            end_time,
            status,
            rows_processed,
            rows_inserted,
            rows_rejected,
            message,
            created_at
        )
        VALUES
        (
            @batch_id,
            'STG_TO_RAW',
            'LOAD_RATING',
            @start_time,
            @end_time,
            'FAILED',
            @rows_processed,
            @rows_inserted,
            0,
            ERROR_MESSAGE(),
            SYSDATETIME()
        );

        THROW;

    END CATCH
END;
GO



/*==============================================================================
  9. BATCH ORCHESTRATION
==============================================================================

  Purpose:
      Execute the complete STG -> RAW process for one batch.

  Transaction strategy:
      - XACT_ABORT OFF intentionally.
      - Each child procedure controls its own transaction.
      - A failed child is caught here.
      - Remaining entities continue.
      - Final batch status becomes FAILED if any child failed.
      - THROW 50003 propagates the batch failure to external orchestrators.

==============================================================================*/

CREATE OR ALTER PROCEDURE dbo.usp_load_raw_batch
    @batch_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    /*
        IMPORTANT:
        XACT_ABORT is OFF intentionally.

        Child procedures use their own transactions and XACT_ABORT ON.
        The parent must be able to catch an individual child failure and
        continue with the remaining independent entities.
    */
    SET XACT_ABORT OFF;


    DECLARE
        @batch_start_time DATETIME2(3) = SYSDATETIME(),
        @batch_end_time   DATETIME2(3),
        @failed_steps     INT = 0,
        @total_processed  BIGINT = 0,
        @total_inserted   BIGINT = 0,
        @status           VARCHAR(20);


    /*----------------------------------------------------------------------
      Validate input
    ----------------------------------------------------------------------*/
    IF @batch_id IS NULL
    BEGIN
        THROW 50001, 'batch_id must be supplied.', 1;
    END;


    /*----------------------------------------------------------------------
      Validate batch existence in STG

      At least one STG table must contain the requested batch.

      We intentionally do not require all 8 entities to have rows.
      Expected/optional entity validation can be added later through a
      control-layer manifest.
    ----------------------------------------------------------------------*/
    IF NOT EXISTS
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
        THROW 50002, 'Specified batch_id does not exist in any STG table.', 1;
    END;


    /*----------------------------------------------------------------------
      1. CUSTOMER
    ----------------------------------------------------------------------*/
    BEGIN TRY

        EXEC dbo.usp_load_raw_customer
            @batch_id = @batch_id;

    END TRY
    BEGIN CATCH

        SET @failed_steps += 1;

    END CATCH;


    /*----------------------------------------------------------------------
      2. RESTAURANT
    ----------------------------------------------------------------------*/
    BEGIN TRY

        EXEC dbo.usp_load_raw_restaurant
            @batch_id = @batch_id;

    END TRY
    BEGIN CATCH

        SET @failed_steps += 1;

    END CATCH;


    /*----------------------------------------------------------------------
      3. MENU ITEM
    ----------------------------------------------------------------------*/
    BEGIN TRY

        EXEC dbo.usp_load_raw_menu_item
            @batch_id = @batch_id;

    END TRY
    BEGIN CATCH

        SET @failed_steps += 1;

    END CATCH;


    /*----------------------------------------------------------------------
      4. DELIVERY PARTNER
    ----------------------------------------------------------------------*/
    BEGIN TRY

        EXEC dbo.usp_load_raw_delivery_partner
            @batch_id = @batch_id;

    END TRY
    BEGIN CATCH

        SET @failed_steps += 1;

    END CATCH;


    /*----------------------------------------------------------------------
      5. ORDER
    ----------------------------------------------------------------------*/
    BEGIN TRY

        EXEC dbo.usp_load_raw_order
            @batch_id = @batch_id;

    END TRY
    BEGIN CATCH

        SET @failed_steps += 1;

    END CATCH;


    /*----------------------------------------------------------------------
      6. ORDER ITEM
    ----------------------------------------------------------------------*/
    BEGIN TRY

        EXEC dbo.usp_load_raw_order_item
            @batch_id = @batch_id;

    END TRY
    BEGIN CATCH

        SET @failed_steps += 1;

    END CATCH;


    /*----------------------------------------------------------------------
      7. DELIVERY PERFORMANCE
    ----------------------------------------------------------------------*/
    BEGIN TRY

        EXEC dbo.usp_load_raw_delivery_performance
            @batch_id = @batch_id;

    END TRY
    BEGIN CATCH

        SET @failed_steps += 1;

    END CATCH;


    /*----------------------------------------------------------------------
      8. RATING
    ----------------------------------------------------------------------*/
    BEGIN TRY

        EXEC dbo.usp_load_raw_rating
            @batch_id = @batch_id;

    END TRY
    BEGIN CATCH

        SET @failed_steps += 1;

    END CATCH;


    /*----------------------------------------------------------------------
      Calculate final batch status
    ----------------------------------------------------------------------*/
    SET @batch_end_time = SYSDATETIME();

    SET @status =
        CASE
            WHEN @failed_steps = 0 THEN 'SUCCESS'
            ELSE 'FAILED'
        END;


    /*----------------------------------------------------------------------
      Calculate total STG rows

      This is based on the actual batch contents rather than summing
      historical ETL log records.

      This makes reruns/replays safe from double-counting.
    ----------------------------------------------------------------------*/
    SELECT
        @total_processed =
              (SELECT COUNT_BIG(*) FROM stg.stg_customer
               WHERE batch_id = @batch_id)
            + (SELECT COUNT_BIG(*) FROM stg.stg_restaurant
               WHERE batch_id = @batch_id)
            + (SELECT COUNT_BIG(*) FROM stg.stg_menu_item
               WHERE batch_id = @batch_id)
            + (SELECT COUNT_BIG(*) FROM stg.stg_delivery_partner
               WHERE batch_id = @batch_id)
            + (SELECT COUNT_BIG(*) FROM stg.stg_order
               WHERE batch_id = @batch_id)
            + (SELECT COUNT_BIG(*) FROM stg.stg_order_item
               WHERE batch_id = @batch_id)
            + (SELECT COUNT_BIG(*) FROM stg.stg_delivery_performance
               WHERE batch_id = @batch_id)
            + (SELECT COUNT_BIG(*) FROM stg.stg_rating
               WHERE batch_id = @batch_id);


    /*----------------------------------------------------------------------
      Calculate total RAW rows

      This represents the final RAW state for the requested batch.
    ----------------------------------------------------------------------*/
    SELECT
        @total_inserted =
              (SELECT COUNT_BIG(*) FROM raw.raw_customer
               WHERE batch_id = @batch_id)
            + (SELECT COUNT_BIG(*) FROM raw.raw_restaurant
               WHERE batch_id = @batch_id)
            + (SELECT COUNT_BIG(*) FROM raw.raw_menu_item
               WHERE batch_id = @batch_id)
            + (SELECT COUNT_BIG(*) FROM raw.raw_delivery_partner
               WHERE batch_id = @batch_id)
            + (SELECT COUNT_BIG(*) FROM raw.raw_order
               WHERE batch_id = @batch_id)
            + (SELECT COUNT_BIG(*) FROM raw.raw_order_item
               WHERE batch_id = @batch_id)
            + (SELECT COUNT_BIG(*) FROM raw.raw_delivery_performance
               WHERE batch_id = @batch_id)
            + (SELECT COUNT_BIG(*) FROM raw.raw_rating
               WHERE batch_id = @batch_id);


    /*----------------------------------------------------------------------
      Batch-level logging
    ----------------------------------------------------------------------*/
    INSERT INTO control.etl_log
    (
        batch_id,
        process_name,
        step_name,
        start_time,
        end_time,
        status,
        rows_processed,
        rows_inserted,
        rows_rejected,
        message,
        created_at
    )
    VALUES
    (
        @batch_id,
        'STG_TO_RAW',
        'LOAD_BATCH',
        @batch_start_time,
        @batch_end_time,
        @status,
        @total_processed,
        @total_inserted,
        0,
        CASE
            WHEN @failed_steps = 0
                THEN NULL
            ELSE CONCAT(
                'STG -> RAW batch completed with ',
                @failed_steps,
                ' failed step(s).'
            )
        END,
        SYSDATETIME()
    );


    /*----------------------------------------------------------------------
      Return final execution summary
    ----------------------------------------------------------------------*/
    SELECT
        @batch_id        AS batch_id,
        @total_processed AS total_rows_processed,
        @total_inserted  AS total_rows_inserted,
        @failed_steps    AS failed_steps,
        @status          AS status;


    /*----------------------------------------------------------------------
      FAILURE PROPAGATION

      This is intentionally executed AFTER the batch-level log and summary.

      External orchestrators must receive an actual SQL error when the
      overall batch fails.

      Examples:
          Python
          SQL Server Agent
          SSIS
          future orchestration layer
    ----------------------------------------------------------------------*/
    IF @failed_steps > 0
    BEGIN
        THROW 50003,
              'STG -> RAW batch completed with one or more failed steps.',
              1;
    END;

END;
GO



/*==============================================================================
  10. PROCEDURE INVENTORY
==============================================================================*/

SELECT
    SCHEMA_NAME(p.schema_id) AS schema_name,
    p.name                   AS procedure_name
FROM sys.procedures p
WHERE p.name IN
(
    'usp_load_raw_customer',
    'usp_load_raw_restaurant',
    'usp_load_raw_menu_item',
    'usp_load_raw_delivery_partner',
    'usp_load_raw_order',
    'usp_load_raw_order_item',
    'usp_load_raw_delivery_performance',
    'usp_load_raw_rating',
    'usp_load_raw_batch'
)
ORDER BY
    p.name;
GO