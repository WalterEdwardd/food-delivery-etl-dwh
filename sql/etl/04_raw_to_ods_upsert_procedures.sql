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
        UPDATE control.etl_log
        SET rows_processed = 0,
            rows_inserted  = 0,
            message        = 'No valid staging rows found to merge (0 clean rows).'
        WHERE step_name    = 'LOAD_CUSTOMER'
          AND batch_id     = @batch_id
          AND status       = 'RUNNING';

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
        UPDATE control.etl_log
        SET rows_processed = 0,
            rows_inserted  = 0,
            message        = 'No valid staging rows found to merge (0 clean rows).'
        WHERE step_name    = 'LOAD_RESTAURANT'
          AND batch_id     = @batch_id
          AND status       = 'RUNNING';

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
        UPDATE control.etl_log
        SET rows_processed = 0,
            rows_inserted  = 0,
            message        = 'No valid staging rows found to merge (0 clean rows).'
        WHERE step_name    = 'LOAD_MENU_ITEM'
          AND batch_id     = @batch_id
          AND status       = 'RUNNING';

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
        UPDATE control.etl_log
        SET rows_processed = 0,
            rows_inserted  = 0,
            message        = 'No valid staging rows found to merge (0 clean rows).'
        WHERE step_name    = 'LOAD_DELIVERY_PARTNER'
          AND batch_id     = @batch_id
          AND status       = 'RUNNING';

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
        UPDATE control.etl_log
        SET rows_processed = 0,
            rows_inserted  = 0,
            message        = 'No valid staging rows found to merge (0 clean rows).'
        WHERE step_name    = 'LOAD_ORDER'
          AND batch_id     = @batch_id
          AND status       = 'RUNNING';

        PRINT 'No rows found in temp.ods_order to merge.';
        RETURN;
    END;

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    -- Audit & Log Orphan Records into control.etl_warning
    DECLARE @orphan_cust_count     INT = 0,
            @orphan_rest_count     INT = 0,
            @orphan_dp_count       INT = 0,
            @mismatch_amount_count INT = 0,
            @high_value_order_count INT = 0;

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

            UNION ALL

            -- 5. High-Value Order Observability Warning (VIP Catering / Large Orders > 5,000)
            SELECT 'ORDER', t.order_id, 
                   'HIGH_VALUE_ORDER', 
                   CONCAT('High-value order detected: total_amount = ', t.total_amount)
            WHERE t.total_amount > 5000
        ) w
        WHERE t.batch_id = @batch_id;

        -- Extract individual category counts for audit logging and console reporting
        SELECT 
            @orphan_cust_count      = COUNT(CASE WHEN warning_type = 'ORPHAN_CUSTOMER_DETECTED' THEN 1 END),
            @orphan_rest_count      = COUNT(CASE WHEN warning_type = 'ORPHAN_RESTAURANT_DETECTED' THEN 1 END),
            @orphan_dp_count        = COUNT(CASE WHEN warning_type = 'ORPHAN_DELIVERY_PARTNER_DETECTED' THEN 1 END),
            @mismatch_amount_count  = COUNT(CASE WHEN warning_type = 'TOTAL_AMOUNT_MISMATCH' THEN 1 END),
            @high_value_order_count = COUNT(CASE WHEN warning_type = 'HIGH_VALUE_ORDER' THEN 1 END)
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

        PRINT CONCAT('ods_order: Total = ', @total_temp, ' | Inserted = ', @inserted_count, ' | Updated = ', @updated_count, ' | Unchanged = ', @unchanged_count, ' | Orphan Cust = ', @orphan_cust_count, ' | Orphan Rest = ', @orphan_rest_count, ' | Orphan DP = ', @orphan_dp_count, ' | Amount Mismatch = ', @mismatch_amount_count, ' | High Value = ', @high_value_order_count);
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
        UPDATE control.etl_log
        SET rows_processed = 0,
            rows_inserted  = 0,
            message        = 'No valid staging rows found to merge (0 clean rows).'
        WHERE step_name    = 'LOAD_ORDER_ITEM'
          AND batch_id     = @batch_id
          AND status       = 'RUNNING';

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
        UPDATE control.etl_log
        SET rows_processed = 0,
            rows_inserted  = 0,
            message        = 'No valid staging rows found to merge (0 clean rows).'
        WHERE step_name    = 'LOAD_DELIVERY_PERFORMANCE'
          AND batch_id     = @batch_id
          AND status       = 'RUNNING';

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
        UPDATE control.etl_log
        SET rows_processed = 0,
            rows_inserted  = 0,
            message        = 'No valid staging rows found to merge (0 clean rows).'
        WHERE step_name    = 'LOAD_RATING'
          AND batch_id     = @batch_id
          AND status       = 'RUNNING';

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

    BEGIN TRY
    -- =========================================================================
    -- 1. CUSTOMER (SSIS Package 05 Conversion)
    -- =========================================================================
    EXEC control.usp_start_raw_to_ods_log @process_name = 'RAW_TO_ODS', @step_name = 'LOAD_CUSTOMER', @batch_id = @batch_id, @table_name = 'raw_customer';
    DELETE FROM temp.ods_customer WHERE batch_id = @batch_id;

    -- GATE 1: customer_id (CSPL - Validate Customer Required Fields)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_customer',
        'customer_id',
        'INVALID_REQUIRED_FIELD',
        'customer_id is null, empty, or invalid format',
        r.customer_id,
        SYSUTCDATETIME()
    FROM raw.raw_customer r
    WHERE r.batch_id = @batch_id
      AND (
          r.customer_id IS NULL 
          OR LTRIM(RTRIM(r.customer_id)) = ''
          OR LEN(LTRIM(RTRIM(r.customer_id))) <> 10
          OR r.customer_id NOT LIKE 'CUST[0-9][0-9][0-9][0-9][0-9][0-9]'
      );

    -- GATE 2: signup_date format (DC - Convert Singup Date Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_customer',
        'signup_date',
        'INVALID_FORMAT',
        'signup_date could not be converted to date',
        r.signup_date,
        SYSUTCDATETIME()
    FROM raw.raw_customer r
    WHERE r.batch_id = @batch_id
      AND (
          TRY_CONVERT(DATE, LTRIM(RTRIM(r.signup_date)), 101) IS NULL
          AND TRY_CONVERT(DATE, LTRIM(RTRIM(r.signup_date)), 105) IS NULL
          AND TRY_CAST(LTRIM(RTRIM(r.signup_date)) AS DATE) IS NULL
      );

    -- GATE 3: city lookup (LKP - Valid City)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_customer',
        'city',
        'MASTER_DATA_NOT_FOUND',
        'city value does not exists in reference master',
        r.city,
        SYSUTCDATETIME()
    FROM raw.raw_customer r
    WHERE r.batch_id = @batch_id
      AND NOT EXISTS (
          SELECT 1 
          FROM ref.ref_city rc 
          WHERE rc.is_active = 1
            AND (rc.city_code = UPPER(LTRIM(RTRIM(r.city))) OR UPPER(rc.city_name) = UPPER(LTRIM(RTRIM(r.city))))
      );

    -- GATE 4: acquisition_channel lookup (LKP - Valid Acquisition Channel)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_customer',
        'acquisition_channel',
        'MASTER_DATA_NOT_FOUND',
        'acquisition_channel value does not exists in reference master',
        r.acquisition_channel,
        SYSUTCDATETIME()
    FROM raw.raw_customer r
    WHERE r.batch_id = @batch_id
      AND NOT EXISTS (
          SELECT 1 
          FROM ref.ref_acquisition_channel rac 
          WHERE rac.is_active = 1
            AND (rac.acquisition_channel_code = UPPER(LTRIM(RTRIM(r.acquisition_channel))) OR UPPER(rac.acquisition_channel_name) = UPPER(LTRIM(RTRIM(r.acquisition_channel))))
      );

    -- QUARANTINE & LOAD CLEAN RECORDS INTO temp.ods_customer (WITH INTRA-BATCH DEDUPLICATION)
    ;WITH Deduplicated_Customer AS (
        SELECT 
            UPPER(LTRIM(RTRIM(r.customer_id))) AS customer_id,
            COALESCE(TRY_CONVERT(DATE, LTRIM(RTRIM(r.signup_date)), 101), TRY_CONVERT(DATE, LTRIM(RTRIM(r.signup_date)), 105), TRY_CAST(LTRIM(RTRIM(r.signup_date)) AS DATE)) AS signup_date,
            COALESCE(rc.city_name, LTRIM(RTRIM(r.city))) AS city,
            COALESCE(rac.acquisition_channel_name, LTRIM(RTRIM(r.acquisition_channel))) AS acquisition_channel,
            r.batch_id,
            r.source_file_name,
            r.source_row_number,
            ROW_NUMBER() OVER (
                PARTITION BY UPPER(LTRIM(RTRIM(r.customer_id)))
                ORDER BY r.source_row_number DESC
            ) AS rn
        FROM raw.raw_customer r
        LEFT JOIN ref.ref_city rc 
            ON rc.is_active = 1 
           AND (rc.city_code = UPPER(LTRIM(RTRIM(r.city))) OR UPPER(rc.city_name) = UPPER(LTRIM(RTRIM(r.city))))
        LEFT JOIN ref.ref_acquisition_channel rac 
            ON rac.is_active = 1 
           AND (rac.acquisition_channel_code = UPPER(LTRIM(RTRIM(r.acquisition_channel))) OR UPPER(rac.acquisition_channel_name) = UPPER(LTRIM(RTRIM(r.acquisition_channel))))
        WHERE r.batch_id = @batch_id
          AND NOT EXISTS (
              SELECT 1 
              FROM control.etl_error err
              WHERE err.batch_id = r.batch_id
                AND err.table_name = 'raw_customer'
                AND err.source_row_number = r.source_row_number
          )
    )
    INSERT INTO temp.ods_customer (
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
        SYSUTCDATETIME()
    FROM Deduplicated_Customer
    WHERE rn = 1;

    EXEC ods.usp_upsert_ods_customer @batch_id = @batch_id;
    EXEC control.usp_end_raw_to_ods_log @step_name = 'LOAD_CUSTOMER', @target_table = 'ods_customer', @raw_table = 'raw_customer', @batch_id = @batch_id;

    -- =========================================================================
    -- 2. RESTAURANT (SSIS Package 03 Conversion)
    -- =========================================================================
    EXEC control.usp_start_raw_to_ods_log @process_name = 'RAW_TO_ODS', @step_name = 'LOAD_RESTAURANT', @batch_id = @batch_id, @table_name = 'raw_restaurant';
    DELETE FROM temp.ods_restaurant WHERE batch_id = @batch_id;

    -- GATE 1: restaurant_id (CSPL - Validate Restaurant ID)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_restaurant',
        'restaurant_id',
        'INVALID_REQUIRED_FIELD',
        'restaurant_id is null, empty, or invalid format',
        r.restaurant_id,
        SYSUTCDATETIME()
    FROM raw.raw_restaurant r
    WHERE r.batch_id = @batch_id
      AND (
          r.restaurant_id IS NULL 
          OR LTRIM(RTRIM(r.restaurant_id)) = ''
          OR LEN(LTRIM(RTRIM(r.restaurant_id))) <> 9
          OR r.restaurant_id NOT LIKE 'REST[0-9][0-9][0-9][0-9][0-9]'
      );

    -- GATE 2: restaurant_name (CSPL - Validate Restaurant Name)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_restaurant',
        'restaurant_name',
        'MISSING_REQUIRED_FIELD',
        'restaurant_name is null or empty',
        r.restaurant_name,
        SYSUTCDATETIME()
    FROM raw.raw_restaurant r
    WHERE r.batch_id = @batch_id
      AND (
          r.restaurant_name IS NULL 
          OR LTRIM(RTRIM(r.restaurant_name)) = ''
      );

    -- GATE 3: onboard_date format (DC - Convert Onboard Date Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_restaurant',
        'onboard_date',
        'INVALID_FORMAT',
        'onboard_date could not be converted to date',
        r.onboard_date,
        SYSUTCDATETIME()
    FROM raw.raw_restaurant r
    WHERE r.batch_id = @batch_id
      AND (
          TRY_CONVERT(DATE, LTRIM(RTRIM(r.onboard_date)), 101) IS NULL
          AND TRY_CAST(LTRIM(RTRIM(r.onboard_date)) AS DATE) IS NULL
      );

    -- GATE 4: onboard_date range (CSPL - Validate Onboard Date Range)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_restaurant',
        'onboard_date',
        'INVALID_RANGE',
        'onboard_date can not be in the future',
        r.onboard_date,
        SYSUTCDATETIME()
FROM raw.raw_restaurant r
    WHERE r.batch_id = @batch_id
      AND COALESCE(TRY_CONVERT(DATE, LTRIM(RTRIM(r.onboard_date)), 101), TRY_CAST(LTRIM(RTRIM(r.onboard_date)) AS DATE)) > CAST(GETDATE() AS DATE);

    -- GATE 5: is_active status (CSPL - Validate IsActive Status)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_restaurant',
        'is_active',
        'INVALID_FORMAT',
        'is_active could not be converted to int',
        r.is_active,
        SYSUTCDATETIME()
    FROM raw.raw_restaurant r
    WHERE r.batch_id = @batch_id
      AND (
          r.is_active IS NULL 
          OR UPPER(LTRIM(RTRIM(r.is_active))) NOT IN ('Y', 'N')
      );

    -- GATE 6: city lookup (LKP - Valid City)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_restaurant',
        'city',
        'MASTER_DATA_NOT_FOUND',
        'city value does not exists in reference master',
        r.city,
        SYSUTCDATETIME()
    FROM raw.raw_restaurant r
    WHERE r.batch_id = @batch_id
      AND NOT EXISTS (
          SELECT 1 
          FROM ref.ref_city rc 
          WHERE rc.is_active = 1
            AND (rc.city_code = UPPER(LTRIM(RTRIM(r.city))) OR UPPER(rc.city_name) = UPPER(LTRIM(RTRIM(r.city))))
      );

    -- GATE 7: cuisine_type lookup (LKP - Valid Cuisine Type)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_restaurant',
        'cuisine_type',
        'MASTER_DATA_NOT_FOUND',
        'cuisine_type value does not exists in reference master',
        r.cuisine_type,
        SYSUTCDATETIME()
    FROM raw.raw_restaurant r
    WHERE r.batch_id = @batch_id
      AND NOT EXISTS (
          SELECT 1 
          FROM ref.ref_cuisine_type rct 
          WHERE rct.is_active = 1
            AND (rct.cuisine_type_code = UPPER(LTRIM(RTRIM(r.cuisine_type))) OR UPPER(rct.cuisine_type_name) = UPPER(LTRIM(RTRIM(r.cuisine_type))))
      );

    -- GATE 8: partner_type lookup (LKP - Partner Type)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_restaurant',
        'partner_type',
        'MASTER_DATA_NOT_FOUND',
        'partner_type value does not exists in reference master',
        r.partner_type,
        SYSUTCDATETIME()
    FROM raw.raw_restaurant r
    WHERE r.batch_id = @batch_id
      AND NOT EXISTS (
          SELECT 1 
          FROM ref.ref_partner_type rpt 
          WHERE rpt.is_active = 1
            AND (rpt.partner_type_code = UPPER(LTRIM(RTRIM(r.partner_type))) OR UPPER(rpt.partner_type_name) = UPPER(LTRIM(RTRIM(r.partner_type))))
      );

    -- QUARANTINE & LOAD CLEAN RECORDS INTO temp.ods_restaurant (WITH INTRA-BATCH DEDUPLICATION)
    ;WITH Deduplicated_Restaurant AS (
        SELECT 
            UPPER(LTRIM(RTRIM(r.restaurant_id))) AS restaurant_id,
            COALESCE(TRY_CONVERT(DATE, LTRIM(RTRIM(r.onboard_date)), 101), TRY_CAST(LTRIM(RTRIM(r.onboard_date)) AS DATE)) AS onboard_date,
            LTRIM(RTRIM(r.restaurant_name)) AS restaurant_name,
            COALESCE(rc.city_name, LTRIM(RTRIM(r.city))) AS city,
            COALESCE(rct.cuisine_type_name, LTRIM(RTRIM(r.cuisine_type))) AS cuisine_type,
            COALESCE(rpt.partner_type_name, LTRIM(RTRIM(r.partner_type))) AS partner_type,
            NULLIF(LTRIM(RTRIM(r.avg_prep_time_min)), '') AS avg_prep_time_min,
            CASE WHEN UPPER(LTRIM(RTRIM(r.is_active))) = 'Y' THEN 1 ELSE 0 END AS is_active,
            r.batch_id,
            r.source_file_name,
            r.source_row_number,
            ROW_NUMBER() OVER (
                PARTITION BY UPPER(LTRIM(RTRIM(r.restaurant_id)))
                ORDER BY r.source_row_number DESC
            ) AS rn
        FROM raw.raw_restaurant r
        LEFT JOIN ref.ref_city rc 
            ON rc.is_active = 1 
           AND (rc.city_code = UPPER(LTRIM(RTRIM(r.city))) OR UPPER(rc.city_name) = UPPER(LTRIM(RTRIM(r.city))))
        LEFT JOIN ref.ref_cuisine_type rct 
            ON rct.is_active = 1 
           AND (rct.cuisine_type_code = UPPER(LTRIM(RTRIM(r.cuisine_type))) OR UPPER(rct.cuisine_type_name) = UPPER(LTRIM(RTRIM(r.cuisine_type))))
        LEFT JOIN ref.ref_partner_type rpt 
            ON rpt.is_active = 1 
           AND (rpt.partner_type_code = UPPER(LTRIM(RTRIM(r.partner_type))) OR UPPER(rpt.partner_type_name) = UPPER(LTRIM(RTRIM(r.partner_type))))
        WHERE r.batch_id = @batch_id
          AND NOT EXISTS (
              SELECT 1 
              FROM control.etl_error err
              WHERE err.batch_id = r.batch_id
                AND err.table_name = 'raw_restaurant'
                AND err.source_row_number = r.source_row_number
          )
    )
    INSERT INTO temp.ods_restaurant (
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
        SYSUTCDATETIME()
    FROM Deduplicated_Restaurant
    WHERE rn = 1;

    EXEC ods.usp_upsert_ods_restaurant @batch_id = @batch_id;
    EXEC control.usp_end_raw_to_ods_log @step_name = 'LOAD_RESTAURANT', @target_table = 'ods_restaurant', @raw_table = 'raw_restaurant', @batch_id = @batch_id;

    -- =========================================================================
    -- 3. DELIVERY PARTNER (SSIS Package 02 Conversion)
    -- =========================================================================
    EXEC control.usp_start_raw_to_ods_log @process_name = 'RAW_TO_ODS', @step_name = 'LOAD_DELIVERY_PARTNER', @batch_id = @batch_id, @table_name = 'raw_delivery_partner';
    DELETE FROM temp.ods_delivery_partner WHERE batch_id = @batch_id;

    -- GATE 1: delivery_partner_id (CSPL - Validate Delivery Partner ID)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_partner',
        'delivery_partner_id',
        'INVALID_REQUIRED_FIELD',
        'delivery_partner_id is null, empty, or invalid format',
        r.delivery_partner_id,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_partner r
    WHERE r.batch_id = @batch_id
      AND (
          r.delivery_partner_id IS NULL 
          OR LTRIM(RTRIM(r.delivery_partner_id)) = ''
          OR LEN(LTRIM(RTRIM(r.delivery_partner_id))) <> 7
          OR r.delivery_partner_id NOT LIKE 'DP[0-9][0-9][0-9][0-9][0-9]'
      );

    -- GATE 2: onboard_date format (DC - Convert Onboard Date Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_partner',
        'onboard_date',
        'INVALID_FORMAT',
        'onboard_date could not be converted to date',
        r.onboard_date,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_partner r
    WHERE r.batch_id = @batch_id
      AND (
          TRY_CONVERT(DATE, LTRIM(RTRIM(r.onboard_date)), 101) IS NULL
          AND TRY_CAST(LTRIM(RTRIM(r.onboard_date)) AS DATE) IS NULL
      );

    -- GATE 3: onboard_date range (CSPL - Validate Onboard Date Range)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_partner',
        'onboard_date',
        'INVALID_RANGE',
        'onboard_date can not be in the future',
        r.onboard_date,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_partner r
    WHERE r.batch_id = @batch_id
      AND COALESCE(TRY_CONVERT(DATE, LTRIM(RTRIM(r.onboard_date)), 101), TRY_CAST(LTRIM(RTRIM(r.onboard_date)) AS DATE)) > CAST(GETDATE() AS DATE);

    -- GATE 4: avg_rating format (DC - Convert Avg Rating Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_partner',
        'avg_rating',
        'INVALID_FORMAT',
        'avg_rating could not be converted to numeric',
        r.avg_rating,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_partner r
    WHERE r.batch_id = @batch_id
      AND (
          r.avg_rating IS NOT NULL 
          AND LTRIM(RTRIM(r.avg_rating)) <> ''
          AND TRY_CAST(LTRIM(RTRIM(r.avg_rating)) AS DECIMAL(5,2)) IS NULL
      );

    -- GATE 5: avg_rating range (CSPL - Validate Avg Rating Range)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_partner',
        'avg_rating',
        'INVALID_RANGE',
        'avg_rating not in range 0-5',
        r.avg_rating,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_partner r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(LTRIM(RTRIM(r.avg_rating)) AS DECIMAL(5,2)) IS NOT NULL
      AND (
          TRY_CAST(LTRIM(RTRIM(r.avg_rating)) AS DECIMAL(5,2)) < 0.0 
          OR TRY_CAST(LTRIM(RTRIM(r.avg_rating)) AS DECIMAL(5,2)) > 5.0
      );

    -- GATE 6: is_active status (CSPL - Validate IsActive Status)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_partner',
        'is_active',
        'INVALID_FORMAT',
        'is_active could not be converted to int',
        r.is_active,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_partner r
    WHERE r.batch_id = @batch_id
      AND (
          r.is_active IS NULL 
          OR UPPER(LTRIM(RTRIM(r.is_active))) NOT IN ('Y', 'N')
      );

    -- GATE 7: city lookup (LKP - Valid City)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_partner',
        'city',
        'MASTER_DATA_NOT_FOUND',
        'city value does not exists in reference master',
        r.city,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_partner r
    WHERE r.batch_id = @batch_id
      AND NOT EXISTS (
          SELECT 1 
          FROM ref.ref_city rc 
          WHERE rc.is_active = 1
            AND (rc.city_code = UPPER(LTRIM(RTRIM(r.city))) OR UPPER(rc.city_name) = UPPER(LTRIM(RTRIM(r.city))))
      );

    -- GATE 8: vehicle_type lookup (LKP - Valid Vehicle Type)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_partner',
        'vehicle_type',
        'MASTER_DATA_NOT_FOUND',
        'vehicle_type value does not exists in reference master',
        r.vehicle_type,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_partner r
    WHERE r.batch_id = @batch_id
      AND NOT EXISTS (
          SELECT 1 
          FROM ref.ref_vehicle_type rvt 
          WHERE rvt.is_active = 1
            AND (rvt.vehicle_type_code = UPPER(LTRIM(RTRIM(r.vehicle_type))) OR UPPER(rvt.vehicle_type_name) = UPPER(LTRIM(RTRIM(r.vehicle_type))))
      );

    -- GATE 9: employment_type lookup (LKP - Valid Employment Type)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_partner',
        'employment_type',
        'MASTER_DATA_NOT_FOUND',
        'employment_type value does not exists in reference master',
        r.employment_type,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_partner r
    WHERE r.batch_id = @batch_id
      AND NOT EXISTS (
          SELECT 1 
          FROM ref.ref_employment_type ret 
          WHERE ret.is_active = 1
            AND (ret.employment_type_code = UPPER(LTRIM(RTRIM(r.employment_type))) OR UPPER(ret.employment_type_name) = UPPER(LTRIM(RTRIM(r.employment_type))))
      );

    -- QUARANTINE & LOAD CLEAN RECORDS INTO temp.ods_delivery_partner (WITH INTRA-BATCH DEDUPLICATION)
    ;WITH Deduplicated_Delivery_Partner AS (
        SELECT 
            UPPER(LTRIM(RTRIM(r.delivery_partner_id))) AS delivery_partner_id,
            COALESCE(TRY_CONVERT(DATE, LTRIM(RTRIM(r.onboard_date)), 101), TRY_CAST(LTRIM(RTRIM(r.onboard_date)) AS DATE)) AS onboard_date,
            CASE 
                WHEN r.partner_name IS NULL OR LTRIM(RTRIM(r.partner_name)) = '' THEN 'UNKNOWN NAME'
                ELSE LTRIM(RTRIM(r.partner_name))
            END AS partner_name,
            COALESCE(rc.city_name, LTRIM(RTRIM(r.city))) AS city,
            COALESCE(rvt.vehicle_type_name, LTRIM(RTRIM(r.vehicle_type))) AS vehicle_type,
            COALESCE(ret.employment_type_name, LTRIM(RTRIM(r.employment_type))) AS employment_type,
            TRY_CAST(LTRIM(RTRIM(r.avg_rating)) AS DECIMAL(5,2)) AS avg_rating,
            CASE WHEN UPPER(LTRIM(RTRIM(r.is_active))) = 'Y' THEN 1 ELSE 0 END AS is_active,
            r.batch_id,
            r.source_file_name,
            r.source_row_number,
            ROW_NUMBER() OVER (
                PARTITION BY UPPER(LTRIM(RTRIM(r.delivery_partner_id)))
                ORDER BY r.source_row_number DESC
            ) AS rn
        FROM raw.raw_delivery_partner r
        LEFT JOIN ref.ref_city rc 
            ON rc.is_active = 1 
           AND (rc.city_code = UPPER(LTRIM(RTRIM(r.city))) OR UPPER(rc.city_name) = UPPER(LTRIM(RTRIM(r.city))))
        LEFT JOIN ref.ref_vehicle_type rvt 
            ON rvt.is_active = 1 
           AND (rvt.vehicle_type_code = UPPER(LTRIM(RTRIM(r.vehicle_type))) OR UPPER(rvt.vehicle_type_name) = UPPER(LTRIM(RTRIM(r.vehicle_type))))
        LEFT JOIN ref.ref_employment_type ret 
            ON ret.is_active = 1 
           AND (ret.employment_type_code = UPPER(LTRIM(RTRIM(r.employment_type))) OR UPPER(ret.employment_type_name) = UPPER(LTRIM(RTRIM(r.employment_type))))
        WHERE r.batch_id = @batch_id
          AND NOT EXISTS (
              SELECT 1 
              FROM control.etl_error err
              WHERE err.batch_id = r.batch_id
                AND err.table_name = 'raw_delivery_partner'
                AND err.source_row_number = r.source_row_number
          )
    )
    INSERT INTO temp.ods_delivery_partner (
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
        SYSUTCDATETIME()
    FROM Deduplicated_Delivery_Partner
    WHERE rn = 1;

    EXEC ods.usp_upsert_ods_delivery_partner @batch_id = @batch_id;
    EXEC control.usp_end_raw_to_ods_log @step_name = 'LOAD_DELIVERY_PARTNER', @target_table = 'ods_delivery_partner', @raw_table = 'raw_delivery_partner', @batch_id = @batch_id;

    -- =========================================================================
    -- 4. MENU ITEM (SSIS Package 04 Conversion)
    -- =========================================================================
    EXEC control.usp_start_raw_to_ods_log @process_name = 'RAW_TO_ODS', @step_name = 'LOAD_MENU_ITEM', @batch_id = @batch_id, @table_name = 'raw_menu_item';
    DELETE FROM temp.ods_menu_item WHERE batch_id = @batch_id;

    -- GATE 1: menu_item_id (CSPL - Validate Menu Item ID)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_menu_item',
        'menu_item_id',
        'INVALID_REQUIRED_FIELD',
        'menu_item_id is null, empty, or invalid format',
        r.menu_item_id,
        SYSUTCDATETIME()
    FROM raw.raw_menu_item r
    WHERE r.batch_id = @batch_id
      AND (
          r.menu_item_id IS NULL 
          OR LTRIM(RTRIM(r.menu_item_id)) = ''
          OR LEN(LTRIM(RTRIM(r.menu_item_id))) <> 14
          OR r.menu_item_id NOT LIKE 'MENU[0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9]'
      );

    -- GATE 2: restaurant_id (LKP - Restaurant ID)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_menu_item',
        'restaurant_id',
        'MASTER_DATA_NOT_FOUND',
        'restaurant_id value does not exists in reference master',
        r.restaurant_id,
        SYSUTCDATETIME()
    FROM raw.raw_menu_item r
    WHERE r.batch_id = @batch_id
      AND (
          r.restaurant_id IS NULL 
          OR LTRIM(RTRIM(r.restaurant_id)) = ''
          OR NOT EXISTS (
              SELECT 1 
              FROM ods.ods_restaurant o 
              WHERE o.restaurant_id = UPPER(LTRIM(RTRIM(r.restaurant_id)))
          )
      );

    -- GATE 3: price format (DC - Converted Price Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_menu_item',
        'price',
        'INVALID_FORMAT',
        'price could not be converted to numeric',
        r.price,
        SYSUTCDATETIME()
    FROM raw.raw_menu_item r
    WHERE r.batch_id = @batch_id
      AND (
          r.price IS NULL 
          OR LTRIM(RTRIM(r.price)) = ''
          OR TRY_CAST(LTRIM(RTRIM(r.price)) AS DECIMAL(10,2)) IS NULL
      );

    -- GATE 4: price range (CSPL - Valid Price Range [price >= 0])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_menu_item',
        'price',
        'INVALID_RANGE',
        'price is less than 0',
        r.price,
        SYSUTCDATETIME()
    FROM raw.raw_menu_item r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(LTRIM(RTRIM(r.price)) AS DECIMAL(10,2)) IS NOT NULL
      AND TRY_CAST(LTRIM(RTRIM(r.price)) AS DECIMAL(10,2)) < 0;

    -- GATE 5: is_veg status (CSPL - Validate IsVegetable Status)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_menu_item',
        'is_veg',
        'INVALID_FORMAT',
        'is_veg could not be converted to int',
        r.is_veg,
        SYSUTCDATETIME()
    FROM raw.raw_menu_item r
    WHERE r.batch_id = @batch_id
      AND (
          r.is_veg IS NULL 
          OR UPPER(LTRIM(RTRIM(r.is_veg))) NOT IN ('Y', 'N')
      );

    -- GATE 6: category lookup (LKP - Category)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_menu_item',
        'category',
        'MASTER_DATA_NOT_FOUND',
        'category value does not exists in reference master',
        r.category,
        SYSUTCDATETIME()
    FROM raw.raw_menu_item r
    WHERE r.batch_id = @batch_id
      AND NOT EXISTS (
          SELECT 1 
          FROM ref.ref_category rc 
          WHERE rc.is_active = 1
            AND (rc.category_code = UPPER(LTRIM(RTRIM(r.category))) OR UPPER(rc.category_name) = UPPER(LTRIM(RTRIM(r.category))))
      );

    -- QUARANTINE & LOAD CLEAN RECORDS INTO temp.ods_menu_item (WITH INTRA-BATCH DEDUPLICATION)
    ;WITH Deduplicated_Menu_Item AS (
        SELECT 
            UPPER(LTRIM(RTRIM(r.menu_item_id))) AS menu_item_id,
            UPPER(LTRIM(RTRIM(r.restaurant_id))) AS restaurant_id,
            CASE 
                WHEN r.item_name IS NULL OR LTRIM(RTRIM(r.item_name)) = '' THEN 'UNKNOWN NAME'
                ELSE LTRIM(RTRIM(r.item_name))
            END AS item_name,
            COALESCE(rc.category_name, LTRIM(RTRIM(r.category))) AS category,
            CASE WHEN UPPER(LTRIM(RTRIM(r.is_veg))) = 'Y' THEN 1 ELSE 0 END AS is_veg,
            TRY_CAST(LTRIM(RTRIM(r.price)) AS DECIMAL(10,2)) AS price,
            r.batch_id,
            r.source_file_name,
            r.source_row_number,
            ROW_NUMBER() OVER (
                PARTITION BY UPPER(LTRIM(RTRIM(r.menu_item_id)))
                ORDER BY r.source_row_number DESC
            ) AS rn
        FROM raw.raw_menu_item r
        LEFT JOIN ref.ref_category rc 
            ON rc.is_active = 1 
           AND (rc.category_code = UPPER(LTRIM(RTRIM(r.category))) OR UPPER(rc.category_name) = UPPER(LTRIM(RTRIM(r.category))))
        WHERE r.batch_id = @batch_id
          AND NOT EXISTS (
              SELECT 1 
              FROM control.etl_error err
              WHERE err.batch_id = r.batch_id
                AND err.table_name = 'raw_menu_item'
                AND err.source_row_number = r.source_row_number
          )
    )
    INSERT INTO temp.ods_menu_item (
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
        SYSUTCDATETIME()
    FROM Deduplicated_Menu_Item
    WHERE rn = 1;

    EXEC ods.usp_upsert_ods_menu_item @batch_id = @batch_id;
    EXEC control.usp_end_raw_to_ods_log @step_name = 'LOAD_MENU_ITEM', @target_table = 'ods_menu_item', @raw_table = 'raw_menu_item', @batch_id = @batch_id;

    -- =========================================================================
    -- 5. ORDER (SSIS Package 06 Conversion)
    -- =========================================================================
    EXEC control.usp_start_raw_to_ods_log @process_name = 'RAW_TO_ODS', @step_name = 'LOAD_ORDER', @batch_id = @batch_id, @table_name = 'raw_order';
    DELETE FROM temp.ods_order WHERE batch_id = @batch_id;

    -- GATE 1: order_id (CSPL - Validate Order Required Fields)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order',
        'order_id',
        'INVALID_REQUIRED_FIELD',
        'order_id is null, empty, or invalid format',
        r.order_id,
        SYSUTCDATETIME()
    FROM raw.raw_order r
    WHERE r.batch_id = @batch_id
      AND (
          r.order_id IS NULL 
          OR LTRIM(RTRIM(r.order_id)) = ''
          OR LEN(LTRIM(RTRIM(r.order_id))) <> 15
          OR r.order_id NOT LIKE 'ORD[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
      );

    -- GATE 2: customer_id (CSPL - Validate Customer Required Fields)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order',
        'customer_id',
        'INVALID_REQUIRED_FIELD',
        'customer_id is null, empty, or invalid format',
        r.customer_id,
        SYSUTCDATETIME()
    FROM raw.raw_order r
    WHERE r.batch_id = @batch_id
      AND (
          r.customer_id IS NULL 
          OR LTRIM(RTRIM(r.customer_id)) = ''
          OR LEN(LTRIM(RTRIM(r.customer_id))) <> 10
          OR r.customer_id NOT LIKE 'CUST[0-9][0-9][0-9][0-9][0-9][0-9]'
      );

    -- GATE 3: restaurant_id (CSPL - Validate Restaurant Required Fields)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order',
        'restaurant_id',
        'INVALID_REQUIRED_FIELD',
        'restaurant_id is null, empty, or invalid format',
        r.restaurant_id,
        SYSUTCDATETIME()
    FROM raw.raw_order r
    WHERE r.batch_id = @batch_id
      AND (
          r.restaurant_id IS NULL 
          OR LTRIM(RTRIM(r.restaurant_id)) = ''
          OR LEN(LTRIM(RTRIM(r.restaurant_id))) <> 9
          OR r.restaurant_id NOT LIKE 'REST[0-9][0-9][0-9][0-9][0-9]'
      );

    -- GATE 4: delivery_partner_id (CSPL - Validate Delivery Partner Required Field)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order',
        'delivery_partner_id',
        'INVALID_REQUIRED_FIELD',
        'delivery_partner_id is null, empty, or invalid format',
        r.delivery_partner_id,
        SYSUTCDATETIME()
    FROM raw.raw_order r
    WHERE r.batch_id = @batch_id
      AND r.delivery_partner_id IS NOT NULL 
      AND LTRIM(RTRIM(r.delivery_partner_id)) <> ''
      AND (
          LEN(LTRIM(RTRIM(r.delivery_partner_id))) <> 7
          OR r.delivery_partner_id NOT LIKE 'DP[0-9][0-9][0-9][0-9][0-9]'
      );

    -- GATE 5: order_timestamp format (DC - Convert Order Timestamp Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order',
        'order_timestamp',
        'INVALID_FORMAT',
        'order_timestamp could not be converted to datetime',
        r.order_timestamp,
        SYSUTCDATETIME()
    FROM raw.raw_order r
    WHERE r.batch_id = @batch_id
      AND (
          TRY_CAST(r.order_timestamp AS DATETIME2) IS NULL 
          AND TRY_CONVERT(DATETIME2, LTRIM(RTRIM(r.order_timestamp)), 120) IS NULL
      );

    -- GATE 6: is_cod (CSPL - Validate IsCOD Status)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order',
        'is_cod',
        'INVALID_FORMAT',
        'is_cod could not be converted to boolean',
        r.is_cod,
        SYSUTCDATETIME()
    FROM raw.raw_order r
    WHERE r.batch_id = @batch_id
      AND (
          r.is_cod IS NULL 
          OR UPPER(LTRIM(RTRIM(r.is_cod))) NOT IN ('Y', 'N')
      );

    -- GATE 7: is_cancelled (CSPL - Validate IsCancelled Status)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order',
        'is_cancelled',
        'INVALID_FORMAT',
        'is_cancelled could not be converted to boolean',
        r.is_cancelled,
        SYSUTCDATETIME()
    FROM raw.raw_order r
    WHERE r.batch_id = @batch_id
      AND (
          r.is_cancelled IS NULL 
          OR UPPER(LTRIM(RTRIM(r.is_cancelled))) NOT IN ('Y', 'N')
      );

    -- GATE 8: subtotal_amount format (DC - Convert SubTotal Amount Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order',
        'subtotal_amount',
        'INVALID_FORMAT',
        'subtotal_amount could not be converted to numeric',
        r.subtotal_amount,
        SYSUTCDATETIME()
    FROM raw.raw_order r
    WHERE r.batch_id = @batch_id
      AND (
          r.subtotal_amount IS NULL 
          OR LTRIM(RTRIM(r.subtotal_amount)) = ''
          OR TRY_CAST(LTRIM(RTRIM(r.subtotal_amount)) AS DECIMAL(18,2)) IS NULL
      );

    -- GATE 9: subtotal_amount range (CSPL - Valid SubTotal Amount Range [subtotal_amount >= 0])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order',
        'subtotal_amount',
        'INVALID_RANGE',
        'subtotal_amount is less than 0',
        r.subtotal_amount,
        SYSUTCDATETIME()
    FROM raw.raw_order r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(LTRIM(RTRIM(r.subtotal_amount)) AS DECIMAL(18,2)) IS NOT NULL
      AND TRY_CAST(LTRIM(RTRIM(r.subtotal_amount)) AS DECIMAL(18,2)) < 0;

    -- GATE 10: discount_amount format (DC - Convert Discount Amount Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order',
        'discount_amount',
        'INVALID_FORMAT',
        'discount_amount could not be converted to numeric',
        r.discount_amount,
        SYSUTCDATETIME()
    FROM raw.raw_order r
    WHERE r.batch_id = @batch_id
      AND r.discount_amount IS NOT NULL 
      AND LTRIM(RTRIM(r.discount_amount)) <> ''
      AND TRY_CAST(LTRIM(RTRIM(r.discount_amount)) AS DECIMAL(18,2)) IS NULL;

    -- GATE 11: discount_amount range (CSPL - Valid Discount Amount Range [discount_amount >= 0])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order',
        'discount_amount',
        'INVALID_RANGE',
        'discount_amount is less than 0',
        r.discount_amount,
        SYSUTCDATETIME()
    FROM raw.raw_order r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(LTRIM(RTRIM(r.discount_amount)) AS DECIMAL(18,2)) IS NOT NULL
      AND TRY_CAST(LTRIM(RTRIM(r.discount_amount)) AS DECIMAL(18,2)) < 0;

    -- GATE 12: delivery_fee format (DC - Convert Delivery Fee Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order',
        'delivery_fee',
        'INVALID_FORMAT',
        'delivery_fee could not be converted to numeric',
        r.delivery_fee,
        SYSUTCDATETIME()
    FROM raw.raw_order r
    WHERE r.batch_id = @batch_id
      AND r.delivery_fee IS NOT NULL 
      AND LTRIM(RTRIM(r.delivery_fee)) <> ''
      AND TRY_CAST(LTRIM(RTRIM(r.delivery_fee)) AS DECIMAL(18,2)) IS NULL;

    -- GATE 13: delivery_fee range (CSPL - Valid Delivery Fee Range [delivery_fee >= 0])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order',
        'delivery_fee',
        'INVALID_RANGE',
        'delivery_fee is less than 0',
        r.delivery_fee,
        SYSUTCDATETIME()
    FROM raw.raw_order r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(LTRIM(RTRIM(r.delivery_fee)) AS DECIMAL(18,2)) IS NOT NULL
      AND TRY_CAST(LTRIM(RTRIM(r.delivery_fee)) AS DECIMAL(18,2)) < 0;

    -- GATE 14: total_amount format (DC - Convert Total Amount Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order',
        'total_amount',
        'INVALID_FORMAT',
        'total_amount could not be converted to numeric',
        r.total_amount,
        SYSUTCDATETIME()
    FROM raw.raw_order r
    WHERE r.batch_id = @batch_id
      AND (
          r.total_amount IS NULL 
          OR LTRIM(RTRIM(r.total_amount)) = ''
          OR TRY_CAST(LTRIM(RTRIM(r.total_amount)) AS DECIMAL(18,2)) IS NULL
      );

    -- GATE 15: total_amount range (CSPL - Valid Total Amount Range [total_amount >= 0])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order',
        'total_amount',
        'INVALID_RANGE',
        'total_amount is less than 0',
        r.total_amount,
        SYSUTCDATETIME()
    FROM raw.raw_order r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(LTRIM(RTRIM(r.total_amount)) AS DECIMAL(18,2)) IS NOT NULL
      AND TRY_CAST(LTRIM(RTRIM(r.total_amount)) AS DECIMAL(18,2)) < 0;

    -- QUARANTINE & LOAD CLEAN RECORDS INTO temp.ods_order (WITH INTRA-BATCH DEDUPLICATION)
    ;WITH Deduplicated_Order AS (
        SELECT 
            UPPER(LTRIM(RTRIM(r.order_id))) AS order_id,
            UPPER(LTRIM(RTRIM(r.customer_id))) AS customer_id,
            UPPER(LTRIM(RTRIM(r.restaurant_id))) AS restaurant_id,
            NULLIF(UPPER(LTRIM(RTRIM(r.delivery_partner_id))), '') AS delivery_partner_id,
            COALESCE(TRY_CAST(r.order_timestamp AS DATETIME2), TRY_CONVERT(DATETIME2, LTRIM(RTRIM(r.order_timestamp)), 120)) AS order_timestamp,
            TRY_CAST(LTRIM(RTRIM(r.subtotal_amount)) AS DECIMAL(18,2)) AS subtotal_amount,
            COALESCE(TRY_CAST(LTRIM(RTRIM(r.discount_amount)) AS DECIMAL(18,2)), 0.00) AS discount_amount,
            COALESCE(TRY_CAST(LTRIM(RTRIM(r.delivery_fee)) AS DECIMAL(18,2)), 0.00) AS delivery_fee,
            TRY_CAST(LTRIM(RTRIM(r.total_amount)) AS DECIMAL(18,2)) AS total_amount,
            CASE WHEN UPPER(LTRIM(RTRIM(r.is_cod))) = 'Y' THEN 1 ELSE 0 END AS is_cod,
            CASE WHEN UPPER(LTRIM(RTRIM(r.is_cancelled))) = 'Y' THEN 1 ELSE 0 END AS is_cancelled,
            r.batch_id,
            r.source_file_name,
            r.source_row_number,
            ROW_NUMBER() OVER (
                PARTITION BY UPPER(LTRIM(RTRIM(r.order_id)))
                ORDER BY r.source_row_number DESC
            ) AS rn
        FROM raw.raw_order r
        WHERE r.batch_id = @batch_id
          AND NOT EXISTS (
              SELECT 1 
              FROM control.etl_error err
              WHERE err.batch_id = r.batch_id
                AND err.table_name = 'raw_order'
                AND err.source_row_number = r.source_row_number
          )
    )
    INSERT INTO temp.ods_order (
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
        SYSUTCDATETIME()
    FROM Deduplicated_Order
    WHERE rn = 1;

    EXEC ods.usp_upsert_ods_order @batch_id = @batch_id;
    EXEC control.usp_end_raw_to_ods_log @step_name = 'LOAD_ORDER', @target_table = 'ods_order', @raw_table = 'raw_order', @batch_id = @batch_id;

    -- =========================================================================
    -- 6. ORDER ITEM (SSIS Package 07 Conversion)
    -- =========================================================================
    EXEC control.usp_start_raw_to_ods_log @process_name = 'RAW_TO_ODS', @step_name = 'LOAD_ORDER_ITEM', @batch_id = @batch_id, @table_name = 'raw_order_item';
    DELETE FROM temp.ods_order_item WHERE batch_id = @batch_id;

    -- GATE 1: order_item_id format & presence (CSPL - Validate Order Item Required Fields)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order_item',
        'order_item_id',
        'INVALID_REQUIRED_FIELD',
        'order_item_id is null, empty, or invalid format',
        r.order_item_id,
        SYSUTCDATETIME()
    FROM raw.raw_order_item r
    WHERE r.batch_id = @batch_id
      AND (
          r.order_item_id IS NULL 
          OR LTRIM(RTRIM(r.order_item_id)) = ''
          OR NOT (
              LTRIM(RTRIM(r.order_item_id)) LIKE 'ITE%' 
              AND LEN(LTRIM(RTRIM(r.order_item_id))) = 18 
              AND SUBSTRING(LTRIM(RTRIM(r.order_item_id)), 4, 15) NOT LIKE '%[^0-9]%'
          )
      );

    -- GATE 2: order_id format & presence (CSPL - Validate Order Required Fields)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order_item',
        'order_id',
        'INVALID_REQUIRED_FIELD',
        'order_id is null, empty, or invalid format',
        r.order_id,
        SYSUTCDATETIME()
    FROM raw.raw_order_item r
    WHERE r.batch_id = @batch_id
      AND (
          r.order_id IS NULL 
          OR LTRIM(RTRIM(r.order_id)) = ''
          OR NOT (
              LTRIM(RTRIM(r.order_id)) LIKE 'ORD%' 
              AND LEN(LTRIM(RTRIM(r.order_id))) = 15 
              AND SUBSTRING(LTRIM(RTRIM(r.order_id)), 4, 12) NOT LIKE '%[^0-9]%'
          )
      );

    -- GATE 3: menu_item_id format & presence (CSPL - Validate Menu Item Required Field)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order_item',
        'menu_item_id',
        'INVALID_REQUIRED_FIELD',
        'menu_item_id is null, empty, or invalid format',
        r.menu_item_id,
        SYSUTCDATETIME()
    FROM raw.raw_order_item r
    WHERE r.batch_id = @batch_id
      AND (
          r.menu_item_id IS NULL 
          OR LTRIM(RTRIM(r.menu_item_id)) = ''
          OR NOT (
              LTRIM(RTRIM(r.menu_item_id)) LIKE 'MENU%' 
              AND LEN(LTRIM(RTRIM(r.menu_item_id))) = 14 
              AND SUBSTRING(LTRIM(RTRIM(r.menu_item_id)), 5, 5) NOT LIKE '%[^0-9]%' 
              AND SUBSTRING(LTRIM(RTRIM(r.menu_item_id)), 10, 1) = '_' 
              AND SUBSTRING(LTRIM(RTRIM(r.menu_item_id)), 11, 4) NOT LIKE '%[^0-9]%'
          )
      );

    -- GATE 4: order_id Master Data Lookup (LKP - Valid Order ID)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order_item',
        'order_id',
        'MASTER_DATA_NOT_FOUND',
        'order_id value does not exists in reference master',
        r.order_id,
        SYSUTCDATETIME()
    FROM raw.raw_order_item r
    WHERE r.batch_id = @batch_id
      AND r.order_id IS NOT NULL 
      AND LTRIM(RTRIM(r.order_id)) <> ''
      AND (
          LTRIM(RTRIM(r.order_id)) LIKE 'ORD%' 
          AND LEN(LTRIM(RTRIM(r.order_id))) = 15 
          AND SUBSTRING(LTRIM(RTRIM(r.order_id)), 4, 12) NOT LIKE '%[^0-9]%'
      )
      AND NOT EXISTS (
          SELECT 1 FROM ods.ods_order o WHERE o.order_id = UPPER(LTRIM(RTRIM(r.order_id)))
      );

    -- GATE 5: menu_item_id Master Data Lookup (LKP - Valid Menu Item ID)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order_item',
        'menu_item_id',
        'MASTER_DATA_NOT_FOUND',
        'menu_item_id value does not exists in reference master',
        r.menu_item_id,
        SYSUTCDATETIME()
    FROM raw.raw_order_item r
    WHERE r.batch_id = @batch_id
      AND r.menu_item_id IS NOT NULL 
      AND LTRIM(RTRIM(r.menu_item_id)) <> ''
      AND (
          LTRIM(RTRIM(r.menu_item_id)) LIKE 'MENU%' 
          AND LEN(LTRIM(RTRIM(r.menu_item_id))) = 14 
          AND SUBSTRING(LTRIM(RTRIM(r.menu_item_id)), 5, 5) NOT LIKE '%[^0-9]%' 
          AND SUBSTRING(LTRIM(RTRIM(r.menu_item_id)), 10, 1) = '_' 
          AND SUBSTRING(LTRIM(RTRIM(r.menu_item_id)), 11, 4) NOT LIKE '%[^0-9]%'
      )
      AND NOT EXISTS (
          SELECT 1 FROM ods.ods_menu_item m WHERE m.menu_item_id = UPPER(LTRIM(RTRIM(r.menu_item_id)))
      );

    -- GATE 6: quantity format (DC - Convert Quantity Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order_item',
        'quantity',
        'INVALID_FORMAT',
        'quantity could not be converted to numeric',
        r.quantity,
        SYSUTCDATETIME()
    FROM raw.raw_order_item r
    WHERE r.batch_id = @batch_id
      AND (
          r.quantity IS NULL 
          OR LTRIM(RTRIM(r.quantity)) = ''
          OR TRY_CAST(LTRIM(RTRIM(r.quantity)) AS INT) IS NULL
      );

    -- GATE 7: quantity range (CSPL - Valid Quantity Range [quantity > 0])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order_item',
        'quantity',
        'INVALID_RANGE',
        'quantity value is less than or equal to 0',
        r.quantity,
        SYSUTCDATETIME()
    FROM raw.raw_order_item r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(LTRIM(RTRIM(r.quantity)) AS INT) IS NOT NULL
      AND TRY_CAST(LTRIM(RTRIM(r.quantity)) AS INT) <= 0;

    -- GATE 8: unit_price format (DC - Convert Unit Price Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order_item',
        'unit_price',
        'INVALID_FORMAT',
        'unit_price could not be converted to numeric',
        r.unit_price,
        SYSUTCDATETIME()
    FROM raw.raw_order_item r
    WHERE r.batch_id = @batch_id
      AND (
          r.unit_price IS NULL 
          OR LTRIM(RTRIM(r.unit_price)) = ''
          OR TRY_CAST(LTRIM(RTRIM(r.unit_price)) AS DECIMAL(18,2)) IS NULL
      );

    -- GATE 9: unit_price range (CSPL - Valid Unit Price Range [unit_price >= 0])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order_item',
        'unit_price',
        'INVALID_RANGE',
        'unit_price not in range 0-1000',
        r.unit_price,
        SYSUTCDATETIME()
    FROM raw.raw_order_item r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(LTRIM(RTRIM(r.unit_price)) AS DECIMAL(18,2)) IS NOT NULL
      AND TRY_CAST(LTRIM(RTRIM(r.unit_price)) AS DECIMAL(18,2)) < 0;

    -- GATE 10: item_discount format (DC - Convert Item Discount Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order_item',
        'item_discount',
        'INVALID_FORMAT',
        'item_discount could not be converted to numeric',
        r.item_discount,
        SYSUTCDATETIME()
    FROM raw.raw_order_item r
    WHERE r.batch_id = @batch_id
      AND (
          r.item_discount IS NULL 
          OR LTRIM(RTRIM(r.item_discount)) = ''
          OR TRY_CAST(LTRIM(RTRIM(r.item_discount)) AS DECIMAL(18,2)) IS NULL
      );

    -- GATE 11: item_discount range (CSPL - Valid Item Discount Range [0 <= item_discount <= quantity * unit_price])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order_item',
        'item_discount',
        'INVALID_RANGE',
        'Item discount is less than 0 or exceeds the total item amount',
        r.item_discount,
        SYSUTCDATETIME()
    FROM raw.raw_order_item r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(LTRIM(RTRIM(r.item_discount)) AS DECIMAL(18,2)) IS NOT NULL
      AND TRY_CAST(LTRIM(RTRIM(r.quantity)) AS INT) IS NOT NULL
      AND TRY_CAST(LTRIM(RTRIM(r.unit_price)) AS DECIMAL(18,2)) IS NOT NULL
      AND (
          TRY_CAST(LTRIM(RTRIM(r.item_discount)) AS DECIMAL(18,2)) < 0 
          OR TRY_CAST(LTRIM(RTRIM(r.item_discount)) AS DECIMAL(18,2)) > (
              TRY_CAST(LTRIM(RTRIM(r.quantity)) AS INT) * TRY_CAST(LTRIM(RTRIM(r.unit_price)) AS DECIMAL(18,2))
          )
      );

    -- GATE 12: line_total format (DC - Convert Line Total Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order_item',
        'line_total',
        'INVALID_FORMAT',
        'line_total could not be converted to numeric',
        r.line_total,
        SYSUTCDATETIME()
    FROM raw.raw_order_item r
    WHERE r.batch_id = @batch_id
      AND (
          r.line_total IS NULL 
          OR LTRIM(RTRIM(r.line_total)) = ''
          OR TRY_CAST(LTRIM(RTRIM(r.line_total)) AS DECIMAL(18,2)) IS NULL
      );

    -- GATE 13: line_total logic (CSPL - Validate Line Total Logic [tolerance 0.02])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_order_item',
        'line_total',
        'INVALID_LOGIC',
        'line_total does not match the calculated value within the allowed tolerance',
        r.line_total,
        SYSUTCDATETIME()
    FROM raw.raw_order_item r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(LTRIM(RTRIM(r.line_total)) AS DECIMAL(18,2)) IS NOT NULL
      AND TRY_CAST(LTRIM(RTRIM(r.quantity)) AS INT) IS NOT NULL
      AND TRY_CAST(LTRIM(RTRIM(r.unit_price)) AS DECIMAL(18,2)) IS NOT NULL
      AND TRY_CAST(LTRIM(RTRIM(r.item_discount)) AS DECIMAL(18,2)) IS NOT NULL
      AND (
          ABS(
              TRY_CAST(LTRIM(RTRIM(r.line_total)) AS DECIMAL(18,2)) 
              - (
                  TRY_CAST(LTRIM(RTRIM(r.quantity)) AS INT) * TRY_CAST(LTRIM(RTRIM(r.unit_price)) AS DECIMAL(18,2)) 
                  - TRY_CAST(LTRIM(RTRIM(r.item_discount)) AS DECIMAL(18,2))
              )
          ) > 0.02
      );

    -- Quarantine Filter: Only load clean records into temp.ods_order_item (WITH INTRA-BATCH DEDUPLICATION)
    ;WITH Deduplicated_Order_Item AS (
        SELECT 
            UPPER(LTRIM(RTRIM(r.order_item_id))) AS order_item_id,
            UPPER(LTRIM(RTRIM(r.order_id))) AS order_id,
            UPPER(LTRIM(RTRIM(r.menu_item_id))) AS menu_item_id,
            TRY_CAST(LTRIM(RTRIM(r.quantity)) AS INT) AS quantity,
            TRY_CAST(LTRIM(RTRIM(r.unit_price)) AS DECIMAL(18,2)) AS unit_price,
            TRY_CAST(LTRIM(RTRIM(r.item_discount)) AS DECIMAL(18,2)) AS item_discount,
            TRY_CAST(LTRIM(RTRIM(r.line_total)) AS DECIMAL(18,2)) AS line_total,
            r.batch_id,
            r.source_file_name,
            r.source_row_number,
            ROW_NUMBER() OVER (
                PARTITION BY UPPER(LTRIM(RTRIM(r.order_item_id)))
                ORDER BY r.source_row_number DESC
            ) AS rn
        FROM raw.raw_order_item r
        WHERE r.batch_id = @batch_id
          AND NOT EXISTS (
              SELECT 1 
              FROM control.etl_error err
              WHERE err.batch_id = r.batch_id
                AND err.table_name = 'raw_order_item'
                AND err.source_row_number = r.source_row_number
          )
    )
    INSERT INTO temp.ods_order_item (
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
        SYSUTCDATETIME()
    FROM Deduplicated_Order_Item
    WHERE rn = 1;

    EXEC ods.usp_upsert_ods_order_item @batch_id = @batch_id;
    EXEC control.usp_end_raw_to_ods_log @step_name = 'LOAD_ORDER_ITEM', @target_table = 'ods_order_item', @raw_table = 'raw_order_item', @batch_id = @batch_id;

    -- =========================================================================
    -- 7. DELIVERY PERFORMANCE (SSIS Package 08 Conversion)
    -- =========================================================================
    EXEC control.usp_start_raw_to_ods_log @process_name = 'RAW_TO_ODS', @step_name = 'LOAD_DELIVERY_PERFORMANCE', @batch_id = @batch_id, @table_name = 'raw_delivery_performance';
    DELETE FROM temp.ods_delivery_performance WHERE batch_id = @batch_id;

    -- Cache Cancelled Orders to enforce business scope (Delivery performance only tracks delivered orders)
    IF OBJECT_ID('tempdb..#Cancelled_Orders') IS NOT NULL DROP TABLE #Cancelled_Orders;
    SELECT DISTINCT order_id 
    INTO #Cancelled_Orders 
    FROM ods.ods_order 
    WHERE is_cancelled = 1;

    CREATE UNIQUE CLUSTERED INDEX CIX_Cancelled_Orders ON #Cancelled_Orders(order_id);

    -- GATE 1: delivery_id format & presence (CSPL - Validate Delivery Required Fields)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'delivery_id',
        'INVALID_REQUIRED_FIELD',
        'delivery_id is null, empty, or invalid format',
        r.delivery_id,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND (
          r.delivery_id IS NULL 
          OR LTRIM(RTRIM(r.delivery_id)) = ''
          OR NOT (
              LTRIM(RTRIM(r.delivery_id)) LIKE 'DEL%' 
              AND LEN(LTRIM(RTRIM(r.delivery_id))) = 15 
              AND SUBSTRING(LTRIM(RTRIM(r.delivery_id)), 4, 12) NOT LIKE '%[^0-9]%'
          )
      );

    -- GATE 2: order_id format & presence (CSPL - Validate Order Required Field)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'order_id',
        'INVALID_REQUIRED_FIELD',
        'order_id is null, empty, or invalid format',
        r.order_id,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND (
          r.order_id IS NULL 
          OR LTRIM(RTRIM(r.order_id)) = ''
          OR NOT (
              LTRIM(RTRIM(r.order_id)) LIKE 'ORD%' 
              AND LEN(LTRIM(RTRIM(r.order_id))) = 15 
              AND SUBSTRING(LTRIM(RTRIM(r.order_id)), 4, 12) NOT LIKE '%[^0-9]%'
          )
      );

    -- GATE 3: order_id Master Data Lookup (LKP - Validate Order ID)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'order_id',
        'MASTER_DATA_NOT_FOUND',
        'order_id value does not exists in reference master',
        r.order_id,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND r.order_id IS NOT NULL 
      AND LTRIM(RTRIM(r.order_id)) <> ''
      AND (
          LTRIM(RTRIM(r.order_id)) LIKE 'ORD%' 
          AND LEN(LTRIM(RTRIM(r.order_id))) = 15 
          AND SUBSTRING(LTRIM(RTRIM(r.order_id)), 4, 12) NOT LIKE '%[^0-9]%'
      )
      AND NOT EXISTS (
          SELECT 1 FROM ods.ods_order o WHERE o.order_id = UPPER(LTRIM(RTRIM(r.order_id)))
      );

    -- GATE 3B: order_id Cancelled Exclusion (CSPL - Exclude Cancelled Orders from Delivery Performance)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'order_id',
        'EXCLUDED_ORDER_CANCELLED',
        'Order was cancelled; delivery was not executed',
        r.order_id,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    INNER JOIN #Cancelled_Orders c
        ON c.order_id = UPPER(LTRIM(RTRIM(r.order_id)))
    WHERE r.batch_id = @batch_id;

    -- GATE 4: expected_delivery_time_min format (DC - Convert Expected Delivery Time)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'expected_delivery_time_min',
        'INVALID_FORMAT',
        'expected_delivery_time_min could not be converted to numeric',
        r.expected_delivery_time_min,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND NOT EXISTS (
          SELECT 1 FROM #Cancelled_Orders c
          WHERE c.order_id = UPPER(LTRIM(RTRIM(r.order_id)))
      )
      AND (
          r.expected_delivery_time_min IS NULL 
          OR LTRIM(RTRIM(r.expected_delivery_time_min)) = ''
          OR TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.expected_delivery_time_min)) AS DECIMAL(18,2)) AS INT) IS NULL
      );

    -- GATE 5: expected_delivery_time_min range (CSPL - Valid Expected Delivery Time Range [5-120])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'expected_delivery_time_min',
        'INVALID_RANGE',
        'expected_delivery_time_min not in range 5-120',
        r.expected_delivery_time_min,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.expected_delivery_time_min)) AS DECIMAL(18,2)) AS INT) IS NOT NULL
      AND (
          TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.expected_delivery_time_min)) AS DECIMAL(18,2)) AS INT) < 5 
          OR TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.expected_delivery_time_min)) AS DECIMAL(18,2)) AS INT) > 120
      );

    -- GATE 6: actual_delivery_time_min format (DC - Convert Actual Delivery Time)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'actual_delivery_time_min',
        'INVALID_FORMAT',
        'actual_delivery_time_min could not be converted to numeric',
        r.actual_delivery_time_min,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND NOT EXISTS (
          SELECT 1 FROM #Cancelled_Orders c
          WHERE c.order_id = UPPER(LTRIM(RTRIM(r.order_id)))
      )
      AND r.actual_delivery_time_min IS NOT NULL 
      AND LTRIM(RTRIM(r.actual_delivery_time_min)) <> ''
      AND TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.actual_delivery_time_min)) AS DECIMAL(18,2)) AS INT) IS NULL;

    -- GATE 7: actual_delivery_time_min range (CSPL - Valid Actual Delivery Time Range [5-180])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'actual_delivery_time_min',
        'INVALID_RANGE',
        'actual_delivery_time_min not in range 5-120',
        r.actual_delivery_time_min,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.actual_delivery_time_min)) AS DECIMAL(18,2)) AS INT) IS NOT NULL
      AND (
          TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.actual_delivery_time_min)) AS DECIMAL(18,2)) AS INT) < 5 
          OR TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.actual_delivery_time_min)) AS DECIMAL(18,2)) AS INT) > 180
      );

    -- GATE 8: distance_km format (DC - Convert Distance Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'distance_km',
        'INVALID_FORMAT',
        'distance_km could not be converted to numeric',
        r.distance_km,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND NOT EXISTS (
          SELECT 1 FROM #Cancelled_Orders c
          WHERE c.order_id = UPPER(LTRIM(RTRIM(r.order_id)))
      )
      AND (
          r.distance_km IS NULL 
          OR LTRIM(RTRIM(r.distance_km)) = ''
          OR TRY_CAST(LTRIM(RTRIM(r.distance_km)) AS DECIMAL(10,2)) IS NULL
      );

    -- GATE 9: distance_km range (CSPL - Valid Distance Range (0-100])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'distance_km',
        'INVALID_RANGE',
        'distance_km not in range 0-100',
        r.distance_km,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(LTRIM(RTRIM(r.distance_km)) AS DECIMAL(10,2)) IS NOT NULL
      AND (
          TRY_CAST(LTRIM(RTRIM(r.distance_km)) AS DECIMAL(10,2)) <= 0 
          OR TRY_CAST(LTRIM(RTRIM(r.distance_km)) AS DECIMAL(10,2)) > 100
      );

    -- GATE 10: order_item format (DC - Convert Order Item Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'order_item',
        'INVALID_FORMAT',
        'order_item could not be converted to numeric',
        r.order_item,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND NOT EXISTS (
          SELECT 1 FROM #Cancelled_Orders c
          WHERE c.order_id = UPPER(LTRIM(RTRIM(r.order_id)))
      )
      AND (
          r.order_item IS NULL 
          OR LTRIM(RTRIM(r.order_item)) = ''
          OR TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.order_item)) AS DECIMAL(18,2)) AS INT) IS NULL
      );

    -- GATE 11: order_item range (CSPL - Valid Order Item Range (0-100])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'order_item',
        'INVALID_RANGE',
        'order_item not in range 0-100',
        r.order_item,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.order_item)) AS DECIMAL(18,2)) AS INT) IS NOT NULL
      AND (
          TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.order_item)) AS DECIMAL(18,2)) AS INT) <= 0 
          OR TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.order_item)) AS DECIMAL(18,2)) AS INT) > 100
      );

    -- GATE 12: delivery_item format (DC - Convert Delivery Item Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'delivery_item',
        'INVALID_FORMAT',
        'delivery_item could not be converted to numeric',
        r.delivery_item,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND NOT EXISTS (
          SELECT 1 FROM #Cancelled_Orders c
          WHERE c.order_id = UPPER(LTRIM(RTRIM(r.order_id)))
      )
      AND r.delivery_item IS NOT NULL 
      AND LTRIM(RTRIM(r.delivery_item)) <> ''
      AND TRY_CAST(TRY_CAST(LTRIM(r.delivery_item) AS DECIMAL(18,2)) AS INT) IS NULL;

    -- GATE 13: delivery_item range (CSPL - Valid Delivery Item Range [0-100])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'delivery_item',
        'INVALID_RANGE',
        'delivery_item not in range 0-100',
        r.delivery_item,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(TRY_CAST(LTRIM(r.delivery_item) AS DECIMAL(18,2)) AS INT) IS NOT NULL
      AND (
          TRY_CAST(TRY_CAST(LTRIM(r.delivery_item) AS DECIMAL(18,2)) AS INT) < 0 
          OR TRY_CAST(TRY_CAST(LTRIM(r.delivery_item) AS DECIMAL(18,2)) AS INT) > 100
      );

    -- GATE 14: prep_time format (DC - Convert PrepTime Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'prep_time',
        'INVALID_FORMAT',
        'prep_time could not be converted to numeric',
        r.prep_time,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND r.prep_time IS NOT NULL 
      AND LTRIM(RTRIM(r.prep_time)) <> ''
      AND TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.prep_time)) AS DECIMAL(18,2)) AS INT) IS NULL;

    -- GATE 15: prep_time range (CSPL - Valid PrepTime Range [0-180])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'prep_time',
        'INVALID_RANGE',
        'prep_time not in range 0-180',
        r.prep_time,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.prep_time)) AS DECIMAL(18,2)) AS INT) IS NOT NULL
      AND (
          TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.prep_time)) AS DECIMAL(18,2)) AS INT) < 0 
          OR TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.prep_time)) AS DECIMAL(18,2)) AS INT) > 180
      );

    -- GATE 16: rider_wait_time format (DC - Convert Rider Wait Time Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'rider_wait_time',
        'INVALID_FORMAT',
        'rider_wait_time could not be converted to numeric',
        r.rider_wait_time,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND r.rider_wait_time IS NOT NULL 
      AND LTRIM(RTRIM(r.rider_wait_time)) <> ''
      AND TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.rider_wait_time)) AS DECIMAL(18,2)) AS INT) IS NULL;

    -- GATE 17: rider_wait_time range (CSPL - Valid Rider Wait Time Range [0-60])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'rider_wait_time',
        'INVALID_RANGE',
        'rider_wait_time not in range 0-60',
        r.rider_wait_time,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.rider_wait_time)) AS DECIMAL(18,2)) AS INT) IS NOT NULL
      AND (
          TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.rider_wait_time)) AS DECIMAL(18,2)) AS INT) < 0 
          OR TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.rider_wait_time)) AS DECIMAL(18,2)) AS INT) > 60
      );

    -- GATE 18: travel_time format (DC - Convert Travel Time Format)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'travel_time',
        'INVALID_FORMAT',
        'travel_time could not be converted to numeric',
        r.travel_time,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND r.travel_time IS NOT NULL 
      AND LTRIM(RTRIM(r.travel_time)) <> ''
      AND TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.travel_time)) AS DECIMAL(18,2)) AS INT) IS NULL;

    -- GATE 19: travel_time range (CSPL - Valid Travel Time Range [0-180])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'travel_time',
        'INVALID_RANGE',
        'travel_time not in range 0-180',
        r.travel_time,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.travel_time)) AS DECIMAL(18,2)) AS INT) IS NOT NULL
      AND (
          TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.travel_time)) AS DECIMAL(18,2)) AS INT) < 0 
          OR TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.travel_time)) AS DECIMAL(18,2)) AS INT) > 180
      );

    -- GATE 20: actual_delivery_time_min logic (CSPL - Validate Delivery Time Logic [actual == prep + travel])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'actual_delivery_time_min',
        'INVALID_LOGIC',
        'actual_delivery_time_min does not equal prep_time + travel_time',
        r.actual_delivery_time_min,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.actual_delivery_time_min)) AS DECIMAL(18,2)) AS INT) IS NOT NULL
      AND TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.prep_time)) AS DECIMAL(18,2)) AS INT) IS NOT NULL
      AND TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.travel_time)) AS DECIMAL(18,2)) AS INT) IS NOT NULL
      AND TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.actual_delivery_time_min)) AS DECIMAL(18,2)) AS INT) <> (
          TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.prep_time)) AS DECIMAL(18,2)) AS INT) 
          + TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.travel_time)) AS DECIMAL(18,2)) AS INT)
      );

    -- GATE 21: rider_wait_time logic (CSPL - Validate Rider Wait Time Logic [rider_wait_time <= prep_time])
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_delivery_performance',
        'rider_wait_time',
        'INVALID_LOGIC',
        'rider_wait_time is greater than prep_time',
        r.rider_wait_time,
        SYSUTCDATETIME()
    FROM raw.raw_delivery_performance r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.rider_wait_time)) AS DECIMAL(18,2)) AS INT) IS NOT NULL
      AND TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.prep_time)) AS DECIMAL(18,2)) AS INT) IS NOT NULL
      AND TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.rider_wait_time)) AS DECIMAL(18,2)) AS INT) > TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.prep_time)) AS DECIMAL(18,2)) AS INT);

    -- Quarantine Filter: Only load clean records into temp.ods_delivery_performance (WITH INTRA-BATCH DEDUPLICATION)
    ;WITH Deduplicated_Delivery_Performance AS (
        SELECT 
            UPPER(LTRIM(RTRIM(r.delivery_id))) AS delivery_id,
            UPPER(LTRIM(RTRIM(r.order_id))) AS order_id,
            TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.prep_time)) AS DECIMAL(18,2)) AS INT) AS prep_time,
            TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.rider_wait_time)) AS DECIMAL(18,2)) AS INT) AS rider_wait_time,
            TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.travel_time)) AS DECIMAL(18,2)) AS INT) AS travel_time,
            TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.order_item)) AS DECIMAL(18,2)) AS INT) AS order_item,
            TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.expected_delivery_time_min)) AS DECIMAL(18,2)) AS INT) AS expected_delivery_time_min,
            TRY_CAST(TRY_CAST(LTRIM(RTRIM(r.actual_delivery_time_min)) AS DECIMAL(18,2)) AS INT) AS actual_delivery_time_min,
            TRY_CAST(TRY_CAST(LTRIM(r.delivery_item) AS DECIMAL(18,2)) AS INT) AS delivery_item,
            TRY_CAST(LTRIM(RTRIM(r.distance_km)) AS DECIMAL(10,2)) AS distance_km,
            r.batch_id,
            r.source_file_name,
            r.source_row_number,
            ROW_NUMBER() OVER (
                PARTITION BY UPPER(LTRIM(RTRIM(r.delivery_id)))
                ORDER BY r.source_row_number DESC
            ) AS rn
        FROM raw.raw_delivery_performance r
        WHERE r.batch_id = @batch_id
          AND NOT EXISTS (
              SELECT 1 
              FROM control.etl_error err
              WHERE err.batch_id = r.batch_id
                AND err.table_name = 'raw_delivery_performance'
                AND err.source_row_number = r.source_row_number
          )
          AND NOT EXISTS (
              SELECT 1 FROM #Cancelled_Orders c
              WHERE c.order_id = UPPER(LTRIM(RTRIM(r.order_id)))
          )
    )
    INSERT INTO temp.ods_delivery_performance (
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
        SYSUTCDATETIME()
    FROM Deduplicated_Delivery_Performance
    WHERE rn = 1;

    EXEC ods.usp_upsert_ods_delivery_performance @batch_id = @batch_id;
    EXEC control.usp_end_raw_to_ods_log @step_name = 'LOAD_DELIVERY_PERFORMANCE', @target_table = 'ods_delivery_performance', @raw_table = 'raw_delivery_performance', @batch_id = @batch_id;
    DROP TABLE IF EXISTS #Cancelled_Orders;

    -- =========================================================================
    -- 8. RATING (SSIS Package 09 Conversion)
    -- =========================================================================
    EXEC control.usp_start_raw_to_ods_log @process_name = 'RAW_TO_ODS', @step_name = 'LOAD_RATING', @batch_id = @batch_id, @table_name = 'raw_rating';
    DELETE FROM temp.ods_rating WHERE batch_id = @batch_id;

    -- GATE 1: rating_id format & presence (CSPL - Validate Rating Required Fields)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_rating',
        'rating_id',
        'INVALID_REQUIRED_FIELD',
        'rating_id is null, empty, or invalid format',
        r.rating_id,
        SYSUTCDATETIME()
    FROM raw.raw_rating r
    WHERE r.batch_id = @batch_id
      AND (
          r.rating_id IS NULL 
          OR LTRIM(RTRIM(r.rating_id)) = ''
          OR NOT (
              LTRIM(RTRIM(r.rating_id)) LIKE 'RAT%' 
              AND LEN(LTRIM(RTRIM(r.rating_id))) = 15 
              AND SUBSTRING(LTRIM(RTRIM(r.rating_id)), 4, 12) NOT LIKE '%[^0-9]%'
          )
      );

    -- GATE 2: order_id format & presence (CSPL - Validate Order Required Fields)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_rating',
        'order_id',
        'INVALID_REQUIRED_FIELD',
        'order_id is null, empty, or invalid format',
        r.order_id,
        SYSUTCDATETIME()
    FROM raw.raw_rating r
    WHERE r.batch_id = @batch_id
      AND (
          r.order_id IS NULL 
          OR LTRIM(RTRIM(r.order_id)) = ''
          OR NOT (
              LTRIM(RTRIM(r.order_id)) LIKE 'ORD%' 
              AND LEN(LTRIM(RTRIM(r.order_id))) = 15 
              AND SUBSTRING(LTRIM(RTRIM(r.order_id)), 4, 12) NOT LIKE '%[^0-9]%'
          )
      );

    -- GATE 3: customer_id format & presence (CSPL - Validate Customer Required Fields)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_rating',
        'customer_id',
        'INVALID_REQUIRED_FIELD',
        'customer_id is null, empty, or invalid format',
        r.customer_id,
        SYSUTCDATETIME()
    FROM raw.raw_rating r
    WHERE r.batch_id = @batch_id
      AND (
          r.customer_id IS NULL 
          OR LTRIM(RTRIM(r.customer_id)) = ''
          OR NOT (
              LTRIM(RTRIM(r.customer_id)) LIKE 'CUST%' 
              AND LEN(LTRIM(RTRIM(r.customer_id))) = 10 
              AND SUBSTRING(LTRIM(RTRIM(r.customer_id)), 5, 6) NOT LIKE '%[^0-9]%'
          )
      );

    -- GATE 4: restaurant_id format & presence (CSPL - Validate Restaurant Required Fields)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_rating',
        'restaurant_id',
        'INVALID_REQUIRED_FIELD',
        'restaurant_id is null, empty, or invalid format',
        r.restaurant_id,
        SYSUTCDATETIME()
    FROM raw.raw_rating r
    WHERE r.batch_id = @batch_id
      AND (
          r.restaurant_id IS NULL 
          OR LTRIM(RTRIM(r.restaurant_id)) = ''
          OR NOT (
              LTRIM(RTRIM(r.restaurant_id)) LIKE 'REST%' 
              AND LEN(LTRIM(RTRIM(r.restaurant_id))) = 9 
              AND SUBSTRING(LTRIM(RTRIM(r.restaurant_id)), 5, 5) NOT LIKE '%[^0-9]%'
          )
      );

    -- GATE 5: order_id Master Data Lookup (LKP - Order ID against ods.ods_order)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_rating',
        'order_id',
        'MASTER_DATA_NOT_FOUND',
        'order_id value does not exists in reference master',
        r.order_id,
        SYSUTCDATETIME()
    FROM raw.raw_rating r
    WHERE r.batch_id = @batch_id
      AND r.order_id IS NOT NULL 
      AND LTRIM(RTRIM(r.order_id)) <> ''
      AND (
          LTRIM(RTRIM(r.order_id)) LIKE 'ORD%' 
          AND LEN(LTRIM(RTRIM(r.order_id))) = 15 
          AND SUBSTRING(LTRIM(RTRIM(r.order_id)), 4, 12) NOT LIKE '%[^0-9]%'
      )
      AND NOT EXISTS (
          SELECT 1 
          FROM ods.ods_order o 
          WHERE o.order_id = UPPER(LTRIM(RTRIM(r.order_id)))
      );

    -- GATE 6: customer_id Master Data Lookup (LKP - Customer ID against ods.ods_customer)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_rating',
        'customer_id',
        'MASTER_DATA_NOT_FOUND',
        'customer_id value does not exists in reference master',
        r.customer_id,
        SYSUTCDATETIME()
    FROM raw.raw_rating r
    WHERE r.batch_id = @batch_id
      AND r.customer_id IS NOT NULL 
      AND LTRIM(RTRIM(r.customer_id)) <> ''
      AND (
          LTRIM(RTRIM(r.customer_id)) LIKE 'CUST%' 
          AND LEN(LTRIM(RTRIM(r.customer_id))) = 10 
          AND SUBSTRING(LTRIM(RTRIM(r.customer_id)), 5, 6) NOT LIKE '%[^0-9]%'
      )
      AND NOT EXISTS (
          SELECT 1 
          FROM ods.ods_customer c 
          WHERE c.customer_id = UPPER(LTRIM(RTRIM(r.customer_id)))
      );

    -- GATE 7: restaurant_id Master Data Lookup (LKP - Restaurant ID against ods.ods_restaurant)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_rating',
        'restaurant_id',
        'MASTER_DATA_NOT_FOUND',
        'restaurant_id value does not exists in reference master',
        r.restaurant_id,
        SYSUTCDATETIME()
    FROM raw.raw_rating r
    WHERE r.batch_id = @batch_id
      AND r.restaurant_id IS NOT NULL 
      AND LTRIM(RTRIM(r.restaurant_id)) <> ''
      AND (
          LTRIM(RTRIM(r.restaurant_id)) LIKE 'REST%' 
          AND LEN(LTRIM(RTRIM(r.restaurant_id))) = 9 
          AND SUBSTRING(LTRIM(RTRIM(r.restaurant_id)), 5, 5) NOT LIKE '%[^0-9]%'
      )
      AND NOT EXISTS (
          SELECT 1 
          FROM ods.ods_restaurant rest 
          WHERE rest.restaurant_id = UPPER(LTRIM(RTRIM(r.restaurant_id)))
      );

    -- GATE 8: rating format conversion (DC - Convert Rating Format to numeric(3,2))
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_rating',
        'rating',
        'INVALID_FORMAT',
        'rating could not be converted to numeric',
        r.rating,
        SYSUTCDATETIME()
    FROM raw.raw_rating r
    WHERE r.batch_id = @batch_id
      AND (
          r.rating IS NULL 
          OR LTRIM(RTRIM(r.rating)) = ''
          OR TRY_CAST(LTRIM(RTRIM(r.rating)) AS DECIMAL(3,2)) IS NULL
      );

    -- GATE 9: rating range check [1 - 5] (CSPL - Valid Rating Range)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_rating',
        'rating',
        'INVALID_RANGE',
        'rating not in range 1 - 5',
        r.rating,
        SYSUTCDATETIME()
    FROM raw.raw_rating r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(LTRIM(RTRIM(r.rating)) AS DECIMAL(3,2)) IS NOT NULL
      AND (
          TRY_CAST(LTRIM(RTRIM(r.rating)) AS DECIMAL(3,2)) < 1.00
          OR TRY_CAST(LTRIM(RTRIM(r.rating)) AS DECIMAL(3,2)) > 5.00
      );

    -- GATE 10: review_timestamp format conversion (DC - Convert Review Timestamp Format to datetime2)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_rating',
        'review_timestamp',
        'INVALID_FORMAT',
        'review_timestamp could not be converted to datetime',
        r.review_timestamp,
        SYSUTCDATETIME()
    FROM raw.raw_rating r
    WHERE r.batch_id = @batch_id
      AND (
          r.review_timestamp IS NULL 
          OR LTRIM(RTRIM(r.review_timestamp)) = ''
          OR TRY_CAST(LTRIM(RTRIM(r.review_timestamp)) AS DATETIME2) IS NULL
      );

    -- GATE 11: sentiment_score format conversion (DC - Convert Sentiment Score Format to numeric(5,4))
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_rating',
        'sentiment_score',
        'INVALID_FORMAT',
        'sentiment_score could not be converted to numeric',
        r.sentiment_score,
        SYSUTCDATETIME()
    FROM raw.raw_rating r
    WHERE r.batch_id = @batch_id
      AND (
          r.sentiment_score IS NULL 
          OR LTRIM(RTRIM(r.sentiment_score)) = ''
          OR TRY_CAST(LTRIM(RTRIM(r.sentiment_score)) AS DECIMAL(5,4)) IS NULL
      );

    -- GATE 12: sentiment_score range check [-1 - 1] (CSPL - Valid Sentiment Score Range)
    INSERT INTO control.etl_error (
        batch_id, source_file_name, source_row_number, table_name, column_name,
        error_type, error_message, raw_value, error_timestamp
    )
    SELECT 
        r.batch_id,
        r.source_file_name,
        r.source_row_number,
        'raw_rating',
        'sentiment_score',
        'INVALID_RANGE',
        'sentiment_score not in range (-1) - 1',
        r.sentiment_score,
        SYSUTCDATETIME()
    FROM raw.raw_rating r
    WHERE r.batch_id = @batch_id
      AND TRY_CAST(LTRIM(RTRIM(r.sentiment_score)) AS DECIMAL(5,4)) IS NOT NULL
      AND (
          TRY_CAST(LTRIM(RTRIM(r.sentiment_score)) AS DECIMAL(5,4)) < -1.0000
          OR TRY_CAST(LTRIM(RTRIM(r.sentiment_score)) AS DECIMAL(5,4)) > 1.0000
      );

    -- Quarantine Filter: Only load clean records into temp.ods_rating (WITH INTRA-BATCH DEDUPLICATION)
    ;WITH Deduplicated_Rating AS (
        SELECT 
            UPPER(LTRIM(RTRIM(r.rating_id))) AS rating_id,
            UPPER(LTRIM(RTRIM(r.order_id))) AS order_id,
            UPPER(LTRIM(RTRIM(r.customer_id))) AS customer_id,
            UPPER(LTRIM(RTRIM(r.restaurant_id))) AS restaurant_id,
            TRY_CAST(LTRIM(RTRIM(r.rating)) AS DECIMAL(3,2)) AS rating,
            NULLIF(LEFT(LTRIM(RTRIM(r.review_text)), 4000), '') AS review_text,
            TRY_CAST(LTRIM(RTRIM(r.review_timestamp)) AS DATETIME2) AS review_timestamp,
            TRY_CAST(LTRIM(RTRIM(r.sentiment_score)) AS DECIMAL(5,4)) AS sentiment_score,
            r.batch_id,
            r.source_file_name,
            r.source_row_number,
            ROW_NUMBER() OVER (
                PARTITION BY UPPER(LTRIM(RTRIM(r.rating_id)))
                ORDER BY r.source_row_number DESC
            ) AS rn
        FROM raw.raw_rating r
        WHERE r.batch_id = @batch_id
          AND NOT EXISTS (
              SELECT 1 
              FROM control.etl_error err
              WHERE err.batch_id = r.batch_id
                AND err.table_name = 'raw_rating'
                AND err.source_row_number = r.source_row_number
          )
    )
    INSERT INTO temp.ods_rating (
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
        SYSUTCDATETIME()
    FROM Deduplicated_Rating
    WHERE rn = 1;

    EXEC ods.usp_upsert_ods_rating @batch_id = @batch_id;
    EXEC control.usp_end_raw_to_ods_log @step_name = 'LOAD_RATING', @target_table = 'ods_rating', @raw_table = 'raw_rating', @batch_id = @batch_id;

    PRINT CONCAT('>>> [ETL RAW -> ODS] Successfully finished load for BATCH_ID = ', @batch_id);
    END TRY
    BEGIN CATCH
        DECLARE @err_msg NVARCHAR(4000) = ERROR_MESSAGE(),
                @err_num INT = ERROR_NUMBER(),
                @err_proc NVARCHAR(128) = ERROR_PROCEDURE(),
                @err_line INT = ERROR_LINE();

        PRINT '==============================================================================';
        PRINT 'PIPELINE FAILED AT: ' + ISNULL(@err_proc, 'ods.usp_load_raw_to_ods_batch') + ' (Line ' + CAST(@err_line AS VARCHAR) + ')';
        PRINT 'Error: ' + @err_msg;
        PRINT '==============================================================================';

        -- Rollback any pending active transaction
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        DROP TABLE IF EXISTS #Cancelled_Orders;

        -- Update any RUNNING step in control.etl_log to FAILED
        UPDATE control.etl_log
        SET end_time = SYSUTCDATETIME(),
            status   = 'FAILED',
            message  = CONCAT('Failed at ', ISNULL(@err_proc, 'RAW_TO_ODS_PIPELINE'), ' (Line ', @err_line, '): ', @err_msg)
        WHERE batch_id = @batch_id
          AND status = 'RUNNING';

        -- Record the pipeline failure in control.etl_error
        INSERT INTO control.etl_error
        (
            batch_id, table_name, error_type, error_message, error_timestamp
        )
        VALUES
        (
            @batch_id, ISNULL(@err_proc, 'ods.usp_load_raw_to_ods_batch'), CONCAT('SQL_ERROR_', @err_num), @err_msg, SYSUTCDATETIME()
        );

        -- Mark batch as FAILED in control.etl_batch
        IF @batch_id > 0
        BEGIN
            UPDATE control.etl_batch
            SET end_time = SYSUTCDATETIME(),
                status   = 'FAILED'
            WHERE batch_id = @batch_id
              AND status IN ('RUNNING', 'SUCCESS', 'PARTIAL');
        END;

        THROW;
    END CATCH;
END;
GO

