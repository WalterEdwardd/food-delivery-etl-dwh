/*
================================================================================
PROJECT : Food Delivery ETL & Data Warehouse
FILE    : 04_raw_to_ods_upsert_procedures.sql
PURPOSE : Production Stored Procedures for RAW -> ODS Incremental Load (Upsert / CDC)
================================================================================
ARCHITECTURE
================================================================================
    raw.raw_* (Source data for the active batch_id)
        ↓  (SSIS Data Flow: Cleanse, Validate, Split Errors to control.etl_error)
    temp.ods_* (Fast Load into temporary staging table)
        ↓  (T-SQL Set-based MERGE with CDC Change Detection)
    ods.ods_* (Target Table: Insert new, Update changed, Preserve unchanged)
================================================================================
*/

USE FoodDeliveryDW;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO


/* ==============================================================================
   1. UPSERT ODS CUSTOMER
============================================================================== */

CREATE OR ALTER PROCEDURE ods.usp_upsert_ods_customer
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT TOP 1 @batch_id = batch_id 
        FROM control.etl_batch 
        WHERE status IN ('RUNNING', 'SUCCESS')
        ORDER BY batch_id DESC;

        IF @batch_id IS NULL OR @batch_id <= 0
            SELECT @batch_id = MAX(batch_id) FROM raw.raw_customer;

        IF @batch_id IS NULL OR @batch_id <= 0
            SELECT TOP 1 @batch_id = batch_id FROM control.etl_batch ORDER BY batch_id DESC;
    END;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        THROW 50010, 'Parameter @batch_id is mandatory or could not be resolved from control.etl_batch or raw.raw_customer.', 1;
    END;

    DECLARE @total_temp INT = 0,
            @inserted_count INT = 0,
            @updated_count  INT = 0;

    SELECT @total_temp = COUNT(*) FROM temp.ods_customer WHERE batch_id = @batch_id;

    IF @total_temp = 0
    BEGIN
        PRINT 'No rows found in temp.ods_customer to merge.';
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Step 1: UPDATE matched and changed records (Set-based CDC via EXCEPT)
        UPDATE target
        SET target.signup_date         = source.signup_date,
            target.city                = source.city,
            target.acquisition_channel = source.acquisition_channel,
            target.batch_id            = source.batch_id,
            target.source_file_name    = source.source_file_name,
            target.source_row_number   = source.source_row_number,
            target.load_timestamp      = SYSUTCDATETIME()
        FROM ods.ods_customer target
        INNER JOIN temp.ods_customer source
            ON target.customer_id = source.customer_id
        WHERE source.batch_id = @batch_id
          AND EXISTS (
              SELECT source.signup_date, source.city, source.acquisition_channel
              EXCEPT
              SELECT target.signup_date, target.city, target.acquisition_channel
          );

        SET @updated_count = @@ROWCOUNT;

        -- Step 2: INSERT brand new records (NOT MATCHED)
        INSERT INTO ods.ods_customer
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
            source.customer_id,
            source.signup_date,
            source.city,
            source.acquisition_channel,
            source.batch_id,
            source.source_file_name,
            source.source_row_number,
            SYSUTCDATETIME()
        FROM temp.ods_customer source
        WHERE source.batch_id = @batch_id
          AND NOT EXISTS (
              SELECT 1
              FROM ods.ods_customer target
              WHERE target.customer_id = source.customer_id
          );

        SET @inserted_count = @@ROWCOUNT;

        DECLARE @unchanged_count INT = @total_temp - (@inserted_count + @updated_count);

        UPDATE control.etl_log
        SET rows_processed = @total_temp,
            rows_inserted  = @inserted_count,
            message        = CONCAT('Upsert completed: ', @inserted_count, ' inserted, ', @updated_count, ' updated, ', @unchanged_count, ' unchanged.')
        WHERE step_name    = 'LOAD_CUSTOMER'
          AND batch_id     = @batch_id
          AND status       = 'RUNNING';

        COMMIT TRANSACTION;

        -- Targeted Staging Cleanup (Isolated by Batch ID to prevent concurrency data loss)
        DELETE FROM temp.ods_customer WHERE batch_id = @batch_id;



        PRINT CONCAT('ods_customer: Total = ', @total_temp, ' | Inserted = ', @inserted_count, ' | Updated = ', @updated_count, ' | Unchanged = ', @unchanged_count);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/* ==============================================================================
   2. UPSERT ODS RESTAURANT
============================================================================== */

CREATE OR ALTER PROCEDURE ods.usp_upsert_ods_restaurant
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT TOP 1 @batch_id = batch_id 
        FROM control.etl_batch 
        WHERE status IN ('RUNNING', 'SUCCESS')
        ORDER BY batch_id DESC;

        IF @batch_id IS NULL OR @batch_id <= 0
            SELECT @batch_id = MAX(batch_id) FROM raw.raw_restaurant;

        IF @batch_id IS NULL OR @batch_id <= 0
            SELECT TOP 1 @batch_id = batch_id FROM control.etl_batch ORDER BY batch_id DESC;
    END;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        THROW 50010, 'Parameter @batch_id is mandatory or could not be resolved from control.etl_batch or raw.raw_restaurant.', 1;
    END;

    DECLARE @total_temp INT = 0,
            @inserted_count INT = 0,
            @updated_count  INT = 0;

    SELECT @total_temp = COUNT(*) FROM temp.ods_restaurant WHERE batch_id = @batch_id;

    IF @total_temp = 0
    BEGIN
        PRINT 'No rows found in temp.ods_restaurant to merge.';
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Step 1: UPDATE matched and changed records (Set-based CDC via EXCEPT)
        UPDATE target
        SET target.onboard_date      = source.onboard_date,
            target.restaurant_name   = source.restaurant_name,
            target.city              = source.city,
            target.cuisine_type      = source.cuisine_type,
            target.partner_type      = source.partner_type,
            target.avg_prep_time_min = source.avg_prep_time_min,
            target.is_active         = source.is_active,
            target.batch_id          = source.batch_id,
            target.source_file_name  = source.source_file_name,
            target.source_row_number = source.source_row_number,
            target.load_timestamp    = SYSUTCDATETIME()
        FROM ods.ods_restaurant target
        INNER JOIN temp.ods_restaurant source
            ON target.restaurant_id = source.restaurant_id
        WHERE source.batch_id = @batch_id
          AND EXISTS (
              SELECT source.onboard_date, source.restaurant_name, source.city, source.cuisine_type, source.partner_type, source.avg_prep_time_min, source.is_active
              EXCEPT
              SELECT target.onboard_date, target.restaurant_name, target.city, target.cuisine_type, target.partner_type, target.avg_prep_time_min, target.is_active
          );

        SET @updated_count = @@ROWCOUNT;

        -- Step 2: INSERT brand new records (NOT MATCHED)
        INSERT INTO ods.ods_restaurant
        (
            restaurant_id,
            onboard_date,
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
            source.restaurant_id,
            source.onboard_date,
            source.restaurant_name,
            source.city,
            source.cuisine_type,
            source.partner_type,
            source.avg_prep_time_min,
            source.is_active,
            source.batch_id,
            source.source_file_name,
            source.source_row_number,
            SYSUTCDATETIME()
        FROM temp.ods_restaurant source
        WHERE source.batch_id = @batch_id
          AND NOT EXISTS (
              SELECT 1
              FROM ods.ods_restaurant target
              WHERE target.restaurant_id = source.restaurant_id
          );

        SET @inserted_count = @@ROWCOUNT;

        DECLARE @unchanged_count INT = @total_temp - (@inserted_count + @updated_count);

        UPDATE control.etl_log
        SET rows_processed = @total_temp,
            rows_inserted  = @inserted_count,
            message        = CONCAT('Upsert completed: ', @inserted_count, ' inserted, ', @updated_count, ' updated, ', @unchanged_count, ' unchanged.')
        WHERE step_name    = 'LOAD_RESTAURANT'
          AND batch_id     = @batch_id
          AND status       = 'RUNNING';

        COMMIT TRANSACTION;

        -- Targeted Staging Cleanup (Isolated by Batch ID to prevent concurrency data loss)
        DELETE FROM temp.ods_restaurant WHERE batch_id = @batch_id;



        PRINT CONCAT('ods_restaurant: Total = ', @total_temp, ' | Inserted = ', @inserted_count, ' | Updated = ', @updated_count, ' | Unchanged = ', @unchanged_count);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/* ==============================================================================
   3. UPSERT ODS MENU ITEM
============================================================================== */

CREATE OR ALTER PROCEDURE ods.usp_upsert_ods_menu_item
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT TOP 1 @batch_id = batch_id 
        FROM control.etl_batch 
        WHERE status IN ('RUNNING', 'SUCCESS')
        ORDER BY batch_id DESC;

        IF @batch_id IS NULL OR @batch_id <= 0
            SELECT @batch_id = MAX(batch_id) FROM raw.raw_menu_item;

        IF @batch_id IS NULL OR @batch_id <= 0
            SELECT TOP 1 @batch_id = batch_id FROM control.etl_batch ORDER BY batch_id DESC;
    END;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        THROW 50010, 'Parameter @batch_id is mandatory or could not be resolved from control.etl_batch or raw.raw_menu_item.', 1;
    END;

    DECLARE @total_temp INT = 0,
            @inserted_count INT = 0,
            @updated_count  INT = 0;

    SELECT @total_temp = COUNT(*) FROM temp.ods_menu_item WHERE batch_id = @batch_id;

    IF @total_temp = 0
    BEGIN
        PRINT 'No rows found in temp.ods_menu_item to merge.';
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Step 1: UPDATE matched and changed records (Set-based CDC via EXCEPT)
        UPDATE target
        SET target.restaurant_id     = source.restaurant_id,
            target.item_name         = source.item_name,
            target.category          = source.category,
            target.is_veg            = source.is_veg,
            target.price             = source.price,
            target.batch_id          = source.batch_id,
            target.source_file_name  = source.source_file_name,
            target.source_row_number = source.source_row_number,
            target.load_timestamp    = SYSUTCDATETIME()
        FROM ods.ods_menu_item target
        INNER JOIN temp.ods_menu_item source
            ON target.menu_item_id = source.menu_item_id
        WHERE source.batch_id = @batch_id
          AND EXISTS (
              SELECT source.restaurant_id, source.item_name, source.category, source.is_veg, source.price
              EXCEPT
              SELECT target.restaurant_id, target.item_name, target.category, target.is_veg, target.price
          );

        SET @updated_count = @@ROWCOUNT;

        -- Step 2: INSERT brand new records (NOT MATCHED)
        INSERT INTO ods.ods_menu_item
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
            source.menu_item_id,
            source.restaurant_id,
            source.item_name,
            source.category,
            source.is_veg,
            source.price,
            source.batch_id,
            source.source_file_name,
            source.source_row_number,
            SYSUTCDATETIME()
        FROM temp.ods_menu_item source
        WHERE source.batch_id = @batch_id
          AND NOT EXISTS (
              SELECT 1
              FROM ods.ods_menu_item target
              WHERE target.menu_item_id = source.menu_item_id
          );

        SET @inserted_count = @@ROWCOUNT;

        DECLARE @unchanged_count INT = @total_temp - (@inserted_count + @updated_count);

        UPDATE control.etl_log
        SET rows_processed = @total_temp,
            rows_inserted  = @inserted_count,
            message        = CONCAT('Upsert completed: ', @inserted_count, ' inserted, ', @updated_count, ' updated, ', @unchanged_count, ' unchanged.')
        WHERE step_name    = 'LOAD_MENU_ITEM'
          AND batch_id     = @batch_id
          AND status       = 'RUNNING';

        COMMIT TRANSACTION;

        -- Targeted Staging Cleanup (Isolated by Batch ID to prevent concurrency data loss)
        DELETE FROM temp.ods_menu_item WHERE batch_id = @batch_id;



        PRINT CONCAT('ods_menu_item: Total = ', @total_temp, ' | Inserted = ', @inserted_count, ' | Updated = ', @updated_count, ' | Unchanged = ', @unchanged_count);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/* ==============================================================================
   4. UPSERT ODS DELIVERY PARTNER
============================================================================== */

CREATE OR ALTER PROCEDURE ods.usp_upsert_ods_delivery_partner
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT TOP 1 @batch_id = batch_id 
        FROM control.etl_batch 
        WHERE status IN ('RUNNING', 'SUCCESS')
        ORDER BY batch_id DESC;

        IF @batch_id IS NULL OR @batch_id <= 0
            SELECT @batch_id = MAX(batch_id) FROM raw.raw_delivery_partner;

        IF @batch_id IS NULL OR @batch_id <= 0
            SELECT TOP 1 @batch_id = batch_id FROM control.etl_batch ORDER BY batch_id DESC;
    END;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        THROW 50010, 'Parameter @batch_id is mandatory or could not be resolved from control.etl_batch or raw.raw_delivery_partner.', 1;
    END;

    DECLARE @total_temp INT = 0,
            @inserted_count INT = 0,
            @updated_count  INT = 0;

    SELECT @total_temp = COUNT(*) FROM temp.ods_delivery_partner WHERE batch_id = @batch_id;

    IF @total_temp = 0
    BEGIN
        PRINT 'No rows found in temp.ods_delivery_partner to merge.';
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Step 1: UPDATE matched and changed records (Set-based CDC via EXCEPT)
        UPDATE target
        SET target.onboard_date      = source.onboard_date,
            target.partner_name      = source.partner_name,
            target.city              = source.city,
            target.vehicle_type      = source.vehicle_type,
            target.employment_type   = source.employment_type,
            target.avg_rating        = source.avg_rating,
            target.is_active         = source.is_active,
            target.batch_id          = source.batch_id,
            target.source_file_name  = source.source_file_name,
            target.source_row_number = source.source_row_number,
            target.load_timestamp    = SYSUTCDATETIME()
        FROM ods.ods_delivery_partner target
        INNER JOIN temp.ods_delivery_partner source
            ON target.delivery_partner_id = source.delivery_partner_id
        WHERE source.batch_id = @batch_id
          AND EXISTS (
              SELECT source.onboard_date, source.partner_name, source.city, source.vehicle_type, source.employment_type, source.avg_rating, source.is_active
              EXCEPT
              SELECT target.onboard_date, target.partner_name, target.city, target.vehicle_type, target.employment_type, target.avg_rating, target.is_active
          );

        SET @updated_count = @@ROWCOUNT;

        -- Step 2: INSERT brand new records (NOT MATCHED)
        INSERT INTO ods.ods_delivery_partner
        (
            delivery_partner_id,
            onboard_date,
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
            source.delivery_partner_id,
            source.onboard_date,
            source.partner_name,
            source.city,
            source.vehicle_type,
            source.employment_type,
            source.avg_rating,
            source.is_active,
            source.batch_id,
            source.source_file_name,
            source.source_row_number,
            SYSUTCDATETIME()
        FROM temp.ods_delivery_partner source
        WHERE source.batch_id = @batch_id
          AND NOT EXISTS (
              SELECT 1
              FROM ods.ods_delivery_partner target
              WHERE target.delivery_partner_id = source.delivery_partner_id
          );

        SET @inserted_count = @@ROWCOUNT;

        DECLARE @unchanged_count INT = @total_temp - (@inserted_count + @updated_count);

        UPDATE control.etl_log
        SET rows_processed = @total_temp,
            rows_inserted  = @inserted_count,
            message        = CONCAT('Upsert completed: ', @inserted_count, ' inserted, ', @updated_count, ' updated, ', @unchanged_count, ' unchanged.')
        WHERE step_name    = 'LOAD_DELIVERY_PARTNER'
          AND batch_id     = @batch_id
          AND status       = 'RUNNING';

        COMMIT TRANSACTION;

        -- Targeted Staging Cleanup (Isolated by Batch ID to prevent concurrency data loss)
        DELETE FROM temp.ods_delivery_partner WHERE batch_id = @batch_id;



        PRINT CONCAT('ods_delivery_partner: Total = ', @total_temp, ' | Inserted = ', @inserted_count, ' | Updated = ', @updated_count, ' | Unchanged = ', @unchanged_count);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/* ==============================================================================
   5. UPSERT ODS ORDER
============================================================================== */

CREATE OR ALTER PROCEDURE ods.usp_upsert_ods_order
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT TOP 1 @batch_id = batch_id 
        FROM control.etl_batch 
        WHERE status IN ('RUNNING', 'SUCCESS')
        ORDER BY batch_id DESC;

        IF @batch_id IS NULL OR @batch_id <= 0
            SELECT @batch_id = MAX(batch_id) FROM raw.raw_order;

        IF @batch_id IS NULL OR @batch_id <= 0
            SELECT TOP 1 @batch_id = batch_id FROM control.etl_batch ORDER BY batch_id DESC;
    END;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        THROW 50010, 'Parameter @batch_id is mandatory or could not be resolved from control.etl_batch or raw.raw_order.', 1;
    END;

    DECLARE @total_temp INT = 0,
            @inserted_count INT = 0,
            @updated_count  INT = 0;

    SELECT @total_temp = COUNT(*) FROM temp.ods_order WHERE batch_id = @batch_id;

    IF @total_temp = 0
    BEGIN
        PRINT 'No rows found in temp.ods_order to merge.';
        RETURN;
    END;

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    -- Audit & Log Orphan Records into control.etl_warning
    DECLARE @orphan_cust_count     INT = 0,
            @orphan_rest_count     INT = 0,
            @orphan_dp_count       INT = 0,
            @mismatch_amount_count INT = 0;

    IF OBJECT_ID('control.etl_warning', 'U') IS NOT NULL
    BEGIN
        -- Idempotent Cleanup: Remove existing warnings for this batch if re-running
        DELETE FROM control.etl_warning 
        WHERE batch_id = @batch_id AND step_name = 'LOAD_ORDER';

        -- Single-Pass Scan with CROSS APPLY: preserves 100% individual multi-warning granularity per order
        INSERT INTO control.etl_warning (
            batch_id, step_name, table_name, order_id, entity_name, entity_id, warning_type, warning_message
        )
        SELECT 
            t.batch_id,
            'LOAD_ORDER',
            'ods_order',
            t.order_id,
            w.entity_name,
            w.entity_id,
            w.warning_type,
            w.warning_message
        FROM temp.ods_order t
        LEFT JOIN ods.ods_customer c 
            ON t.customer_id = c.customer_id
        LEFT JOIN ods.ods_restaurant r 
            ON t.restaurant_id = r.restaurant_id
        LEFT JOIN ods.ods_delivery_partner dp 
            ON t.delivery_partner_id = dp.delivery_partner_id
        CROSS APPLY (
            -- 1. Orphan Customer Warning
            SELECT 'CUSTOMER' AS entity_name, t.customer_id AS entity_id, 
                   'ORPHAN_CUSTOMER_DETECTED' AS warning_type, 
                   CONCAT('Customer ID ', t.customer_id, ' not found in ods.ods_customer (retained for compliance / revenue)') AS warning_message
            WHERE c.customer_id IS NULL

            UNION ALL

            -- 2. Orphan Restaurant Warning
            SELECT 'RESTAURANT', t.restaurant_id, 
                   'ORPHAN_RESTAURANT_DETECTED', 
                   CONCAT('Restaurant ID ', t.restaurant_id, ' not found in ods.ods_restaurant')
            WHERE r.restaurant_id IS NULL

            UNION ALL

            -- 3. Orphan Delivery Partner Warning
            SELECT 'DELIVERY_PARTNER', t.delivery_partner_id, 
                   'ORPHAN_DELIVERY_PARTNER_DETECTED', 
                   CONCAT('Delivery Partner ID ', t.delivery_partner_id, ' not found in ods.ods_delivery_partner')
            WHERE t.delivery_partner_id IS NOT NULL 
              AND LTRIM(RTRIM(t.delivery_partner_id)) <> '' 
              AND dp.delivery_partner_id IS NULL

            UNION ALL

            -- 4. Total Amount Discrepancy Warning (Financial Integrity Audit)
            SELECT 'FINANCIAL_INTEGRITY', t.order_id, 
                   'TOTAL_AMOUNT_MISMATCH', 
                   CONCAT('Total amount (', t.total_amount, 
                          ') <> Calculated (subtotal ', t.subtotal_amount, 
                          ' - discount ', ISNULL(t.discount_amount, 0), 
                          ' + fee ', ISNULL(t.delivery_fee, 0), 
                          ' = ', (t.subtotal_amount - ISNULL(t.discount_amount, 0) + ISNULL(t.delivery_fee, 0)), 
                          '). Diff: ', (t.total_amount - (t.subtotal_amount - ISNULL(t.discount_amount, 0) + ISNULL(t.delivery_fee, 0))))
            WHERE t.total_amount IS NOT NULL 
              AND t.subtotal_amount IS NOT NULL
              AND ABS(t.total_amount - (t.subtotal_amount - ISNULL(t.discount_amount, 0) + ISNULL(t.delivery_fee, 0))) > 0.01
        ) w
        WHERE t.batch_id = @batch_id;

        -- Extract individual category counts for audit logging and console reporting
        SELECT 
            @orphan_cust_count     = COUNT(CASE WHEN warning_type = 'ORPHAN_CUSTOMER_DETECTED' THEN 1 END),
            @orphan_rest_count     = COUNT(CASE WHEN warning_type = 'ORPHAN_RESTAURANT_DETECTED' THEN 1 END),
            @orphan_dp_count       = COUNT(CASE WHEN warning_type = 'ORPHAN_DELIVERY_PARTNER_DETECTED' THEN 1 END),
            @mismatch_amount_count = COUNT(CASE WHEN warning_type = 'TOTAL_AMOUNT_MISMATCH' THEN 1 END)
        FROM control.etl_warning
        WHERE batch_id = @batch_id AND step_name = 'LOAD_ORDER';
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Step 1: UPDATE matched and changed records (Set-based CDC via EXCEPT)
        UPDATE target
        SET target.customer_id         = source.customer_id,
            target.restaurant_id       = source.restaurant_id,
            target.delivery_partner_id = source.delivery_partner_id,
            target.order_timestamp     = source.order_timestamp,
            target.subtotal_amount     = source.subtotal_amount,
            target.discount_amount     = source.discount_amount,
            target.delivery_fee        = source.delivery_fee,
            target.total_amount        = source.total_amount,
            target.is_cod              = source.is_cod,
            target.is_cancelled        = source.is_cancelled,
            target.batch_id            = source.batch_id,
            target.source_file_name    = source.source_file_name,
            target.source_row_number   = source.source_row_number,
            target.load_timestamp      = SYSUTCDATETIME()
        FROM ods.ods_order target
        INNER JOIN temp.ods_order source
            ON target.order_id = source.order_id
        WHERE source.batch_id = @batch_id
          AND EXISTS (
              SELECT 
                  source.customer_id, 
                  source.restaurant_id, 
                  source.delivery_partner_id,
                  source.order_timestamp, 
                  source.subtotal_amount, 
                  source.discount_amount, 
                  source.delivery_fee, 
                  source.total_amount, 
                  source.is_cod, 
                  source.is_cancelled
              EXCEPT
              SELECT 
                  target.customer_id, 
                  target.restaurant_id, 
                  target.delivery_partner_id,
                  target.order_timestamp, 
                  target.subtotal_amount, 
                  target.discount_amount, 
                  target.delivery_fee, 
                  target.total_amount, 
                  target.is_cod, 
                  target.is_cancelled
          );

        SET @updated_count = @@ROWCOUNT;

        -- Step 2: INSERT brand new records (NOT MATCHED)
        INSERT INTO ods.ods_order
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
            source.order_id,
            source.customer_id,
            source.restaurant_id,
            source.delivery_partner_id,
            source.order_timestamp,
            source.subtotal_amount,
            source.discount_amount,
            source.delivery_fee,
            source.total_amount,
            source.is_cod,
            source.is_cancelled,
            source.batch_id,
            source.source_file_name,
            source.source_row_number,
            SYSUTCDATETIME()
        FROM temp.ods_order source
        WHERE source.batch_id = @batch_id
          AND NOT EXISTS (
              SELECT 1
              FROM ods.ods_order target
              WHERE target.order_id = source.order_id
          );

        SET @inserted_count = @@ROWCOUNT;

        DECLARE @unchanged_count INT = @total_temp - (@inserted_count + @updated_count);

        UPDATE control.etl_log
        SET rows_processed = @total_temp,
            rows_inserted  = @inserted_count,
            message        = CONCAT('Upsert completed: ', @inserted_count, ' inserted, ', @updated_count, ' updated, ', @unchanged_count, ' unchanged. Warnings: ', @orphan_cust_count, ' orphan cust, ', @orphan_rest_count, ' orphan rest, ', @orphan_dp_count, ' orphan dp, ', @mismatch_amount_count, ' amount mismatch.')
        WHERE step_name    = 'LOAD_ORDER'
          AND batch_id     = @batch_id
          AND status       = 'RUNNING';

        COMMIT TRANSACTION;

        -- Targeted Staging Cleanup (Isolated by Batch ID to prevent concurrency data loss)
        DELETE FROM temp.ods_order WHERE batch_id = @batch_id;

        PRINT CONCAT('ods_order: Total = ', @total_temp, ' | Inserted = ', @inserted_count, ' | Updated = ', @updated_count, ' | Unchanged = ', @unchanged_count, ' | Orphan Cust = ', @orphan_cust_count, ' | Orphan Rest = ', @orphan_rest_count, ' | Orphan DP = ', @orphan_dp_count, ' | Amount Mismatch = ', @mismatch_amount_count);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/* ==============================================================================
   6. UPSERT ODS ORDER ITEM
============================================================================== */

CREATE OR ALTER PROCEDURE ods.usp_upsert_ods_order_item
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT TOP 1 @batch_id = batch_id 
        FROM control.etl_batch 
        WHERE status IN ('RUNNING', 'SUCCESS')
        ORDER BY batch_id DESC;

        IF @batch_id IS NULL OR @batch_id <= 0
            SELECT @batch_id = MAX(batch_id) FROM raw.raw_order_item;

        IF @batch_id IS NULL OR @batch_id <= 0
            SELECT TOP 1 @batch_id = batch_id FROM control.etl_batch ORDER BY batch_id DESC;
    END;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        THROW 50010, 'Parameter @batch_id is mandatory or could not be resolved from control.etl_batch or raw.raw_order_item.', 1;
    END;

    DECLARE @total_temp INT = 0,
            @inserted_count INT = 0,
            @updated_count  INT = 0;

    SELECT @total_temp = COUNT(*) FROM temp.ods_order_item WHERE batch_id = @batch_id;

    IF @total_temp = 0
    BEGIN
        PRINT 'No rows found in temp.ods_order_item to merge.';
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Step 1: UPDATE matched and changed records (Set-based CDC via EXCEPT)
        UPDATE target
        SET target.order_id          = source.order_id,
            target.menu_item_id      = source.menu_item_id,
            target.quantity          = source.quantity,
            target.unit_price        = source.unit_price,
            target.item_discount     = source.item_discount,
            target.line_total        = source.line_total,
            target.batch_id          = source.batch_id,
            target.source_file_name  = source.source_file_name,
            target.source_row_number = source.source_row_number,
            target.load_timestamp    = SYSUTCDATETIME()
        FROM ods.ods_order_item target
        INNER JOIN temp.ods_order_item source
            ON target.order_item_id = source.order_item_id
        WHERE source.batch_id = @batch_id
          AND EXISTS (
              SELECT source.order_id, source.menu_item_id, source.quantity, source.unit_price, source.item_discount, source.line_total
              EXCEPT
              SELECT target.order_id, target.menu_item_id, target.quantity, target.unit_price, target.item_discount, target.line_total
          );

        SET @updated_count = @@ROWCOUNT;

        -- Step 2: INSERT brand new records (NOT MATCHED)
        INSERT INTO ods.ods_order_item
        (
            order_item_id,
            order_id,
            menu_item_id,
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
            source.order_item_id,
            source.order_id,
            source.menu_item_id,
            source.quantity,
            source.unit_price,
            source.item_discount,
            source.line_total,
            source.batch_id,
            source.source_file_name,
            source.source_row_number,
            SYSUTCDATETIME()
        FROM temp.ods_order_item source
        WHERE source.batch_id = @batch_id
          AND NOT EXISTS (
              SELECT 1
              FROM ods.ods_order_item target
              WHERE target.order_item_id = source.order_item_id
          );

        SET @inserted_count = @@ROWCOUNT;

        DECLARE @unchanged_count INT = @total_temp - (@inserted_count + @updated_count);

        UPDATE control.etl_log
        SET rows_processed = @total_temp,
            rows_inserted  = @inserted_count,
            message        = CONCAT('Upsert completed: ', @inserted_count, ' inserted, ', @updated_count, ' updated, ', @unchanged_count, ' unchanged.')
        WHERE step_name    = 'LOAD_ORDER_ITEM'
          AND batch_id     = @batch_id
          AND status       = 'RUNNING';

        COMMIT TRANSACTION;

        -- Targeted Staging Cleanup (Isolated by Batch ID to prevent concurrency data loss)
        DELETE FROM temp.ods_order_item WHERE batch_id = @batch_id;



        PRINT CONCAT('ods_order_item: Total = ', @total_temp, ' | Inserted = ', @inserted_count, ' | Updated = ', @updated_count, ' | Unchanged = ', @unchanged_count);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/* ==============================================================================
   7. UPSERT ODS DELIVERY PERFORMANCE
============================================================================== */

CREATE OR ALTER PROCEDURE ods.usp_upsert_ods_delivery_performance
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT TOP 1 @batch_id = batch_id 
        FROM control.etl_batch 
        WHERE status IN ('RUNNING', 'SUCCESS')
        ORDER BY batch_id DESC;

        IF @batch_id IS NULL OR @batch_id <= 0
            SELECT @batch_id = MAX(batch_id) FROM raw.raw_delivery_performance;

        IF @batch_id IS NULL OR @batch_id <= 0
            SELECT TOP 1 @batch_id = batch_id FROM control.etl_batch ORDER BY batch_id DESC;
    END;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        THROW 50010, 'Parameter @batch_id is mandatory or could not be resolved from control.etl_batch or raw.raw_delivery_performance.', 1;
    END;

    DECLARE @total_temp INT = 0,
            @inserted_count INT = 0,
            @updated_count  INT = 0;

    SELECT @total_temp = COUNT(*) FROM temp.ods_delivery_performance WHERE batch_id = @batch_id;

    IF @total_temp = 0
    BEGIN
        PRINT 'No rows found in temp.ods_delivery_performance to merge.';
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Step 1: UPDATE matched and changed records (Set-based CDC via EXCEPT)
        UPDATE target
        SET target.order_id                   = source.order_id,
            target.prep_time                  = source.prep_time,
            target.rider_wait_time            = source.rider_wait_time,
            target.travel_time                = source.travel_time,
            target.order_item                 = source.order_item,
            target.expected_delivery_time_min = source.expected_delivery_time_min,
            target.actual_delivery_time_min   = source.actual_delivery_time_min,
            target.delivery_item              = source.delivery_item,
            target.distance_km                = source.distance_km,
            target.batch_id                   = source.batch_id,
            target.source_file_name           = source.source_file_name,
            target.source_row_number          = source.source_row_number,
            target.load_timestamp             = SYSUTCDATETIME()
        FROM ods.ods_delivery_performance target
        INNER JOIN temp.ods_delivery_performance source
            ON target.delivery_id = source.delivery_id
        WHERE source.batch_id = @batch_id
          AND EXISTS (
              SELECT source.order_id, source.prep_time, source.rider_wait_time, source.travel_time, source.order_item, source.expected_delivery_time_min, source.actual_delivery_time_min, source.delivery_item, source.distance_km
              EXCEPT
              SELECT target.order_id, target.prep_time, target.rider_wait_time, target.travel_time, target.order_item, target.expected_delivery_time_min, target.actual_delivery_time_min, target.delivery_item, target.distance_km
          );

        SET @updated_count = @@ROWCOUNT;

        -- Step 2: INSERT brand new records (NOT MATCHED)
        INSERT INTO ods.ods_delivery_performance
        (
            delivery_id,
            order_id,
            prep_time,
            rider_wait_time,
            travel_time,
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
            source.delivery_id,
            source.order_id,
            source.prep_time,
            source.rider_wait_time,
            source.travel_time,
            source.order_item,
            source.expected_delivery_time_min,
            source.actual_delivery_time_min,
            source.delivery_item,
            source.distance_km,
            source.batch_id,
            source.source_file_name,
            source.source_row_number,
            SYSUTCDATETIME()
        FROM temp.ods_delivery_performance source
        WHERE source.batch_id = @batch_id
          AND NOT EXISTS (
              SELECT 1
              FROM ods.ods_delivery_performance target
              WHERE target.delivery_id = source.delivery_id
          );

        SET @inserted_count = @@ROWCOUNT;

        DECLARE @unchanged_count INT = @total_temp - (@inserted_count + @updated_count);

        UPDATE control.etl_log
        SET rows_processed = @total_temp,
            rows_inserted  = @inserted_count,
            message        = CONCAT('Upsert completed: ', @inserted_count, ' inserted, ', @updated_count, ' updated, ', @unchanged_count, ' unchanged.')
        WHERE step_name    = 'LOAD_DELIVERY_PERFORMANCE'
          AND batch_id     = @batch_id
          AND status       = 'RUNNING';

        COMMIT TRANSACTION;

        -- Targeted Staging Cleanup (Isolated by Batch ID to prevent concurrency data loss)
        DELETE FROM temp.ods_delivery_performance WHERE batch_id = @batch_id;



        PRINT CONCAT('ods_delivery_performance: Total = ', @total_temp, ' | Inserted = ', @inserted_count, ' | Updated = ', @updated_count, ' | Unchanged = ', @unchanged_count);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


/* ==============================================================================
   8. UPSERT ODS RATING
============================================================================== */

CREATE OR ALTER PROCEDURE ods.usp_upsert_ods_rating
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT TOP 1 @batch_id = batch_id 
        FROM control.etl_batch 
        WHERE status IN ('RUNNING', 'SUCCESS')
        ORDER BY batch_id DESC;

        IF @batch_id IS NULL OR @batch_id <= 0
            SELECT @batch_id = MAX(batch_id) FROM raw.raw_rating;

        IF @batch_id IS NULL OR @batch_id <= 0
            SELECT TOP 1 @batch_id = batch_id FROM control.etl_batch ORDER BY batch_id DESC;
    END;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        THROW 50010, 'Parameter @batch_id is mandatory or could not be resolved from control.etl_batch or raw.raw_rating.', 1;
    END;

    DECLARE @total_temp INT = 0,
            @inserted_count INT = 0,
            @updated_count  INT = 0;

    SELECT @total_temp = COUNT(*) FROM temp.ods_rating WHERE batch_id = @batch_id;

    IF @total_temp = 0
    BEGIN
        PRINT 'No rows found in temp.ods_rating to merge.';
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Step 1: UPDATE matched and changed records (Set-based CDC via EXCEPT)
        UPDATE target
        SET target.order_id          = source.order_id,
            target.customer_id       = source.customer_id,
            target.restaurant_id     = source.restaurant_id,
            target.rating            = source.rating,
            target.review_text       = source.review_text,
            target.review_timestamp  = source.review_timestamp,
            target.sentiment_score   = source.sentiment_score,
            target.batch_id          = source.batch_id,
            target.source_file_name  = source.source_file_name,
            target.source_row_number = source.source_row_number,
            target.load_timestamp    = SYSUTCDATETIME()
        FROM ods.ods_rating target
        INNER JOIN temp.ods_rating source
            ON target.rating_id = source.rating_id
        WHERE source.batch_id = @batch_id
          AND EXISTS (
              SELECT source.order_id, source.customer_id, source.restaurant_id, source.rating, source.review_text, source.review_timestamp, source.sentiment_score
              EXCEPT
              SELECT target.order_id, target.customer_id, target.restaurant_id, target.rating, target.review_text, target.review_timestamp, target.sentiment_score
          );

        SET @updated_count = @@ROWCOUNT;

        -- Step 2: INSERT brand new records (NOT MATCHED)
        INSERT INTO ods.ods_rating
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
            source.rating_id,
            source.order_id,
            source.customer_id,
            source.restaurant_id,
            source.rating,
            source.review_text,
            source.review_timestamp,
            source.sentiment_score,
            source.batch_id,
            source.source_file_name,
            source.source_row_number,
            SYSUTCDATETIME()
        FROM temp.ods_rating source
        WHERE source.batch_id = @batch_id
          AND NOT EXISTS (
              SELECT 1
              FROM ods.ods_rating target
              WHERE target.rating_id = source.rating_id
          );

        SET @inserted_count = @@ROWCOUNT;

        DECLARE @unchanged_count INT = @total_temp - (@inserted_count + @updated_count);

        UPDATE control.etl_log
        SET rows_processed = @total_temp,
            rows_inserted  = @inserted_count,
            message        = CONCAT('Upsert completed: ', @inserted_count, ' inserted, ', @updated_count, ' updated, ', @unchanged_count, ' unchanged.')
        WHERE step_name    = 'LOAD_RATING'
          AND batch_id     = @batch_id
          AND status       = 'RUNNING';

        COMMIT TRANSACTION;

        -- Targeted Staging Cleanup (Isolated by Batch ID to prevent concurrency data loss)
        DELETE FROM temp.ods_rating WHERE batch_id = @batch_id;



        PRINT CONCAT('ods_rating: Total = ', @total_temp, ' | Inserted = ', @inserted_count, ' | Updated = ', @updated_count, ' | Unchanged = ', @unchanged_count);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO




/* ==============================================================================
   9. ORCHESTRATION: BATCH RAW TO ODS UPSERT PIPELINE
   PURPOSE: Production Native T-SQL execution engine for RAW -> ODS transformation.
            - Cleanses, standardizes, and validates records across all 8 entities.
            - Logs data quality and quarantine errors to control.etl_error.
            - Merges clean records into ODS via set-based UPSERT.
            - Used as the primary runtime orchestrator by Python (run_monthly_pipeline.py),
              providing a high-performance alternative to SSIS (.dtsx).
============================================================================== */

CREATE OR ALTER PROCEDURE ods.usp_load_raw_to_ods_batch
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT TOP 1 @batch_id = batch_id FROM control.etl_batch ORDER BY batch_id DESC;
        IF @batch_id IS NULL SELECT @batch_id = MAX(batch_id) FROM raw.raw_order;
    END;

    IF @batch_id IS NULL
    BEGIN
        THROW 50020, 'Cannot determine batch_id for RAW to ODS load.', 1;
    END;

    PRINT CONCAT('>>> [ETL RAW -> ODS] Starting load for BATCH_ID = ', @batch_id);

    -- =========================================================================
    -- 1. CUSTOMER
    -- =========================================================================
    EXEC control.usp_start_raw_to_ods_log @process_name = 'RAW_TO_ODS', @step_name = 'LOAD_CUSTOMER', @batch_id = @batch_id, @table_name = 'raw_customer';
    DELETE FROM temp.ods_customer WHERE batch_id = @batch_id;

    INSERT INTO temp.ods_customer (
        customer_id, signup_date, city, acquisition_channel, batch_id, source_file_name, source_row_number, load_timestamp
    )
    SELECT 
        LTRIM(RTRIM(customer_id)),
        COALESCE(TRY_CAST(signup_date AS DATE), TRY_CONVERT(DATE, LTRIM(RTRIM(signup_date)), 105)),
        LTRIM(RTRIM(city)),
        NULLIF(LTRIM(RTRIM(acquisition_channel)), ''),
        batch_id,
        source_file_name,
        source_row_number,
        SYSUTCDATETIME()
    FROM raw.raw_customer
    WHERE batch_id = @batch_id;

    EXEC ods.usp_upsert_ods_customer @batch_id = @batch_id;
    EXEC control.usp_end_raw_to_ods_log @step_name = 'LOAD_CUSTOMER', @target_table = 'ods_customer', @raw_table = 'raw_customer', @batch_id = @batch_id;

    -- =========================================================================
    -- 2. RESTAURANT
    -- =========================================================================
    EXEC control.usp_start_raw_to_ods_log @process_name = 'RAW_TO_ODS', @step_name = 'LOAD_RESTAURANT', @batch_id = @batch_id, @table_name = 'raw_restaurant';
    DELETE FROM temp.ods_restaurant WHERE batch_id = @batch_id;

    INSERT INTO temp.ods_restaurant (
        restaurant_id, onboard_date, restaurant_name, city, cuisine_type, partner_type, avg_prep_time_min, is_active, batch_id, source_file_name, source_row_number, load_timestamp
    )
    SELECT 
        LTRIM(RTRIM(restaurant_id)),
        COALESCE(TRY_CAST(onboard_date AS DATE), TRY_CONVERT(DATE, LTRIM(RTRIM(onboard_date)), 101)),
        LTRIM(RTRIM(restaurant_name)),
        LTRIM(RTRIM(city)),
        LTRIM(RTRIM(cuisine_type)),
        LTRIM(RTRIM(partner_type)),
        NULLIF(LTRIM(RTRIM(avg_prep_time_min)), ''),
        CASE WHEN UPPER(LTRIM(RTRIM(is_active))) IN ('Y', '1', 'TRUE') THEN 1 ELSE 0 END,
        batch_id,
        source_file_name,
        source_row_number,
        SYSUTCDATETIME()
    FROM raw.raw_restaurant
    WHERE batch_id = @batch_id;

    EXEC ods.usp_upsert_ods_restaurant @batch_id = @batch_id;
    EXEC control.usp_end_raw_to_ods_log @step_name = 'LOAD_RESTAURANT', @target_table = 'ods_restaurant', @raw_table = 'raw_restaurant', @batch_id = @batch_id;

    -- =========================================================================
    -- 3. DELIVERY PARTNER
    -- =========================================================================
    EXEC control.usp_start_raw_to_ods_log @process_name = 'RAW_TO_ODS', @step_name = 'LOAD_DELIVERY_PARTNER', @batch_id = @batch_id, @table_name = 'raw_delivery_partner';
    DELETE FROM temp.ods_delivery_partner WHERE batch_id = @batch_id;

    INSERT INTO temp.ods_delivery_partner (
        delivery_partner_id, onboard_date, partner_name, city, vehicle_type, employment_type, avg_rating, is_active, batch_id, source_file_name, source_row_number, load_timestamp
    )
    SELECT 
        LTRIM(RTRIM(delivery_partner_id)),
        COALESCE(TRY_CAST(onboard_date AS DATE), TRY_CONVERT(DATE, LTRIM(RTRIM(onboard_date)), 101)),
        LTRIM(RTRIM(partner_name)),
        LTRIM(RTRIM(city)),
        NULLIF(LTRIM(RTRIM(vehicle_type)), ''),
        NULLIF(LTRIM(RTRIM(employment_type)), ''),
        TRY_CAST(LTRIM(RTRIM(avg_rating)) AS DECIMAL(5,2)),
        CASE WHEN UPPER(LTRIM(RTRIM(is_active))) IN ('Y', '1', 'TRUE') THEN 1 ELSE 0 END,
        batch_id,
        source_file_name,
        source_row_number,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_partner
    WHERE batch_id = @batch_id;

    EXEC ods.usp_upsert_ods_delivery_partner @batch_id = @batch_id;
    EXEC control.usp_end_raw_to_ods_log @step_name = 'LOAD_DELIVERY_PARTNER', @target_table = 'ods_delivery_partner', @raw_table = 'raw_delivery_partner', @batch_id = @batch_id;

    -- =========================================================================
    -- 4. MENU ITEM
    -- =========================================================================
    EXEC control.usp_start_raw_to_ods_log @process_name = 'RAW_TO_ODS', @step_name = 'LOAD_MENU_ITEM', @batch_id = @batch_id, @table_name = 'raw_menu_item';
    DELETE FROM temp.ods_menu_item WHERE batch_id = @batch_id;

    INSERT INTO temp.ods_menu_item (
        menu_item_id, restaurant_id, item_name, category, is_veg, price, batch_id, source_file_name, source_row_number, load_timestamp
    )
    SELECT 
        LTRIM(RTRIM(menu_item_id)),
        LTRIM(RTRIM(restaurant_id)),
        LTRIM(RTRIM(item_name)),
        LTRIM(RTRIM(category)),
        CASE WHEN UPPER(LTRIM(RTRIM(is_veg))) IN ('Y', '1', 'TRUE') THEN 1 ELSE 0 END,
        TRY_CAST(LTRIM(RTRIM(price)) AS DECIMAL(10,2)),
        batch_id,
        source_file_name,
        source_row_number,
        SYSUTCDATETIME()
    FROM raw.raw_menu_item
    WHERE batch_id = @batch_id;

    EXEC ods.usp_upsert_ods_menu_item @batch_id = @batch_id;
    EXEC control.usp_end_raw_to_ods_log @step_name = 'LOAD_MENU_ITEM', @target_table = 'ods_menu_item', @raw_table = 'raw_menu_item', @batch_id = @batch_id;

    -- =========================================================================
    -- 5. ORDER
    -- =========================================================================
    EXEC control.usp_start_raw_to_ods_log @process_name = 'RAW_TO_ODS', @step_name = 'LOAD_ORDER', @batch_id = @batch_id, @table_name = 'raw_order';
    DELETE FROM temp.ods_order WHERE batch_id = @batch_id;

    -- Insert clean orders to temp
    INSERT INTO temp.ods_order (
        order_id, customer_id, restaurant_id, delivery_partner_id, order_timestamp,
        subtotal_amount, discount_amount, delivery_fee, total_amount, is_cod, is_cancelled,
        batch_id, source_file_name, source_row_number, load_timestamp
    )
    SELECT 
        LTRIM(RTRIM(o.order_id)),
        LTRIM(RTRIM(o.customer_id)),
        LTRIM(RTRIM(o.restaurant_id)),
        NULLIF(LTRIM(RTRIM(o.delivery_partner_id)), ''),
        TRY_CAST(o.order_timestamp AS DATETIME2),
        TRY_CAST(o.subtotal_amount AS DECIMAL(18,2)),
        TRY_CAST(o.discount_amount AS DECIMAL(18,2)),
        TRY_CAST(o.delivery_fee AS DECIMAL(18,2)),
        TRY_CAST(o.total_amount AS DECIMAL(18,2)),
        CASE WHEN UPPER(LTRIM(RTRIM(o.is_cod))) IN ('Y', '1', 'TRUE') THEN 1 ELSE 0 END,
        CASE WHEN UPPER(LTRIM(RTRIM(o.is_cancelled))) IN ('Y', '1', 'TRUE') THEN 1 ELSE 0 END,
        o.batch_id,
        o.source_file_name,
        o.source_row_number,
        SYSUTCDATETIME()
    FROM raw.raw_order o
    WHERE o.batch_id = @batch_id;

    EXEC ods.usp_upsert_ods_order @batch_id = @batch_id;
    EXEC control.usp_end_raw_to_ods_log @step_name = 'LOAD_ORDER', @target_table = 'ods_order', @raw_table = 'raw_order', @batch_id = @batch_id;

    -- =========================================================================
    -- 6. ORDER ITEM
    -- =========================================================================
    EXEC control.usp_start_raw_to_ods_log @process_name = 'RAW_TO_ODS', @step_name = 'LOAD_ORDER_ITEM', @batch_id = @batch_id, @table_name = 'raw_order_item';
    DELETE FROM temp.ods_order_item WHERE batch_id = @batch_id;

    -- Log FK violations: order_id missing in ods.ods_order
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        oi.batch_id,
        oi.source_file_name,
        oi.source_row_number,
        'raw_order_item',
        'order_id',
        'MASTER_DATA_NOT_FOUND',
        'order_id value does not exists in reference master',
        oi.order_id,
        SYSDATETIME()
    FROM raw.raw_order_item oi
    WHERE oi.batch_id = @batch_id
      AND NOT EXISTS (
          SELECT 1 FROM ods.ods_order o WHERE o.order_id = oi.order_id
      );

    -- Insert clean order items to temp
    INSERT INTO temp.ods_order_item (
        order_item_id, order_id, menu_item_id, quantity, unit_price, item_discount, line_total,
        batch_id, source_file_name, source_row_number, load_timestamp
    )
    SELECT 
        LTRIM(RTRIM(oi.order_item_id)),
        LTRIM(RTRIM(oi.order_id)),
        LTRIM(RTRIM(oi.menu_item_id)),
        TRY_CAST(oi.quantity AS INT),
        TRY_CAST(oi.unit_price AS DECIMAL(18,2)),
        TRY_CAST(oi.item_discount AS DECIMAL(18,2)),
        TRY_CAST(oi.line_total AS DECIMAL(18,2)),
        oi.batch_id,
        oi.source_file_name,
        oi.source_row_number,
        SYSUTCDATETIME()
    FROM raw.raw_order_item oi
    WHERE oi.batch_id = @batch_id
      AND EXISTS (
          SELECT 1 FROM ods.ods_order o WHERE o.order_id = oi.order_id
      );

    EXEC ods.usp_upsert_ods_order_item @batch_id = @batch_id;
    EXEC control.usp_end_raw_to_ods_log @step_name = 'LOAD_ORDER_ITEM', @target_table = 'ods_order_item', @raw_table = 'raw_order_item', @batch_id = @batch_id;

    -- =========================================================================
    -- 7. DELIVERY PERFORMANCE
    -- =========================================================================
    EXEC control.usp_start_raw_to_ods_log @process_name = 'RAW_TO_ODS', @step_name = 'LOAD_DELIVERY_PERFORMANCE', @batch_id = @batch_id, @table_name = 'raw_delivery_performance';
    DELETE FROM temp.ods_delivery_performance WHERE batch_id = @batch_id;

    -- Log FK violations: order_id missing in ods.ods_order
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        dp.batch_id,
        dp.source_file_name,
        dp.source_row_number,
        'raw_delivery_performance',
        'order_id',
        'MASTER_DATA_NOT_FOUND',
        'order_id value does not exists in reference master',
        dp.order_id,
        SYSDATETIME()
    FROM raw.raw_delivery_performance dp
    WHERE dp.batch_id = @batch_id
      AND NOT EXISTS (
          SELECT 1 FROM ods.ods_order o WHERE o.order_id = dp.order_id
      );

    -- Log format errors for actual_delivery_time_min
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        dp.batch_id,
        dp.source_file_name,
        dp.source_row_number,
        'raw_delivery_performance',
        'actual_delivery_time_min',
        'INVALID_FORMAT',
        'actual_delivery_time_min could not be converted to numeric',
        dp.actual_delivery_time_min,
        SYSDATETIME()
    FROM raw.raw_delivery_performance dp
    WHERE dp.batch_id = @batch_id
      AND EXISTS (
          SELECT 1 FROM ods.ods_order o WHERE o.order_id = dp.order_id
      )
      AND (dp.actual_delivery_time_min IS NULL OR LTRIM(RTRIM(dp.actual_delivery_time_min)) = '' OR TRY_CAST(TRY_CAST(dp.actual_delivery_time_min AS FLOAT) AS INT) IS NULL);

    -- Log format errors for order_item
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        dp.batch_id,
        dp.source_file_name,
        dp.source_row_number,
        'raw_delivery_performance',
        'order_item',
        'INVALID_FORMAT',
        'order_item could not be converted to numeric',
        dp.order_item,
        SYSDATETIME()
    FROM raw.raw_delivery_performance dp
    WHERE dp.batch_id = @batch_id
      AND EXISTS (
          SELECT 1 FROM ods.ods_order o WHERE o.order_id = dp.order_id
      )
      AND (dp.order_item IS NULL OR LTRIM(RTRIM(dp.order_item)) = '' OR TRY_CAST(TRY_CAST(dp.order_item AS FLOAT) AS INT) IS NULL);

    -- Log format errors for delivery_item
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        dp.batch_id,
        dp.source_file_name,
        dp.source_row_number,
        'raw_delivery_performance',
        'delivery_item',
        'INVALID_FORMAT',
        'delivery_item could not be converted to numeric',
        dp.delivery_item,
        SYSDATETIME()
    FROM raw.raw_delivery_performance dp
    WHERE dp.batch_id = @batch_id
      AND EXISTS (
          SELECT 1 FROM ods.ods_order o WHERE o.order_id = dp.order_id
      )
      AND (dp.delivery_item IS NULL OR LTRIM(RTRIM(dp.delivery_item)) = '' OR TRY_CAST(TRY_CAST(dp.delivery_item AS FLOAT) AS INT) IS NULL);

    -- Insert clean delivery performance to temp
    INSERT INTO temp.ods_delivery_performance (
        delivery_id, order_id, prep_time, rider_wait_time, travel_time,
        order_item, expected_delivery_time_min, actual_delivery_time_min,
        delivery_item, distance_km, batch_id, source_file_name, source_row_number, load_timestamp
    )
    SELECT 
        LTRIM(RTRIM(dp.delivery_id)),
        LTRIM(RTRIM(dp.order_id)),
        TRY_CAST(TRY_CAST(dp.prep_time AS FLOAT) AS INT),
        TRY_CAST(TRY_CAST(dp.rider_wait_time AS FLOAT) AS INT),
        TRY_CAST(TRY_CAST(dp.travel_time AS FLOAT) AS INT),
        TRY_CAST(TRY_CAST(dp.order_item AS FLOAT) AS INT),
        TRY_CAST(TRY_CAST(dp.expected_delivery_time_min AS FLOAT) AS INT),
        TRY_CAST(TRY_CAST(dp.actual_delivery_time_min AS FLOAT) AS INT),
        TRY_CAST(TRY_CAST(dp.delivery_item AS FLOAT) AS INT),
        TRY_CAST(dp.distance_km AS DECIMAL(10,2)),
        dp.batch_id,
        dp.source_file_name,
        dp.source_row_number,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance dp
    WHERE dp.batch_id = @batch_id
      AND EXISTS (
          SELECT 1 FROM ods.ods_order o WHERE o.order_id = dp.order_id
      )
      AND (dp.actual_delivery_time_min IS NOT NULL AND LTRIM(RTRIM(dp.actual_delivery_time_min)) <> '' AND TRY_CAST(TRY_CAST(dp.actual_delivery_time_min AS FLOAT) AS INT) IS NOT NULL)
      AND (dp.order_item IS NOT NULL AND LTRIM(RTRIM(dp.order_item)) <> '' AND TRY_CAST(TRY_CAST(dp.order_item AS FLOAT) AS INT) IS NOT NULL)
      AND (dp.delivery_item IS NOT NULL AND LTRIM(RTRIM(dp.delivery_item)) <> '' AND TRY_CAST(TRY_CAST(dp.delivery_item AS FLOAT) AS INT) IS NOT NULL);

    EXEC ods.usp_upsert_ods_delivery_performance @batch_id = @batch_id;
    EXEC control.usp_end_raw_to_ods_log @step_name = 'LOAD_DELIVERY_PERFORMANCE', @target_table = 'ods_delivery_performance', @raw_table = 'raw_delivery_performance', @batch_id = @batch_id;

    -- =========================================================================
    -- 8. RATING
    -- =========================================================================
    EXEC control.usp_start_raw_to_ods_log @process_name = 'RAW_TO_ODS', @step_name = 'LOAD_RATING', @batch_id = @batch_id, @table_name = 'raw_rating';
    DELETE FROM temp.ods_rating WHERE batch_id = @batch_id;

    INSERT INTO temp.ods_rating (
        rating_id, order_id, customer_id, restaurant_id, rating, review_text,
        review_timestamp, sentiment_score, batch_id, source_file_name, source_row_number, load_timestamp
    )
    SELECT 
        LTRIM(RTRIM(rating_id)),
        LTRIM(RTRIM(order_id)),
        LTRIM(RTRIM(customer_id)),
        LTRIM(RTRIM(restaurant_id)),
        TRY_CAST(rating AS DECIMAL(3,2)),
        NULLIF(LTRIM(RTRIM(review_text)), ''),
        TRY_CAST(review_timestamp AS DATETIME2),
        TRY_CAST(sentiment_score AS DECIMAL(5,4)),
        batch_id,
        source_file_name,
        source_row_number,
        SYSUTCDATETIME()
    FROM raw.raw_rating
    WHERE batch_id = @batch_id;

    EXEC ods.usp_upsert_ods_rating @batch_id = @batch_id;
    EXEC control.usp_end_raw_to_ods_log @step_name = 'LOAD_RATING', @target_table = 'ods_rating', @raw_table = 'raw_rating', @batch_id = @batch_id;

    PRINT CONCAT('>>> [ETL RAW -> ODS] Successfully finished load for BATCH_ID = ', @batch_id);
END;
GO

