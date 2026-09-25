/* ==============================================================================
   PROJECT : Food Delivery ETL & Data Warehouse
   FILE    : 02_raw_to_ods_logging_procedures.sql
   PURPOSE : Standardized logging procedures for ETL packages (RAW -> ODS)
   ============================================================================== */

USE FoodDeliveryDW;
GO

/* ==============================================================================
   1. PROCEDURE: control.usp_start_raw_to_ods_log
   PURPOSE  : Ghi nhận bắt đầu thực thi một bước ETL RAW -> ODS (status = 'RUNNING').
   ============================================================================== */
CREATE OR ALTER PROCEDURE control.usp_start_raw_to_ods_log
    @process_name   VARCHAR(100) = 'RAW_TO_ODS',
    @step_name      VARCHAR(200),
    @batch_id       BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Chuẩn hóa UPPER CASE đồng bộ với tầng STG
    SET @process_name = UPPER(LTRIM(RTRIM(@process_name)));
    SET @step_name    = UPPER(LTRIM(RTRIM(@step_name)));

    -- Nếu không truyền batch_id, tự động lấy batch mới nhất từ control.etl_batch
    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT TOP 1 @batch_id = batch_id
        FROM control.etl_batch
        ORDER BY batch_id DESC;

        -- Fallback lấy max batch_id từ raw_delivery_partner nếu control.etl_batch trống
        IF @batch_id IS NULL
        BEGIN
            SELECT @batch_id = MAX(batch_id) FROM raw.raw_delivery_partner;
        END;
    END;

    IF @batch_id IS NULL
    BEGIN
        THROW 50010, 'Cannot determine batch_id for ETL logging.', 1;
    END;

    -- Đóng các log cũ bị treo ở RUNNING (nếu có do phiên trước bị crash)
    UPDATE control.etl_log
    SET status   = 'FAILED',
        end_time = SYSDATETIME(),
        message  = 'Aborted: Superseded by a new execution run.'
    WHERE step_name = @step_name
      AND status    = 'RUNNING';

    -- Ghi nhận log mới
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
   PURPOSE  : Cập nhật kết thúc bước ETL RAW -> ODS (tính toán số dòng, status, end_time).
              Đối soát: rows_rejected = rows_processed (từ RAW) - rows_inserted (vào ODS).
   ============================================================================== */
CREATE OR ALTER PROCEDURE control.usp_end_raw_to_ods_log
    @step_name          VARCHAR(200),
    @target_table       VARCHAR(200) = NULL,   -- Ví dụ: 'ods_delivery_partner'
    @raw_table          VARCHAR(200) = NULL,   -- Ví dụ: 'raw_delivery_partner'
    @error_table_name   VARCHAR(200) = NULL,   -- Tương thích ngược nếu truyền error_table_name
    @batch_id           BIGINT = NULL,
    @status_override    VARCHAR(20) = NULL,    -- Ví dụ: 'FAILED'
    @error_message      VARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Chuẩn hóa UPPER CASE đồng bộ với tầng STG
    SET @step_name = UPPER(LTRIM(RTRIM(@step_name)));

    DECLARE 
        @log_id         BIGINT,
        @cur_batch_id   BIGINT,
        @rows_processed BIGINT = 0,
        @rows_inserted  BIGINT = 0,
        @rows_rejected  BIGINT = 0,
        @final_status   VARCHAR(20),
        @sql            NVARCHAR(MAX);

    -- Tìm log_id mới nhất đang ở trạng thái RUNNING của step_name này
    SELECT TOP 1
        @log_id       = log_id,
        @cur_batch_id = batch_id
    FROM control.etl_log
    WHERE step_name = @step_name
      AND status = 'RUNNING'
    ORDER BY log_id DESC;

    -- Nếu không tìm thấy RUNNING, tìm log_id gần nhất của step_name
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

    -- Ưu tiên batch_id truyền vào nếu có
    IF @batch_id IS NOT NULL AND @batch_id > 0
        SET @cur_batch_id = @batch_id;

    -- Xử lý trường hợp FAILED do hệ thống
    IF @status_override = 'FAILED'
    BEGIN
        UPDATE control.etl_log
        SET end_time = SYSDATETIME(),
            status   = 'FAILED',
            message  = COALESCE(@error_message, 'Task failed during execution.')
        WHERE log_id = @log_id;
        RETURN;
    END;

    -- Nhận diện tên bảng RAW (từ @raw_table hoặc @error_table_name hoặc suy ra từ @target_table)
    IF @raw_table IS NULL AND @error_table_name IS NOT NULL
        SET @raw_table = @error_table_name;

    IF @raw_table IS NULL AND @target_table LIKE 'ods[_]%'
        SET @raw_table = 'raw_' + SUBSTRING(@target_table, 5, LEN(@target_table));

    -- 1. Đếm tổng số dòng nguồn được xử lý từ bảng RAW
    IF @raw_table IS NOT NULL
    BEGIN
        SET @sql = N'SELECT @cnt = COUNT_BIG(*) FROM raw.' + QUOTENAME(@raw_table) + N' WHERE batch_id = @b;';
        EXEC sp_executesql @sql, N'@b BIGINT, @cnt BIGINT OUTPUT', @b = @cur_batch_id, @cnt = @rows_processed OUTPUT;
    END;

    -- 2. Đếm số dòng hợp lệ đã ghi thành công vào bảng ODS
    IF @target_table IS NOT NULL
    BEGIN
        SET @sql = N'SELECT @cnt = COUNT_BIG(*) FROM ods.' + QUOTENAME(@target_table) + N' WHERE batch_id = @b;';
        EXEC sp_executesql @sql, N'@b BIGINT, @cnt BIGINT OUTPUT', @b = @cur_batch_id, @cnt = @rows_inserted OUTPUT;
    END;

    SET @rows_processed = COALESCE(@rows_processed, 0);
    SET @rows_inserted  = COALESCE(@rows_inserted, 0);

    -- 3. Số dòng bị reject = Tổng số dòng RAW - Số dòng thành công ODS
    -- (Đảm bảo chuẩn xác kể cả khi 1 row lỗi bị ghi nhiều lần vào etl_error do vi phạm nhiều rule)
    IF @rows_processed >= @rows_inserted
        SET @rows_rejected = @rows_processed - @rows_inserted;
    ELSE
        SET @rows_rejected = 0;

    -- 4. Xác định trạng thái
    IF @rows_rejected > 0
        SET @final_status = 'PARTIAL';
    ELSE
        SET @final_status = 'SUCCESS';

    -- 5. Cập nhật bảng etl_log
    UPDATE control.etl_log
    SET end_time       = SYSDATETIME(),
        status         = @final_status,
        rows_processed = @rows_processed,
        rows_inserted  = @rows_inserted,
        rows_rejected  = @rows_rejected,
        message        = @error_message
    WHERE log_id = @log_id;
END;
GO
