/* ==============================================================================
   QUICKBITE DATA PLATFORM
   Food Delivery ETL & Data Warehouse

   MAINTENANCE PROCEDURES: LOG PURGE & RETENTION POLICY
   
   Database : FoodDeliveryDW
   Schema   : control
   File     : sql/etl/06_maintenance_procedures.sql
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


/* ==============================================================================
   PROCEDURE: dwh.usp_maintain_dwh_indexes_and_stats
   Description:
       Performs automated index maintenance (Reorganize / Rebuild) and
       Statistics updates across all Dimension and Fact tables in schema 'dwh'.
       - Fragmentation >= 30%: ALTER INDEX ... REBUILD
       - Fragmentation between 10% and 30%: ALTER INDEX ... REORGANIZE
       - Update statistics with FULLSCAN on all DWH tables
       - Logs audit details to control.etl_log
   Parameters:
       @rebuild_threshold    FLOAT = 30.0
       @reorganize_threshold FLOAT = 10.0
       @update_stats         BIT   = 1
       @batch_id             BIGINT = NULL
============================================================================== */
CREATE OR ALTER PROCEDURE dwh.usp_maintain_dwh_indexes_and_stats
    @rebuild_threshold    FLOAT = 30.0,
    @reorganize_threshold FLOAT = 10.0,
    @update_stats         BIT   = 1,
    @batch_id             BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM dwh.fact_order;
        IF @batch_id IS NULL SELECT @batch_id = 1;
    END;

    DECLARE @process_name   VARCHAR(100) = 'DWH_MAINTENANCE',
            @step_name      VARCHAR(200) = 'INDEX_STATS_MAINTENANCE',
            @start_time     DATETIME2(3) = SYSUTCDATETIME(),
            @rebuild_count  INT = 0,
            @reorg_count    INT = 0,
            @stats_count    INT = 0;

    INSERT INTO control.etl_log
    (
        batch_id, process_name, step_name, start_time,
        status, message, created_at
    )
    VALUES
    (
        @batch_id, @process_name, @step_name, @start_time,
        'RUNNING', 'Started DWH Index and Statistics maintenance', SYSUTCDATETIME()
    );

    BEGIN TRY
        PRINT '==============================================================================';
        PRINT 'DWH LAYER INDEX AND STATISTICS MAINTENANCE';
        PRINT '==============================================================================';

        -- 1. Index Rebuild / Reorganize based on fragmentation
        DECLARE @table_name NVARCHAR(128),
                @index_name NVARCHAR(128),
                @avg_frag   FLOAT,
                @sql        NVARCHAR(MAX);

        DECLARE index_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT 
            t.name AS table_name,
            i.name AS index_name,
            ps.avg_fragmentation_in_percent
        FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
        JOIN sys.tables t ON ps.object_id = t.object_id
        JOIN sys.schemas s ON t.schema_id = s.schema_id
        JOIN sys.indexes i ON ps.object_id = i.object_id AND ps.index_id = i.index_id
        WHERE s.name = 'dwh'
          AND i.name IS NOT NULL
          AND ps.page_count > 8; -- Only fragment-test indexes spanning more than 8 pages (64KB)

        OPEN index_cursor;
        FETCH NEXT FROM index_cursor INTO @table_name, @index_name, @avg_frag;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF @avg_frag >= @rebuild_threshold
            BEGIN
                SET @sql = CONCAT('ALTER INDEX [', @index_name, '] ON dwh.[', @table_name, '] REBUILD;');
                EXEC sp_executesql @sql;
                SET @rebuild_count += 1;
                PRINT CONCAT('  - REBUILT: [', @table_name, '].[', @index_name, '] (Frag: ', CAST(ROUND(@avg_frag, 2) AS VARCHAR), '%)');
            END
            ELSE IF @avg_frag >= @reorganize_threshold
            BEGIN
                SET @sql = CONCAT('ALTER INDEX [', @index_name, '] ON dwh.[', @table_name, '] REORGANIZE;');
                EXEC sp_executesql @sql;
                SET @reorg_count += 1;
                PRINT CONCAT('  - REORGANIZED: [', @table_name, '].[', @index_name, '] (Frag: ', CAST(ROUND(@avg_frag, 2) AS VARCHAR), '%)');
            END;

            FETCH NEXT FROM index_cursor INTO @table_name, @index_name, @avg_frag;
        END;

        CLOSE index_cursor;
        DEALLOCATE index_cursor;

        -- 2. Update Statistics for all DWH tables
        IF @update_stats = 1
        BEGIN
            PRINT '------------------------------------------------------------------------------';
            PRINT 'UPDATING STATISTICS ON DWH TABLES (WITH FULLSCAN)';
            PRINT '------------------------------------------------------------------------------';

            DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT t.name
            FROM sys.tables t
            JOIN sys.schemas s ON t.schema_id = s.schema_id
            WHERE s.name = 'dwh';

            OPEN table_cursor;
            FETCH NEXT FROM table_cursor INTO @table_name;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @sql = CONCAT('UPDATE STATISTICS dwh.[', @table_name, '] WITH FULLSCAN;');
                EXEC sp_executesql @sql;
                SET @stats_count += 1;
                PRINT CONCAT('  - UPDATED STATS: dwh.[', @table_name, ']');

                FETCH NEXT FROM table_cursor INTO @table_name;
            END;

            CLOSE table_cursor;
            DEALLOCATE table_cursor;
        END;

        -- 3. Log Success
        UPDATE control.etl_log
        SET end_time       = SYSUTCDATETIME(),
            status         = 'SUCCESS',
            rows_processed = @stats_count,
            message        = CONCAT('Maintenance Completed: Rebuilt=', @rebuild_count, 
                                   ', Reorganized=', @reorg_count, 
                                   ', Stats Updated=', @stats_count)
        WHERE batch_id  = @batch_id
          AND step_name = @step_name
          AND status    = 'RUNNING';

        PRINT '==============================================================================';
        PRINT CONCAT('[SUCCESS] DWH Maintenance Completed: Rebuilt=', @rebuild_count, 
                     ', Reorganized=', @reorg_count, ', Stats Updated=', @stats_count);
        PRINT '==============================================================================';

    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'index_cursor') >= 0
        BEGIN
            CLOSE index_cursor;
            DEALLOCATE index_cursor;
        END;
        IF CURSOR_STATUS('local', 'table_cursor') >= 0
        BEGIN
            CLOSE table_cursor;
            DEALLOCATE table_cursor;
        END;

        DECLARE @error_msg NVARCHAR(4000) = ERROR_MESSAGE();

        UPDATE control.etl_log
        SET end_time       = SYSUTCDATETIME(),
            status         = 'FAILED',
            message        = CONCAT('FAILED: ', @error_msg)
        WHERE batch_id  = @batch_id
          AND step_name = @step_name
          AND status    = 'RUNNING';

        PRINT '*** [ERROR] DWH Maintenance failed: ' + @error_msg;
        THROW;
    END CATCH;
END;
GO

PRINT 'Compiled procedure dwh.usp_maintain_dwh_indexes_and_stats successfully.';
GO
