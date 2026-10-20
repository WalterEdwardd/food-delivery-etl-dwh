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
    DECLARE @rows_warning_purged BIGINT = 0;
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

    IF OBJECT_ID('control.etl_warning', 'U') IS NOT NULL
    BEGIN
        SELECT @rows_warning_purged = COUNT(*)
        FROM control.etl_warning w
        WHERE w.batch_id IN (SELECT batch_id FROM @target_batches)
           OR w.warning_timestamp < @cutoff_date;
    END;

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
        PRINT '  - control.etl_error:   ' + CAST(@rows_error_purged AS VARCHAR(20)) + ' rows';
        PRINT '  - control.etl_warning: ' + CAST(@rows_warning_purged AS VARCHAR(20)) + ' rows';
        IF @purge_error_only = 0
        BEGIN
            PRINT '  - control.etl_log:     ' + CAST(@rows_log_purged AS VARCHAR(20)) + ' rows';
            PRINT '  - control.etl_batch:   ' + CAST(@rows_batch_purged AS VARCHAR(20)) + ' rows';
        END;
        PRINT 'No records were deleted (Dry Run mode active).';
        
        SELECT 
            'DRY_RUN' AS execution_mode,
            @retention_days AS retention_days,
            @cutoff_date AS cutoff_date,
            @rows_error_purged AS error_rows_to_purge,
            @rows_warning_purged AS warning_rows_to_purge,
            @rows_log_purged AS log_rows_to_purge,
            @rows_batch_purged AS batch_rows_to_purge,
            DATEDIFF(MILLISECOND, @start_time, SYSUTCDATETIME()) AS elapsed_ms;

        RETURN;
    END;

    -- LIVE PURGE EXECUTION IN TRANSACTION
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Step 1: Delete from child tables (control.etl_error, control.etl_warning)
        DELETE FROM control.etl_error
        WHERE batch_id IN (SELECT batch_id FROM @target_batches)
           OR error_timestamp < @cutoff_date;

        SET @rows_error_purged = @@ROWCOUNT;

        IF OBJECT_ID('control.etl_warning', 'U') IS NOT NULL
        BEGIN
            DELETE FROM control.etl_warning
            WHERE batch_id IN (SELECT batch_id FROM @target_batches)
               OR warning_timestamp < @cutoff_date;

            SET @rows_warning_purged = @@ROWCOUNT;
        END;

        -- Step 2 & 3: Delete from etl_log and etl_batch if @purge_error_only = 0
        IF @purge_error_only = 0
        BEGIN
            -- Step 2: Delete from control.etl_log (Child Table)
            DELETE FROM control.etl_log
            WHERE batch_id IN (SELECT batch_id FROM @target_batches)
               OR start_time < @cutoff_date;

            SET @rows_log_purged = @@ROWCOUNT;

            -- Step 3: Delete from control.etl_batch (Parent Table)
            -- Only delete batches that have no remaining child logs, errors, or warnings
            DELETE FROM control.etl_batch
            WHERE batch_id IN (SELECT batch_id FROM @target_batches)
              AND NOT EXISTS (SELECT 1 FROM control.etl_log l WHERE l.batch_id = control.etl_batch.batch_id)
              AND NOT EXISTS (SELECT 1 FROM control.etl_error e WHERE e.batch_id = control.etl_batch.batch_id)
              AND NOT EXISTS (SELECT 1 FROM control.etl_warning w WHERE w.batch_id = control.etl_batch.batch_id);

            SET @rows_batch_purged = @@ROWCOUNT;
        END;

        COMMIT TRANSACTION;

        PRINT '[SUCCESS] Live purge completed successfully:';
        PRINT '  - control.etl_error purged:   ' + CAST(@rows_error_purged AS VARCHAR(20)) + ' rows';
        PRINT '  - control.etl_warning purged: ' + CAST(@rows_warning_purged AS VARCHAR(20)) + ' rows';
        PRINT '  - control.etl_log purged:     ' + CAST(@rows_log_purged AS VARCHAR(20)) + ' rows';
        PRINT '  - control.etl_batch purged:   ' + CAST(@rows_batch_purged AS VARCHAR(20)) + ' rows';

        SELECT 
            'LIVE_PURGE' AS execution_mode,
            @retention_days AS retention_days,
            @cutoff_date AS cutoff_date,
            @rows_error_purged AS error_rows_purged,
            @rows_warning_purged AS warning_rows_purged,
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
       - Hybrid Architecture:
           1. Rowstore B-Tree Indexes (Dimensions):
              * Fragmentation >= 30%: ALTER INDEX ... REBUILD
              * Fragmentation between 10% and 30%: ALTER INDEX ... REORGANIZE
           2. Clustered Columnstore Indexes (Facts):
              * Deleted rows >= 20% or @force_fact_rebuild = 1: ALTER INDEX ... REBUILD
              * Delta rowgroups or deleted rows > 0: ALTER INDEX ... REORGANIZE WITH (COMPRESS_ALL_ROW_GROUPS = ON)
           3. Statistics Updates:
              * Dimensions: UPDATE STATISTICS ... WITH FULLSCAN
              * Facts: UPDATE STATISTICS ... WITH SAMPLE 20 PERCENT
       - Logs audit details to control.etl_log
   Parameters:
       @rebuild_threshold    FLOAT  = 30.0
       @reorganize_threshold FLOAT  = 10.0
       @update_stats         BIT    = 1
       @force_fact_rebuild   BIT    = 0
       @batch_id             BIGINT = NULL
============================================================================= */
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dwh.usp_maintain_dwh_indexes_and_stats
    @rebuild_threshold    FLOAT  = 30.0,
    @reorganize_threshold FLOAT  = 10.0,
    @update_stats         BIT    = 1,
    @force_fact_rebuild   BIT    = 0,
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

    DECLARE @process_name               VARCHAR(100) = 'DWH_MAINTENANCE',
            @step_name                  VARCHAR(200) = 'INDEX_STATS_MAINTENANCE',
            @start_time                 DATETIME2(3) = SYSUTCDATETIME(),
            @rebuild_count              INT = 0,
            @reorg_count                INT = 0,
            @columnstore_rebuild_count  INT = 0,
            @columnstore_reorg_count    INT = 0,
            @stats_count                INT = 0;

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
        PRINT 'DWH LAYER INDEX AND STATISTICS MAINTENANCE (HYBRID ENGINE)';
        PRINT '==============================================================================';

        DECLARE @sql NVARCHAR(MAX);

        -- 1. Rowstore (B-Tree) Index Maintenance for Dimensions
        PRINT '------------------------------------------------------------------------------';
        PRINT '1. ROWSTORE (B-TREE) INDEX MAINTENANCE (DIMENSIONS)';
        PRINT '------------------------------------------------------------------------------';

        DECLARE @table_name NVARCHAR(128),
                @index_name NVARCHAR(128),
                @avg_frag   FLOAT;

        DECLARE rowstore_cursor CURSOR LOCAL FAST_FORWARD FOR
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
          AND i.type_desc IN ('CLUSTERED', 'NONCLUSTERED')
          AND ps.page_count > 8; -- Only fragment-test indexes spanning more than 8 pages (64KB)

        OPEN rowstore_cursor;
        FETCH NEXT FROM rowstore_cursor INTO @table_name, @index_name, @avg_frag;

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

            FETCH NEXT FROM rowstore_cursor INTO @table_name, @index_name, @avg_frag;
        END;

        CLOSE rowstore_cursor;
        DEALLOCATE rowstore_cursor;

        -- 2. Clustered Columnstore Index (CCI) Maintenance for Facts
        PRINT '------------------------------------------------------------------------------';
        PRINT '2. CLUSTERED COLUMNSTORE INDEX (CCI) MAINTENANCE (FACT TABLES)';
        PRINT '------------------------------------------------------------------------------';

        DECLARE @cs_table_name NVARCHAR(128),
                @cs_index_name NVARCHAR(128),
                @total_rows    BIGINT,
                @deleted_rows  BIGINT,
                @del_pct       FLOAT,
                @delta_rgs     INT;

        DECLARE columnstore_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT 
            t.name AS table_name,
            i.name AS index_name,
            ISNULL(SUM(rg.total_rows), 0) AS total_rows,
            ISNULL(SUM(rg.deleted_rows), 0) AS deleted_rows,
            CASE 
                WHEN ISNULL(SUM(rg.total_rows), 0) > 0 
                THEN CAST(ISNULL(SUM(rg.deleted_rows), 0) AS FLOAT) / SUM(rg.total_rows) * 100.0 
                ELSE 0.0 
            END AS deleted_rows_pct,
            COUNT(CASE WHEN rg.state_desc IN ('OPEN', 'CLOSED') THEN 1 END) AS delta_rowgroups_count
        FROM sys.tables t
        JOIN sys.schemas s ON t.schema_id = s.schema_id
        JOIN sys.indexes i ON t.object_id = i.object_id
        LEFT JOIN sys.dm_db_column_store_row_group_physical_stats rg 
            ON t.object_id = rg.object_id AND i.index_id = rg.index_id
        WHERE s.name = 'dwh'
          AND i.type_desc IN ('CLUSTERED COLUMNSTORE', 'NONCLUSTERED COLUMNSTORE')
        GROUP BY t.name, i.name;

        OPEN columnstore_cursor;
        FETCH NEXT FROM columnstore_cursor INTO @cs_table_name, @cs_index_name, @total_rows, @deleted_rows, @del_pct, @delta_rgs;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF @force_fact_rebuild = 1 OR @del_pct >= 20.0
            BEGIN
                SET @sql = CONCAT('ALTER INDEX [', @cs_index_name, '] ON dwh.[', @cs_table_name, '] REBUILD;');
                EXEC sp_executesql @sql;
                SET @columnstore_rebuild_count += 1;
                PRINT CONCAT('  - COLUMNSTORE REBUILT: [', @cs_table_name, '].[', @cs_index_name, '] (Deleted Rows: ', CAST(ROUND(@del_pct, 2) AS VARCHAR), '%, Total Rows: ', @total_rows, ')');
            END
            ELSE IF @delta_rgs > 0 OR @deleted_rows > 0
            BEGIN
                SET @sql = CONCAT('ALTER INDEX [', @cs_index_name, '] ON dwh.[', @cs_table_name, '] REORGANIZE WITH (COMPRESS_ALL_ROW_GROUPS = ON);');
                EXEC sp_executesql @sql;
                SET @columnstore_reorg_count += 1;
                PRINT CONCAT('  - COLUMNSTORE REORGANIZED: [', @cs_table_name, '].[', @cs_index_name, '] (Compressed Delta RGs: ', @delta_rgs, ', Purged Deleted Rows: ', @deleted_rows, ')');
            END
            ELSE
            BEGIN
                PRINT CONCAT('  - COLUMNSTORE HEALTHY: [', @cs_table_name, '].[', @cs_index_name, ']');
            END;

            FETCH NEXT FROM columnstore_cursor INTO @cs_table_name, @cs_index_name, @total_rows, @deleted_rows, @del_pct, @delta_rgs;
        END;

        CLOSE columnstore_cursor;
        DEALLOCATE columnstore_cursor;

        -- 3. Update Statistics for all DWH tables (Hybrid: FULLSCAN for Dim, SAMPLE 20% for Fact)
        IF @update_stats = 1
        BEGIN
            PRINT '------------------------------------------------------------------------------';
            PRINT '3. UPDATING STATISTICS ON DWH TABLES (HYBRID FULLSCAN / SAMPLE)';
            PRINT '------------------------------------------------------------------------------';

            DECLARE @stats_table_name NVARCHAR(128),
                    @is_fact          BIT;

            DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT t.name,
                   CASE WHEN t.name LIKE 'fact_%' THEN 1 ELSE 0 END AS is_fact
            FROM sys.tables t
            JOIN sys.schemas s ON t.schema_id = s.schema_id
            WHERE s.name = 'dwh';

            OPEN table_cursor;
            FETCH NEXT FROM table_cursor INTO @stats_table_name, @is_fact;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                IF @is_fact = 1
                BEGIN
                    -- Fact tables: Sample 20% to avoid massive I/O while keeping robust distribution histograms
                    SET @sql = CONCAT('UPDATE STATISTICS dwh.[', @stats_table_name, '] WITH SAMPLE 20 PERCENT;');
                    EXEC sp_executesql @sql;
                    PRINT CONCAT('  - UPDATED STATS (SAMPLE 20%): dwh.[', @stats_table_name, ']');
                END
                ELSE
                BEGIN
                    -- Dimension tables: Fullscan for 100% precision on lookup keys and attributes
                    SET @sql = CONCAT('UPDATE STATISTICS dwh.[', @stats_table_name, '] WITH FULLSCAN;');
                    EXEC sp_executesql @sql;
                    PRINT CONCAT('  - UPDATED STATS (FULLSCAN): dwh.[', @stats_table_name, ']');
                END;

                SET @stats_count += 1;
                FETCH NEXT FROM table_cursor INTO @stats_table_name, @is_fact;
            END;

            CLOSE table_cursor;
            DEALLOCATE table_cursor;
        END;

        -- 4. Log Success
        UPDATE control.etl_log
        SET end_time       = SYSUTCDATETIME(),
            status         = 'SUCCESS',
            rows_processed = @stats_count,
            message        = CONCAT('Maintenance Completed: Rowstore Rebuilt=', @rebuild_count, 
                                   ', Rowstore Reorganized=', @reorg_count, 
                                   ', CS Rebuilt=', @columnstore_rebuild_count, 
                                   ', CS Reorganized=', @columnstore_reorg_count, 
                                   ', Stats Updated=', @stats_count)
        WHERE batch_id  = @batch_id
          AND step_name = @step_name
          AND status    = 'RUNNING';

        PRINT '==============================================================================';
        PRINT CONCAT('[SUCCESS] DWH Maintenance Completed: Rowstore Rebuilt=', @rebuild_count, 
                     ', Rowstore Reorg=', @reorg_count, 
                     ', CS Rebuilt=', @columnstore_rebuild_count, 
                     ', CS Reorg=', @columnstore_reorg_count, 
                     ', Stats Updated=', @stats_count);
        PRINT '==============================================================================';

    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'rowstore_cursor') >= 0
        BEGIN
            CLOSE rowstore_cursor;
            DEALLOCATE rowstore_cursor;
        END;
        IF CURSOR_STATUS('local', 'columnstore_cursor') >= 0
        BEGIN
            CLOSE columnstore_cursor;
            DEALLOCATE columnstore_cursor;
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


/* ==============================================================================
   PROCEDURE: temp.usp_purge_stale_temp_ods
   Description:
       Automated self-healing cleanup for intermediate staging tables (schema 'temp').
       Deletes stale/orphaned staging records left behind by interrupted or crashed
       SSIS executions to prevent space bloat and ensure staging cleanliness.
       
       Candidates for purging:
           1. Rows with load_timestamp older than @retention_hours (default: 24h).
           2. Rows belonging to batches already marked COMPLETED, SUCCESS, or FAILED in control.etl_batch.

   Parameters:
       @retention_hours INT = 24  - Age threshold in hours. Default: 24.
       @dry_run         BIT = 0   - If 1, previews record counts without deleting. Default: 0.
============================================================================== */
CREATE OR ALTER PROCEDURE temp.usp_purge_stale_temp_ods
    @retention_hours INT = 24,
    @dry_run         BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @cutoff_time DATETIME2(3) = DATEADD(HOUR, -@retention_hours, SYSUTCDATETIME());
    DECLARE @cust_count INT = 0,
            @rest_count INT = 0,
            @menu_count INT = 0,
            @dp_count   INT = 0,
            @ord_count  INT = 0,
            @oi_count   INT = 0,
            @perf_count INT = 0,
            @rat_count  INT = 0;

    PRINT '==============================================================================';
    PRINT 'STALE STAGING TABLE PURGE & RECOVERY (SCHEMA: temp)';
    PRINT '==============================================================================';
    PRINT 'Cutoff Timestamp (UTC): ' + CONVERT(VARCHAR(30), @cutoff_time, 121);
    PRINT 'Retention Threshold:    ' + CAST(@retention_hours AS VARCHAR(10)) + ' hours';
    PRINT 'Mode:                   ' + CASE WHEN @dry_run = 1 THEN 'DRY RUN (Preview Only)' ELSE 'LIVE PURGE' END;
    PRINT '------------------------------------------------------------------------------';

    -- Identify batches already finished or failed
    DECLARE @finished_batches TABLE (batch_id BIGINT PRIMARY KEY);
    INSERT INTO @finished_batches (batch_id)
    SELECT batch_id
    FROM control.etl_batch
    WHERE status IN ('COMPLETED', 'SUCCESS', 'FAILED');

    IF @dry_run = 1
    BEGIN
        SELECT @cust_count = COUNT(*) FROM temp.ods_customer WHERE load_timestamp < @cutoff_time OR batch_id IN (SELECT batch_id FROM @finished_batches);
        SELECT @rest_count = COUNT(*) FROM temp.ods_restaurant WHERE load_timestamp < @cutoff_time OR batch_id IN (SELECT batch_id FROM @finished_batches);
        SELECT @menu_count = COUNT(*) FROM temp.ods_menu_item WHERE load_timestamp < @cutoff_time OR batch_id IN (SELECT batch_id FROM @finished_batches);
        SELECT @dp_count   = COUNT(*) FROM temp.ods_delivery_partner WHERE load_timestamp < @cutoff_time OR batch_id IN (SELECT batch_id FROM @finished_batches);
        SELECT @ord_count  = COUNT(*) FROM temp.ods_order WHERE load_timestamp < @cutoff_time OR batch_id IN (SELECT batch_id FROM @finished_batches);
        SELECT @oi_count   = COUNT(*) FROM temp.ods_order_item WHERE load_timestamp < @cutoff_time OR batch_id IN (SELECT batch_id FROM @finished_batches);
        SELECT @perf_count = COUNT(*) FROM temp.ods_delivery_performance WHERE load_timestamp < @cutoff_time OR batch_id IN (SELECT batch_id FROM @finished_batches);
        SELECT @rat_count  = COUNT(*) FROM temp.ods_rating WHERE load_timestamp < @cutoff_time OR batch_id IN (SELECT batch_id FROM @finished_batches);

        PRINT CONCAT('[DRY RUN] Stale rows candidate for purge: customer=', @cust_count, ', restaurant=', @rest_count, ', menu_item=', @menu_count, ', delivery_partner=', @dp_count, ', order=', @ord_count, ', order_item=', @oi_count, ', delivery_perf=', @perf_count, ', rating=', @rat_count);
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM temp.ods_customer WHERE load_timestamp < @cutoff_time OR batch_id IN (SELECT batch_id FROM @finished_batches);
        SET @cust_count = @@ROWCOUNT;

        DELETE FROM temp.ods_restaurant WHERE load_timestamp < @cutoff_time OR batch_id IN (SELECT batch_id FROM @finished_batches);
        SET @rest_count = @@ROWCOUNT;

        DELETE FROM temp.ods_menu_item WHERE load_timestamp < @cutoff_time OR batch_id IN (SELECT batch_id FROM @finished_batches);
        SET @menu_count = @@ROWCOUNT;

        DELETE FROM temp.ods_delivery_partner WHERE load_timestamp < @cutoff_time OR batch_id IN (SELECT batch_id FROM @finished_batches);
        SET @dp_count = @@ROWCOUNT;

        DELETE FROM temp.ods_order WHERE load_timestamp < @cutoff_time OR batch_id IN (SELECT batch_id FROM @finished_batches);
        SET @ord_count = @@ROWCOUNT;

        DELETE FROM temp.ods_order_item WHERE load_timestamp < @cutoff_time OR batch_id IN (SELECT batch_id FROM @finished_batches);
        SET @oi_count = @@ROWCOUNT;

        DELETE FROM temp.ods_delivery_performance WHERE load_timestamp < @cutoff_time OR batch_id IN (SELECT batch_id FROM @finished_batches);
        SET @perf_count = @@ROWCOUNT;

        DELETE FROM temp.ods_rating WHERE load_timestamp < @cutoff_time OR batch_id IN (SELECT batch_id FROM @finished_batches);
        SET @rat_count = @@ROWCOUNT;

        COMMIT TRANSACTION;

        PRINT CONCAT('[SUCCESS] Stale staging records purged: customer=', @cust_count, ', restaurant=', @rest_count, ', menu_item=', @menu_count, ', delivery_partner=', @dp_count, ', order=', @ord_count, ', order_item=', @oi_count, ', delivery_perf=', @perf_count, ', rating=', @rat_count);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

PRINT 'Compiled procedure temp.usp_purge_stale_temp_ods successfully.';
GO

