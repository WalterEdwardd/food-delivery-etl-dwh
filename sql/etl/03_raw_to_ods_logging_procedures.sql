/* ==============================================================================
   PROJECT : Food Delivery ETL & Data Warehouse
   FILE    : 03_raw_to_ods_logging_procedures.sql
   PURPOSE : Standardized logging procedures for ETL packages (RAW -> ODS)
   ============================================================================== */

USE FoodDeliveryDW;
GO

/* ==============================================================================
   1. PROCEDURE: control.usp_start_raw_to_ods_log
   PURPOSE  : Register start of an ETL step execution RAW -> ODS (status = 'RUNNING').
   ============================================================================== */
CREATE OR ALTER PROCEDURE control.usp_start_raw_to_ods_log
    @process_name   VARCHAR(100) = 'RAW_TO_ODS',
    @step_name      VARCHAR(200),
    @batch_id       BIGINT = NULL,
    @table_name     VARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Standardize to uppercase for consistency with STG layer
    SET @process_name = UPPER(LTRIM(RTRIM(@process_name)));
    SET @step_name    = UPPER(LTRIM(RTRIM(@step_name)));

    -- If batch_id is not provided, fetch the latest batch from control.etl_batch
    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT TOP 1 @batch_id = batch_id
        FROM control.etl_batch
        ORDER BY batch_id DESC;

        -- Fallback to max batch_id from raw_delivery_partner if control.etl_batch is empty
        IF @batch_id IS NULL
        BEGIN
            SELECT @batch_id = MAX(batch_id) FROM raw.raw_delivery_partner;
        END;
    END;

    IF @batch_id IS NULL
    BEGIN
        THROW 50010, 'Cannot determine batch_id for ETL logging.', 1;
    END;

    -- Close stale logs stuck in RUNNING state (e.g. from previous crashes)
    UPDATE control.etl_log
    SET status   = 'FAILED',
        end_time = SYSDATETIME(),
        message  = 'Aborted: Superseded by a new execution run.'
    WHERE step_name = @step_name
      AND status    = 'RUNNING';

    -- [IDEMPOTENCY] Clear old error logs for this table and batch upon rerun
    DECLARE @clean_table VARCHAR(200) = @table_name;
    IF @clean_table IS NULL AND @step_name LIKE '%CUSTOMER%' SET @clean_table = 'raw_customer';
    IF @clean_table IS NULL AND @step_name LIKE '%RESTAURANT%' SET @clean_table = 'raw_restaurant';
    IF @clean_table IS NULL AND @step_name LIKE '%MENU_ITEM%' SET @clean_table = 'raw_menu_item';
    IF @clean_table IS NULL AND @step_name LIKE '%DELIVERY_PARTNER%' SET @clean_table = 'raw_delivery_partner';
    IF @clean_table IS NULL AND @step_name LIKE '%ORDER_ITEM%' SET @clean_table = 'raw_order_item';
    IF @clean_table IS NULL AND @step_name LIKE '%ORDER%' SET @clean_table = 'raw_order';
    IF @clean_table IS NULL AND @step_name LIKE '%DELIVERY_PERFORMANCE%' SET @clean_table = 'raw_delivery_performance';
    IF @clean_table IS NULL AND @step_name LIKE '%RATING%' SET @clean_table = 'raw_rating';

    IF @clean_table IS NOT NULL
    BEGIN
        DELETE FROM control.etl_error
        WHERE batch_id = @batch_id
          AND table_name IN (@clean_table, REPLACE(@clean_table, 'raw_', 'ods_'), REPLACE(@clean_table, 'raw_', ''));
    END;

    -- Register new log entry
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
        @process_name,
        @step_name,
        SYSDATETIME(),
        NULL,
        'RUNNING',
        NULL,
        NULL,
        NULL,
        NULL,
        SYSDATETIME()
    );
END;
GO

/* ==============================================================================
   2. PROCEDURE: control.usp_end_raw_to_ods_log
   PURPOSE  : Update completion of an ETL step RAW -> ODS (calculate row counts, status, end_time).
              Reconciliation: rows_rejected = rows_processed (from RAW) - rows_inserted (into ODS).
   ============================================================================== */
CREATE OR ALTER PROCEDURE control.usp_end_raw_to_ods_log
    @step_name          VARCHAR(200),
    @target_table       VARCHAR(200) = NULL,   -- e.g. 'ods_delivery_partner'
    @raw_table          VARCHAR(200) = NULL,   -- e.g. 'raw_delivery_partner'
    @error_table_name   VARCHAR(200) = NULL,   -- Backward compatibility for error_table_name
    @batch_id           BIGINT = NULL,
    @status_override    VARCHAR(20) = NULL,    -- e.g. 'FAILED'
    @error_message      VARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Standardize to uppercase for consistency with STG layer
    SET @step_name = UPPER(LTRIM(RTRIM(@step_name)));

    DECLARE 
        @log_id         BIGINT,
        @cur_batch_id   BIGINT,
        @rows_processed BIGINT = 0,
        @rows_inserted  BIGINT = 0,
        @rows_rejected  BIGINT = 0,
        @final_status   VARCHAR(20),
        @sql            NVARCHAR(MAX);

    -- Find the latest log_id in RUNNING state for this step_name
    SELECT TOP 1
        @log_id       = log_id,
        @cur_batch_id = batch_id
    FROM control.etl_log
    WHERE step_name = @step_name
      AND status = 'RUNNING'
    ORDER BY log_id DESC;

    -- If no RUNNING log is found, search for the most recent log_id
    IF @log_id IS NULL
    BEGIN
        SELECT TOP 1
            @log_id       = log_id,
            @cur_batch_id = batch_id
        FROM control.etl_log
        WHERE step_name = @step_name
        ORDER BY log_id DESC;
    END;

    IF @log_id IS NULL
    BEGIN
        RETURN;
    END;

    -- Prioritize provided batch_id if available
    IF @batch_id IS NOT NULL AND @batch_id > 0
        SET @cur_batch_id = @batch_id;

    -- Handle system failure override
    IF @status_override = 'FAILED'
    BEGIN
        UPDATE control.etl_log
        SET end_time = SYSDATETIME(),
            status   = 'FAILED',
            message  = COALESCE(@error_message, 'Task failed during execution.')
        WHERE log_id = @log_id;
        RETURN;
    END;

    -- Identify RAW table name
    IF @raw_table IS NULL AND @error_table_name IS NOT NULL
        SET @raw_table = @error_table_name;

    IF @raw_table IS NULL AND @target_table LIKE 'ods[_]%'
        SET @raw_table = 'raw_' + SUBSTRING(@target_table, 5, LEN(@target_table));

    -- 1. Count total source rows processed from RAW table
    IF @raw_table IS NOT NULL
    BEGIN
        SET @sql = N'SELECT @cnt = COUNT_BIG(*) FROM raw.' + QUOTENAME(@raw_table) + N' WHERE batch_id = @b;';
        EXEC sp_executesql @sql, N'@b BIGINT, @cnt BIGINT OUTPUT', @b = @cur_batch_id, @cnt = @rows_processed OUTPUT;
    END;

    -- 2. Count valid rows successfully written to ODS table
    -- (Prefer counting from temp.<target_table> if present as it contains clean batch rows)
    IF @target_table IS NOT NULL
    BEGIN
        IF OBJECT_ID('temp.' + QUOTENAME(@target_table), 'U') IS NOT NULL
        BEGIN
            SET @sql = N'SELECT @cnt = COUNT_BIG(*) FROM temp.' + QUOTENAME(@target_table) + N';';
            EXEC sp_executesql @sql, N'@cnt BIGINT OUTPUT', @cnt = @rows_inserted OUTPUT;
        END
        ELSE
        BEGIN
            SET @sql = N'SELECT @cnt = COUNT_BIG(*) FROM ods.' + QUOTENAME(@target_table) + N' WHERE batch_id = @b;';
            EXEC sp_executesql @sql, N'@b BIGINT, @cnt BIGINT OUTPUT', @b = @cur_batch_id, @cnt = @rows_inserted OUTPUT;
        END
    END;

    SET @rows_processed = COALESCE(@rows_processed, 0);
    SET @rows_inserted  = COALESCE(@rows_inserted, 0);

    -- 3. Rejected rows = Total RAW rows - Successful ODS rows
    IF @rows_processed >= @rows_inserted
        SET @rows_rejected = @rows_processed - @rows_inserted;
    ELSE
        SET @rows_rejected = 0;

    -- 4. Determine final status
    IF @rows_rejected > 0
        SET @final_status = 'PARTIAL';
    ELSE
        SET @final_status = 'SUCCESS';

    -- 5. Update etl_log table (preserve detailed message from Upsert step if exists)
    UPDATE control.etl_log
    SET end_time       = SYSDATETIME(),
        status         = @final_status,
        rows_processed = @rows_processed,
        rows_inserted  = @rows_inserted,
        rows_rejected  = @rows_rejected,
        message        = COALESCE(message, @error_message)
    WHERE log_id = @log_id;
END;
GO
