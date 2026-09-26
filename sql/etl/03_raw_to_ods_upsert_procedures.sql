/*
================================================================================
PROJECT : Food Delivery ETL & Data Warehouse
FILE    : 03_raw_to_ods_upsert_procedures.sql
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

    IF @batch_id IS NULL
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM temp.ods_customer;
    END;

    DECLARE @total_temp INT = 0,
            @inserted_count INT = 0,
            @updated_count  INT = 0;

    SELECT @total_temp = COUNT(*) FROM temp.ods_customer;

    IF @total_temp = 0
    BEGIN
        PRINT 'No rows found in temp.ods_customer to merge.';
        RETURN;
    END;

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    BEGIN TRY
        BEGIN TRANSACTION;

        MERGE ods.ods_customer AS target
        USING temp.ods_customer AS source
        ON target.customer_id = source.customer_id
        WHEN MATCHED AND (
            ISNULL(target.signup_date, '1900-01-01')          <> ISNULL(source.signup_date, '1900-01-01')
            OR ISNULL(target.city, '')                        <> ISNULL(source.city, '')
            OR ISNULL(target.acquisition_channel, '')         <> ISNULL(source.acquisition_channel, '')
        )
        THEN UPDATE SET
            target.signup_date         = source.signup_date,
            target.city                = source.city,
            target.acquisition_channel = source.acquisition_channel,
            target.batch_id            = source.batch_id,
            target.source_file_name    = source.source_file_name,
            target.source_row_number   = source.source_row_number,
            target.load_timestamp      = SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
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
            VALUES
            (
                source.customer_id,
                source.signup_date,
                source.city,
                source.acquisition_channel,
                source.batch_id,
                source.source_file_name,
                source.source_row_number,
                SYSUTCDATETIME()
            )
        OUTPUT $action INTO @merge_actions;

        SELECT 
            @inserted_count = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
            @updated_count  = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
        FROM @merge_actions;

        DECLARE @unchanged_count INT = @total_temp - (@inserted_count + @updated_count);

        UPDATE control.etl_log
        SET message = CONCAT('Upsert completed: ', @inserted_count, ' inserted, ', @updated_count, ' updated, ', @unchanged_count, ' unchanged.')
        WHERE step_name = 'LOAD_CUSTOMER'
          AND status = 'RUNNING';

        COMMIT TRANSACTION;

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

    IF @batch_id IS NULL
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM temp.ods_restaurant;
    END;

    DECLARE @total_temp INT = 0,
            @inserted_count INT = 0,
            @updated_count  INT = 0;

    SELECT @total_temp = COUNT(*) FROM temp.ods_restaurant;

    IF @total_temp = 0
    BEGIN
        PRINT 'No rows found in temp.ods_restaurant to merge.';
        RETURN;
    END;

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    BEGIN TRY
        BEGIN TRANSACTION;

        MERGE ods.ods_restaurant AS target
        USING temp.ods_restaurant AS source
        ON target.restaurant_id = source.restaurant_id
        WHEN MATCHED AND (
            ISNULL(target.restaurant_name, '')   <> ISNULL(source.restaurant_name, '')
            OR ISNULL(target.city, '')           <> ISNULL(source.city, '')
            OR ISNULL(target.cuisine_type, '')   <> ISNULL(source.cuisine_type, '')
            OR ISNULL(target.partner_type, '')   <> ISNULL(source.partner_type, '')
            OR ISNULL(target.avg_prep_time_min, '') <> ISNULL(source.avg_prep_time_min, '')
            OR ISNULL(target.is_active, 2)       <> ISNULL(source.is_active, 2)
        )
        THEN UPDATE SET
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
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
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
            VALUES
            (
                source.restaurant_id,
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
            )
        OUTPUT $action INTO @merge_actions;

        SELECT 
            @inserted_count = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
            @updated_count  = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
        FROM @merge_actions;

        DECLARE @unchanged_count INT = @total_temp - (@inserted_count + @updated_count);

        UPDATE control.etl_log
        SET message = CONCAT('Upsert completed: ', @inserted_count, ' inserted, ', @updated_count, ' updated, ', @unchanged_count, ' unchanged.')
        WHERE step_name = 'LOAD_RESTAURANT'
          AND status = 'RUNNING';

        COMMIT TRANSACTION;

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

    IF @batch_id IS NULL
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM temp.ods_menu_item;
    END;

    DECLARE @total_temp INT = 0,
            @inserted_count INT = 0,
            @updated_count  INT = 0;

    SELECT @total_temp = COUNT(*) FROM temp.ods_menu_item;

    IF @total_temp = 0
    BEGIN
        PRINT 'No rows found in temp.ods_menu_item to merge.';
        RETURN;
    END;

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    BEGIN TRY
        BEGIN TRANSACTION;

        MERGE ods.ods_menu_item AS target
        USING temp.ods_menu_item AS source
        ON target.menu_item_id = source.menu_item_id
        WHEN MATCHED AND (
            ISNULL(target.restaurant_id, '')   <> ISNULL(source.restaurant_id, '')
            OR ISNULL(target.item_name, '')    <> ISNULL(source.item_name, '')
            OR ISNULL(target.category, '')     <> ISNULL(source.category, '')
            OR ISNULL(target.is_veg, 2)        <> ISNULL(source.is_veg, 2)
            OR ISNULL(target.price, -1)        <> ISNULL(source.price, -1)
        )
        THEN UPDATE SET
            target.restaurant_id     = source.restaurant_id,
            target.item_name         = source.item_name,
            target.category          = source.category,
            target.is_veg            = source.is_veg,
            target.price             = source.price,
            target.batch_id          = source.batch_id,
            target.source_file_name  = source.source_file_name,
            target.source_row_number = source.source_row_number,
            target.load_timestamp    = SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
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
            VALUES
            (
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
            )
        OUTPUT $action INTO @merge_actions;

        SELECT 
            @inserted_count = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
            @updated_count  = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
        FROM @merge_actions;

        DECLARE @unchanged_count INT = @total_temp - (@inserted_count + @updated_count);

        UPDATE control.etl_log
        SET message = CONCAT('Upsert completed: ', @inserted_count, ' inserted, ', @updated_count, ' updated, ', @unchanged_count, ' unchanged.')
        WHERE step_name = 'LOAD_MENU_ITEM'
          AND status = 'RUNNING';

        COMMIT TRANSACTION;

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

    IF @batch_id IS NULL
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM temp.ods_delivery_partner;
    END;

    DECLARE @total_temp INT = 0,
            @inserted_count INT = 0,
            @updated_count  INT = 0;

    SELECT @total_temp = COUNT(*) FROM temp.ods_delivery_partner;

    IF @total_temp = 0
    BEGIN
        PRINT 'No rows found in temp.ods_delivery_partner to merge.';
        RETURN;
    END;

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    BEGIN TRY
        BEGIN TRANSACTION;

        MERGE ods.ods_delivery_partner AS target
        USING temp.ods_delivery_partner AS source
        ON target.delivery_partner_id = source.delivery_partner_id
        WHEN MATCHED AND (
            ISNULL(target.partner_name, '')       <> ISNULL(source.partner_name, '')
            OR ISNULL(target.city, '')            <> ISNULL(source.city, '')
            OR ISNULL(target.vehicle_type, '')    <> ISNULL(source.vehicle_type, '')
            OR ISNULL(target.employment_type, '') <> ISNULL(source.employment_type, '')
            OR ISNULL(target.avg_rating, -1)      <> ISNULL(source.avg_rating, -1)
            OR ISNULL(target.is_active, 2)        <> ISNULL(source.is_active, 2)
        )
        THEN UPDATE SET
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
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
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
            VALUES
            (
                source.delivery_partner_id,
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
            )
        OUTPUT $action INTO @merge_actions;

        SELECT 
            @inserted_count = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
            @updated_count  = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
        FROM @merge_actions;

        DECLARE @unchanged_count INT = @total_temp - (@inserted_count + @updated_count);

        UPDATE control.etl_log
        SET message = CONCAT('Upsert completed: ', @inserted_count, ' inserted, ', @updated_count, ' updated, ', @unchanged_count, ' unchanged.')
        WHERE step_name = 'LOAD_DELIVERY_PARTNER'
          AND status = 'RUNNING';

        COMMIT TRANSACTION;

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

    IF @batch_id IS NULL
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM temp.ods_order;
    END;

    DECLARE @total_temp INT = 0,
            @inserted_count INT = 0,
            @updated_count  INT = 0;

    SELECT @total_temp = COUNT(*) FROM temp.ods_order;

    IF @total_temp = 0
    BEGIN
        PRINT 'No rows found in temp.ods_order to merge.';
        RETURN;
    END;

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    BEGIN TRY
        BEGIN TRANSACTION;

        MERGE ods.ods_order AS target
        USING temp.ods_order AS source
        ON target.order_id = source.order_id
        WHEN MATCHED AND (
            ISNULL(target.customer_id, '')           <> ISNULL(source.customer_id, '')
            OR ISNULL(target.restaurant_id, '')       <> ISNULL(source.restaurant_id, '')
            OR ISNULL(target.delivery_partner_id, '') <> ISNULL(source.delivery_partner_id, '')
            OR ISNULL(target.order_timestamp, '1900-01-01') <> ISNULL(source.order_timestamp, '1900-01-01')
            OR ISNULL(target.subtotal_amount, -1)     <> ISNULL(source.subtotal_amount, -1)
            OR ISNULL(target.discount_amount, -1)     <> ISNULL(source.discount_amount, -1)
            OR ISNULL(target.delivery_fee, -1)        <> ISNULL(source.delivery_fee, -1)
            OR ISNULL(target.total_amount, -1)        <> ISNULL(source.total_amount, -1)
            OR ISNULL(target.is_cod, 2)               <> ISNULL(source.is_cod, 2)
            OR ISNULL(target.is_cancelled, 2)         <> ISNULL(source.is_cancelled, 2)
        )
        THEN UPDATE SET
            target.customer_id         = source.customer_id,
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
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
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
            VALUES
            (
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
            )
        OUTPUT $action INTO @merge_actions;

        SELECT 
            @inserted_count = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
            @updated_count  = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
        FROM @merge_actions;

        DECLARE @unchanged_count INT = @total_temp - (@inserted_count + @updated_count);

        UPDATE control.etl_log
        SET message = CONCAT('Upsert completed: ', @inserted_count, ' inserted, ', @updated_count, ' updated, ', @unchanged_count, ' unchanged.')
        WHERE step_name = 'LOAD_ORDER'
          AND status = 'RUNNING';

        COMMIT TRANSACTION;

        PRINT CONCAT('ods_order: Total = ', @total_temp, ' | Inserted = ', @inserted_count, ' | Updated = ', @updated_count, ' | Unchanged = ', @unchanged_count);
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

    IF @batch_id IS NULL
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM temp.ods_order_item;
    END;

    DECLARE @total_temp INT = 0,
            @inserted_count INT = 0,
            @updated_count  INT = 0;

    SELECT @total_temp = COUNT(*) FROM temp.ods_order_item;

    IF @total_temp = 0
    BEGIN
        PRINT 'No rows found in temp.ods_order_item to merge.';
        RETURN;
    END;

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    BEGIN TRY
        BEGIN TRANSACTION;

        MERGE ods.ods_order_item AS target
        USING temp.ods_order_item AS source
        ON target.order_line_id = source.order_line_id
        WHEN MATCHED AND (
            ISNULL(target.order_id, '')       <> ISNULL(source.order_id, '')
            OR ISNULL(target.menu_item_id, '') <> ISNULL(source.menu_item_id, '')
            OR ISNULL(target.quantity, -1)     <> ISNULL(source.quantity, -1)
            OR ISNULL(target.unit_price, -1)   <> ISNULL(source.unit_price, -1)
            OR ISNULL(target.item_discount, -1)<> ISNULL(source.item_discount, -1)
            OR ISNULL(target.line_total, -1)   <> ISNULL(source.line_total, -1)
        )
        THEN UPDATE SET
            target.order_id          = source.order_id,
            target.menu_item_id      = source.menu_item_id,
            target.quantity          = source.quantity,
            target.unit_price        = source.unit_price,
            target.item_discount     = source.item_discount,
            target.line_total        = source.line_total,
            target.batch_id          = source.batch_id,
            target.source_file_name  = source.source_file_name,
            target.source_row_number = source.source_row_number,
            target.load_timestamp    = SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
            (
                order_line_id,
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
            VALUES
            (
                source.order_line_id,
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
            )
        OUTPUT $action INTO @merge_actions;

        SELECT 
            @inserted_count = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
            @updated_count  = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
        FROM @merge_actions;

        DECLARE @unchanged_count INT = @total_temp - (@inserted_count + @updated_count);

        UPDATE control.etl_log
        SET message = CONCAT('Upsert completed: ', @inserted_count, ' inserted, ', @updated_count, ' updated, ', @unchanged_count, ' unchanged.')
        WHERE step_name = 'LOAD_ORDER_ITEM'
          AND status = 'RUNNING';

        COMMIT TRANSACTION;

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

    IF @batch_id IS NULL
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM temp.ods_delivery_performance;
    END;

    DECLARE @total_temp INT = 0,
            @inserted_count INT = 0,
            @updated_count  INT = 0;

    SELECT @total_temp = COUNT(*) FROM temp.ods_delivery_performance;

    IF @total_temp = 0
    BEGIN
        PRINT 'No rows found in temp.ods_delivery_performance to merge.';
        RETURN;
    END;

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    BEGIN TRY
        BEGIN TRANSACTION;

        MERGE ods.ods_delivery_performance AS target
        USING temp.ods_delivery_performance AS source
        ON target.delivery_id = source.delivery_id
        WHEN MATCHED AND (
            ISNULL(target.order_id, '')                   <> ISNULL(source.order_id, '')
            OR ISNULL(target.order_item, -1)              <> ISNULL(source.order_item, -1)
            OR ISNULL(target.expected_delivery_time_min, -1) <> ISNULL(source.expected_delivery_time_min, -1)
            OR ISNULL(target.actual_delivery_time_min, -1)   <> ISNULL(source.actual_delivery_time_min, -1)
            OR ISNULL(target.delivery_item, -1)           <> ISNULL(source.delivery_item, -1)
            OR ISNULL(target.distance_km, -1)             <> ISNULL(source.distance_km, -1)
        )
        THEN UPDATE SET
            target.order_id                   = source.order_id,
            target.order_item                 = source.order_item,
            target.expected_delivery_time_min = source.expected_delivery_time_min,
            target.actual_delivery_time_min   = source.actual_delivery_time_min,
            target.delivery_item              = source.delivery_item,
            target.distance_km                = source.distance_km,
            target.batch_id                   = source.batch_id,
            target.source_file_name           = source.source_file_name,
            target.source_row_number          = source.source_row_number,
            target.load_timestamp             = SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
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
            VALUES
            (
                source.delivery_id,
                source.order_id,
                source.order_item,
                source.expected_delivery_time_min,
                source.actual_delivery_time_min,
                source.delivery_item,
                source.distance_km,
                source.batch_id,
                source.source_file_name,
                source.source_row_number,
                SYSUTCDATETIME()
            )
        OUTPUT $action INTO @merge_actions;

        SELECT 
            @inserted_count = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
            @updated_count  = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
        FROM @merge_actions;

        DECLARE @unchanged_count INT = @total_temp - (@inserted_count + @updated_count);

        UPDATE control.etl_log
        SET message = CONCAT('Upsert completed: ', @inserted_count, ' inserted, ', @updated_count, ' updated, ', @unchanged_count, ' unchanged.')
        WHERE step_name = 'LOAD_DELIVERY_PERFORMANCE'
          AND status = 'RUNNING';

        COMMIT TRANSACTION;

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

    IF @batch_id IS NULL
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM temp.ods_rating;
    END;

    DECLARE @total_temp INT = 0,
            @inserted_count INT = 0,
            @updated_count  INT = 0;

    SELECT @total_temp = COUNT(*) FROM temp.ods_rating;

    IF @total_temp = 0
    BEGIN
        PRINT 'No rows found in temp.ods_rating to merge.';
        RETURN;
    END;

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    BEGIN TRY
        BEGIN TRANSACTION;

        MERGE ods.ods_rating AS target
        USING temp.ods_rating AS source
        ON target.rating_id = source.rating_id
        WHEN MATCHED AND (
            ISNULL(target.order_id, '')         <> ISNULL(source.order_id, '')
            OR ISNULL(target.customer_id, '')   <> ISNULL(source.customer_id, '')
            OR ISNULL(target.restaurant_id, '') <> ISNULL(source.restaurant_id, '')
            OR ISNULL(target.rating, -1)        <> ISNULL(source.rating, -1)
            OR ISNULL(target.review_text, '')   <> ISNULL(source.review_text, '')
            OR ISNULL(target.review_timestamp, '1900-01-01') <> ISNULL(source.review_timestamp, '1900-01-01')
            OR ISNULL(target.sentiment_score, -1)<> ISNULL(source.sentiment_score, -1)
        )
        THEN UPDATE SET
            target.order_id          = source.order_id,
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
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
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
            VALUES
            (
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
            )
        OUTPUT $action INTO @merge_actions;

        SELECT 
            @inserted_count = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
            @updated_count  = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
        FROM @merge_actions;

        DECLARE @unchanged_count INT = @total_temp - (@inserted_count + @updated_count);

        UPDATE control.etl_log
        SET message = CONCAT('Upsert completed: ', @inserted_count, ' inserted, ', @updated_count, ' updated, ', @unchanged_count, ' unchanged.')
        WHERE step_name = 'LOAD_RATING'
          AND status = 'RUNNING';

        COMMIT TRANSACTION;

        PRINT CONCAT('ods_rating: Total = ', @total_temp, ' | Inserted = ', @inserted_count, ' | Updated = ', @updated_count, ' | Unchanged = ', @unchanged_count);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
