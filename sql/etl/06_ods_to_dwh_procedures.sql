/*
================================================================================
PROJECT : Food Delivery ETL & Data Warehouse
FILE    : 06_ods_to_dwh_procedures.sql
PURPOSE : Production Stored Procedures for ODS -> DWH Dimensional ETL
          (Dimensional Modeling, SCD Type 1 Upsert, Surrogate Key Allocation)
================================================================================
ARCHITECTURE
================================================================================
    ods.ods_* (Cleaned, Standardized Operational Data Store)
        ↓
    T-SQL Set-based Stored Procedures (MERGE / Change Detection / Surrogate Keys)
        ↓
    dwh.dim_* & dwh.fact_* (Dimensional Enterprise Data Warehouse)
================================================================================
TABLE OF PROCEDURES:
    1. dwh.usp_seed_dimensions_and_unknowns
    2. dwh.usp_load_dim_customer
================================================================================
*/

USE FoodDeliveryDW;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO


/* ==============================================================================
   1. PROCEDURE: dwh.usp_seed_dimensions_and_unknowns
   PURPOSE  : Idempotent initialization of Date, Time, Reference lookups,
              and Unknown Members (-1) across all dimensions to ensure 
              referential integrity during Fact loads.
============================================================================== */

CREATE OR ALTER PROCEDURE dwh.usp_seed_dimensions_and_unknowns
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    PRINT '>>> [DWH] Initializing Dimensions, References, and Unknown Members...';

    BEGIN TRY
        BEGIN TRANSACTION;

        /* ----------------------------------------------------------------------
           1.1 Seed Reference: dim_rating_type
        ---------------------------------------------------------------------- */
        IF NOT EXISTS (SELECT 1 FROM dwh.dim_rating_type WHERE rating_type_id = 1)
        BEGIN
            INSERT INTO dwh.dim_rating_type (rating_type_id, rating_type, min_score, max_score)
            VALUES
                (0, 'Unknown',   0.00, 0.00),
                (1, 'Excellent', 4.60, 5.00),
                (2, 'Good',      4.00, 4.59),
                (3, 'Average',   3.00, 3.99),
                (4, 'Poor',      2.00, 2.99),
                (5, 'Very Bad',  1.00, 1.99);
            PRINT '    - Seeded dwh.dim_rating_type';
        END;

        /* ----------------------------------------------------------------------
           1.2 Seed Reference: dim_sentiment_type
        ---------------------------------------------------------------------- */
        IF NOT EXISTS (SELECT 1 FROM dwh.dim_sentiment_type WHERE sentiment_type_id = 1)
        BEGIN
            INSERT INTO dwh.dim_sentiment_type (sentiment_type_id, sentiment_type, min_score, max_score)
            VALUES
                (0, 'Unknown',    0.0000, 0.0000),
                (1, 'Positive',   0.2000, 1.0000),
                (2, 'Neutral',   -0.2000, 0.1999),
                (3, 'Negative',  -1.0000, -0.2001);
            PRINT '    - Seeded dwh.dim_sentiment_type';
        END;

        /* ----------------------------------------------------------------------
           1.3 Seed Reference: dim_aspect (6 VoC Dimensions)
        ---------------------------------------------------------------------- */
        IF NOT EXISTS (SELECT 1 FROM dwh.dim_aspect WHERE aspect_id = 1)
        BEGIN
            INSERT INTO dwh.dim_aspect (aspect_id, aspect_name, aspect_description)
            VALUES
                (0, 'Unknown',          'Chưa phân loại'),
                (1, 'Food Quality',     'Chất lượng đồ ăn (ngon, nguội, mặn, tươi...)'),
                (2, 'Delivery Service', 'Dịch vụ giao vận (đúng giờ, trễ, đổ vỡ, sai món...)'),
                (3, 'Customer Support', 'Dịch vụ khách hàng (thái độ nhân viên, hỗ trợ, hoàn tiền...)'),
                (4, 'Packaging',        'Quy cách đóng gói (nguyên vẹn, rách, hở seal, đổ...)'),
                (5, 'Portion & Value',  'Khẩu phần & Giá cả (nhiều, ít, đáng tiền...)'),
                (6, 'Food Safety',      'An toàn vệ sinh (sạch sẽ, ngộ độc, mốc, hỏng...)');
            PRINT '    - Seeded dwh.dim_aspect';
        END;

        /* ----------------------------------------------------------------------
           1.4 Seed Calendar: dim_date (2024 to 2026)
        ---------------------------------------------------------------------- */
        IF NOT EXISTS (SELECT 1 FROM dwh.dim_date WHERE date_key = -1)
        BEGIN
            INSERT INTO dwh.dim_date
            (
                date_key, full_date, year, quarter, quarter_name,
                month, month_name, month_short, year_month, week_of_year,
                day_of_month, day_of_week, day_name, day_short, is_weekend,
                fiscal_year, fiscal_quarter, fiscal_quarter_number, fiscal_month, fiscal_month_number,
                period, period_id
            )
            VALUES
            (
                -1, '1900-01-01', 1900, 0, 'N/A',
                0, 'Unknown', 'UNK', '1900-00', 0,
                0, 0, 'Unknown', 'UNK', 0,
                1900, 'N/A', 0, 'Unknown', 0,
                'Unknown', 0
            );
        END;

        IF (SELECT COUNT(*) FROM dwh.dim_date WHERE date_key <> -1) < 1000
        BEGIN
            DECLARE @StartDate DATE = '2024-01-01';
            DECLARE @EndDate   DATE = '2026-12-31';

            WITH DateSequence AS
            (
                SELECT @StartDate AS CurrentDate
                UNION ALL
                SELECT DATEADD(DAY, 1, CurrentDate)
                FROM DateSequence
                WHERE CurrentDate < @EndDate
            )
            INSERT INTO dwh.dim_date
            (
                date_key, full_date, year, quarter, quarter_name,
                month, month_name, month_short, year_month, week_of_year,
                day_of_month, day_of_week, day_name, day_short, is_weekend,
                fiscal_year, fiscal_quarter, fiscal_quarter_number, fiscal_month, fiscal_month_number,
                period, period_id
            )
            SELECT
                CAST(CONVERT(VARCHAR(8), CurrentDate, 112) AS INT) AS date_key,
                CurrentDate AS full_date,
                YEAR(CurrentDate) AS year,
                DATEPART(QUARTER, CurrentDate) AS quarter,
                'Q' + CAST(DATEPART(QUARTER, CurrentDate) AS VARCHAR(1)) AS quarter_name,
                MONTH(CurrentDate) AS month,
                DATENAME(MONTH, CurrentDate) AS month_name,
                LEFT(DATENAME(MONTH, CurrentDate), 3) AS month_short,
                CONVERT(VARCHAR(7), CurrentDate, 120) AS year_month,
                DATEPART(ISO_WEEK, CurrentDate) AS week_of_year,
                DAY(CurrentDate) AS day_of_month,
                DATEPART(WEEKDAY, CurrentDate) AS day_of_week,
                DATENAME(WEEKDAY, CurrentDate) AS day_name,
                LEFT(DATENAME(WEEKDAY, CurrentDate), 3) AS day_short,
                CASE WHEN DATEPART(WEEKDAY, CurrentDate) IN (1, 7) THEN 1 ELSE 0 END AS is_weekend,
                CASE WHEN MONTH(CurrentDate) >= 4 THEN YEAR(CurrentDate) ELSE YEAR(CurrentDate) - 1 END AS fiscal_year,
                CASE 
                    WHEN MONTH(CurrentDate) BETWEEN 4 AND 6   THEN 'FQ1'
                    WHEN MONTH(CurrentDate) BETWEEN 7 AND 9   THEN 'FQ2'
                    WHEN MONTH(CurrentDate) BETWEEN 10 AND 12 THEN 'FQ3'
                    ELSE 'FQ4'
                END AS fiscal_quarter,
                CASE 
                    WHEN MONTH(CurrentDate) BETWEEN 4 AND 6   THEN 1
                    WHEN MONTH(CurrentDate) BETWEEN 7 AND 9   THEN 2
                    WHEN MONTH(CurrentDate) BETWEEN 10 AND 12 THEN 3
                    ELSE 4
                END AS fiscal_quarter_number,
                DATENAME(MONTH, CurrentDate) AS fiscal_month,
                CASE 
                    WHEN MONTH(CurrentDate) >= 4 THEN MONTH(CurrentDate) - 3
                    ELSE MONTH(CurrentDate) + 9
                END AS fiscal_month_number,
                CASE 
                    WHEN CurrentDate < '2025-06-01' THEN 'Pre-Crisis'
                    WHEN CurrentDate BETWEEN '2025-06-01' AND '2025-07-31' THEN 'Crisis'
                    WHEN CurrentDate BETWEEN '2025-08-01' AND '2025-09-30' THEN 'Recovery'
                    ELSE 'Post-Recovery'
                END AS period,
                CASE 
                    WHEN CurrentDate < '2025-06-01' THEN 1
                    WHEN CurrentDate BETWEEN '2025-06-01' AND '2025-07-31' THEN 2
                    WHEN CurrentDate BETWEEN '2025-08-01' AND '2025-09-30' THEN 3
                    ELSE 4
                END AS period_id
            FROM DateSequence
            WHERE NOT EXISTS (
                SELECT 1 FROM dwh.dim_date WHERE full_date = CurrentDate
            )
            OPTION (MAXRECURSION 2000);

            PRINT '    - Seeded dwh.dim_date (2024 to 2026)';
        END;

        /* ----------------------------------------------------------------------
           1.5 Seed Time: dim_time (1,440 minutes)
        ---------------------------------------------------------------------- */
        IF NOT EXISTS (SELECT 1 FROM dwh.dim_time WHERE time_key = -1)
        BEGIN
            INSERT INTO dwh.dim_time
            (
                time_key, time_value, hour, minute, hour_12, am_pm, time_display,
                time_group, time_group_id, is_peak_hour
            )
            VALUES
            (
                -1, NULL, 0, 0, 0, 'NA', 'Unknown',
                'Unknown', 0, 0
            );
        END;

        IF (SELECT COUNT(*) FROM dwh.dim_time WHERE time_key <> -1) < 1440
        BEGIN
            WITH MinuteSequence AS
            (
                SELECT 0 AS MinuteOfDay
                UNION ALL
                SELECT MinuteOfDay + 1
                FROM MinuteSequence
                WHERE MinuteOfDay < 1439
            )
            INSERT INTO dwh.dim_time
            (
                time_key, time_value, hour, minute, hour_12, am_pm, time_display,
                time_group, time_group_id, is_peak_hour
            )
            SELECT
                (MinuteOfDay / 60) * 100 + (MinuteOfDay % 60) AS time_key,
                TIMEFROMPARTS(MinuteOfDay / 60, MinuteOfDay % 60, 0, 0, 0) AS time_value,
                MinuteOfDay / 60 AS hour,
                MinuteOfDay % 60 AS minute,
                CASE 
                    WHEN (MinuteOfDay / 60) = 0 THEN 12
                    WHEN (MinuteOfDay / 60) > 12 THEN (MinuteOfDay / 60) - 12
                    ELSE (MinuteOfDay / 60)
                END AS hour_12,
                CASE WHEN (MinuteOfDay / 60) >= 12 THEN 'PM' ELSE 'AM' END AS am_pm,
                RIGHT('0' + CAST(
                    CASE 
                        WHEN (MinuteOfDay / 60) = 0 THEN 12
                        WHEN (MinuteOfDay / 60) > 12 THEN (MinuteOfDay / 60) - 12
                        ELSE (MinuteOfDay / 60)
                    END AS VARCHAR(2)), 2) + ':' +
                RIGHT('0' + CAST((MinuteOfDay % 60) AS VARCHAR(2)), 2) + ' ' +
                CASE WHEN (MinuteOfDay / 60) >= 12 THEN 'PM' ELSE 'AM' END AS time_display,
                CASE 
                    WHEN MinuteOfDay / 60 BETWEEN 12 AND 13 THEN '12h-14h'
                    WHEN MinuteOfDay / 60 BETWEEN 14 AND 17 THEN '14h-18h'
                    WHEN MinuteOfDay / 60 = 18              THEN '18h-19h'
                    WHEN MinuteOfDay / 60 BETWEEN 19 AND 21 THEN '19h-22h'
                    WHEN MinuteOfDay / 60 BETWEEN 22 AND 23 THEN '22h-24h'
                    ELSE 'Off-Peak / Morning'
                END AS time_group,
                CASE 
                    WHEN MinuteOfDay / 60 BETWEEN 12 AND 13 THEN 1
                    WHEN MinuteOfDay / 60 BETWEEN 14 AND 17 THEN 2
                    WHEN MinuteOfDay / 60 = 18              THEN 3
                    WHEN MinuteOfDay / 60 BETWEEN 19 AND 21 THEN 4
                    WHEN MinuteOfDay / 60 BETWEEN 22 AND 23 THEN 5
                    ELSE 6
                END AS time_group_id,
                CASE 
                    WHEN MinuteOfDay / 60 BETWEEN 12 AND 13 OR MinuteOfDay / 60 BETWEEN 19 AND 21 THEN 1
                    ELSE 0
                END AS is_peak_hour
            FROM MinuteSequence
            WHERE NOT EXISTS (
                SELECT 1 FROM dwh.dim_time WHERE time_key = (MinuteOfDay / 60) * 100 + (MinuteOfDay % 60)
            )
            OPTION (MAXRECURSION 1500);

            PRINT '    - Seeded dwh.dim_time (1,440 minutes)';
        END;

        /* ----------------------------------------------------------------------
           1.6 Seed Unknown Members (-1) for Entity Dimensions
        ---------------------------------------------------------------------- */
        -- Customer Unknown (-1)
        IF NOT EXISTS (SELECT 1 FROM dwh.dim_customer WHERE customer_key = -1)
        BEGIN
            SET IDENTITY_INSERT dwh.dim_customer ON;
            INSERT INTO dwh.dim_customer (customer_key, customer_id, signup_date, city, acquisition_channel, batch_id)
            VALUES (-1, 'UNKNOWN', '1900-01-01', 'Unknown', 'Unknown', 0);
            SET IDENTITY_INSERT dwh.dim_customer OFF;
            PRINT '    - Seeded dwh.dim_customer Unknown Member (-1)';
        END;

        -- Restaurant Unknown (-1)
        IF NOT EXISTS (SELECT 1 FROM dwh.dim_restaurant WHERE restaurant_key = -1)
        BEGIN
            SET IDENTITY_INSERT dwh.dim_restaurant ON;
            INSERT INTO dwh.dim_restaurant (restaurant_key, restaurant_id, restaurant_name, city, cuisine_type, partner_type, avg_prep_time_min, is_active, batch_id)
            VALUES (-1, 'UNKNOWN', 'Unknown Restaurant', 'Unknown', 'Unknown', 'Unknown', NULL, 0, 0);
            SET IDENTITY_INSERT dwh.dim_restaurant OFF;
            PRINT '    - Seeded dwh.dim_restaurant Unknown Member (-1)';
        END;

        -- Delivery Partner Unknown (-1)
        IF NOT EXISTS (SELECT 1 FROM dwh.dim_delivery_partner WHERE delivery_partner_key = -1)
        BEGIN
            SET IDENTITY_INSERT dwh.dim_delivery_partner ON;
            INSERT INTO dwh.dim_delivery_partner (delivery_partner_key, delivery_partner_id, partner_name, city, vehicle_type, employment_type, avg_rating, is_active, batch_id)
            VALUES (-1, 'UNKNOWN', 'Unknown Driver', 'Unknown', 'Unknown', 'Unknown', NULL, 0, 0);
            SET IDENTITY_INSERT dwh.dim_delivery_partner OFF;
            PRINT '    - Seeded dwh.dim_delivery_partner Unknown Member (-1)';
        END;

        -- Menu Item Unknown (-1)
        IF NOT EXISTS (SELECT 1 FROM dwh.dim_menu_item WHERE menu_item_key = -1)
        BEGIN
            SET IDENTITY_INSERT dwh.dim_menu_item ON;
            INSERT INTO dwh.dim_menu_item (menu_item_key, menu_item_id, restaurant_id, restaurant_key, item_name, category, is_veg, price, batch_id)
            VALUES (-1, 'UNKNOWN', 'UNKNOWN', -1, 'Unknown Item', 'Unknown', NULL, 0.00, 0);
            SET IDENTITY_INSERT dwh.dim_menu_item OFF;
            PRINT '    - Seeded dwh.dim_menu_item Unknown Member (-1)';
        END;

        COMMIT TRANSACTION;
        PRINT '>>> [DWH] All Dimension Seeds and Unknown Members successfully initialized.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        PRINT '*** ERROR in dwh.usp_seed_dimensions_and_unknowns: ' + @ErrorMessage;
        THROW;
    END CATCH;
END;
GO


/* ==============================================================================
   2. PROCEDURE: dwh.usp_load_dim_customer
   PURPOSE  : Incremental Upsert (SCD Type 1) from ods.ods_customer to dwh.dim_customer.
              - Allocates surrogate key (customer_key BIGINT IDENTITY)
              - Updates changed attributes (city, signup_date, acquisition_channel)
              - Logs operation details to control.etl_log
============================================================================== */

CREATE OR ALTER PROCEDURE dwh.usp_load_dim_customer
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 2.1 Determine Active Batch ID
    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM ods.ods_customer;

        IF @batch_id IS NULL
            SELECT @batch_id = 1;
    END;

    DECLARE @process_name   VARCHAR(100) = 'ODS_TO_DWH',
            @step_name      VARCHAR(200) = 'LOAD_DIM_CUSTOMER',
            @start_time     DATETIME2(3) = SYSUTCDATETIME(),
            @rows_read      BIGINT = 0,
            @rows_inserted  BIGINT = 0,
            @rows_updated   BIGINT = 0;

    -- 2.2 Register Start in control.etl_log
    INSERT INTO control.etl_log
    (
        batch_id, process_name, step_name, start_time,
        status, message, created_at
    )
    VALUES
    (
        @batch_id, @process_name, @step_name, @start_time,
        'RUNNING', 'Started loading dim_customer from ODS', SYSUTCDATETIME()
    );

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @rows_read = COUNT(*) FROM ods.ods_customer;

        -- 2.3 Set-based MERGE (SCD Type 1)
        MERGE dwh.dim_customer AS target
        USING ods.ods_customer AS source
        ON target.customer_id = source.customer_id

        -- When changed, update profile and timestamps
        WHEN MATCHED AND (
            ISNULL(target.signup_date, '1900-01-01')      <> ISNULL(source.signup_date, '1900-01-01')
            OR ISNULL(target.city, '')                    <> ISNULL(source.city, '')
            OR ISNULL(target.acquisition_channel, '')     <> ISNULL(source.acquisition_channel, '')
        )
        THEN UPDATE SET
            target.signup_date         = source.signup_date,
            target.city                = source.city,
            target.acquisition_channel = source.acquisition_channel,
            target.batch_id            = source.batch_id,
            target.load_timestamp      = SYSUTCDATETIME()

        -- When new, insert and auto-allocate surrogate key
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
            (
                customer_id,
                signup_date,
                city,
                acquisition_channel,
                batch_id,
                load_timestamp
            )
            VALUES
            (
                source.customer_id,
                source.signup_date,
                source.city,
                source.acquisition_channel,
                source.batch_id,
                SYSUTCDATETIME()
            )
        OUTPUT $action INTO @merge_actions;

        SELECT 
            @rows_inserted = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
            @rows_updated  = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
        FROM @merge_actions;

        COMMIT TRANSACTION;

        -- 2.4 Update Successful Log
        UPDATE control.etl_log
        SET end_time       = SYSUTCDATETIME(),
            status         = 'SUCCESS',
            rows_processed = @rows_read,
            rows_inserted  = @rows_inserted,
            rows_rejected  = 0,
            message        = CONCAT('Successfully processed: Read=', @rows_read, 
                                    ', Inserted=', @rows_inserted, 
                                    ', Updated=', @rows_updated)
        WHERE batch_id   = @batch_id
          AND step_name  = @step_name
          AND status     = 'RUNNING';

        PRINT CONCAT('>>> [DWH] dim_customer load complete: Read=', @rows_read, 
                     ', Inserted=', @rows_inserted, 
                     ', Updated=', @rows_updated);

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        DECLARE @ErrorMsg NVARCHAR(4000) = ERROR_MESSAGE();

        -- Log Failure
        UPDATE control.etl_log
        SET end_time       = SYSUTCDATETIME(),
            status         = 'FAILED',
            rows_processed = @rows_read,
            rows_inserted  = @rows_inserted,
            rows_rejected  = @rows_read - @rows_inserted,
            message        = CONCAT('FAILED: ', @ErrorMsg)
        WHERE batch_id   = @batch_id
          AND step_name  = @step_name
          AND status     = 'RUNNING';

        PRINT '*** [ERROR] dim_customer load failed: ' + @ErrorMsg;
        THROW;
    END CATCH;
END;
GO
