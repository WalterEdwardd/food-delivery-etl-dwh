/* ==============================================================================
   QUICKBITE DATA PLATFORM
   Food Delivery ETL & Data Warehouse

   MAINTENANCE PROCEDURES: LOG PURGE & RETENTION POLICY
   
   Database : FoodDeliveryDW
   Schema   : control
   File     : sql/etl/04_maintenance_procedures.sql
   Purpose  : Automate periodic cleanup of historical ETL audit logs and error
              records to maintain optimal database performance and storage.
============================================================================== */

USE FoodDeliveryDW;
GO

/* ==============================================================================
   PROCEDURE: control.usp_purge_etl_logs
   Description:
       Purges historical records from control.etl_error, control.etl_log,
       and control.etl_batch based on a retention window (default: 30 days).
       
       Maintains strict Foreign Key integrity by deleting child records first:
           1. control.etl_error  (Child of etl_batch)
           2. control.etl_log    (Child of etl_batch)
           3. control.etl_batch  (Parent)

   Parameters:
       @retention_days   INT  - Number of days to retain (records older than this are purged). Default: 30.
       @purge_error_only BIT  - If 1, only purges etl_error records, retaining batch/log metadata. Default: 0.
       @dry_run          BIT  - If 1, previews record counts without deleting anything. Default: 0.
============================================================================== */
CREATE OR ALTER PROCEDURE control.usp_purge_etl_logs
    @retention_days   INT = 30,
    @purge_error_only BIT = 0,
    @dry_run          BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @cutoff_date DATETIME2(3);
    DECLARE @rows_error_purged BIGINT = 0;
    DECLARE @rows_log_purged BIGINT = 0;
    DECLARE @rows_batch_purged BIGINT = 0;
    DECLARE @start_time DATETIME2(3) = SYSUTCDATETIME();

    -- Validate input parameter
    IF @retention_days < 1
    BEGIN
        RAISERROR('Retention days must be at least 1.', 16, 1);
        RETURN;
    END;

    -- Calculate cutoff threshold (UTC)
    SET @cutoff_date = DATEADD(DAY, -@retention_days, SYSUTCDATETIME());

    PRINT '==============================================================================';
    PRINT 'ETL LOG PURGE & RETENTION POLICY EXECUTION';
    PRINT '==============================================================================';
    PRINT 'Cutoff Timestamp (UTC): ' + CONVERT(VARCHAR(30), @cutoff_date, 121);
    PRINT 'Retention Window: ' + CAST(@retention_days AS VARCHAR(10)) + ' days';
    PRINT 'Purge Error Only: ' + CASE WHEN @purge_error_only = 1 THEN 'YES' ELSE 'NO' END;
    PRINT 'Mode: ' + CASE WHEN @dry_run = 1 THEN 'DRY RUN (Preview Only)' ELSE 'LIVE PURGE' END;
    PRINT '------------------------------------------------------------------------------';

    -- Identify target batch IDs to purge
    DECLARE @target_batches TABLE (batch_id BIGINT PRIMARY KEY);

    INSERT INTO @target_batches (batch_id)
    SELECT batch_id
    FROM control.etl_batch
    WHERE start_time < @cutoff_date
      AND status IN ('SUCCESS', 'FAILED', 'PARTIAL');

    -- Calculate candidate rows
    SELECT @rows_error_purged = COUNT(*)
    FROM control.etl_error e
    WHERE e.batch_id IN (SELECT batch_id FROM @target_batches)
       OR e.error_timestamp < @cutoff_date;

    IF @purge_error_only = 0
    BEGIN
        SELECT @rows_log_purged = COUNT(*)
        FROM control.etl_log l
        WHERE l.batch_id IN (SELECT batch_id FROM @target_batches)
           OR l.start_time < @cutoff_date;

        SELECT @rows_batch_purged = COUNT(*)
        FROM @target_batches;
    END;

    -- If DRY RUN mode, report counts and exit cleanly
    IF @dry_run = 1
    BEGIN
        PRINT '[DRY RUN] Identified records eligible for purging:';
        PRINT '  - control.etl_error: ' + CAST(@rows_error_purged AS VARCHAR(20)) + ' rows';
        IF @purge_error_only = 0
        BEGIN
            PRINT '  - control.etl_log:   ' + CAST(@rows_log_purged AS VARCHAR(20)) + ' rows';
            PRINT '  - control.etl_batch: ' + CAST(@rows_batch_purged AS VARCHAR(20)) + ' rows';
        END;
        PRINT 'No records were deleted (Dry Run mode active).';
        
        SELECT 
            'DRY_RUN' AS execution_mode,
            @retention_days AS retention_days,
            @cutoff_date AS cutoff_date,
            @rows_error_purged AS error_rows_to_purge,
            @rows_log_purged AS log_rows_to_purge,
            @rows_batch_purged AS batch_rows_to_purge,
            DATEDIFF(MILLISECOND, @start_time, SYSUTCDATETIME()) AS elapsed_ms;

        RETURN;
    END;

    -- LIVE PURGE EXECUTION IN TRANSACTION
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Step 1: Delete from control.etl_error (Child Table)
        DELETE FROM control.etl_error
        WHERE batch_id IN (SELECT batch_id FROM @target_batches)
           OR error_timestamp < @cutoff_date;

        SET @rows_error_purged = @@ROWCOUNT;

        -- Step 2 & 3: Delete from etl_log and etl_batch if @purge_error_only = 0
        IF @purge_error_only = 0
        BEGIN
            -- Step 2: Delete from control.etl_log (Child Table)
            DELETE FROM control.etl_log
            WHERE batch_id IN (SELECT batch_id FROM @target_batches)
               OR start_time < @cutoff_date;

            SET @rows_log_purged = @@ROWCOUNT;

            -- Step 3: Delete from control.etl_batch (Parent Table)
            -- Only delete batches that have no remaining child logs or errors
            DELETE FROM control.etl_batch
            WHERE batch_id IN (SELECT batch_id FROM @target_batches)
              AND NOT EXISTS (SELECT 1 FROM control.etl_log l WHERE l.batch_id = control.etl_batch.batch_id)
              AND NOT EXISTS (SELECT 1 FROM control.etl_error e WHERE e.batch_id = control.etl_batch.batch_id);

            SET @rows_batch_purged = @@ROWCOUNT;
        END;

        COMMIT TRANSACTION;

        PRINT '[SUCCESS] Live purge completed successfully:';
        PRINT '  - control.etl_error purged: ' + CAST(@rows_error_purged AS VARCHAR(20)) + ' rows';
        PRINT '  - control.etl_log purged:   ' + CAST(@rows_log_purged AS VARCHAR(20)) + ' rows';
        PRINT '  - control.etl_batch purged: ' + CAST(@rows_batch_purged AS VARCHAR(20)) + ' rows';

        SELECT 
            'LIVE_PURGE' AS execution_mode,
            @retention_days AS retention_days,
            @cutoff_date AS cutoff_date,
            @rows_error_purged AS error_rows_purged,
            @rows_log_purged AS log_rows_purged,
            @rows_batch_purged AS batch_rows_purged,
            DATEDIFF(MILLISECOND, @start_time, SYSUTCDATETIME()) AS elapsed_ms;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @err_msg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @err_num INT = ERROR_NUMBER();
        PRINT '[ERROR] Log purge failed: ' + @err_msg;
        RAISERROR('usp_purge_etl_logs failed (Error %d): %s', 16, 1, @err_num, @err_msg);
    END CATCH;
END;
GO

PRINT 'Compiled procedure control.usp_purge_etl_logs successfully.';
GO


/* ==============================================================================
   PROCEDURE: stg.usp_truncate_stg_tables
   Description:
       Truncates all transient staging tables in schema 'stg' to prepare
       for a fresh batch ingestion or reclaim disk space after RAW load.
============================================================================== */
CREATE OR ALTER PROCEDURE stg.usp_truncate_stg_tables
AS
BEGIN
    SET NOCOUNT ON;

    PRINT '==============================================================================';
    PRINT 'TRUNCATING TRANSIENT STAGING TABLES (SCHEMA: stg)';
    PRINT '==============================================================================';

    TRUNCATE TABLE stg.stg_customer;
    TRUNCATE TABLE stg.stg_restaurant;
    TRUNCATE TABLE stg.stg_menu_item;
    TRUNCATE TABLE stg.stg_delivery_partner;
    TRUNCATE TABLE stg.stg_order;
    TRUNCATE TABLE stg.stg_order_item;
    TRUNCATE TABLE stg.stg_delivery_performance;
    TRUNCATE TABLE stg.stg_rating;

    PRINT '[SUCCESS] All 8 staging tables truncated successfully.';
END;
GO

PRINT 'Compiled procedure stg.usp_truncate_stg_tables successfully.';
GO
