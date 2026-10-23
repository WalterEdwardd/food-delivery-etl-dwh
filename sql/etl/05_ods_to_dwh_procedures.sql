/*
================================================================================
PROJECT : Food Delivery ETL & Data Warehouse
FILE    : 05_ods_to_dwh_procedures.sql
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
    3. dwh.usp_load_dim_delivery_partner
    4. dwh.usp_load_dim_restaurant
    5. dwh.usp_load_dim_menu_item
    6. dwh.usp_load_fact_order
    7. dwh.usp_load_fact_order_item
    8. dwh.usp_load_fact_delivery_performance
    9. dwh.usp_load_fact_rating
    10. dwh.usp_load_fact_review_aspect
    11. dwh.usp_enrich_dimensions_behavioral_metrics
    12. dwh.usp_relink_orphan_facts
    13. dwh.usp_run_ods_to_dwh_pipeline
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
           1.0 Seed Reference: dim_life_cycles
        ---------------------------------------------------------------------- */
        IF NOT EXISTS (SELECT 1 FROM dwh.dim_life_cycles WHERE lc_id = 1)
        BEGIN
            INSERT INTO dwh.dim_life_cycles (lc_id, life_cycle, description)
            VALUES
                (0, 'Unknown',     'Default fallback for entities with no transaction history or unknown state'),
                (1, 'New',         'Entities newly registered or onboarded within the last 30 days'),
                (2, 'Retained',    'Active entities maintaining regular order activities within the last 30 days'),
                (3, 'Reactivated', 'Entities previously inactive (>30 days) that have resumed transactions'),
                (4, 'Churned',     'Entities with no order or transaction activity for more than 30 days');
            PRINT '    - Seeded dwh.dim_life_cycles';
        END;

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
        MERGE dwh.dim_aspect AS target
        USING (
            VALUES
                (0, 'Unknown',          'Unclassified feedback aspect'),
                (1, 'Food Quality',     'Taste, freshness, temperature, cooking quality'),
                (2, 'Delivery Service', 'Rider punctuality, attitude, transit handling, delivery accuracy'),
                (3, 'Customer Support', 'Agent responsiveness, dispute resolution, refund assistance'),
                (4, 'Packaging',        'Container condition, sealing, spill prevention'),
                (5, 'Portion & Value',  'Serving size, quantity sufficiency, value for money'),
                (6, 'Food Safety',      'Hygiene standards, contamination, foreign objects, expiration')
        ) AS source (aspect_id, aspect_name, aspect_description)
        ON target.aspect_id = source.aspect_id
        WHEN MATCHED THEN
            UPDATE SET 
                target.aspect_name = source.aspect_name,
                target.aspect_description = source.aspect_description
        WHEN NOT MATCHED THEN
            INSERT (aspect_id, aspect_name, aspect_description)
            VALUES (source.aspect_id, source.aspect_name, source.aspect_description);

        PRINT '    - Seeded & Synchronized dwh.dim_aspect (100% English)';

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
                -- Standard F&B Dayparts (24-Hour Business Context):
                --   ID 1: '06:00 - 11:00' -> Breakfast & Morning Coffee/Tea (Non-Peak)
                --   ID 2: '11:00 - 14:00' -> Lunch Rush / Lunch Peak (Peak Hour)
                --   ID 3: '14:00 - 17:00' -> Afternoon Snacks & Tea Break (Non-Peak)
                --   ID 4: '17:00 - 21:00' -> Dinner Rush / Dinner Peak (Peak Hour)
                --   ID 5: '21:00 - 24:00' -> Late Evening / Supper / Late Diners (Non-Peak)
                --   ID 6: '00:00 - 06:00' -> Overnight / Midnight to Early Morning (Non-Peak)
                CASE 
                    WHEN MinuteOfDay / 60 BETWEEN 6 AND 10  THEN '06:00 - 11:00'
                    WHEN MinuteOfDay / 60 BETWEEN 11 AND 13 THEN '11:00 - 14:00'
                    WHEN MinuteOfDay / 60 BETWEEN 14 AND 16 THEN '14:00 - 17:00'
                    WHEN MinuteOfDay / 60 BETWEEN 17 AND 20 THEN '17:00 - 21:00'
                    WHEN MinuteOfDay / 60 BETWEEN 21 AND 23 THEN '21:00 - 24:00'
                    ELSE '00:00 - 06:00'
                END AS time_group,
                CASE 
                    WHEN MinuteOfDay / 60 BETWEEN 6 AND 10  THEN 1
                    WHEN MinuteOfDay / 60 BETWEEN 11 AND 13 THEN 2
                    WHEN MinuteOfDay / 60 BETWEEN 14 AND 16 THEN 3
                    WHEN MinuteOfDay / 60 BETWEEN 17 AND 20 THEN 4
                    WHEN MinuteOfDay / 60 BETWEEN 21 AND 23 THEN 5
                    ELSE 6
                END AS time_group_id,
                CASE 
                    WHEN MinuteOfDay / 60 BETWEEN 11 AND 13 OR MinuteOfDay / 60 BETWEEN 17 AND 20 THEN 1
                    ELSE 0
                END AS is_peak_hour
            FROM MinuteSequence
            WHERE NOT EXISTS (
                SELECT 1 FROM dwh.dim_time WHERE time_key = (MinuteOfDay / 60) * 100 + (MinuteOfDay % 60)
            )
            OPTION (MAXRECURSION 1500);

            PRINT '    - Seeded dwh.dim_time (1,440 minutes)';
        END;

        -- Ensure all existing time_groups in dim_time conform to Option A 24-hour F&B Dayparts
        --   ID 1: '06:00 - 11:00' -> Breakfast & Morning Coffee/Tea
        --   ID 2: '11:00 - 14:00' -> Lunch Rush / Lunch Peak (is_peak_hour = 1)
        --   ID 3: '14:00 - 17:00' -> Afternoon Snacks & Tea Break
        --   ID 4: '17:00 - 21:00' -> Dinner Rush / Dinner Peak (is_peak_hour = 1)
        --   ID 5: '21:00 - 24:00' -> Late Evening / Supper
        --   ID 6: '00:00 - 06:00' -> Overnight / Midnight to Early Morning
        UPDATE dwh.dim_time
        SET time_group = CASE 
                            WHEN hour BETWEEN 6 AND 10  THEN '06:00 - 11:00'
                            WHEN hour BETWEEN 11 AND 13 THEN '11:00 - 14:00'
                            WHEN hour BETWEEN 14 AND 16 THEN '14:00 - 17:00'
                            WHEN hour BETWEEN 17 AND 20 THEN '17:00 - 21:00'
                            WHEN hour BETWEEN 21 AND 23 THEN '21:00 - 24:00'
                            ELSE '00:00 - 06:00'
                         END,
            time_group_id = CASE 
                               WHEN hour BETWEEN 6 AND 10  THEN 1
                               WHEN hour BETWEEN 11 AND 13 THEN 2
                               WHEN hour BETWEEN 14 AND 16 THEN 3
                               WHEN hour BETWEEN 17 AND 20 THEN 4
                               WHEN hour BETWEEN 21 AND 23 THEN 5
                               ELSE 6
                            END,
            is_peak_hour = CASE 
                              WHEN hour BETWEEN 11 AND 13 OR hour BETWEEN 17 AND 20 THEN 1
                              ELSE 0
                           END
        WHERE time_key <> -1;

        PRINT '    - Synchronized dwh.dim_time time_group (24-Hour Option A F&B Dayparts)';

        /* ----------------------------------------------------------------------
           1.6 Seed Unknown Members (-1) for Entity Dimensions
        ---------------------------------------------------------------------- */
        -- Customer Unknown (-1)
        IF NOT EXISTS (SELECT 1 FROM dwh.dim_customer WHERE customer_key = -1)
        BEGIN
            SET IDENTITY_INSERT dwh.dim_customer ON;
            INSERT INTO dwh.dim_customer (customer_key, customer_id, signup_date, city, acquisition_channel, last_active, life_cycle_id, valid_from, valid_to, is_current, batch_id)
            VALUES (-1, 'UNKNOWN', '1900-01-01', 'Unknown', 'Unknown', '1900-01-01', 0, '1900-01-01', '9999-12-31', 1, 0);
            SET IDENTITY_INSERT dwh.dim_customer OFF;
            PRINT '    - Seeded dwh.dim_customer Unknown Member (-1)';
        END;

        -- Restaurant Unknown (-1)
        IF NOT EXISTS (SELECT 1 FROM dwh.dim_restaurant WHERE restaurant_key = -1)
        BEGIN
            SET IDENTITY_INSERT dwh.dim_restaurant ON;
            INSERT INTO dwh.dim_restaurant (restaurant_key, restaurant_id, onboard_date, restaurant_name, city, cuisine_type, partner_type, avg_prep_time_min, is_active, min_prep_min, max_prep_min, prep_time_group, prep_time_index, last_active, life_cycle_id, valid_from, valid_to, is_current, batch_id)
            VALUES (-1, 'UNKNOWN', '1900-01-01', 'Unknown Restaurant', 'Unknown', 'Unknown', 'Unknown', 'Unknown', 0, 0, 0, 'Unknown', 0, '1900-01-01', 0, '1900-01-01', '9999-12-31', 1, 0);
            SET IDENTITY_INSERT dwh.dim_restaurant OFF;
            PRINT '    - Seeded dwh.dim_restaurant Unknown Member (-1)';
        END;

        -- Delivery Partner Unknown (-1)
        IF NOT EXISTS (SELECT 1 FROM dwh.dim_delivery_partner WHERE delivery_partner_key = -1)
        BEGIN
            SET IDENTITY_INSERT dwh.dim_delivery_partner ON;
            INSERT INTO dwh.dim_delivery_partner (delivery_partner_key, delivery_partner_id, onboard_date, partner_name, city, vehicle_type, employment_type, avg_rating, is_active, rating_type_id, rating_type, last_active, life_cycle_id, valid_from, valid_to, is_current, batch_id)
            VALUES (-1, 'UNKNOWN', '1900-01-01', 'Unknown Driver', 'Unknown', 'Unknown', 'Unknown', NULL, 0, 0, 'Unknown', '1900-01-01', 0, '1900-01-01', '9999-12-31', 1, 0);
            SET IDENTITY_INSERT dwh.dim_delivery_partner OFF;
            PRINT '    - Seeded dwh.dim_delivery_partner Unknown Member (-1)';
        END;

        -- Menu Item Unknown (-1)
        IF NOT EXISTS (SELECT 1 FROM dwh.dim_menu_item WHERE menu_item_key = -1)
        BEGIN
            SET IDENTITY_INSERT dwh.dim_menu_item ON;
            INSERT INTO dwh.dim_menu_item (menu_item_key, menu_item_id, restaurant_key, item_name, category, is_veg, price, batch_id)
            VALUES (-1, 'UNKNOWN', -1, 'Unknown Item', 'Unknown', NULL, 0.00, 0);
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

        SELECT @rows_read = COUNT(*) FROM ods.ods_customer
        WHERE (@batch_id = -1 OR batch_id = @batch_id);

        -- 2.3 Set-based ETL: Base Profile Load with Semantic Defaults
        DECLARE @max_order_date DATE;
        SELECT @max_order_date = MAX(CAST(order_timestamp AS DATE))
        FROM ods.ods_order
        WHERE order_timestamp IS NOT NULL;

        IF @max_order_date IS NULL
            SET @max_order_date = CAST(SYSUTCDATETIME() AS DATE);

        IF OBJECT_ID('tempdb..#CustomerPrepared') IS NOT NULL DROP TABLE #CustomerPrepared;

        SELECT 
            c.customer_id,
            c.signup_date,
            c.city,
            c.acquisition_channel,
            c.signup_date                                               AS last_active,
            CAST(0 AS TINYINT)                                          AS life_cycle_id,  -- 0: Unknown (chưa phát sinh giao dịch)
            c.batch_id
        INTO #CustomerPrepared
        FROM ods.ods_customer c
        WHERE (@batch_id = -1 OR c.batch_id = @batch_id);

        DECLARE @effective_date DATE;
        SELECT @effective_date = MIN(CAST(order_timestamp AS DATE))
        FROM ods.ods_order
        WHERE (@batch_id = -1 OR batch_id = @batch_id);

        IF @effective_date IS NULL
            SET @effective_date = CAST(SYSUTCDATETIME() AS DATE);

        DECLARE @yesterday DATE = DATEADD(DAY, -1, @effective_date);

        -- Step A: Insert Brand New Customers (never seen before in dim_customer)
        INSERT INTO dwh.dim_customer
        (
            customer_id, signup_date, city, acquisition_channel,
            last_active, life_cycle_id,
            valid_from, valid_to, is_current,
            batch_id, load_timestamp
        )
        SELECT 
            src.customer_id, src.signup_date, src.city, src.acquisition_channel,
            src.last_active, src.life_cycle_id,
            ISNULL(src.signup_date, '1900-01-01'), '9999-12-31', 1,
            src.batch_id, SYSUTCDATETIME()
        FROM #CustomerPrepared src
        WHERE NOT EXISTS (
            SELECT 1 FROM dwh.dim_customer d WHERE d.customer_id = src.customer_id
        );

        SET @rows_inserted = @@ROWCOUNT;

        -- Step B: Handle SCD Type 2 Changes (City changes on existing active record)
        IF OBJECT_ID('tempdb..#Customer_SCD2') IS NOT NULL DROP TABLE #Customer_SCD2;
        SELECT 
            src.customer_id, src.signup_date, src.city, src.acquisition_channel,
            COALESCE(tgt.last_active, src.last_active)                       AS last_active,
            COALESCE(tgt.life_cycle_id, src.life_cycle_id)                   AS life_cycle_id,
            src.batch_id,
            tgt.valid_from                                                   AS tgt_valid_from
        INTO #Customer_SCD2
        FROM #CustomerPrepared src
        INNER JOIN dwh.dim_customer tgt
            ON src.customer_id = tgt.customer_id
           AND tgt.is_current = 1
        WHERE ISNULL(tgt.city, '') <> ISNULL(src.city, '');

        IF EXISTS (SELECT 1 FROM #Customer_SCD2)
        BEGIN
            -- B.0 Log detailed SCD2 field changes
            INSERT INTO control.dim_change_log
            (
                batch_id, dimension_name, business_id,
                surrogate_key_old, surrogate_key_new,
                change_type, column_name, old_value, new_value,
                effective_date, logged_at
            )
            SELECT 
                @batch_id, 'dim_customer', chg.customer_id,
                tgt.customer_key, 
                CASE WHEN chg.tgt_valid_from >= @effective_date THEN tgt.customer_key ELSE NULL END,
                CASE WHEN chg.tgt_valid_from >= @effective_date THEN 'SCD2_SAME_DAY_CORRECTION' ELSE 'SCD2_VERSION' END,
                delta.col_name, delta.old_val, delta.new_val,
                @effective_date, SYSUTCDATETIME()
            FROM #Customer_SCD2 chg
            INNER JOIN dwh.dim_customer tgt
                ON chg.customer_id = tgt.customer_id
               AND tgt.is_current = 1
            CROSS APPLY (
                SELECT 'city' AS col_name, tgt.city AS old_val, chg.city AS new_val
                WHERE ISNULL(tgt.city, '') <> ISNULL(chg.city, '')
            ) delta;

            -- B.1a In-place Overwrite for Same-Day Changes (guardrail against valid_to < valid_from)
            UPDATE tgt
            SET tgt.city                = chg.city,
                tgt.signup_date         = chg.signup_date,
                tgt.acquisition_channel = chg.acquisition_channel,
                tgt.batch_id            = chg.batch_id,
                tgt.load_timestamp      = SYSUTCDATETIME()
            FROM dwh.dim_customer tgt
            INNER JOIN #Customer_SCD2 chg ON tgt.customer_id = chg.customer_id
            WHERE tgt.is_current = 1
              AND chg.tgt_valid_from >= @effective_date;

            SET @rows_updated = @rows_updated + @@ROWCOUNT;

            -- B.1b Expire prior version for Different-Day Changes
            UPDATE tgt
            SET tgt.valid_to       = @yesterday,
                tgt.is_current     = 0,
                tgt.load_timestamp = SYSUTCDATETIME()
            FROM dwh.dim_customer tgt
            INNER JOIN #Customer_SCD2 chg ON tgt.customer_id = chg.customer_id
            WHERE tgt.is_current = 1
              AND chg.tgt_valid_from < @effective_date;

            SET @rows_updated = @rows_updated + @@ROWCOUNT;

            -- B.2 Insert new active version for Different-Day Changes
            INSERT INTO dwh.dim_customer
            (
                customer_id, signup_date, city, acquisition_channel,
                last_active, life_cycle_id,
                valid_from, valid_to, is_current,
                batch_id, load_timestamp
            )
            SELECT 
                chg.customer_id, chg.signup_date, chg.city, chg.acquisition_channel,
                chg.last_active, chg.life_cycle_id,
                @effective_date, '9999-12-31', 1,
                chg.batch_id, SYSUTCDATETIME()
            FROM #Customer_SCD2 chg
            WHERE chg.tgt_valid_from < @effective_date;

            SET @rows_inserted = @rows_inserted + @@ROWCOUNT;

            -- B.3 Update new surrogate key in change log (for new versions only)
            UPDATE l
            SET l.surrogate_key_new = tgt.customer_key
            FROM control.dim_change_log l
            INNER JOIN dwh.dim_customer tgt
                ON l.business_id = tgt.customer_id
               AND tgt.is_current = 1
            WHERE l.batch_id = @batch_id
              AND l.dimension_name = 'dim_customer'
              AND l.surrogate_key_new IS NULL;
        END;

        -- Step C: Handle SCD Type 1 in-place updates (Demographics only; behavioral metrics are enriched post-fact)
        UPDATE tgt
        SET tgt.signup_date            = src.signup_date,
            tgt.acquisition_channel    = src.acquisition_channel,
            tgt.batch_id               = src.batch_id,
            tgt.load_timestamp         = SYSUTCDATETIME()
        FROM dwh.dim_customer tgt
        INNER JOIN #CustomerPrepared src
            ON tgt.customer_id = src.customer_id
           AND tgt.is_current = 1
        WHERE NOT EXISTS (SELECT 1 FROM #Customer_SCD2 scd WHERE scd.customer_id = tgt.customer_id)
          AND (
            ISNULL(tgt.signup_date, '1900-01-01')          <> ISNULL(src.signup_date, '1900-01-01')
            OR ISNULL(tgt.acquisition_channel, '')         <> ISNULL(src.acquisition_channel, '')
          );

        SET @rows_updated = @rows_updated + @@ROWCOUNT;

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


/* ==============================================================================
   3. PROCEDURE: dwh.usp_load_dim_delivery_partner
   PURPOSE  : Incremental Upsert (SCD Type 1) from ods.ods_delivery_partner to dwh.dim_delivery_partner.
              - Allocates surrogate key (delivery_partner_key BIGINT IDENTITY)
              - Updates changed attributes (onboard_date, partner_name, city, vehicle_type, employment_type, avg_rating, is_active)
              - Logs operation details to control.etl_log
============================================================================== */

CREATE OR ALTER PROCEDURE dwh.usp_load_dim_delivery_partner
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 3.1 Determine Active Batch ID
    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM ods.ods_delivery_partner;

        IF @batch_id IS NULL
            SELECT @batch_id = 1;
    END;

    DECLARE @process_name   VARCHAR(100) = 'ODS_TO_DWH',
            @step_name      VARCHAR(200) = 'LOAD_DIM_DELIVERY_PARTNER',
            @start_time     DATETIME2(3) = SYSUTCDATETIME(),
            @rows_read      BIGINT = 0,
            @rows_inserted  BIGINT = 0,
            @rows_updated   BIGINT = 0;

    -- 3.2 Register Start in control.etl_log
    INSERT INTO control.etl_log
    (
        batch_id, process_name, step_name, start_time,
        status, message, created_at
    )
    VALUES
    (
        @batch_id, @process_name, @step_name, @start_time,
        'RUNNING', 'Started loading dim_delivery_partner from ODS', SYSUTCDATETIME()
    );

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @rows_read = COUNT(*) FROM ods.ods_delivery_partner
        WHERE (@batch_id = -1 OR batch_id = @batch_id);

        -- 3.3 Set-based ETL: Base Profile Load with Semantic Defaults
        DECLARE @max_order_date DATE;
        SELECT @max_order_date = MAX(CAST(order_timestamp AS DATE))
        FROM ods.ods_order
        WHERE order_timestamp IS NOT NULL;

        IF @max_order_date IS NULL
            SET @max_order_date = CAST(SYSUTCDATETIME() AS DATE);

        IF OBJECT_ID('tempdb..#DriverPrepared') IS NOT NULL DROP TABLE #DriverPrepared;

        SELECT 
            dp.delivery_partner_id,
            dp.onboard_date,
            dp.partner_name,
            dp.city,
            dp.vehicle_type,
            dp.employment_type,
            dp.avg_rating,
            dp.is_active,
            rt.rating_type_id,
            rt.rating_type,
            -- Behavioral Defaults (to be enriched post-fact by usp_enrich_dimensions_behavioral_metrics)
            dp.onboard_date                                             AS last_active,
            CAST(0 AS TINYINT)                                          AS life_cycle_id,  -- 0: Unknown (chưa phát sinh giao dịch)
            dp.batch_id
        INTO #DriverPrepared
        FROM ods.ods_delivery_partner dp
        LEFT JOIN dwh.dim_rating_type rt 
            ON dp.avg_rating >= rt.min_score 
           AND dp.avg_rating <= rt.max_score 
           AND rt.rating_type_id <> 0
        WHERE (@batch_id = -1 OR dp.batch_id = @batch_id);

        DECLARE @effective_date DATE;
        SELECT @effective_date = MIN(CAST(order_timestamp AS DATE))
        FROM ods.ods_order
        WHERE (@batch_id = -1 OR batch_id = @batch_id);

        IF @effective_date IS NULL
            SET @effective_date = CAST(SYSUTCDATETIME() AS DATE);

        DECLARE @yesterday DATE = DATEADD(DAY, -1, @effective_date);

        -- Step A: Insert Brand New Delivery Partners
        INSERT INTO dwh.dim_delivery_partner
        (
            delivery_partner_id, onboard_date, partner_name, city,
            vehicle_type, employment_type, avg_rating, is_active,
            rating_type_id, rating_type,
            last_active, life_cycle_id,
            valid_from, valid_to, is_current,
            batch_id, load_timestamp
        )
        SELECT 
            src.delivery_partner_id, src.onboard_date, src.partner_name, src.city,
            src.vehicle_type, src.employment_type, src.avg_rating, src.is_active,
            src.rating_type_id, src.rating_type,
            src.last_active, src.life_cycle_id,
            ISNULL(src.onboard_date, '1900-01-01'), '9999-12-31', 1,
            src.batch_id, SYSUTCDATETIME()
        FROM #DriverPrepared src
        WHERE NOT EXISTS (
            SELECT 1 FROM dwh.dim_delivery_partner d WHERE d.delivery_partner_id = src.delivery_partner_id
        );

        SET @rows_inserted = @@ROWCOUNT;

        -- Step B: Handle SCD Type 2 Changes (partner_name, city, vehicle_type, employment_type, is_active)
        IF OBJECT_ID('tempdb..#Driver_SCD2') IS NOT NULL DROP TABLE #Driver_SCD2;
        SELECT 
            src.delivery_partner_id, src.onboard_date, src.partner_name, src.city,
            src.vehicle_type, src.employment_type, src.avg_rating, src.is_active,
            src.rating_type_id, src.rating_type,
            COALESCE(tgt.last_active, src.last_active)                       AS last_active,
            COALESCE(tgt.life_cycle_id, src.life_cycle_id)                   AS life_cycle_id,
            src.batch_id,
            tgt.valid_from                                                   AS tgt_valid_from
        INTO #Driver_SCD2
        FROM #DriverPrepared src
        INNER JOIN dwh.dim_delivery_partner tgt
            ON src.delivery_partner_id = tgt.delivery_partner_id
           AND tgt.is_current = 1
        WHERE ISNULL(tgt.partner_name, '')     <> ISNULL(src.partner_name, '')
           OR ISNULL(tgt.city, '')             <> ISNULL(src.city, '')
           OR ISNULL(tgt.vehicle_type, '')     <> ISNULL(src.vehicle_type, '')
           OR ISNULL(tgt.employment_type, '')  <> ISNULL(src.employment_type, '')
           OR ISNULL(tgt.is_active, 2)         <> ISNULL(src.is_active, 2);

        IF EXISTS (SELECT 1 FROM #Driver_SCD2)
        BEGIN
            -- B.0 Log detailed SCD2 field changes
            INSERT INTO control.dim_change_log
            (
                batch_id, dimension_name, business_id,
                surrogate_key_old, surrogate_key_new,
                change_type, column_name, old_value, new_value,
                effective_date, logged_at
            )
            SELECT 
                @batch_id, 'dim_delivery_partner', chg.delivery_partner_id,
                tgt.delivery_partner_key, 
                CASE WHEN chg.tgt_valid_from >= @effective_date THEN tgt.delivery_partner_key ELSE NULL END,
                CASE WHEN chg.tgt_valid_from >= @effective_date THEN 'SCD2_SAME_DAY_CORRECTION' ELSE 'SCD2_VERSION' END,
                delta.col_name, delta.old_val, delta.new_val,
                @effective_date, SYSUTCDATETIME()
            FROM #Driver_SCD2 chg
            INNER JOIN dwh.dim_delivery_partner tgt
                ON chg.delivery_partner_id = tgt.delivery_partner_id
               AND tgt.is_current = 1
            CROSS APPLY (
                SELECT 'partner_name' AS col_name, tgt.partner_name AS old_val, chg.partner_name AS new_val
                WHERE ISNULL(tgt.partner_name, '')     <> ISNULL(chg.partner_name, '')
                UNION ALL
                SELECT 'city', tgt.city, chg.city
                WHERE ISNULL(tgt.city, '')             <> ISNULL(chg.city, '')
                UNION ALL
                SELECT 'vehicle_type', tgt.vehicle_type, chg.vehicle_type
                WHERE ISNULL(tgt.vehicle_type, '')     <> ISNULL(chg.vehicle_type, '')
                UNION ALL
                SELECT 'employment_type', tgt.employment_type, chg.employment_type
                WHERE ISNULL(tgt.employment_type, '')  <> ISNULL(chg.employment_type, '')
                UNION ALL
                SELECT 'is_active', CAST(tgt.is_active AS VARCHAR(10)), CAST(chg.is_active AS VARCHAR(10))
                WHERE ISNULL(tgt.is_active, 2)         <> ISNULL(chg.is_active, 2)
            ) delta;

            -- B.1a In-place Overwrite for Same-Day Changes (guardrail against valid_to < valid_from)
            UPDATE tgt
            SET tgt.partner_name       = chg.partner_name,
                tgt.city               = chg.city,
                tgt.vehicle_type       = chg.vehicle_type,
                tgt.employment_type    = chg.employment_type,
                tgt.is_active          = chg.is_active,
                tgt.onboard_date       = chg.onboard_date,
                tgt.avg_rating         = chg.avg_rating,
                tgt.rating_type_id     = chg.rating_type_id,
                tgt.rating_type        = chg.rating_type,
                tgt.batch_id           = chg.batch_id,
                tgt.load_timestamp     = SYSUTCDATETIME()
            FROM dwh.dim_delivery_partner tgt
            INNER JOIN #Driver_SCD2 chg ON tgt.delivery_partner_id = chg.delivery_partner_id
            WHERE tgt.is_current = 1
              AND chg.tgt_valid_from >= @effective_date;

            SET @rows_updated = @rows_updated + @@ROWCOUNT;

            -- B.1b Expire prior version for Different-Day Changes
            UPDATE tgt
            SET tgt.valid_to       = @yesterday,
                tgt.is_current     = 0,
                tgt.load_timestamp = SYSUTCDATETIME()
            FROM dwh.dim_delivery_partner tgt
            INNER JOIN #Driver_SCD2 chg ON tgt.delivery_partner_id = chg.delivery_partner_id
            WHERE tgt.is_current = 1
              AND chg.tgt_valid_from < @effective_date;

            SET @rows_updated = @rows_updated + @@ROWCOUNT;

            -- B.2 Insert new active version for Different-Day Changes
            INSERT INTO dwh.dim_delivery_partner
            (
                delivery_partner_id, onboard_date, partner_name, city,
                vehicle_type, employment_type, avg_rating, is_active,
                rating_type_id, rating_type,
                last_active, life_cycle_id,
                valid_from, valid_to, is_current,
                batch_id, load_timestamp
            )
            SELECT 
                chg.delivery_partner_id, chg.onboard_date, chg.partner_name, chg.city,
                chg.vehicle_type, chg.employment_type, chg.avg_rating, chg.is_active,
                chg.rating_type_id, chg.rating_type,
                chg.last_active, chg.life_cycle_id,
                @effective_date, '9999-12-31', 1,
                chg.batch_id, SYSUTCDATETIME()
            FROM #Driver_SCD2 chg
            WHERE chg.tgt_valid_from < @effective_date;

            SET @rows_inserted = @rows_inserted + @@ROWCOUNT;

            -- B.3 Update new surrogate key in change log (for new versions only)
            UPDATE l
            SET l.surrogate_key_new = tgt.delivery_partner_key
            FROM control.dim_change_log l
            INNER JOIN dwh.dim_delivery_partner tgt
                ON l.business_id = tgt.delivery_partner_id
               AND tgt.is_current = 1
            WHERE l.batch_id = @batch_id
              AND l.dimension_name = 'dim_delivery_partner'
              AND l.surrogate_key_new IS NULL;
        END;

        -- Step C: Handle SCD Type 1 in-place updates (Demographics/Ratings only; behavioral metrics are enriched post-fact)
        UPDATE tgt
        SET tgt.onboard_date           = src.onboard_date,
            tgt.avg_rating             = src.avg_rating,
            tgt.rating_type_id         = src.rating_type_id,
            tgt.rating_type            = src.rating_type,
            tgt.batch_id               = src.batch_id,
            tgt.load_timestamp         = SYSUTCDATETIME()
        FROM dwh.dim_delivery_partner tgt
        INNER JOIN #DriverPrepared src
            ON tgt.delivery_partner_id = src.delivery_partner_id
           AND tgt.is_current = 1
        WHERE NOT EXISTS (SELECT 1 FROM #Driver_SCD2 scd WHERE scd.delivery_partner_id = tgt.delivery_partner_id)
          AND (
            ISNULL(tgt.onboard_date, '1900-01-01')          <> ISNULL(src.onboard_date, '1900-01-01')
            OR ISNULL(tgt.avg_rating, -1)                   <> ISNULL(src.avg_rating, -1)
            OR ISNULL(tgt.rating_type_id, 255)              <> ISNULL(src.rating_type_id, 255)
            OR ISNULL(tgt.rating_type, '')                  <> ISNULL(src.rating_type, '')
          );

        SET @rows_updated = @rows_updated + @@ROWCOUNT;

        COMMIT TRANSACTION;

        -- 3.4 Update Successful Log
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

        PRINT CONCAT('>>> [DWH] dim_delivery_partner load complete: Read=', @rows_read, 
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

        PRINT '*** [ERROR] dim_delivery_partner load failed: ' + @ErrorMsg;
        THROW;
    END CATCH;
END;
GO


/* ==============================================================================
   4. PROCEDURE: dwh.usp_load_dim_restaurant
   PURPOSE  : Incremental Upsert (SCD Type 1) from ods.ods_restaurant to dwh.dim_restaurant.
              - Allocates surrogate key (restaurant_key BIGINT IDENTITY)
              - Updates changed attributes (onboard_date, restaurant_name, city, cuisine_type, partner_type, avg_prep_time_min, is_active)
              - Logs operation details to control.etl_log
============================================================================== */

CREATE OR ALTER PROCEDURE dwh.usp_load_dim_restaurant
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 4.1 Determine Active Batch ID
    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM ods.ods_restaurant;

        IF @batch_id IS NULL
            SELECT @batch_id = 1;
    END;

    DECLARE @process_name   VARCHAR(100) = 'ODS_TO_DWH',
            @step_name      VARCHAR(200) = 'LOAD_DIM_RESTAURANT',
            @start_time     DATETIME2(3) = SYSUTCDATETIME(),
            @rows_read      BIGINT = 0,
            @rows_inserted  BIGINT = 0,
            @rows_updated   BIGINT = 0;

    -- 4.2 Register Start in control.etl_log
    INSERT INTO control.etl_log
    (
        batch_id, process_name, step_name, start_time,
        status, message, created_at
    )
    VALUES
    (
        @batch_id, @process_name, @step_name, @start_time,
        'RUNNING', 'Started loading dim_restaurant from ODS', SYSUTCDATETIME()
    );

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @rows_read = COUNT(*) FROM ods.ods_restaurant
        WHERE (@batch_id = -1 OR batch_id = @batch_id);


        -- 4.3 Set-based ETL: Base Profile Load with Semantic Defaults
        DECLARE @max_order_date DATE;
        SELECT @max_order_date = MAX(CAST(order_timestamp AS DATE))
        FROM ods.ods_order
        WHERE order_timestamp IS NOT NULL;

        IF @max_order_date IS NULL
            SET @max_order_date = CAST(SYSUTCDATETIME() AS DATE);

        IF OBJECT_ID('tempdb..#RestPrepared') IS NOT NULL DROP TABLE #RestPrepared;

        SELECT 
            r.restaurant_id,
            r.onboard_date,
            r.restaurant_name,
            r.city,
            r.cuisine_type,
            r.partner_type,
            r.avg_prep_time_min,
            r.is_active,
            -- Prep time attributes (static profile derivation)
            CASE 
                WHEN r.avg_prep_time_min = '<=15' THEN 0
                WHEN r.avg_prep_time_min = '16-25' THEN 16
                WHEN r.avg_prep_time_min = '26-40' THEN 26
                WHEN r.avg_prep_time_min = '>40'  THEN 41
            END AS min_prep_min,
            CASE 
                WHEN r.avg_prep_time_min = '<=15' THEN 15
                WHEN r.avg_prep_time_min = '16-25' THEN 25
                WHEN r.avg_prep_time_min = '26-40' THEN 40
                WHEN r.avg_prep_time_min = '>40'  THEN 60
            END AS max_prep_min,
            CASE 
                WHEN r.avg_prep_time_min = '<=15' THEN 'Fast'
                WHEN r.avg_prep_time_min = '16-25' THEN 'Moderate'
                WHEN r.avg_prep_time_min = '26-40' THEN 'Slow'
                WHEN r.avg_prep_time_min = '>40'  THEN 'Very Slow'
            END AS prep_time_group,
            CASE 
                WHEN r.avg_prep_time_min = '<=15' THEN 1
                WHEN r.avg_prep_time_min = '16-25' THEN 2
                WHEN r.avg_prep_time_min = '26-40' THEN 3
                WHEN r.avg_prep_time_min = '>40'  THEN 4
            END AS prep_time_index,
            -- Behavioral Defaults (to be enriched post-fact by usp_enrich_dimensions_behavioral_metrics)
            r.onboard_date                                              AS last_active,
            CAST(0 AS TINYINT)                                          AS life_cycle_id,  -- 0: Unknown (chưa phát sinh giao dịch)
            r.batch_id
        INTO #RestPrepared
        FROM ods.ods_restaurant r
        WHERE (@batch_id = -1 OR r.batch_id = @batch_id);

        DECLARE @effective_date DATE;
        SELECT @effective_date = MIN(CAST(order_timestamp AS DATE))
        FROM ods.ods_order
        WHERE (@batch_id = -1 OR batch_id = @batch_id);

        IF @effective_date IS NULL
            SET @effective_date = CAST(SYSUTCDATETIME() AS DATE);

        DECLARE @yesterday DATE = DATEADD(DAY, -1, @effective_date);

        -- Step A: Insert Brand New Restaurants
        INSERT INTO dwh.dim_restaurant
        (
            restaurant_id, onboard_date, restaurant_name, city,
            cuisine_type, partner_type, avg_prep_time_min, is_active,
            min_prep_min, max_prep_min, prep_time_group, prep_time_index,
            last_active, life_cycle_id,
            valid_from, valid_to, is_current,
            batch_id, load_timestamp
        )
        SELECT 
            src.restaurant_id, src.onboard_date, src.restaurant_name, src.city,
            src.cuisine_type, src.partner_type, src.avg_prep_time_min, src.is_active,
            src.min_prep_min, src.max_prep_min, src.prep_time_group, src.prep_time_index,
            src.last_active, src.life_cycle_id,
            ISNULL(src.onboard_date, '1900-01-01'), '9999-12-31', 1,
            src.batch_id, SYSUTCDATETIME()
        FROM #RestPrepared src
        WHERE NOT EXISTS (
            SELECT 1 FROM dwh.dim_restaurant d WHERE d.restaurant_id = src.restaurant_id
        );

        SET @rows_inserted = @@ROWCOUNT;

        -- Step B: Handle SCD Type 2 Changes (restaurant_name, city, cuisine_type, partner_type, is_active)
        IF OBJECT_ID('tempdb..#Rest_SCD2') IS NOT NULL DROP TABLE #Rest_SCD2;
        SELECT 
            src.restaurant_id, src.onboard_date, src.restaurant_name, src.city,
            src.cuisine_type, src.partner_type, src.avg_prep_time_min, src.is_active,
            src.min_prep_min, src.max_prep_min, src.prep_time_group, src.prep_time_index,
            COALESCE(tgt.last_active, src.last_active)                       AS last_active,
            COALESCE(tgt.life_cycle_id, src.life_cycle_id)                   AS life_cycle_id,
            src.batch_id,
            tgt.valid_from                                                   AS tgt_valid_from
        INTO #Rest_SCD2
        FROM #RestPrepared src
        INNER JOIN dwh.dim_restaurant tgt
            ON src.restaurant_id = tgt.restaurant_id
           AND tgt.is_current = 1
        WHERE ISNULL(tgt.restaurant_name, '') <> ISNULL(src.restaurant_name, '')
           OR ISNULL(tgt.city, '')            <> ISNULL(src.city, '')
           OR ISNULL(tgt.cuisine_type, '')    <> ISNULL(src.cuisine_type, '')
           OR ISNULL(tgt.partner_type, '')    <> ISNULL(src.partner_type, '')
           OR ISNULL(tgt.is_active, 2)        <> ISNULL(src.is_active, 2);

        IF EXISTS (SELECT 1 FROM #Rest_SCD2)
        BEGIN
            -- B.0 Log detailed SCD2 field changes
            INSERT INTO control.dim_change_log
            (
                batch_id, dimension_name, business_id,
                surrogate_key_old, surrogate_key_new,
                change_type, column_name, old_value, new_value,
                effective_date, logged_at
            )
            SELECT 
                @batch_id, 'dim_restaurant', chg.restaurant_id,
                tgt.restaurant_key, 
                CASE WHEN chg.tgt_valid_from >= @effective_date THEN tgt.restaurant_key ELSE NULL END,
                CASE WHEN chg.tgt_valid_from >= @effective_date THEN 'SCD2_SAME_DAY_CORRECTION' ELSE 'SCD2_VERSION' END,
                delta.col_name, delta.old_val, delta.new_val,
                @effective_date, SYSUTCDATETIME()
            FROM #Rest_SCD2 chg
            INNER JOIN dwh.dim_restaurant tgt
                ON chg.restaurant_id = tgt.restaurant_id
               AND tgt.is_current = 1
            CROSS APPLY (
                SELECT 'restaurant_name' AS col_name, tgt.restaurant_name AS old_val, chg.restaurant_name AS new_val
                WHERE ISNULL(tgt.restaurant_name, '') <> ISNULL(chg.restaurant_name, '')
                UNION ALL
                SELECT 'city', tgt.city, chg.city
                WHERE ISNULL(tgt.city, '')            <> ISNULL(chg.city, '')
                UNION ALL
                SELECT 'cuisine_type', tgt.cuisine_type, chg.cuisine_type
                WHERE ISNULL(tgt.cuisine_type, '')    <> ISNULL(chg.cuisine_type, '')
                UNION ALL
                SELECT 'partner_type', tgt.partner_type, chg.partner_type
                WHERE ISNULL(tgt.partner_type, '')    <> ISNULL(chg.partner_type, '')
                UNION ALL
                SELECT 'is_active', CAST(tgt.is_active AS VARCHAR(10)), CAST(chg.is_active AS VARCHAR(10))
                WHERE ISNULL(tgt.is_active, 2)        <> ISNULL(chg.is_active, 2)
            ) delta;

            -- B.1a In-place Overwrite for Same-Day Changes (guardrail against valid_to < valid_from)
            UPDATE tgt
            SET tgt.restaurant_name    = chg.restaurant_name,
                tgt.city               = chg.city,
                tgt.cuisine_type       = chg.cuisine_type,
                tgt.partner_type       = chg.partner_type,
                tgt.is_active          = chg.is_active,
                tgt.onboard_date       = chg.onboard_date,
                tgt.avg_prep_time_min  = chg.avg_prep_time_min,
                tgt.min_prep_min       = chg.min_prep_min,
                tgt.max_prep_min       = chg.max_prep_min,
                tgt.prep_time_group    = chg.prep_time_group,
                tgt.prep_time_index    = chg.prep_time_index,
                tgt.batch_id           = chg.batch_id,
                tgt.load_timestamp     = SYSUTCDATETIME()
            FROM dwh.dim_restaurant tgt
            INNER JOIN #Rest_SCD2 chg ON tgt.restaurant_id = chg.restaurant_id
            WHERE tgt.is_current = 1
              AND chg.tgt_valid_from >= @effective_date;

            SET @rows_updated = @rows_updated + @@ROWCOUNT;

            -- B.1b Expire prior version for Different-Day Changes
            UPDATE tgt
            SET tgt.valid_to       = @yesterday,
                tgt.is_current     = 0,
                tgt.load_timestamp = SYSUTCDATETIME()
            FROM dwh.dim_restaurant tgt
            INNER JOIN #Rest_SCD2 chg ON tgt.restaurant_id = chg.restaurant_id
            WHERE tgt.is_current = 1
              AND chg.tgt_valid_from < @effective_date;

            SET @rows_updated = @rows_updated + @@ROWCOUNT;

            -- B.2 Insert new active version for Different-Day Changes
            INSERT INTO dwh.dim_restaurant
            (
                restaurant_id, onboard_date, restaurant_name, city,
                cuisine_type, partner_type, avg_prep_time_min, is_active,
                min_prep_min, max_prep_min, prep_time_group, prep_time_index,
                last_active, life_cycle_id,
                valid_from, valid_to, is_current,
                batch_id, load_timestamp
            )
            SELECT 
                chg.restaurant_id, chg.onboard_date, chg.restaurant_name, chg.city,
                chg.cuisine_type, chg.partner_type, chg.avg_prep_time_min, chg.is_active,
                chg.min_prep_min, chg.max_prep_min, chg.prep_time_group, chg.prep_time_index,
                chg.last_active, chg.life_cycle_id,
                @effective_date, '9999-12-31', 1,
                chg.batch_id, SYSUTCDATETIME()
            FROM #Rest_SCD2 chg
            WHERE chg.tgt_valid_from < @effective_date;

            SET @rows_inserted = @rows_inserted + @@ROWCOUNT;

            -- B.3 Update new surrogate key in change log (for new versions only)
            UPDATE l
            SET l.surrogate_key_new = tgt.restaurant_key
            FROM control.dim_change_log l
            INNER JOIN dwh.dim_restaurant tgt
                ON l.business_id = tgt.restaurant_id
               AND tgt.is_current = 1
            WHERE l.batch_id = @batch_id
              AND l.dimension_name = 'dim_restaurant'
              AND l.surrogate_key_new IS NULL;
        END;

        -- Step C: Handle SCD Type 1 in-place updates (Demographics/Prep times only; behavioral metrics are enriched post-fact)
        UPDATE tgt
        SET tgt.onboard_date           = src.onboard_date,
            tgt.avg_prep_time_min      = src.avg_prep_time_min,
            tgt.min_prep_min           = src.min_prep_min,
            tgt.max_prep_min           = src.max_prep_min,
            tgt.prep_time_group        = src.prep_time_group,
            tgt.prep_time_index        = src.prep_time_index,
            tgt.batch_id               = src.batch_id,
            tgt.load_timestamp         = SYSUTCDATETIME()
        FROM dwh.dim_restaurant tgt
        INNER JOIN #RestPrepared src
            ON tgt.restaurant_id = src.restaurant_id
           AND tgt.is_current = 1
        WHERE NOT EXISTS (SELECT 1 FROM #Rest_SCD2 scd WHERE scd.restaurant_id = tgt.restaurant_id)
          AND (
            ISNULL(tgt.onboard_date, '1900-01-01')          <> ISNULL(src.onboard_date, '1900-01-01')
            OR ISNULL(tgt.avg_prep_time_min, '')            <> ISNULL(src.avg_prep_time_min, '')
            OR ISNULL(tgt.min_prep_min, -1)                 <> ISNULL(src.min_prep_min, -1)
            OR ISNULL(tgt.max_prep_min, -1)                 <> ISNULL(src.max_prep_min, -1)
            OR ISNULL(tgt.prep_time_group, '')              <> ISNULL(src.prep_time_group, '')
            OR ISNULL(tgt.prep_time_index, 0)               <> ISNULL(src.prep_time_index, 0)
          );

        SET @rows_updated = @rows_updated + @@ROWCOUNT;

        COMMIT TRANSACTION;

        -- 4.4 Update Successful Log
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

        PRINT CONCAT('>>> [DWH] dim_restaurant load complete: Read=', @rows_read, 
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

        PRINT '*** [ERROR] dim_restaurant load failed: ' + @ErrorMsg;
        THROW;
    END CATCH;
END;
GO


/* ==============================================================================
   5. PROCEDURE: dwh.usp_load_dim_menu_item
   PURPOSE  : Incremental Upsert (SCD Type 1) from ods.ods_menu_item to dwh.dim_menu_item.
              - Resolves restaurant_key via lookup to dwh.dim_restaurant (fallback to -1)
              - Allocates surrogate key (menu_item_key BIGINT IDENTITY)
              - Updates changed attributes (restaurant_key, item_name, category, is_veg, price)
              - Logs operation details to control.etl_log
============================================================================== */

CREATE OR ALTER PROCEDURE dwh.usp_load_dim_menu_item
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 5.1 Determine Active Batch ID
    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM ods.ods_menu_item;

        IF @batch_id IS NULL
            SELECT @batch_id = 1;
    END;

    DECLARE @process_name   VARCHAR(100) = 'ODS_TO_DWH',
            @step_name      VARCHAR(200) = 'LOAD_DIM_MENU_ITEM',
            @start_time     DATETIME2(3) = SYSUTCDATETIME(),
            @rows_read      BIGINT = 0,
            @rows_inserted  BIGINT = 0,
            @rows_updated   BIGINT = 0;

    -- 5.2 Register Start in control.etl_log
    INSERT INTO control.etl_log
    (
        batch_id, process_name, step_name, start_time,
        status, message, created_at
    )
    VALUES
    (
        @batch_id, @process_name, @step_name, @start_time,
        'RUNNING', 'Started loading dim_menu_item from ODS', SYSUTCDATETIME()
    );

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @rows_read = COUNT(*) FROM ods.ods_menu_item
        WHERE (@batch_id = -1 OR batch_id = @batch_id);

        -- 5.3 Set-based MERGE (SCD Type 1) with Restaurant Key resolution
        MERGE dwh.dim_menu_item AS target
        USING (
            SELECT 
                m.menu_item_id,
                ISNULL(r.restaurant_key, -1) AS restaurant_key,
                m.item_name,
                m.category,
                m.is_veg,
                m.price,
                m.batch_id
            FROM ods.ods_menu_item m
            LEFT JOIN dwh.dim_restaurant r
                ON m.restaurant_id = r.restaurant_id
               AND r.is_current = 1
            WHERE (@batch_id = -1 OR m.batch_id = @batch_id)
        ) AS source
        ON target.menu_item_id = source.menu_item_id

        -- When changed, update attributes and timestamps
        WHEN MATCHED AND (
            ISNULL(target.restaurant_key, -2)     <> ISNULL(source.restaurant_key, -2)
            OR ISNULL(target.item_name, '')          <> ISNULL(source.item_name, '')
            OR ISNULL(target.category, '')           <> ISNULL(source.category, '')
            OR ISNULL(target.is_veg, 2)              <> ISNULL(source.is_veg, 2)
            OR ISNULL(target.price, -1)              <> ISNULL(source.price, -1)
        )
        THEN UPDATE SET
            target.restaurant_key  = source.restaurant_key,
            target.item_name       = source.item_name,
            target.category        = source.category,
            target.is_veg          = source.is_veg,
            target.price           = source.price,
            target.batch_id        = source.batch_id,
            target.load_timestamp  = SYSUTCDATETIME()

        -- When new, insert and auto-allocate surrogate key
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
            (
                menu_item_id,
                restaurant_key,
                item_name,
                category,
                is_veg,
                price,
                batch_id,
                load_timestamp
            )
            VALUES
            (
                source.menu_item_id,
                source.restaurant_key,
                source.item_name,
                source.category,
                source.is_veg,
                source.price,
                source.batch_id,
                SYSUTCDATETIME()
            )
        OUTPUT $action INTO @merge_actions;

        SELECT 
            @rows_inserted = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
            @rows_updated  = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
        FROM @merge_actions;

        COMMIT TRANSACTION;

        -- 5.4 Update Successful Log
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

        PRINT CONCAT('>>> [DWH] dim_menu_item load complete: Read=', @rows_read, 
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

        PRINT '*** [ERROR] dim_menu_item load failed: ' + @ErrorMsg;
        THROW;
    END CATCH;
END;
GO


/* ==============================================================================
   6. PROCEDURE: dwh.usp_load_fact_order
   PURPOSE  : Incremental Load / Upsert from ods.ods_order to dwh.fact_order.
              - Grain: One row per order (Transaction Grain)
              - Surrogate Key: order_key BIGINT IDENTITY(1,1)
              - Degenerate Dimension: order_id
              - Dimension Lookups with Fallback to -1:
                * order_date_key       -> dwh.dim_date (YYYYMMDD)
                * order_time_key       -> dwh.dim_time (HHMM)
                * customer_key         -> dwh.dim_customer
                * restaurant_key       -> dwh.dim_restaurant
                * delivery_partner_key -> dwh.dim_delivery_partner (handles unassigned/cancelled orders)
              - Fully Additive Facts: subtotal_amount, discount_amount, delivery_fee, total_amount
              - Semi-additive Flags : is_cod, is_cancelled
              - Idempotent MERGE on order_id
              - Comprehensive ETL Logging to control.etl_log
============================================================================== */

CREATE OR ALTER PROCEDURE dwh.usp_load_fact_order
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 6.1 Determine Active Batch ID
    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM ods.ods_order;

        IF @batch_id IS NULL
            SELECT @batch_id = 1;
    END;

    DECLARE @process_name   VARCHAR(100) = 'ODS_TO_DWH',
            @step_name      VARCHAR(200) = 'LOAD_FACT_ORDER',
            @start_time     DATETIME2(3) = SYSUTCDATETIME(),
            @rows_read      BIGINT = 0,
            @rows_inserted  BIGINT = 0,
            @rows_updated   BIGINT = 0;

    -- 6.2 Register Start in control.etl_log
    INSERT INTO control.etl_log
    (
        batch_id, process_name, step_name, start_time,
        status, message, created_at
    )
    VALUES
    (
        @batch_id, @process_name, @step_name, @start_time,
        'RUNNING', 'Started loading fact_order from ODS', SYSUTCDATETIME()
    );

    BEGIN TRY
        SELECT @rows_read = COUNT(*) FROM ods.ods_order
        WHERE (@batch_id = -1 OR batch_id = @batch_id);

        -- 6.3 Stage and Transform Source Orders with Incremental Dimensional Lookups
        IF OBJECT_ID('tempdb..#OrderBase') IS NOT NULL DROP TABLE #OrderBase;
        SELECT 
            o.order_id,
            o.customer_id,
            o.restaurant_id,
            NULLIF(LTRIM(RTRIM(o.delivery_partner_id)), '') AS delivery_partner_id,
            o.order_timestamp,
            CAST(o.order_timestamp AS DATE) AS order_date,
            o.subtotal_amount,
            o.discount_amount,
            o.delivery_fee,
            o.total_amount,
            o.is_cod,
            o.is_cancelled,
            o.batch_id
        INTO #OrderBase
        FROM ods.ods_order o
        WHERE (@batch_id = -1 OR o.batch_id = @batch_id);

        CREATE CLUSTERED INDEX CIX_OrderBase_id ON #OrderBase(order_id);
        CREATE NONCLUSTERED INDEX IX_OrderBase_cust ON #OrderBase(customer_id, order_date);
        CREATE NONCLUSTERED INDEX IX_OrderBase_rest ON #OrderBase(restaurant_id, order_date);
        CREATE NONCLUSTERED INDEX IX_OrderBase_driver ON #OrderBase(delivery_partner_id, order_date);

        IF OBJECT_ID('tempdb..#CustLag') IS NOT NULL DROP TABLE #CustLag;
        SELECT customer_id, order_date,
               LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS intra_last_order_date
        INTO #CustLag
        FROM (SELECT DISTINCT customer_id, order_date FROM #OrderBase) d;
        CREATE CLUSTERED INDEX CIX_CustLag ON #CustLag(customer_id, order_date);

        IF OBJECT_ID('tempdb..#RestLag') IS NOT NULL DROP TABLE #RestLag;
        SELECT restaurant_id, order_date,
               LAG(order_date) OVER (PARTITION BY restaurant_id ORDER BY order_date) AS intra_last_order_date
        INTO #RestLag
        FROM (SELECT DISTINCT restaurant_id, order_date FROM #OrderBase) d;
        CREATE CLUSTERED INDEX CIX_RestLag ON #RestLag(restaurant_id, order_date);

        IF OBJECT_ID('tempdb..#DriverLag') IS NOT NULL DROP TABLE #DriverLag;
        SELECT delivery_partner_id, order_date,
               LAG(order_date) OVER (PARTITION BY delivery_partner_id ORDER BY order_date) AS intra_last_order_date
        INTO #DriverLag
        FROM (SELECT DISTINCT delivery_partner_id, order_date FROM #OrderBase WHERE delivery_partner_id IS NOT NULL) d;
        CREATE CLUSTERED INDEX CIX_DriverLag ON #DriverLag(delivery_partner_id, order_date);

        IF OBJECT_ID('tempdb..#StageOrder') IS NOT NULL DROP TABLE #StageOrder;

        SELECT 
            o.order_id,
            ISNULL(d.date_key, -1)                          AS order_date_key,
            ISNULL(t.time_key, -1)                          AS order_time_key,
            ISNULL(c.customer_key, -1)                      AS customer_key,
            ISNULL(r.restaurant_key, -1)                    AS restaurant_key,
            ISNULL(dp.delivery_partner_key, -1)             AS delivery_partner_key,
            o.subtotal_amount,
            o.discount_amount,
            o.delivery_fee,
            o.total_amount,
            (ISNULL(o.subtotal_amount, 0) - ISNULL(o.discount_amount, 0)) AS net_order_value,
            o.is_cod,
            o.is_cancelled,
            -- Lifecycle State Attribution: Reuses dim_customer.last_active cache instead of full fact scans
            CASE 
                WHEN COALESCE(cl.intra_last_order_date, CASE WHEN ISNULL(c.life_cycle_id, 0) = 0 THEN NULL ELSE c.last_active END) IS NULL THEN 1
                WHEN DATEDIFF(DAY, COALESCE(cl.intra_last_order_date, c.last_active), o.order_date) <= 60 THEN 2
                WHEN DATEDIFF(DAY, COALESCE(cl.intra_last_order_date, c.last_active), o.order_date) > 60 THEN 3
                ELSE 0
            END AS cust_lc_id,
            CASE 
                WHEN COALESCE(rl.intra_last_order_date, CASE WHEN ISNULL(r.life_cycle_id, 0) = 0 THEN NULL ELSE r.last_active END) IS NULL THEN 1
                WHEN DATEDIFF(DAY, COALESCE(rl.intra_last_order_date, r.last_active), o.order_date) <= 60 THEN 2
                WHEN DATEDIFF(DAY, COALESCE(rl.intra_last_order_date, r.last_active), o.order_date) > 60 THEN 3
                ELSE 0
            END AS rest_lc_id,
            CASE 
                WHEN o.delivery_partner_id IS NULL THEN NULL
                WHEN COALESCE(dl.intra_last_order_date, CASE WHEN ISNULL(dp.life_cycle_id, 0) = 0 THEN NULL ELSE dp.last_active END) IS NULL THEN 1
                WHEN DATEDIFF(DAY, COALESCE(dl.intra_last_order_date, dp.last_active), o.order_date) <= 30 THEN 2
                WHEN DATEDIFF(DAY, COALESCE(dl.intra_last_order_date, dp.last_active), o.order_date) > 30 THEN 3
                ELSE 0
            END AS driver_lc_id,
            o.batch_id
        INTO #StageOrder
        FROM #OrderBase o
        LEFT JOIN dwh.dim_date d
            ON d.date_key = CAST(CONVERT(VARCHAR(8), o.order_timestamp, 112) AS INT)
        LEFT JOIN dwh.dim_time t
            ON t.time_key = (DATEPART(HOUR, o.order_timestamp) * 100) + DATEPART(MINUTE, o.order_timestamp)
        LEFT JOIN dwh.dim_customer c
            ON o.customer_id = c.customer_id
           AND o.order_date >= c.valid_from
           AND o.order_date <= c.valid_to
        LEFT JOIN dwh.dim_restaurant r
            ON o.restaurant_id = r.restaurant_id
           AND o.order_date >= r.valid_from
           AND o.order_date <= r.valid_to
        LEFT JOIN dwh.dim_delivery_partner dp
            ON o.delivery_partner_id = dp.delivery_partner_id
           AND o.order_date >= dp.valid_from
           AND o.order_date <= dp.valid_to
        LEFT JOIN #CustLag cl
            ON o.customer_id = cl.customer_id AND o.order_date = cl.order_date
        LEFT JOIN #RestLag rl
            ON o.restaurant_id = rl.restaurant_id AND o.order_date = rl.order_date
        LEFT JOIN #DriverLag dl
            ON o.delivery_partner_id = dl.delivery_partner_id AND o.order_date = dl.order_date;

        CREATE CLUSTERED INDEX CIX_StageOrder_id ON #StageOrder(order_id);

        BEGIN TRANSACTION;

        -- 6.4 Targeted UPDATE on Modified Orders
        UPDATE target
        SET 
            target.order_date_key       = source.order_date_key,
            target.order_time_key       = source.order_time_key,
            target.customer_key         = source.customer_key,
            target.restaurant_key       = source.restaurant_key,
            target.delivery_partner_key = source.delivery_partner_key,
            target.subtotal_amount      = source.subtotal_amount,
            target.discount_amount      = source.discount_amount,
            target.delivery_fee         = source.delivery_fee,
            target.total_amount         = source.total_amount,
            target.net_order_value      = source.net_order_value,
            target.is_cod               = source.is_cod,
            target.is_cancelled         = source.is_cancelled,
            target.cust_lc_id           = source.cust_lc_id,
            target.rest_lc_id           = source.rest_lc_id,
            target.driver_lc_id         = source.driver_lc_id,
            target.batch_id             = source.batch_id,
            target.load_timestamp       = SYSUTCDATETIME()
        FROM dwh.fact_order target
        INNER JOIN #StageOrder source
            ON target.order_id = source.order_id
        WHERE (
            target.order_date_key                               <> source.order_date_key
            OR target.order_time_key                            <> source.order_time_key
            OR target.customer_key                              <> source.customer_key
            OR target.restaurant_key                            <> source.restaurant_key
            OR target.delivery_partner_key                      <> source.delivery_partner_key
            OR ISNULL(target.subtotal_amount, -1)               <> ISNULL(source.subtotal_amount, -1)
            OR ISNULL(target.discount_amount, -1)               <> ISNULL(source.discount_amount, -1)
            OR ISNULL(target.delivery_fee, -1)                  <> ISNULL(source.delivery_fee, -1)
            OR ISNULL(target.total_amount, -1)                  <> ISNULL(source.total_amount, -1)
            OR ISNULL(target.net_order_value, -1)              <> ISNULL(source.net_order_value, -1)
            OR ISNULL(target.is_cod, 2)                         <> ISNULL(source.is_cod, 2)
            OR ISNULL(target.is_cancelled, 2)                   <> ISNULL(source.is_cancelled, 2)
            OR ISNULL(target.cust_lc_id, 255)                   <> ISNULL(source.cust_lc_id, 255)
            OR ISNULL(target.rest_lc_id, 255)                   <> ISNULL(source.rest_lc_id, 255)
            OR ISNULL(target.driver_lc_id, 255)                 <> ISNULL(source.driver_lc_id, 255)
        );

        SET @rows_updated = @@ROWCOUNT;

        -- 6.5 Fast Bulk INSERT for Brand New Orders (Minimal Logging / Direct Path Insert)
        INSERT INTO dwh.fact_order WITH (TABLOCK)
        (
            order_id,
            order_date_key,
            order_time_key,
            customer_key,
            restaurant_key,
            delivery_partner_key,
            subtotal_amount,
            discount_amount,
            delivery_fee,
            total_amount,
            net_order_value,
            is_cod,
            is_cancelled,
            cust_lc_id,
            rest_lc_id,
            driver_lc_id,
            batch_id,
            load_timestamp
        )
        SELECT 
            source.order_id,
            source.order_date_key,
            source.order_time_key,
            source.customer_key,
            source.restaurant_key,
            source.delivery_partner_key,
            source.subtotal_amount,
            source.discount_amount,
            source.delivery_fee,
            source.total_amount,
            source.net_order_value,
            source.is_cod,
            source.is_cancelled,
            source.cust_lc_id,
            source.rest_lc_id,
            source.driver_lc_id,
            source.batch_id,
            SYSUTCDATETIME()
        FROM #StageOrder source
        WHERE NOT EXISTS (
            SELECT 1 
            FROM dwh.fact_order target
            WHERE target.order_id = source.order_id
        );

        SET @rows_inserted = @@ROWCOUNT;

        COMMIT TRANSACTION;

        IF OBJECT_ID('tempdb..#StageOrder') IS NOT NULL DROP TABLE #StageOrder;

        -- 6.4 Update Successful Log
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

        PRINT CONCAT('>>> [DWH] fact_order load complete: Read=', @rows_read, 
                     ', Inserted=', @rows_inserted, 
                     ', Updated=', @rows_updated);

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF OBJECT_ID('tempdb..#StageOrder') IS NOT NULL DROP TABLE #StageOrder;

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

        PRINT '*** [ERROR] fact_order load failed: ' + @ErrorMsg;
        THROW;
    END CATCH;
END;
GO


/* ==============================================================================
   7. PROCEDURE: dwh.usp_load_fact_order_item
   PURPOSE  : Incremental Load / Upsert from ods.ods_order_item to dwh.fact_order_item.
              - Grain: One row per order line item (Order Item Grain)
              - Surrogate Key: order_item_key BIGINT IDENTITY(1,1)
              - Degenerate Dimensions: order_item_id, order_id
              - Dimension Lookups with Fallback to -1:
                * order_date_key -> inherited from dwh.fact_order (fallback -1)
                * customer_key   -> inherited from dwh.fact_order (fallback -1)
                * restaurant_key -> inherited from dwh.fact_order (fallback -1)
                * menu_item_key  -> lookup from dwh.dim_menu_item (fallback -1)
              - Quantitative Measures:
                * quantity
                * unit_price
                * gross_line_total = quantity * unit_price
                * item_discount
                * net_line_total   = (quantity * unit_price) - item_discount
              - Idempotent MERGE on order_item_id
              - Comprehensive ETL Logging to control.etl_log
============================================================================== */

CREATE OR ALTER PROCEDURE dwh.usp_load_fact_order_item
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 7.1 Determine Active Batch ID
    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM ods.ods_order_item;

        IF @batch_id IS NULL
            SELECT @batch_id = 1;
    END;

    DECLARE @process_name   VARCHAR(100) = 'ODS_TO_DWH',
            @step_name      VARCHAR(200) = 'LOAD_FACT_ORDER_ITEM',
            @start_time     DATETIME2(3) = SYSUTCDATETIME(),
            @rows_read      BIGINT = 0,
            @rows_inserted  BIGINT = 0,
            @rows_updated   BIGINT = 0;

    -- 7.2 Register Start in control.etl_log
    INSERT INTO control.etl_log
    (
        batch_id, process_name, step_name, start_time,
        status, message, created_at
    )
    VALUES
    (
        @batch_id, @process_name, @step_name, @start_time,
        'RUNNING', 'Started loading fact_order_item from ODS', SYSUTCDATETIME()
    );

    BEGIN TRY
        SELECT @rows_read = COUNT(*) FROM ods.ods_order_item
        WHERE (@batch_id = -1 OR batch_id = @batch_id);

        -- 7.3 Stage and Transform Source Order Items with Dimensional Lookups
        IF OBJECT_ID('tempdb..#StageOrderItem') IS NOT NULL DROP TABLE #StageOrderItem;

        SELECT 
            oi.order_item_id,
            oi.order_id,
            ISNULL(fo.order_date_key, -1)                  AS order_date_key,
            ISNULL(fo.customer_key, -1)                    AS customer_key,
            ISNULL(fo.restaurant_key, -1)                  AS restaurant_key,
            ISNULL(mi.menu_item_key, -1)                   AS menu_item_key,
            oi.quantity,
            oi.unit_price,
            CAST(oi.quantity * oi.unit_price AS DECIMAL(18,2)) AS gross_line_total,
            oi.item_discount,
            CAST((oi.quantity * oi.unit_price) - oi.item_discount AS DECIMAL(18,2)) AS net_line_total,
            oi.batch_id
        INTO #StageOrderItem
        FROM ods.ods_order_item oi
        LEFT JOIN dwh.fact_order fo
            ON oi.order_id = fo.order_id
        LEFT JOIN dwh.dim_menu_item mi
            ON oi.menu_item_id = mi.menu_item_id
        WHERE (@batch_id = -1 OR oi.batch_id = @batch_id);

        CREATE CLUSTERED INDEX CIX_StageOrderItem_id ON #StageOrderItem(order_item_id);

        BEGIN TRANSACTION;

        -- 7.4 Targeted UPDATE on Modified Line Items
        UPDATE target
        SET 
            target.order_id          = source.order_id,
            target.order_date_key    = source.order_date_key,
            target.customer_key      = source.customer_key,
            target.restaurant_key    = source.restaurant_key,
            target.menu_item_key     = source.menu_item_key,
            target.quantity          = source.quantity,
            target.unit_price        = source.unit_price,
            target.gross_line_total  = source.gross_line_total,
            target.item_discount     = source.item_discount,
            target.net_line_total    = source.net_line_total,
            target.batch_id          = source.batch_id,
            target.load_timestamp    = SYSUTCDATETIME()
        FROM dwh.fact_order_item target
        INNER JOIN #StageOrderItem source
            ON target.order_item_id = source.order_item_id
        WHERE (
            target.order_id                                     <> source.order_id
            OR target.order_date_key                            <> source.order_date_key
            OR target.customer_key                              <> source.customer_key
            OR target.restaurant_key                            <> source.restaurant_key
            OR target.menu_item_key                             <> source.menu_item_key
            OR ISNULL(target.quantity, -1)                      <> ISNULL(source.quantity, -1)
            OR ISNULL(target.unit_price, -1)                    <> ISNULL(source.unit_price, -1)
            OR ISNULL(target.gross_line_total, -1)              <> ISNULL(source.gross_line_total, -1)
            OR ISNULL(target.item_discount, -1)                 <> ISNULL(source.item_discount, -1)
            OR ISNULL(target.net_line_total, -1)                <> ISNULL(source.net_line_total, -1)
        );

        SET @rows_updated = @@ROWCOUNT;

        -- 7.5 Fast Bulk INSERT for Brand New Line Items (Minimal Logging / Direct Path Insert)
        INSERT INTO dwh.fact_order_item WITH (TABLOCK)
        (
            order_item_id,
            order_id,
            order_date_key,
            customer_key,
            restaurant_key,
            menu_item_key,
            quantity,
            unit_price,
            gross_line_total,
            item_discount,
            net_line_total,
            batch_id,
            load_timestamp
        )
        SELECT 
            source.order_item_id,
            source.order_id,
            source.order_date_key,
            source.customer_key,
            source.restaurant_key,
            source.menu_item_key,
            source.quantity,
            source.unit_price,
            source.gross_line_total,
            source.item_discount,
            source.net_line_total,
            source.batch_id,
            SYSUTCDATETIME()
        FROM #StageOrderItem source
        WHERE NOT EXISTS (
            SELECT 1 
            FROM dwh.fact_order_item target
            WHERE target.order_item_id = source.order_item_id
        );

        SET @rows_inserted = @@ROWCOUNT;

        COMMIT TRANSACTION;

        IF OBJECT_ID('tempdb..#StageOrderItem') IS NOT NULL DROP TABLE #StageOrderItem;

        -- 7.4 Update Successful Log
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

        PRINT CONCAT('>>> [DWH] fact_order_item load complete: Read=', @rows_read, 
                     ', Inserted=', @rows_inserted, 
                     ', Updated=', @rows_updated);

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF OBJECT_ID('tempdb..#StageOrderItem') IS NOT NULL DROP TABLE #StageOrderItem;

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

        PRINT '*** [ERROR] fact_order_item load failed: ' + @ErrorMsg;
        THROW;
    END CATCH;
END;
GO


/* ==============================================================================
   8. PROCEDURE: dwh.usp_load_fact_delivery_performance
   PURPOSE  : Incremental Load / Upsert from ods.ods_delivery_performance 
              to dwh.fact_delivery_performance.
              - Grain: Delivery Execution Grain (One row per delivery attempt)
              - Surrogate Key: delivery_key BIGINT IDENTITY(1,1)
              - Degenerate Dimensions: delivery_id, order_id
              - Dimension Lookups via fact_order (fallback to -1):
                * delivery_date_key    -> fo.order_date_key
                * restaurant_key       -> fo.restaurant_key
                * delivery_partner_key -> fo.delivery_partner_key
              - Operational & OTIF Metrics:
                * order_item
                * delivery_item
                * is_infull            = CASE WHEN delivery_item >= order_item THEN 1 ELSE 0 END
                * prep_time
                * rider_wait_time
                * travel_time
                * expected_delivery_time_min
                * actual_delivery_time_min
                * delivery_delay_min   = actual_delivery_time_min - expected_delivery_time_min (Signed Variance)
                * is_ontime            = CASE WHEN actual_delivery_time_min <= expected_delivery_time_min THEN 1 ELSE 0 END
                * distance_km
              - Idempotent MERGE on delivery_id
              - Comprehensive ETL Logging to control.etl_log
============================================================================== */

CREATE OR ALTER PROCEDURE dwh.usp_load_fact_delivery_performance
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 8.1 Determine Active Batch ID
    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM ods.ods_delivery_performance;

        IF @batch_id IS NULL
            SELECT @batch_id = 1;
    END;

    DECLARE @process_name   VARCHAR(100) = 'ODS_TO_DWH',
            @step_name      VARCHAR(200) = 'LOAD_FACT_DELIVERY_PERFORMANCE',
            @start_time     DATETIME2(3) = SYSUTCDATETIME(),
            @rows_read      BIGINT = 0,
            @rows_inserted  BIGINT = 0,
            @rows_updated   BIGINT = 0;

    -- 8.2 Register Start in control.etl_log
    INSERT INTO control.etl_log
    (
        batch_id, process_name, step_name, start_time,
        status, message, created_at
    )
    VALUES
    (
        @batch_id, @process_name, @step_name, @start_time,
        'RUNNING', 'Started loading fact_delivery_performance from ODS', SYSUTCDATETIME()
    );

    BEGIN TRY
        SELECT @rows_read = COUNT(*) FROM ods.ods_delivery_performance
        WHERE (@batch_id = -1 OR batch_id = @batch_id);

        -- 8.3 Stage and Transform Source Delivery Performance
        IF OBJECT_ID('tempdb..#StageDelivPerf') IS NOT NULL DROP TABLE #StageDelivPerf;

        SELECT 
            dp.delivery_id,
            dp.order_id,
            ISNULL(fo.order_date_key, -1)                          AS delivery_date_key,
            ISNULL(fo.customer_key, -1)                            AS customer_key,
            ISNULL(fo.restaurant_key, -1)                          AS restaurant_key,
            ISNULL(fo.delivery_partner_key, -1)                    AS delivery_partner_key,
            dp.order_item,
            dp.delivery_item,
            CAST(CASE WHEN dp.delivery_item >= dp.order_item THEN 1 ELSE 0 END AS BIT) AS is_infull,
            dp.prep_time,
            dp.rider_wait_time,
            dp.travel_time,
            dp.expected_delivery_time_min,
            dp.actual_delivery_time_min,
            (dp.actual_delivery_time_min - dp.expected_delivery_time_min) AS delivery_delay_min,
            CAST(CASE WHEN dp.actual_delivery_time_min <= dp.expected_delivery_time_min THEN 1 ELSE 0 END AS BIT) AS is_ontime,
            CASE 
                WHEN dp.actual_delivery_time_min > dp.expected_delivery_time_min 
                THEN (dp.actual_delivery_time_min - dp.expected_delivery_time_min) 
                ELSE NULL 
            END AS late_time,
            CASE 
                WHEN dp.prep_time > dr.max_prep_min 
                THEN (dp.prep_time - dr.max_prep_min) 
                ELSE NULL 
            END AS prep_late_time,
            CASE 
                WHEN dp.actual_delivery_time_min > dp.expected_delivery_time_min 
                     AND (dp.prep_time - dr.max_prep_min) > 0 
                     AND (dp.prep_time - dr.max_prep_min) >= (dp.actual_delivery_time_min - dp.expected_delivery_time_min)
                    THEN 'Prep-Time'
                WHEN dp.actual_delivery_time_min > dp.expected_delivery_time_min 
                     AND (dp.prep_time - dr.max_prep_min) > 0 
                     AND (dp.prep_time - dr.max_prep_min) < (dp.actual_delivery_time_min - dp.expected_delivery_time_min)
                    THEN 'Both'
                WHEN dp.actual_delivery_time_min > dp.expected_delivery_time_min 
                     AND (dp.prep_time <= dr.max_prep_min OR dr.max_prep_min IS NULL) 
                     AND (dp.actual_delivery_time_min - dp.expected_delivery_time_min) > 0
                    THEN 'Travel-Time'
                ELSE NULL 
            END AS late_reason,
            CAST(CASE WHEN dp.actual_delivery_time_min <= dp.expected_delivery_time_min AND dp.delivery_item >= dp.order_item THEN 1 ELSE 0 END AS BIT) AS is_otif,
            dp.distance_km,
            CASE 
                WHEN dp.distance_km <= 3.0 THEN '< 3 km'
                WHEN dp.distance_km <= 5.0 THEN '3 - 5 km'
                WHEN dp.distance_km > 5.0  THEN '> 5 km'
                ELSE NULL
            END AS distance_bins,
            CASE 
                WHEN dp.travel_time <= 15 THEN '< 15 mins'
                WHEN dp.travel_time <= 30 THEN '15 - 30 mins'
                WHEN dp.travel_time <= 45 THEN '30 - 45 mins'
                WHEN dp.travel_time > 45  THEN '> 45 mins'
                ELSE NULL
            END AS travel_bins,
            CASE 
                WHEN dp.prep_time <= 15 THEN '< 15 mins'
                WHEN dp.prep_time <= 30 THEN '15 - 30 mins'
                WHEN dp.prep_time <= 45 THEN '30 - 45 mins'
                WHEN dp.prep_time <= 60 THEN '45 - 60 mins'
                WHEN dp.prep_time > 60  THEN '> 60 mins'
                ELSE NULL
            END AS prep_time_bins,
            CASE 
                WHEN dp.actual_delivery_time_min <= 30 THEN '< 30 mins'
                WHEN dp.actual_delivery_time_min <= 45 THEN '30 - 45 mins'
                WHEN dp.actual_delivery_time_min <= 55 THEN '45 - 55 mins'
                WHEN dp.actual_delivery_time_min <= 65 THEN '55 - 65 mins'
                WHEN dp.actual_delivery_time_min > 65  THEN '> 65 mins'
                ELSE NULL
            END AS actual_bins,
            dp.batch_id
        INTO #StageDelivPerf
        FROM ods.ods_delivery_performance dp
        LEFT JOIN dwh.fact_order fo
            ON dp.order_id = fo.order_id
        LEFT JOIN dwh.dim_restaurant dr
            ON fo.restaurant_key = dr.restaurant_key
        WHERE (@batch_id = -1 OR dp.batch_id = @batch_id);

        CREATE CLUSTERED INDEX CIX_StageDelivPerf_id ON #StageDelivPerf(delivery_id);

        BEGIN TRANSACTION;

        -- 8.4 Targeted UPDATE on Modified Delivery Performance
        UPDATE target
        SET 
            target.order_id                   = source.order_id,
            target.delivery_date_key          = source.delivery_date_key,
            target.customer_key               = source.customer_key,
            target.restaurant_key             = source.restaurant_key,
            target.delivery_partner_key       = source.delivery_partner_key,
            target.order_item                 = source.order_item,
            target.delivery_item              = source.delivery_item,
            target.is_infull                  = source.is_infull,
            target.prep_time                  = source.prep_time,
            target.rider_wait_time            = source.rider_wait_time,
            target.travel_time                = source.travel_time,
            target.expected_delivery_time_min = source.expected_delivery_time_min,
            target.actual_delivery_time_min   = source.actual_delivery_time_min,
            target.delivery_delay_min         = source.delivery_delay_min,
            target.is_ontime                  = source.is_ontime,
            target.late_time                  = source.late_time,
            target.prep_late_time             = source.prep_late_time,
            target.late_reason                = source.late_reason,
            target.is_otif                    = source.is_otif,
            target.distance_km                = source.distance_km,
            target.distance_bins              = source.distance_bins,
            target.travel_bins                = source.travel_bins,
            target.prep_time_bins             = source.prep_time_bins,
            target.actual_bins                = source.actual_bins,
            target.batch_id                   = source.batch_id,
            target.load_timestamp             = SYSUTCDATETIME()
        FROM dwh.fact_delivery_performance target
        INNER JOIN #StageDelivPerf source
            ON target.delivery_id = source.delivery_id
        WHERE (
            target.order_id                                            <> source.order_id
            OR target.delivery_date_key                                <> source.delivery_date_key
            OR target.customer_key                                     <> source.customer_key
            OR target.restaurant_key                                   <> source.restaurant_key
            OR target.delivery_partner_key                             <> source.delivery_partner_key
            OR ISNULL(target.order_item, -1)                           <> ISNULL(source.order_item, -1)
            OR ISNULL(target.delivery_item, -1)                        <> ISNULL(source.delivery_item, -1)
            OR ISNULL(target.is_infull, 2)                             <> ISNULL(source.is_infull, 2)
            OR ISNULL(target.prep_time, -1)                            <> ISNULL(source.prep_time, -1)
            OR ISNULL(target.rider_wait_time, -1)                      <> ISNULL(source.rider_wait_time, -1)
            OR ISNULL(target.travel_time, -1)                          <> ISNULL(source.travel_time, -1)
            OR ISNULL(target.expected_delivery_time_min, -1)           <> ISNULL(source.expected_delivery_time_min, -1)
            OR ISNULL(target.actual_delivery_time_min, -1)             <> ISNULL(source.actual_delivery_time_min, -1)
            OR ISNULL(target.delivery_delay_min, -9999)                <> ISNULL(source.delivery_delay_min, -9999)
            OR ISNULL(target.is_ontime, 2)                             <> ISNULL(source.is_ontime, 2)
            OR ISNULL(target.late_time, -1)                            <> ISNULL(source.late_time, -1)
            OR ISNULL(target.prep_late_time, -1)                       <> ISNULL(source.prep_late_time, -1)
            OR ISNULL(target.late_reason, '')                          <> ISNULL(source.late_reason, '')
            OR ISNULL(target.is_otif, 2)                               <> ISNULL(source.is_otif, 2)
            OR ISNULL(target.distance_km, -1)                          <> ISNULL(source.distance_km, -1)
            OR ISNULL(target.distance_bins, '')                        <> ISNULL(source.distance_bins, '')
            OR ISNULL(target.travel_bins, '')                          <> ISNULL(source.travel_bins, '')
            OR ISNULL(target.prep_time_bins, '')                       <> ISNULL(source.prep_time_bins, '')
            OR ISNULL(target.actual_bins, '')                          <> ISNULL(source.actual_bins, '')
        );

        SET @rows_updated = @@ROWCOUNT;

        -- 8.5 Fast Bulk INSERT for Brand New Delivery Records (Minimal Logging / Direct Path Insert)
        INSERT INTO dwh.fact_delivery_performance WITH (TABLOCK)
        (
            delivery_id,
            order_id,
            delivery_date_key,
            customer_key,
            restaurant_key,
            delivery_partner_key,
            order_item,
            delivery_item,
            is_infull,
            prep_time,
            rider_wait_time,
            travel_time,
            expected_delivery_time_min,
            actual_delivery_time_min,
            delivery_delay_min,
            is_ontime,
            late_time,
            prep_late_time,
            late_reason,
            is_otif,
            distance_km,
            distance_bins,
            travel_bins,
            prep_time_bins,
            actual_bins,
            batch_id,
            load_timestamp
        )
        SELECT 
            source.delivery_id,
            source.order_id,
            source.delivery_date_key,
            source.customer_key,
            source.restaurant_key,
            source.delivery_partner_key,
            source.order_item,
            source.delivery_item,
            source.is_infull,
            source.prep_time,
            source.rider_wait_time,
            source.travel_time,
            source.expected_delivery_time_min,
            source.actual_delivery_time_min,
            source.delivery_delay_min,
            source.is_ontime,
            source.late_time,
            source.prep_late_time,
            source.late_reason,
            source.is_otif,
            source.distance_km,
            source.distance_bins,
            source.travel_bins,
            source.prep_time_bins,
            source.actual_bins,
            source.batch_id,
            SYSUTCDATETIME()
        FROM #StageDelivPerf source
        WHERE NOT EXISTS (
            SELECT 1 
            FROM dwh.fact_delivery_performance target
            WHERE target.delivery_id = source.delivery_id
        );

        SET @rows_inserted = @@ROWCOUNT;

        COMMIT TRANSACTION;

        IF OBJECT_ID('tempdb..#StageDelivPerf') IS NOT NULL DROP TABLE #StageDelivPerf;

        -- 8.4 Update Successful Log
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

        PRINT CONCAT('>>> [DWH] fact_delivery_performance load complete: Read=', @rows_read, 
                     ', Inserted=', @rows_inserted, 
                     ', Updated=', @rows_updated);

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF OBJECT_ID('tempdb..#StageDelivPerf') IS NOT NULL DROP TABLE #StageDelivPerf;

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

        PRINT '*** [ERROR] fact_delivery_performance load failed: ' + @ErrorMsg;
        THROW;
    END CATCH;
END;
GO


/* ==============================================================================
   9. PROCEDURE: dwh.usp_load_fact_rating
   PURPOSE  : Incremental Load / Upsert from ods.ods_rating to dwh.fact_rating.
              - Grain: Order Rating Grain (One row per rating / order)
              - Surrogate Key: rating_key BIGINT IDENTITY(1,1)
              - Degenerate Dimensions: rating_id, order_id
              - Dimension Lookups with Fallback:
                * rating_date_key      -> dwh.dim_date (fallback -1)
                * rating_time_key      -> dwh.dim_time (fallback -1)
                * customer_key         -> dwh.dim_customer (fallback -1)
                * restaurant_key       -> dwh.dim_restaurant (fallback -1)
                * delivery_partner_key -> dwh.dim_delivery_partner via dwh.fact_order (fallback -1)
                * rating_type_id       -> dwh.dim_rating_type (fallback 0)
                * sentiment_type_id    -> dwh.dim_sentiment_type (fallback 0)
              - Measures & Qualitative:
                * rating
                * sentiment_score
                * review_text
              - Idempotent MERGE on rating_id
              - Comprehensive ETL Logging to control.etl_log
============================================================================== */

CREATE OR ALTER PROCEDURE dwh.usp_load_fact_rating
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 9.1 Determine Active Batch ID
    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM ods.ods_rating;

        IF @batch_id IS NULL
            SELECT @batch_id = 1;
    END;

    DECLARE @process_name   VARCHAR(100) = 'ODS_TO_DWH',
            @step_name      VARCHAR(200) = 'LOAD_FACT_RATING',
            @start_time     DATETIME2(3) = SYSUTCDATETIME(),
            @rows_read      BIGINT = 0,
            @rows_inserted  BIGINT = 0,
            @rows_updated   BIGINT = 0;

    -- 9.2 Register Start in control.etl_log
    INSERT INTO control.etl_log
    (
        batch_id, process_name, step_name, start_time,
        status, message, created_at
    )
    VALUES
    (
        @batch_id, @process_name, @step_name, @start_time,
        'RUNNING', 'Started loading fact_rating from ODS', SYSUTCDATETIME()
    );

    BEGIN TRY
        SELECT @rows_read = COUNT(*) FROM ods.ods_rating
        WHERE (@batch_id = -1 OR batch_id = @batch_id);

        -- 9.3 Stage and Transform Source Rating with Dimensional Lookups
        IF OBJECT_ID('tempdb..#StageRating') IS NOT NULL DROP TABLE #StageRating;

        SELECT 
            r.rating_id,
            r.order_id,
            ISNULL(d.date_key, -1)                  AS rating_date_key,
            ISNULL(t.time_key, -1)                  AS rating_time_key,
            ISNULL(fo.customer_key, ISNULL(c.customer_key, -1))          AS customer_key,
            ISNULL(fo.restaurant_key, ISNULL(res.restaurant_key, -1))      AS restaurant_key,
            ISNULL(fo.delivery_partner_key, -1) AS delivery_partner_key,
            r.rating,
            ISNULL(rt.rating_type_id, 0)        AS rating_type_id,
            r.sentiment_score,
            ISNULL(st.sentiment_type_id, 0)     AS sentiment_type_id,
            r.review_text,
            r.batch_id
        INTO #StageRating
        FROM ods.ods_rating r
        LEFT JOIN dwh.fact_order fo
            ON r.order_id = fo.order_id
        LEFT JOIN dwh.dim_date d
            ON d.date_key = CAST(CONVERT(VARCHAR(8), r.review_timestamp, 112) AS INT)
        LEFT JOIN dwh.dim_time t
            ON t.time_key = (DATEPART(HOUR, r.review_timestamp) * 100) + DATEPART(MINUTE, r.review_timestamp)
        LEFT JOIN dwh.dim_customer c
            ON r.customer_id = c.customer_id
           AND CAST(r.review_timestamp AS DATE) >= c.valid_from
           AND CAST(r.review_timestamp AS DATE) <= c.valid_to
        LEFT JOIN dwh.dim_restaurant res
            ON r.restaurant_id = res.restaurant_id
           AND CAST(r.review_timestamp AS DATE) >= res.valid_from
           AND CAST(r.review_timestamp AS DATE) <= res.valid_to
        LEFT JOIN dwh.dim_rating_type rt
            ON r.rating BETWEEN rt.min_score AND rt.max_score AND rt.rating_type_id <> 0
        LEFT JOIN dwh.dim_sentiment_type st
            ON r.sentiment_score BETWEEN st.min_score AND st.max_score AND st.sentiment_type_id <> 0
        WHERE (@batch_id = -1 OR r.batch_id = @batch_id);

        CREATE CLUSTERED INDEX CIX_StageRating_id ON #StageRating(rating_id);

        BEGIN TRANSACTION;

        -- 9.4 Targeted UPDATE on Modified Ratings
        UPDATE target
        SET 
            target.order_id              = source.order_id,
            target.rating_date_key       = source.rating_date_key,
            target.rating_time_key       = source.rating_time_key,
            target.customer_key          = source.customer_key,
            target.restaurant_key        = source.restaurant_key,
            target.delivery_partner_key  = source.delivery_partner_key,
            target.rating                = source.rating,
            target.rating_type_id        = source.rating_type_id,
            target.sentiment_score       = source.sentiment_score,
            target.sentiment_type_id     = source.sentiment_type_id,
            target.review_text           = source.review_text,
            target.batch_id              = source.batch_id,
            target.load_timestamp        = SYSUTCDATETIME()
        FROM dwh.fact_rating target
        INNER JOIN #StageRating source
            ON target.rating_id = source.rating_id
        WHERE (
            target.order_id                                       <> source.order_id
            OR target.rating_date_key                             <> source.rating_date_key
            OR target.rating_time_key                             <> source.rating_time_key
            OR target.customer_key                                <> source.customer_key
            OR target.restaurant_key                              <> source.restaurant_key
            OR target.delivery_partner_key                        <> source.delivery_partner_key
            OR ISNULL(target.rating, -1)                          <> ISNULL(source.rating, -1)
            OR ISNULL(target.rating_type_id, 255)                 <> ISNULL(source.rating_type_id, 255)
            OR ISNULL(target.sentiment_score, -9.0000)            <> ISNULL(source.sentiment_score, -9.0000)
            OR ISNULL(target.sentiment_type_id, 255)              <> ISNULL(source.sentiment_type_id, 255)
            OR ISNULL(target.review_text, '')                     <> ISNULL(source.review_text, '')
        );

        SET @rows_updated = @@ROWCOUNT;

        -- 9.5 Fast Bulk INSERT for Brand New Ratings (Minimal Logging / Direct Path Insert)
        INSERT INTO dwh.fact_rating WITH (TABLOCK)
        (
            rating_id,
            order_id,
            rating_date_key,
            rating_time_key,
            customer_key,
            restaurant_key,
            delivery_partner_key,
            rating,
            rating_type_id,
            sentiment_score,
            sentiment_type_id,
            review_text,
            batch_id,
            load_timestamp
        )
        SELECT 
            source.rating_id,
            source.order_id,
            source.rating_date_key,
            source.rating_time_key,
            source.customer_key,
            source.restaurant_key,
            source.delivery_partner_key,
            source.rating,
            source.rating_type_id,
            source.sentiment_score,
            source.sentiment_type_id,
            source.review_text,
            source.batch_id,
            SYSUTCDATETIME()
        FROM #StageRating source
        WHERE NOT EXISTS (
            SELECT 1 
            FROM dwh.fact_rating target
            WHERE target.rating_id = source.rating_id
        );

        SET @rows_inserted = @@ROWCOUNT;

        COMMIT TRANSACTION;

        IF OBJECT_ID('tempdb..#StageRating') IS NOT NULL DROP TABLE #StageRating;

        -- 9.4 Update Successful Log
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

        PRINT CONCAT('>>> [DWH] fact_rating load complete: Read=', @rows_read, 
                     ', Inserted=', @rows_inserted, 
                     ', Updated=', @rows_updated);

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF OBJECT_ID('tempdb..#StageRating') IS NOT NULL DROP TABLE #StageRating;

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

        PRINT '*** [ERROR] fact_rating load failed: ' + @ErrorMsg;
        THROW;
    END CATCH;
END;
GO


/* ==============================================================================
   10. PROCEDURE: dwh.usp_load_fact_review_aspect
   PURPOSE  : Set-based MERGE for Review Aspect Facts using the AI ABSA Cache
              (ref.ref_review_aspect_cache). Ensures full lineage, conformed 
              dimensions, and idempotent loading.
============================================================================== */

CREATE OR ALTER PROCEDURE dwh.usp_load_fact_review_aspect
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 10.0 Determine Active Batch ID
    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM dwh.fact_rating;

        IF @batch_id IS NULL
            SELECT @batch_id = 1;
    END;

    DECLARE @process_name   VARCHAR(100) = 'ODS_TO_DWH',
            @step_name      VARCHAR(100) = 'LOAD_FACT_REVIEW_ASPECT',
            @start_time     DATETIME2(3) = SYSUTCDATETIME(),
            @rows_read      BIGINT = 0,
            @rows_inserted  BIGINT = 0,
            @rows_updated   BIGINT = 0;

    -- 10.1 Register Start in control.etl_log
    INSERT INTO control.etl_log
    (
        batch_id, process_name, step_name, start_time,
        status, message, created_at
    )
    VALUES
    (
        @batch_id, @process_name, @step_name, @start_time,
        'RUNNING', 'Started loading fact_review_aspect from fact_rating and AI cache', SYSUTCDATETIME()
    );

    BEGIN TRY
        SELECT @rows_read = COUNT(*) 
        FROM dwh.fact_rating r
        JOIN ref.ref_review_aspect_cache c
            ON HASHBYTES('SHA2_256', LOWER(LTRIM(RTRIM(r.review_text)))) = CONVERT(VARBINARY(64), c.review_hash, 2)
        WHERE (@batch_id = -1 OR r.batch_id = @batch_id);

        -- 10.2 Stage and Transform Source Review Aspects from AI Cache
        IF OBJECT_ID('tempdb..#StageReviewAspect') IS NOT NULL DROP TABLE #StageReviewAspect;

        SELECT 
            r.rating_key,
            c.aspect_id,
            c.sentiment_type_id,
            c.matched_phrase,
            r.batch_id
        INTO #StageReviewAspect
        FROM dwh.fact_rating r
        JOIN ref.ref_review_aspect_cache c
            ON HASHBYTES('SHA2_256', LOWER(LTRIM(RTRIM(r.review_text)))) = CONVERT(VARBINARY(64), c.review_hash, 2)
        WHERE (@batch_id = -1 OR r.batch_id = @batch_id);

        CREATE CLUSTERED INDEX CIX_StageReviewAspect ON #StageReviewAspect(rating_key, aspect_id, sentiment_type_id);

        BEGIN TRANSACTION;

        -- 10.3 Targeted UPDATE on Modified Review Aspects
        UPDATE target
        SET 
            target.matched_phrase    = source.matched_phrase,
            target.batch_id          = source.batch_id,
            target.load_timestamp    = SYSUTCDATETIME()
        FROM dwh.fact_review_aspect target
        INNER JOIN #StageReviewAspect source
            ON target.rating_key = source.rating_key
           AND target.aspect_id = source.aspect_id
           AND target.sentiment_type_id = source.sentiment_type_id
        WHERE ISNULL(target.matched_phrase, '') <> ISNULL(source.matched_phrase, '');

        SET @rows_updated = @@ROWCOUNT;

        -- 10.4 Fast Bulk INSERT for Brand New Review Aspects (Minimal Logging / Direct Path Insert)
        INSERT INTO dwh.fact_review_aspect WITH (TABLOCK)
        (
            rating_key,
            aspect_id,
            sentiment_type_id,
            matched_phrase,
            batch_id,
            load_timestamp
        )
        SELECT 
            source.rating_key,
            source.aspect_id,
            source.sentiment_type_id,
            source.matched_phrase,
            source.batch_id,
            SYSUTCDATETIME()
        FROM #StageReviewAspect source
        WHERE NOT EXISTS (
            SELECT 1 
            FROM dwh.fact_review_aspect target
            WHERE target.rating_key = source.rating_key
              AND target.aspect_id = source.aspect_id
              AND target.sentiment_type_id = source.sentiment_type_id
        );

        SET @rows_inserted = @@ROWCOUNT;

        COMMIT TRANSACTION;

        IF OBJECT_ID('tempdb..#StageReviewAspect') IS NOT NULL DROP TABLE #StageReviewAspect;

        -- 10.5 Update Successful Log
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

        PRINT CONCAT('>>> [DWH] fact_review_aspect load complete: Read=', @rows_read, 
                     ', Inserted=', @rows_inserted, 
                     ', Updated=', @rows_updated);

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF OBJECT_ID('tempdb..#StageReviewAspect') IS NOT NULL DROP TABLE #StageReviewAspect;

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

        PRINT '*** [ERROR] fact_review_aspect load failed: ' + @ErrorMsg;
        THROW;
    END CATCH;
END;
GO

/* ==============================================================================
   11. PROCEDURE: dwh.usp_enrich_dimensions_behavioral_metrics
   PURPOSE  : Post-Fact Dimension Transaction Metrics Enrichment (Two-Pass Architecture).
              Calculates and updates transaction-bound metrics directly from
              dwh.fact_order into dwh.dim_customer, dwh.dim_restaurant, and
              dwh.dim_delivery_partner for active batch entities:
                - last_active (date of latest order)
                - life_cycle_id (transaction lifecycle state at latest order: 1: New, 2: Retained, 3: Reactivated)
              Note: Dynamic time-decaying metrics (days_since_last_active, is_churned,
              churned_date, last_status_id, churn_risk) are computed dynamically
              by the Serving Layer Views (bi.dim_customer, bi.dim_restaurant,
              bi.dim_delivery_partner) without incurring table update overhead.
============================================================================== */

CREATE OR ALTER PROCEDURE dwh.usp_enrich_dimensions_behavioral_metrics
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @process_name   VARCHAR(100) = 'DWH_DIM_ENRICHMENT',
            @step_name      VARCHAR(200) = 'ENRICH_DIM_METRICS',
            @start_time     DATETIME2(3) = SYSUTCDATETIME();

    IF @batch_id IS NULL OR @batch_id <= 0
        SELECT @batch_id = MAX(batch_id) FROM dwh.fact_order;

    IF @batch_id IS NULL SET @batch_id = 1;

    INSERT INTO control.etl_log
    (
        batch_id, process_name, step_name, start_time,
        status, message, created_at
    )
    VALUES
    (
        @batch_id, @process_name, @step_name, @start_time,
        'RUNNING', 'Started post-fact dimension behavioral enrichment', SYSUTCDATETIME()
    );

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1.0 Determine Active Entity Keys in Current Batch (Incremental Isolation)
        IF OBJECT_ID('tempdb..#ActiveCustKeys') IS NOT NULL DROP TABLE #ActiveCustKeys;
        SELECT DISTINCT customer_key 
        INTO #ActiveCustKeys 
        FROM dwh.fact_order 
        WHERE customer_key <> -1 AND (@batch_id = -1 OR batch_id = @batch_id);
        CREATE CLUSTERED INDEX CIX_ActiveCustKeys ON #ActiveCustKeys(customer_key);

        IF OBJECT_ID('tempdb..#ActiveRestKeys') IS NOT NULL DROP TABLE #ActiveRestKeys;
        SELECT DISTINCT restaurant_key 
        INTO #ActiveRestKeys 
        FROM dwh.fact_order 
        WHERE restaurant_key <> -1 AND (@batch_id = -1 OR batch_id = @batch_id);
        CREATE CLUSTERED INDEX CIX_ActiveRestKeys ON #ActiveRestKeys(restaurant_key);

        IF OBJECT_ID('tempdb..#ActiveDriverKeys') IS NOT NULL DROP TABLE #ActiveDriverKeys;
        SELECT DISTINCT delivery_partner_key 
        INTO #ActiveDriverKeys 
        FROM dwh.fact_order 
        WHERE delivery_partner_key <> -1 AND (@batch_id = -1 OR batch_id = @batch_id);
        CREATE CLUSTERED INDEX CIX_ActiveDriverKeys ON #ActiveDriverKeys(delivery_partner_key);

        /* ----------------------------------------------------------------------
           1.2 Enrich Customer Transaction Metrics (Targeted Active Batch)
        ---------------------------------------------------------------------- */
        ;WITH LastOrdersCust AS (
            SELECT 
                fo.customer_key,
                MAX(d.full_date) AS last_order_date
            FROM dwh.fact_order fo
            JOIN dwh.dim_date d ON fo.order_date_key = d.date_key
            INNER JOIN #ActiveCustKeys ak ON fo.customer_key = ak.customer_key
            GROUP BY fo.customer_key
        ),
        LastLifecycleCust AS (
            SELECT 
                fo.customer_key,
                lo.last_order_date,
                MAX(fo.cust_lc_id) AS last_cust_lc_id
            FROM dwh.fact_order fo
            JOIN dwh.dim_date d ON fo.order_date_key = d.date_key
            JOIN LastOrdersCust lo ON fo.customer_key = lo.customer_key AND d.full_date = lo.last_order_date
            GROUP BY fo.customer_key, lo.last_order_date
        )
        UPDATE c
        SET c.last_active   = COALESCE(ll.last_order_date, c.signup_date),
            c.life_cycle_id = ISNULL(ll.last_cust_lc_id, 0)
        FROM dwh.dim_customer c
        INNER JOIN #ActiveCustKeys ak ON c.customer_key = ak.customer_key
        LEFT JOIN LastLifecycleCust ll ON c.customer_key = ll.customer_key
        WHERE c.customer_key <> -1 AND c.is_current = 1;

        PRINT '    - Enriched dim_customer transaction metrics from fact_order';

        /* ----------------------------------------------------------------------
           1.3 Enrich Restaurant Transaction Metrics (Targeted Active Batch)
        ---------------------------------------------------------------------- */
        ;WITH LastOrdersRest AS (
            SELECT 
                fo.restaurant_key,
                MAX(d.full_date) AS last_order_date
            FROM dwh.fact_order fo
            JOIN dwh.dim_date d ON fo.order_date_key = d.date_key
            INNER JOIN #ActiveRestKeys ak ON fo.restaurant_key = ak.restaurant_key
            GROUP BY fo.restaurant_key
        ),
        LastLifecycleRest AS (
            SELECT 
                fo.restaurant_key,
                lo.last_order_date,
                MAX(fo.rest_lc_id) AS last_rest_lc_id
            FROM dwh.fact_order fo
            JOIN dwh.dim_date d ON fo.order_date_key = d.date_key
            JOIN LastOrdersRest lo ON fo.restaurant_key = lo.restaurant_key AND d.full_date = lo.last_order_date
            GROUP BY fo.restaurant_key, lo.last_order_date
        )
        UPDATE r
        SET r.last_active   = COALESCE(ll.last_order_date, r.onboard_date),
            r.life_cycle_id = ISNULL(ll.last_rest_lc_id, 0)
        FROM dwh.dim_restaurant r
        INNER JOIN #ActiveRestKeys ak ON r.restaurant_key = ak.restaurant_key
        LEFT JOIN LastLifecycleRest ll ON r.restaurant_key = ll.restaurant_key
        WHERE r.restaurant_key <> -1 AND r.is_current = 1;

        PRINT '    - Enriched dim_restaurant transaction metrics from fact_order';

        /* ----------------------------------------------------------------------
           1.4 Enrich Delivery Partner Transaction Metrics (Targeted Active Batch)
        ---------------------------------------------------------------------- */
        ;WITH LastOrdersDriver AS (
            SELECT 
                fo.delivery_partner_key,
                MAX(d.full_date) AS last_order_date
            FROM dwh.fact_order fo
            JOIN dwh.dim_date d ON fo.order_date_key = d.date_key
            INNER JOIN #ActiveDriverKeys ak ON fo.delivery_partner_key = ak.delivery_partner_key
            WHERE fo.delivery_partner_key <> -1
            GROUP BY fo.delivery_partner_key
        ),
        LastLifecycleDriver AS (
            SELECT 
                fo.delivery_partner_key,
                lo.last_order_date,
                MAX(fo.driver_lc_id) AS last_driver_lc_id
            FROM dwh.fact_order fo
            JOIN dwh.dim_date d ON fo.order_date_key = d.date_key
            JOIN LastOrdersDriver lo ON fo.delivery_partner_key = lo.delivery_partner_key AND d.full_date = lo.last_order_date
            GROUP BY fo.delivery_partner_key, lo.last_order_date
        )
        UPDATE dp
        SET dp.last_active   = COALESCE(ll.last_order_date, dp.onboard_date),
            dp.life_cycle_id = ISNULL(ll.last_driver_lc_id, 0)
        FROM dwh.dim_delivery_partner dp
        INNER JOIN #ActiveDriverKeys ak ON dp.delivery_partner_key = ak.delivery_partner_key
        LEFT JOIN LastLifecycleDriver ll ON dp.delivery_partner_key = ll.delivery_partner_key
        WHERE dp.delivery_partner_key <> -1 AND dp.is_current = 1;

        PRINT '    - Enriched dim_delivery_partner transaction metrics from fact_order';

        COMMIT TRANSACTION;

        UPDATE control.etl_log
        SET end_time   = SYSUTCDATETIME(),
            status     = 'SUCCESS',
            message    = 'Successfully enriched behavioral metrics across dim_customer, dim_restaurant, and dim_delivery_partner from fact_order'
        WHERE batch_id = @batch_id AND step_name = @step_name AND status = 'RUNNING';

        PRINT '>>> [DWH] Post-fact dimension behavioral enrichment complete.';

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        DECLARE @ErrorMsg NVARCHAR(4000) = ERROR_MESSAGE();

        UPDATE control.etl_log
        SET end_time   = SYSUTCDATETIME(),
            status     = 'FAILED',
            message    = CONCAT('FAILED: ', @ErrorMsg)
        WHERE batch_id = @batch_id AND step_name = @step_name AND status = 'RUNNING';

        PRINT '*** [ERROR] Post-fact enrichment failed: ' + @ErrorMsg;
        THROW;
    END CATCH;
END;
GO

/* ==============================================================================
   12. PROCEDURE: dwh.usp_relink_orphan_facts
   PURPOSE  : Automated self-healing reconciliation procedure to re-link orphan fact rows
              (carrying -1 unknown surrogate keys due to out-of-order or late-arriving parent orders).
              Scans downstream fact tables (fact_order_item, fact_delivery_performance, fact_rating)
              and reconciles foreign keys with dwh.fact_order once the parent order arrives.
   PARAMETERS:
       @batch_id BIGINT = NULL (Audit batch identifier)
       @dry_run  BIT    = 0    (If 1, previews candidate counts without modifying data)
============================================================================== */

CREATE OR ALTER PROCEDURE dwh.usp_relink_orphan_facts
    @batch_id BIGINT = NULL,
    @dry_run  BIT    = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rows_relinked_order_item BIGINT = 0,
            @rows_relinked_delivery   BIGINT = 0,
            @rows_relinked_rating     BIGINT = 0,
            @start_time               DATETIME2(3) = SYSUTCDATETIME();

    IF @batch_id IS NULL OR @batch_id <= 0
    BEGIN
        SELECT @batch_id = MAX(batch_id) FROM dwh.fact_order;
        IF @batch_id IS NULL SET @batch_id = 1;
    END;

    PRINT '==============================================================================';
    PRINT 'RECONCILING ORPHAN FACTS (LATE-ARRIVING PARENT ORDERS)';
    PRINT '==============================================================================';
    PRINT 'Mode: ' + CASE WHEN @dry_run = 1 THEN 'DRY RUN (Preview Only)' ELSE 'LIVE RECONCILIATION' END;
    PRINT '------------------------------------------------------------------------------';

    BEGIN TRY
        IF @dry_run = 1
        BEGIN
            SELECT @rows_relinked_order_item = COUNT(*)
            FROM dwh.fact_order_item oi
            INNER JOIN dwh.fact_order fo ON oi.order_id = fo.order_id
            WHERE (
                (oi.customer_key = -1 AND fo.customer_key <> -1)
                OR (oi.order_date_key = -1 AND fo.order_date_key <> -1)
                OR (oi.restaurant_key = -1 AND fo.restaurant_key <> -1)
            );

            SELECT @rows_relinked_delivery = COUNT(*)
            FROM dwh.fact_delivery_performance dp
            INNER JOIN dwh.fact_order fo ON dp.order_id = fo.order_id
            WHERE (
                (dp.customer_key = -1 AND fo.customer_key <> -1)
                OR (dp.delivery_date_key = -1 AND fo.order_date_key <> -1)
                OR (dp.restaurant_key = -1 AND fo.restaurant_key <> -1)
                OR (dp.delivery_partner_key = -1 AND fo.delivery_partner_key <> -1)
            );

            SELECT @rows_relinked_rating = COUNT(*)
            FROM dwh.fact_rating r
            INNER JOIN dwh.fact_order fo ON r.order_id = fo.order_id
            WHERE (
                (r.delivery_partner_key = -1 AND fo.delivery_partner_key <> -1)
                OR (r.customer_key = -1 AND fo.customer_key <> -1)
                OR (r.restaurant_key = -1 AND fo.restaurant_key <> -1)
            );

            PRINT CONCAT('[DRY RUN PREVIEW] Candidate orphan rows to re-link: order_item=', @rows_relinked_order_item,
                         ', delivery_performance=', @rows_relinked_delivery,
                         ', rating=', @rows_relinked_rating);
            RETURN;
        END;

        BEGIN TRANSACTION;

        -- 1. Reconcile dwh.fact_order_item
        UPDATE oi
        SET oi.order_date_key = CASE WHEN oi.order_date_key = -1 THEN fo.order_date_key ELSE oi.order_date_key END,
            oi.customer_key   = CASE WHEN oi.customer_key = -1 THEN fo.customer_key ELSE oi.customer_key END,
            oi.restaurant_key = CASE WHEN oi.restaurant_key = -1 THEN fo.restaurant_key ELSE oi.restaurant_key END,
            oi.load_timestamp = SYSUTCDATETIME()
        FROM dwh.fact_order_item oi
        INNER JOIN dwh.fact_order fo ON oi.order_id = fo.order_id
        WHERE (
            (oi.customer_key = -1 AND fo.customer_key <> -1)
            OR (oi.order_date_key = -1 AND fo.order_date_key <> -1)
            OR (oi.restaurant_key = -1 AND fo.restaurant_key <> -1)
        );

        SET @rows_relinked_order_item = @@ROWCOUNT;

        -- 2. Reconcile dwh.fact_delivery_performance
        UPDATE dp
        SET dp.delivery_date_key    = CASE WHEN dp.delivery_date_key = -1 THEN fo.order_date_key ELSE dp.delivery_date_key END,
            dp.customer_key         = CASE WHEN dp.customer_key = -1 THEN fo.customer_key ELSE dp.customer_key END,
            dp.restaurant_key       = CASE WHEN dp.restaurant_key = -1 THEN fo.restaurant_key ELSE dp.restaurant_key END,
            dp.delivery_partner_key = CASE WHEN dp.delivery_partner_key = -1 THEN fo.delivery_partner_key ELSE dp.delivery_partner_key END,
            dp.load_timestamp       = SYSUTCDATETIME()
        FROM dwh.fact_delivery_performance dp
        INNER JOIN dwh.fact_order fo ON dp.order_id = fo.order_id
        WHERE (
            (dp.customer_key = -1 AND fo.customer_key <> -1)
            OR (dp.delivery_date_key = -1 AND fo.order_date_key <> -1)
            OR (dp.restaurant_key = -1 AND fo.restaurant_key <> -1)
            OR (dp.delivery_partner_key = -1 AND fo.delivery_partner_key <> -1)
        );

        SET @rows_relinked_delivery = @@ROWCOUNT;

        -- 3. Reconcile dwh.fact_rating
        UPDATE r
        SET r.delivery_partner_key = CASE WHEN r.delivery_partner_key = -1 THEN fo.delivery_partner_key ELSE r.delivery_partner_key END,
            r.customer_key         = CASE WHEN r.customer_key = -1 THEN fo.customer_key ELSE r.customer_key END,
            r.restaurant_key       = CASE WHEN r.restaurant_key = -1 THEN fo.restaurant_key ELSE r.restaurant_key END,
            r.load_timestamp       = SYSUTCDATETIME()
        FROM dwh.fact_rating r
        INNER JOIN dwh.fact_order fo ON r.order_id = fo.order_id
        WHERE (
            (r.delivery_partner_key = -1 AND fo.delivery_partner_key <> -1)
            OR (r.customer_key = -1 AND fo.customer_key <> -1)
            OR (r.restaurant_key = -1 AND fo.restaurant_key <> -1)
        );

        SET @rows_relinked_rating = @@ROWCOUNT;

        COMMIT TRANSACTION;

        PRINT CONCAT('[SUCCESS] Re-linked orphan fact records: order_item=', @rows_relinked_order_item,
                     ', delivery_performance=', @rows_relinked_delivery,
                     ', rating=', @rows_relinked_rating);

        -- Audit log entry
        INSERT INTO control.etl_log
        (
            batch_id, process_name, step_name, start_time, end_time,
            status, rows_processed, rows_inserted, rows_rejected, message, created_at
        )
        VALUES
        (
            @batch_id, 'DWH_RECONCILIATION', 'RELINK_ORPHAN_FACTS', @start_time, SYSUTCDATETIME(),
            'SUCCESS', 
            (@rows_relinked_order_item + @rows_relinked_delivery + @rows_relinked_rating),
            0,
            0,
            CONCAT('Re-linked orphan facts: order_item=', @rows_relinked_order_item, 
                   ', delivery=', @rows_relinked_delivery, 
                   ', rating=', @rows_relinked_rating),
            SYSUTCDATETIME()
        );
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @err_msg NVARCHAR(4000) = ERROR_MESSAGE(),
                @err_num INT = ERROR_NUMBER();
        INSERT INTO control.etl_error (batch_id, table_name, error_type, error_message, error_timestamp)
        VALUES (@batch_id, 'dwh.usp_relink_orphan_facts', CONCAT('SQL_ERROR_', @err_num), @err_msg, SYSUTCDATETIME());
        THROW;
    END CATCH;
END;
GO

PRINT 'Compiled procedure dwh.usp_relink_orphan_facts successfully.';
GO


/* ==============================================================================
   13. PROCEDURE: dwh.usp_run_ods_to_dwh_pipeline
   PURPOSE  : Master Orchestrator for ODS -> DWH Dimensional Pipeline.
              Executes all dimension seeding, entity loading, and fact processing
              in strict dependency order (Two-Pass Post-Fact Architecture).
============================================================================== */

CREATE OR ALTER PROCEDURE dwh.usp_run_ods_to_dwh_pipeline
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Auto-resolve active batch_id for incremental load if not explicitly specified
    -- Explicitly passing @batch_id = -1 remains supported for full pipeline backfills
    IF @batch_id IS NULL OR @batch_id = 0
    BEGIN
        SELECT TOP 1 @batch_id = batch_id 
        FROM control.etl_batch 
        WHERE status IN ('RUNNING', 'SUCCESS') 
        ORDER BY batch_id DESC;

        IF @batch_id IS NULL OR @batch_id <= 0
            SELECT @batch_id = MAX(batch_id) FROM ods.ods_order;

        IF @batch_id IS NULL OR @batch_id <= 0
            SET @batch_id = -1;
    END;

    PRINT '==============================================================================';
    PRINT 'STARTING END-TO-END ODS -> DWH PIPELINE EXECUTION (BATCH: ' + CAST(@batch_id AS VARCHAR(10)) + ')';
    PRINT '==============================================================================';

    BEGIN TRY
        -- Stage 0: Dimension Seeds & Unknown Members (-1)
        PRINT '>>> Step 1/12: Seeding Reference Dimensions and Unknown Members...';
        EXEC dwh.usp_seed_dimensions_and_unknowns;

        -- Stage 1: Entity Dimensions Base Profile Load
        PRINT '>>> Step 2/12: Loading dim_customer...';
        EXEC dwh.usp_load_dim_customer @batch_id = @batch_id;

        PRINT '>>> Step 3/12: Loading dim_restaurant...';
        EXEC dwh.usp_load_dim_restaurant @batch_id = @batch_id;

        PRINT '>>> Step 4/12: Loading dim_delivery_partner...';
        EXEC dwh.usp_load_dim_delivery_partner @batch_id = @batch_id;

        PRINT '>>> Step 5/12: Loading dim_menu_item...';
        EXEC dwh.usp_load_dim_menu_item @batch_id = @batch_id;

        -- Stage 2: Core Fact Order (Computes order-level lifecycles cust_lc_id, rest_lc_id, driver_lc_id)
        PRINT '>>> Step 6/12: Loading fact_order...';
        EXEC dwh.usp_load_fact_order @batch_id = @batch_id;

        -- Stage 3: Post-Fact Dimension Enrichment (Two-Pass: Enriches Dim metrics directly from fact_order)
        PRINT '>>> Step 7/12: Enriching Dimension Behavioral Metrics from fact_order...';
        EXEC dwh.usp_enrich_dimensions_behavioral_metrics @batch_id = @batch_id;

        -- Stage 4: Downstream Fact Tables
        PRINT '>>> Step 8/12: Loading fact_order_item...';
        EXEC dwh.usp_load_fact_order_item @batch_id = @batch_id;

        PRINT '>>> Step 9/12: Loading fact_delivery_performance...';
        EXEC dwh.usp_load_fact_delivery_performance @batch_id = @batch_id;

        PRINT '>>> Step 10/12: Loading fact_rating...';
        EXEC dwh.usp_load_fact_rating @batch_id = @batch_id;

        -- Stage 5: VoC Text Analytics Fact
        PRINT '>>> Step 11/12: Loading fact_review_aspect...';
        EXEC dwh.usp_load_fact_review_aspect @batch_id = @batch_id;

        -- Stage 6: Self-Healing & Reconciliation of Late-Arriving Parent Facts
        PRINT '>>> Step 12/12: Reconciling Orphan Facts (Late-Arriving Orders)...';
        EXEC dwh.usp_relink_orphan_facts @batch_id = @batch_id, @dry_run = 0;

        -- Stage 7: Close End-to-End Batch Lifecycle (Captures true pipeline completion & quarantined error counts)
        IF @batch_id > 0
        BEGIN
            DECLARE @batch_error_records BIGINT = 0;
            SELECT @batch_error_records = COUNT(DISTINCT 
                CASE 
                    WHEN source_file_name IS NOT NULL AND source_row_number IS NOT NULL 
                    THEN CONCAT(source_file_name, '|', CAST(source_row_number AS VARCHAR(20)))
                    ELSE CAST(error_id AS VARCHAR(20))
                END
            )
            FROM control.etl_error
            WHERE batch_id = @batch_id;

            UPDATE control.etl_batch
            SET end_time        = SYSUTCDATETIME(),
                status          = CASE 
                    WHEN @batch_error_records > 0 THEN 'PARTIAL'
                    ELSE 'SUCCESS'
                END,
                error_records   = ISNULL(@batch_error_records, 0),
                success_records = CASE 
                    WHEN total_records >= ISNULL(@batch_error_records, 0) 
                    THEN total_records - ISNULL(@batch_error_records, 0) 
                    ELSE total_records 
                END
            WHERE batch_id = @batch_id
              AND status IN ('RUNNING', 'SUCCESS', 'PARTIAL');
        END;

        PRINT '==============================================================================';
        PRINT 'END-TO-END ODS -> DWH PIPELINE COMPLETED SUCCESSFULLY (TWO-PASS ARCHITECTURE)!';
        PRINT '==============================================================================';
    END TRY
    BEGIN CATCH
        DECLARE @err_msg NVARCHAR(4000) = ERROR_MESSAGE(),
                @err_num INT = ERROR_NUMBER(),
                @err_proc NVARCHAR(128) = ERROR_PROCEDURE(),
                @err_line INT = ERROR_LINE();

        PRINT '==============================================================================';
        PRINT 'PIPELINE FAILED AT: ' + ISNULL(@err_proc, 'dwh.usp_run_ods_to_dwh_pipeline') + ' (Line ' + CAST(@err_line AS VARCHAR) + ')';
        PRINT 'Error: ' + @err_msg;
        PRINT '==============================================================================';

        INSERT INTO control.etl_error
        (
            batch_id, table_name, error_type, error_message, error_timestamp
        )
        VALUES
        (
            @batch_id, ISNULL(@err_proc, 'ODS_TO_DWH_PIPELINE'), CONCAT('SQL_ERROR_', @err_num), @err_msg, SYSUTCDATETIME()
        );

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
