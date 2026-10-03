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
            INSERT INTO dwh.dim_customer (customer_key, customer_id, signup_date, city, acquisition_channel, last_active, days_since_last_active, churn_risk, life_cycle_id, last_status_id, is_churned, churned_date, batch_id)
            VALUES (-1, 'UNKNOWN', '1900-01-01', 'Unknown', 'Unknown', '1900-01-01', 0, 'Unknown', 0, 0, 0, NULL, 0);
            SET IDENTITY_INSERT dwh.dim_customer OFF;
            PRINT '    - Seeded dwh.dim_customer Unknown Member (-1)';
        END;

        -- Restaurant Unknown (-1)
        IF NOT EXISTS (SELECT 1 FROM dwh.dim_restaurant WHERE restaurant_key = -1)
        BEGIN
            SET IDENTITY_INSERT dwh.dim_restaurant ON;
            INSERT INTO dwh.dim_restaurant (restaurant_key, restaurant_id, onboard_date, restaurant_name, city, cuisine_type, partner_type, avg_prep_time_min, is_active, min_prep_min, max_prep_min, prep_time_group, prep_time_index, last_active, days_since_last_active, churn_risk, life_cycle_id, last_status_id, is_churned, churned_date, batch_id)
            VALUES (-1, 'UNKNOWN', '1900-01-01', 'Unknown Restaurant', 'Unknown', 'Unknown', 'Unknown', 'Unknown', 0, 0, 0, 'Unknown', 0, '1900-01-01', 0, 'Unknown', 0, 0, 0, NULL, 0);
            SET IDENTITY_INSERT dwh.dim_restaurant OFF;
            PRINT '    - Seeded dwh.dim_restaurant Unknown Member (-1)';
        END;

        -- Delivery Partner Unknown (-1)
        IF NOT EXISTS (SELECT 1 FROM dwh.dim_delivery_partner WHERE delivery_partner_key = -1)
        BEGIN
            SET IDENTITY_INSERT dwh.dim_delivery_partner ON;
            INSERT INTO dwh.dim_delivery_partner (delivery_partner_key, delivery_partner_id, onboard_date, partner_name, city, vehicle_type, employment_type, avg_rating, is_active, last_active, days_since_last_active, churn_risk, life_cycle_id, last_status_id, is_churned, churned_date, rating_type_id, rating_type, batch_id)
            VALUES (-1, 'UNKNOWN', '1900-01-01', 'Unknown Driver', 'Unknown', 'Unknown', 'Unknown', NULL, 0, '1900-01-01', 0, 'Unknown', 0, 0, 0, NULL, 0, 'Unknown', 0);
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

        -- 2.3 Set-based MERGE (SCD Type 1) with Lifecycle & Churn Risk calculation
        DECLARE @max_order_date DATE;
        SELECT @max_order_date = ISNULL(MAX(CAST(order_timestamp AS DATE)), '2025-09-30')
        FROM ods.ods_order
        WHERE order_timestamp IS NOT NULL;

        WITH CustomerOrders AS
        (
            SELECT 
                o.customer_id,
                CAST(o.order_timestamp AS DATE) AS order_date,
                CASE 
                    WHEN CAST(o.order_timestamp AS DATE) < '2025-06-01' THEN 1
                    WHEN CAST(o.order_timestamp AS DATE) BETWEEN '2025-06-01' AND '2025-07-31' THEN 2
                    WHEN CAST(o.order_timestamp AS DATE) BETWEEN '2025-08-01' AND '2025-09-30' THEN 3
                    ELSE 4
                END AS period_id
            FROM ods.ods_order o
            WHERE o.order_timestamp IS NOT NULL
        ),
        CustomerActivity AS
        (
            SELECT 
                customer_id,
                MAX(order_date) AS last_order_date
            FROM CustomerOrders
            GROUP BY customer_id
        ),
        CustomerPeriods AS
        (
            SELECT 
                co.customer_id,
                MAX(CASE WHEN co.order_date = ca.last_order_date THEN co.period_id END) AS this_period,
                MAX(CASE WHEN co.order_date < ca.last_order_date THEN co.period_id END) AS last_period
            FROM CustomerOrders co
            INNER JOIN CustomerActivity ca ON co.customer_id = ca.customer_id
            GROUP BY co.customer_id
        ),
        CustomerMetrics AS
        (
            SELECT 
                c.customer_id,
                c.signup_date,
                c.city,
                c.acquisition_channel,
                c.batch_id,
                COALESCE(ca.last_order_date, c.signup_date) AS last_active,
                DATEDIFF(DAY, COALESCE(ca.last_order_date, c.signup_date), @max_order_date) AS days_since_last_active,
                CASE 
                    WHEN ca.last_order_date IS NULL THEN 0 -- Unknown (no transaction history)
                    WHEN cp.last_period IS NULL THEN 1    -- New (no prior order before last active date)
                    WHEN cp.last_period = cp.this_period THEN 2 -- Retained (same period)
                    WHEN cp.last_period + 1 = cp.this_period THEN 2 -- Retained (consecutive period)
                    WHEN cp.last_period + 2 <= cp.this_period THEN 3 -- Reactivated (skipped 1 or more periods)
                    ELSE 0
                END AS life_cycle_id
            FROM ods.ods_customer c
            LEFT JOIN CustomerActivity ca ON c.customer_id = ca.customer_id
            LEFT JOIN CustomerPeriods cp ON c.customer_id = cp.customer_id
            WHERE (@batch_id = -1 OR c.batch_id = @batch_id)
        ),
        CustomerFinal AS
        (
            SELECT 
                cm.customer_id,
                cm.signup_date,
                cm.city,
                cm.acquisition_channel,
                cm.last_active,
                cm.days_since_last_active,
                cm.life_cycle_id,
                -- is_churned
                CASE 
                    WHEN cm.last_active IS NULL THEN 0
                    WHEN DATEADD(DAY, 60, cm.last_active) >= '2025-08-01' THEN 0
                    WHEN DATEADD(DAY, 60, cm.last_active) < '2025-08-01' AND cm.life_cycle_id IN (0, 1, 2) THEN 1
                    ELSE 0
                END AS is_churned,
                -- churned_date
                CASE 
                    WHEN (
                        CASE 
                            WHEN cm.last_active IS NULL THEN 0
                            WHEN DATEADD(DAY, 60, cm.last_active) >= '2025-08-01' THEN 0
                            WHEN DATEADD(DAY, 60, cm.last_active) < '2025-08-01' AND cm.life_cycle_id IN (0, 1, 2) THEN 1
                            ELSE 0
                        END
                    ) = 1 THEN DATEADD(DAY, 60, cm.last_active)
                    ELSE NULL
                END AS churned_date,
                -- last_status_id: SWITCH(TRUE(), is_churned = 1, 4, life_cycle)
                CASE 
                    WHEN (
                        CASE 
                            WHEN cm.last_active IS NULL THEN 0
                            WHEN DATEADD(DAY, 60, cm.last_active) >= '2025-08-01' THEN 0
                            WHEN DATEADD(DAY, 60, cm.last_active) < '2025-08-01' AND cm.life_cycle_id IN (0, 1, 2) THEN 1
                            ELSE 0
                        END
                    ) = 1 THEN 4
                    ELSE cm.life_cycle_id
                END AS last_status_id,
                -- churn_risk
                CASE 
                    WHEN (
                        CASE 
                            WHEN cm.last_active IS NULL THEN 0
                            WHEN DATEADD(DAY, 60, cm.last_active) >= '2025-08-01' THEN 0
                            WHEN DATEADD(DAY, 60, cm.last_active) < '2025-08-01' AND cm.life_cycle_id IN (0, 1, 2) THEN 1
                            ELSE 0
                        END
                    ) = 1 THEN 'Churned'
                    WHEN cm.life_cycle_id = 2 AND cm.days_since_last_active > 45 THEN 'High'
                    WHEN cm.life_cycle_id <> 2 AND cm.days_since_last_active > 30 THEN 'High'
                    WHEN cm.life_cycle_id = 2 AND cm.days_since_last_active BETWEEN 20 AND 45 THEN 'Medium'
                    WHEN cm.life_cycle_id <> 2 AND cm.days_since_last_active BETWEEN 10 AND 30 THEN 'Medium'
                    WHEN cm.life_cycle_id = 2 AND cm.days_since_last_active < 20 THEN 'Low'
                    WHEN cm.life_cycle_id <> 2 AND cm.days_since_last_active < 10 THEN 'Low'
                    ELSE 'Undefined'
                END AS churn_risk,
                cm.batch_id
            FROM CustomerMetrics cm
        )
        MERGE dwh.dim_customer AS target
        USING CustomerFinal AS source
        ON target.customer_id = source.customer_id

        -- When changed, update profile and timestamps
        WHEN MATCHED AND (
            ISNULL(target.signup_date, '1900-01-01')          <> ISNULL(source.signup_date, '1900-01-01')
            OR ISNULL(target.city, '')                        <> ISNULL(source.city, '')
            OR ISNULL(target.acquisition_channel, '')         <> ISNULL(source.acquisition_channel, '')
            OR ISNULL(target.last_active, '1900-01-01')       <> ISNULL(source.last_active, '1900-01-01')
            OR ISNULL(target.days_since_last_active, -1)      <> ISNULL(source.days_since_last_active, -1)
            OR ISNULL(target.churn_risk, '')                  <> ISNULL(source.churn_risk, '')
            OR ISNULL(target.life_cycle_id, 255)              <> ISNULL(source.life_cycle_id, 255)
            OR ISNULL(target.last_status_id, 255)             <> ISNULL(source.last_status_id, 255)
            OR ISNULL(target.is_churned, 2)                   <> ISNULL(source.is_churned, 2)
            OR ISNULL(target.churned_date, '1900-01-01')      <> ISNULL(source.churned_date, '1900-01-01')
        )
        THEN UPDATE SET
            target.signup_date            = source.signup_date,
            target.city                   = source.city,
            target.acquisition_channel    = source.acquisition_channel,
            target.last_active            = source.last_active,
            target.days_since_last_active = source.days_since_last_active,
            target.churn_risk             = source.churn_risk,
            target.life_cycle_id          = source.life_cycle_id,
            target.last_status_id         = source.last_status_id,
            target.is_churned             = source.is_churned,
            target.churned_date           = source.churned_date,
            target.batch_id               = source.batch_id,
            target.load_timestamp         = SYSUTCDATETIME()

        -- When new, insert and auto-allocate surrogate key
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
            (
                customer_id,
                signup_date,
                city,
                acquisition_channel,
                last_active,
                days_since_last_active,
                churn_risk,
                life_cycle_id,
                last_status_id,
                is_churned,
                churned_date,
                batch_id,
                load_timestamp
            )
            VALUES
            (
                source.customer_id,
                source.signup_date,
                source.city,
                source.acquisition_channel,
                source.last_active,
                source.days_since_last_active,
                source.churn_risk,
                source.life_cycle_id,
                source.last_status_id,
                source.is_churned,
                source.churned_date,
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

        -- 3.3 Set-based MERGE (SCD Type 1) with Lifecycle & Churn Risk calculation
        DECLARE @max_order_date DATE;
        SELECT @max_order_date = ISNULL(MAX(CAST(order_timestamp AS DATE)), '2025-09-30')
        FROM ods.ods_order
        WHERE order_timestamp IS NOT NULL;

        WITH DriverOrders AS
        (
            SELECT 
                o.delivery_partner_id,
                CAST(o.order_timestamp AS DATE) AS order_date,
                CASE 
                    WHEN CAST(o.order_timestamp AS DATE) < '2025-06-01' THEN 1
                    WHEN CAST(o.order_timestamp AS DATE) BETWEEN '2025-06-01' AND '2025-07-31' THEN 2
                    WHEN CAST(o.order_timestamp AS DATE) BETWEEN '2025-08-01' AND '2025-09-30' THEN 3
                    ELSE 4
                END AS period_id
            FROM ods.ods_order o
            WHERE o.order_timestamp IS NOT NULL AND o.delivery_partner_id IS NOT NULL
        ),
        DriverActivity AS
        (
            SELECT 
                delivery_partner_id,
                MAX(order_date) AS last_order_date
            FROM DriverOrders
            GROUP BY delivery_partner_id
        ),
        DriverPeriods AS
        (
            SELECT 
                dro.delivery_partner_id,
                MAX(CASE WHEN dro.order_date = da.last_order_date THEN dro.period_id END) AS this_period,
                MAX(CASE WHEN dro.order_date < da.last_order_date THEN dro.period_id END) AS last_period
            FROM DriverOrders dro
            INNER JOIN DriverActivity da ON dro.delivery_partner_id = da.delivery_partner_id
            GROUP BY dro.delivery_partner_id
        ),
        DriverMetrics AS
        (
            SELECT 
                dp.delivery_partner_id,
                dp.onboard_date,
                dp.partner_name,
                dp.city,
                dp.vehicle_type,
                dp.employment_type,
                dp.avg_rating,
                dp.is_active,
                dp.batch_id,
                rt.rating_type_id,
                rt.rating_type,
                COALESCE(da.last_order_date, dp.onboard_date) AS last_active,
                DATEDIFF(DAY, COALESCE(da.last_order_date, dp.onboard_date), @max_order_date) AS days_since_last_active,
                CASE 
                    WHEN da.last_order_date IS NULL THEN 0 -- Unknown (no transaction history)
                    WHEN drp.last_period IS NULL THEN 1    -- New (no prior order before last active date)
                    WHEN drp.last_period = drp.this_period THEN 2 -- Retained (same period)
                    WHEN drp.last_period + 1 = drp.this_period THEN 2 -- Retained (consecutive period)
                    WHEN drp.last_period + 2 <= drp.this_period THEN 3 -- Reactivated (skipped 1 or more periods)
                    ELSE 0
                END AS life_cycle_id
            FROM ods.ods_delivery_partner dp
            LEFT JOIN DriverActivity da ON dp.delivery_partner_id = da.delivery_partner_id
            LEFT JOIN DriverPeriods drp ON dp.delivery_partner_id = drp.delivery_partner_id
            LEFT JOIN dwh.dim_rating_type rt 
                ON dp.avg_rating >= rt.min_score 
               AND dp.avg_rating <= rt.max_score 
               AND rt.rating_type_id <> 0
            WHERE (@batch_id = -1 OR dp.batch_id = @batch_id)
        ),
        DriverFinal AS
        (
            SELECT 
                dm.delivery_partner_id,
                dm.onboard_date,
                dm.partner_name,
                dm.city,
                dm.vehicle_type,
                dm.employment_type,
                dm.avg_rating,
                dm.is_active,
                dm.rating_type_id,
                dm.rating_type,
                dm.last_active,
                dm.days_since_last_active,
                dm.life_cycle_id,
                -- is_churned (30 days buffer)
                CASE 
                    WHEN dm.last_active IS NULL THEN 0
                    WHEN DATEADD(DAY, 30, dm.last_active) >= '2025-08-01' THEN 0
                    WHEN DATEADD(DAY, 30, dm.last_active) < '2025-08-01' AND dm.life_cycle_id IN (0, 1, 2) THEN 1
                    ELSE 0
                END AS is_churned,
                -- churned_date (30 days)
                CASE 
                    WHEN (
                        CASE 
                            WHEN dm.last_active IS NULL THEN 0
                            WHEN DATEADD(DAY, 30, dm.last_active) >= '2025-08-01' THEN 0
                            WHEN DATEADD(DAY, 30, dm.last_active) < '2025-08-01' AND dm.life_cycle_id IN (0, 1, 2) THEN 1
                            ELSE 0
                        END
                    ) = 1 THEN DATEADD(DAY, 30, dm.last_active)
                    ELSE NULL
                END AS churned_date,
                -- last_status_id: SWITCH(TRUE(), is_churned = 1, 4, life_cycle)
                CASE 
                    WHEN (
                        CASE 
                            WHEN dm.last_active IS NULL THEN 0
                            WHEN DATEADD(DAY, 30, dm.last_active) >= '2025-08-01' THEN 0
                            WHEN DATEADD(DAY, 30, dm.last_active) < '2025-08-01' AND dm.life_cycle_id IN (0, 1, 2) THEN 1
                            ELSE 0
                        END
                    ) = 1 THEN 4
                    ELSE dm.life_cycle_id
                END AS last_status_id,
                -- churn_risk
                CASE 
                    WHEN (
                        CASE 
                            WHEN dm.last_active IS NULL THEN 0
                            WHEN DATEADD(DAY, 30, dm.last_active) >= '2025-08-01' THEN 0
                            WHEN DATEADD(DAY, 30, dm.last_active) < '2025-08-01' AND dm.life_cycle_id IN (0, 1, 2) THEN 1
                            ELSE 0
                        END
                    ) = 1 THEN 'Churned'
                    WHEN dm.life_cycle_id = 2 AND dm.days_since_last_active > 30 THEN 'High'
                    WHEN dm.life_cycle_id = 2 AND dm.days_since_last_active BETWEEN 15 AND 30 THEN 'Medium'
                    WHEN dm.life_cycle_id = 2 AND dm.days_since_last_active < 15 THEN 'Low'
                    WHEN dm.life_cycle_id <> 2 AND dm.days_since_last_active > 15 THEN 'High'
                    WHEN dm.life_cycle_id <> 2 AND dm.days_since_last_active BETWEEN 7 AND 15 THEN 'Medium'
                    WHEN dm.life_cycle_id <> 2 AND dm.days_since_last_active < 7 THEN 'Low'
                    ELSE 'Undefined'
                END AS churn_risk,
                dm.batch_id
            FROM DriverMetrics dm
        )
        MERGE dwh.dim_delivery_partner AS target
        USING DriverFinal AS source
        ON target.delivery_partner_id = source.delivery_partner_id

        -- When changed, update attributes and timestamps
        WHEN MATCHED AND (
            ISNULL(target.onboard_date, '1900-01-01')          <> ISNULL(source.onboard_date, '1900-01-01')
            OR ISNULL(target.partner_name, '')                 <> ISNULL(source.partner_name, '')
            OR ISNULL(target.city, '')                         <> ISNULL(source.city, '')
            OR ISNULL(target.vehicle_type, '')                 <> ISNULL(source.vehicle_type, '')
            OR ISNULL(target.employment_type, '')              <> ISNULL(source.employment_type, '')
            OR ISNULL(target.avg_rating, -1)                   <> ISNULL(source.avg_rating, -1)
            OR ISNULL(target.is_active, 2)                     <> ISNULL(source.is_active, 2)
            OR ISNULL(target.last_active, '1900-01-01')        <> ISNULL(source.last_active, '1900-01-01')
            OR ISNULL(target.days_since_last_active, -1)       <> ISNULL(source.days_since_last_active, -1)
            OR ISNULL(target.churn_risk, '')                   <> ISNULL(source.churn_risk, '')
            OR ISNULL(target.life_cycle_id, 255)               <> ISNULL(source.life_cycle_id, 255)
            OR ISNULL(target.last_status_id, 255)              <> ISNULL(source.last_status_id, 255)
            OR ISNULL(target.is_churned, 2)                    <> ISNULL(source.is_churned, 2)
            OR ISNULL(target.churned_date, '1900-01-01')      <> ISNULL(source.churned_date, '1900-01-01')
            OR ISNULL(target.rating_type_id, 255)              <> ISNULL(source.rating_type_id, 255)
            OR ISNULL(target.rating_type, '')                  <> ISNULL(source.rating_type, '')
        )
        THEN UPDATE SET
            target.onboard_date           = source.onboard_date,
            target.partner_name           = source.partner_name,
            target.city                   = source.city,
            target.vehicle_type           = source.vehicle_type,
            target.employment_type        = source.employment_type,
            target.avg_rating             = source.avg_rating,
            target.is_active              = source.is_active,
            target.last_active            = source.last_active,
            target.days_since_last_active = source.days_since_last_active,
            target.churn_risk             = source.churn_risk,
            target.life_cycle_id          = source.life_cycle_id,
            target.last_status_id         = source.last_status_id,
            target.is_churned             = source.is_churned,
            target.churned_date           = source.churned_date,
            target.rating_type_id         = source.rating_type_id,
            target.rating_type            = source.rating_type,
            target.batch_id               = source.batch_id,
            target.load_timestamp         = SYSUTCDATETIME()

        -- When new, insert and auto-allocate surrogate key
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
            (
                delivery_partner_id,
                onboard_date,
                partner_name,
                city,
                vehicle_type,
                employment_type,
                avg_rating,
                is_active,
                last_active,
                days_since_last_active,
                churn_risk,
                life_cycle_id,
                last_status_id,
                is_churned,
                churned_date,
                rating_type_id,
                rating_type,
                batch_id,
                load_timestamp
            )
            VALUES
            (
                source.delivery_partner_id,
                source.onboard_date,
                source.partner_name,
                source.city,
                source.vehicle_type,
                source.employment_type,
                source.avg_rating,
                source.is_active,
                source.last_active,
                source.days_since_last_active,
                source.churn_risk,
                source.life_cycle_id,
                source.last_status_id,
                source.is_churned,
                source.churned_date,
                source.rating_type_id,
                source.rating_type,
                source.batch_id,
                SYSUTCDATETIME()
            )
        OUTPUT $action INTO @merge_actions;

        SELECT 
            @rows_inserted = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
            @rows_updated  = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
        FROM @merge_actions;

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

        -- 4.3 Set-based MERGE (SCD Type 1) with Prep Times, Lifecycle & Churn Risk
        DECLARE @max_order_date DATE;
        SELECT @max_order_date = ISNULL(MAX(CAST(order_timestamp AS DATE)), '2025-09-30')
        FROM ods.ods_order
        WHERE order_timestamp IS NOT NULL;

        WITH RestOrders AS
        (
            SELECT 
                o.restaurant_id,
                CAST(o.order_timestamp AS DATE) AS order_date,
                CASE 
                    WHEN CAST(o.order_timestamp AS DATE) < '2025-06-01' THEN 1
                    WHEN CAST(o.order_timestamp AS DATE) BETWEEN '2025-06-01' AND '2025-07-31' THEN 2
                    WHEN CAST(o.order_timestamp AS DATE) BETWEEN '2025-08-01' AND '2025-09-30' THEN 3
                    ELSE 4
                END AS period_id
            FROM ods.ods_order o
            WHERE o.order_timestamp IS NOT NULL
        ),
        RestActivity AS
        (
            SELECT 
                restaurant_id,
                MAX(order_date) AS last_order_date
            FROM RestOrders
            GROUP BY restaurant_id
        ),
        RestPeriods AS
        (
            SELECT 
                ro.restaurant_id,
                MAX(CASE WHEN ro.order_date = ra.last_order_date THEN ro.period_id END) AS this_period,
                MAX(CASE WHEN ro.order_date < ra.last_order_date THEN ro.period_id END) AS last_period
            FROM RestOrders ro
            INNER JOIN RestActivity ra ON ro.restaurant_id = ra.restaurant_id
            GROUP BY ro.restaurant_id
        ),
        RestMetrics AS
        (
            SELECT 
                r.restaurant_id,
                r.onboard_date,
                r.restaurant_name,
                r.city,
                r.cuisine_type,
                r.partner_type,
                r.avg_prep_time_min,
                r.is_active,
                r.batch_id,
                -- Prep time attributes (no ELSE)
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
                -- Activity dates & lifecycle
                COALESCE(ra.last_order_date, r.onboard_date) AS last_active,
                DATEDIFF(DAY, COALESCE(ra.last_order_date, r.onboard_date), @max_order_date) AS days_since_last_active,
                CASE 
                    WHEN ra.last_order_date IS NULL THEN 0 -- Unknown (no transaction history)
                    WHEN rp.last_period IS NULL THEN 1    -- New (no prior order before last active date)
                    WHEN rp.last_period = rp.this_period THEN 2 -- Retained (same period)
                    WHEN rp.last_period + 1 = rp.this_period THEN 2 -- Retained (consecutive period)
                    WHEN rp.last_period + 2 <= rp.this_period THEN 3 -- Reactivated (skipped 1 or more periods)
                    ELSE 0
                END AS life_cycle_id
            FROM ods.ods_restaurant r
            LEFT JOIN RestActivity ra ON r.restaurant_id = ra.restaurant_id
            LEFT JOIN RestPeriods rp ON r.restaurant_id = rp.restaurant_id
            WHERE (@batch_id = -1 OR r.batch_id = @batch_id)
        ),
        RestFinal AS
        (
            SELECT 
                rm.restaurant_id,
                rm.onboard_date,
                rm.restaurant_name,
                rm.city,
                rm.cuisine_type,
                rm.partner_type,
                rm.avg_prep_time_min,
                rm.is_active,
                rm.min_prep_min,
                rm.max_prep_min,
                rm.prep_time_group,
                rm.prep_time_index,
                rm.last_active,
                rm.days_since_last_active,
                rm.life_cycle_id,
                -- is_churned
                CASE 
                    WHEN rm.last_active IS NULL THEN 0
                    WHEN DATEADD(DAY, 60, rm.last_active) >= '2025-08-01' THEN 0
                    WHEN DATEADD(DAY, 60, rm.last_active) < '2025-08-01' AND rm.life_cycle_id IN (0, 1, 2) THEN 1
                    ELSE 0
                END AS is_churned,
                -- churned_date
                CASE 
                    WHEN (
                        CASE 
                            WHEN rm.last_active IS NULL THEN 0
                            WHEN DATEADD(DAY, 60, rm.last_active) >= '2025-08-01' THEN 0
                            WHEN DATEADD(DAY, 60, rm.last_active) < '2025-08-01' AND rm.life_cycle_id IN (0, 1, 2) THEN 1
                            ELSE 0
                        END
                    ) = 1 THEN DATEADD(DAY, 60, rm.last_active)
                    ELSE NULL
                END AS churned_date,
                -- last_status_id: SWITCH(TRUE(), is_churned = 1, 4, life_cycle)
                CASE 
                    WHEN (
                        CASE 
                            WHEN rm.last_active IS NULL THEN 0
                            WHEN DATEADD(DAY, 60, rm.last_active) >= '2025-08-01' THEN 0
                            WHEN DATEADD(DAY, 60, rm.last_active) < '2025-08-01' AND rm.life_cycle_id IN (0, 1, 2) THEN 1
                            ELSE 0
                        END
                    ) = 1 THEN 4
                    ELSE rm.life_cycle_id
                END AS last_status_id,
                -- churn_risk
                CASE 
                    WHEN (
                        CASE 
                            WHEN rm.last_active IS NULL THEN 0
                            WHEN DATEADD(DAY, 60, rm.last_active) >= '2025-08-01' THEN 0
                            WHEN DATEADD(DAY, 60, rm.last_active) < '2025-08-01' AND rm.life_cycle_id IN (0, 1, 2) THEN 1
                            ELSE 0
                        END
                    ) = 1 THEN 'Churned'
                    WHEN rm.life_cycle_id = 2 AND rm.days_since_last_active > 45 THEN 'High'
                    WHEN rm.life_cycle_id <> 2 AND rm.days_since_last_active > 21 THEN 'High'
                    WHEN rm.life_cycle_id = 2 AND rm.days_since_last_active BETWEEN 15 AND 45 THEN 'Medium'
                    WHEN rm.life_cycle_id <> 2 AND rm.days_since_last_active BETWEEN 8 AND 21 THEN 'Medium'
                    WHEN rm.life_cycle_id = 2 AND rm.days_since_last_active < 15 THEN 'Low'
                    WHEN rm.life_cycle_id <> 2 AND rm.days_since_last_active <= 7 THEN 'Low'
                    ELSE 'Undefined'
                END AS churn_risk,
                rm.batch_id
            FROM RestMetrics rm
        )
        MERGE dwh.dim_restaurant AS target
        USING RestFinal AS source
        ON target.restaurant_id = source.restaurant_id

        -- When changed, update attributes and timestamps
        WHEN MATCHED AND (
            ISNULL(target.onboard_date, '1900-01-01')          <> ISNULL(source.onboard_date, '1900-01-01')
            OR ISNULL(target.restaurant_name, '')              <> ISNULL(source.restaurant_name, '')
            OR ISNULL(target.city, '')                         <> ISNULL(source.city, '')
            OR ISNULL(target.cuisine_type, '')                 <> ISNULL(source.cuisine_type, '')
            OR ISNULL(target.partner_type, '')                 <> ISNULL(source.partner_type, '')
            OR ISNULL(target.avg_prep_time_min, '')            <> ISNULL(source.avg_prep_time_min, '')
            OR ISNULL(target.is_active, 2)                     <> ISNULL(source.is_active, 2)
            OR ISNULL(target.min_prep_min, -1)                 <> ISNULL(source.min_prep_min, -1)
            OR ISNULL(target.max_prep_min, -1)                 <> ISNULL(source.max_prep_min, -1)
            OR ISNULL(target.prep_time_group, '')              <> ISNULL(source.prep_time_group, '')
            OR ISNULL(target.prep_time_index, 0)               <> ISNULL(source.prep_time_index, 0)
            OR ISNULL(target.last_active, '1900-01-01')        <> ISNULL(source.last_active, '1900-01-01')
            OR ISNULL(target.days_since_last_active, -1)       <> ISNULL(source.days_since_last_active, -1)
            OR ISNULL(target.churn_risk, '')                   <> ISNULL(source.churn_risk, '')
            OR ISNULL(target.life_cycle_id, 255)               <> ISNULL(source.life_cycle_id, 255)
            OR ISNULL(target.last_status_id, 255)              <> ISNULL(source.last_status_id, 255)
            OR ISNULL(target.is_churned, 2)                    <> ISNULL(source.is_churned, 2)
            OR ISNULL(target.churned_date, '1900-01-01')       <> ISNULL(source.churned_date, '1900-01-01')
        )
        THEN UPDATE SET
            target.onboard_date           = source.onboard_date,
            target.restaurant_name        = source.restaurant_name,
            target.city                   = source.city,
            target.cuisine_type           = source.cuisine_type,
            target.partner_type           = source.partner_type,
            target.avg_prep_time_min      = source.avg_prep_time_min,
            target.is_active              = source.is_active,
            target.min_prep_min           = source.min_prep_min,
            target.max_prep_min           = source.max_prep_min,
            target.prep_time_group        = source.prep_time_group,
            target.prep_time_index        = source.prep_time_index,
            target.last_active            = source.last_active,
            target.days_since_last_active = source.days_since_last_active,
            target.churn_risk             = source.churn_risk,
            target.life_cycle_id          = source.life_cycle_id,
            target.last_status_id         = source.last_status_id,
            target.is_churned             = source.is_churned,
            target.churned_date           = source.churned_date,
            target.batch_id               = source.batch_id,
            target.load_timestamp         = SYSUTCDATETIME()

        -- When new, insert and auto-allocate surrogate key
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
            (
                restaurant_id,
                onboard_date,
                restaurant_name,
                city,
                cuisine_type,
                partner_type,
                avg_prep_time_min,
                is_active,
                min_prep_min,
                max_prep_min,
                prep_time_group,
                prep_time_index,
                last_active,
                days_since_last_active,
                churn_risk,
                life_cycle_id,
                last_status_id,
                is_churned,
                churned_date,
                batch_id,
                load_timestamp
            )
            VALUES
            (
                source.restaurant_id,
                source.onboard_date,
                source.restaurant_name,
                source.city,
                source.cuisine_type,
                source.partner_type,
                source.avg_prep_time_min,
                source.is_active,
                source.min_prep_min,
                source.max_prep_min,
                source.prep_time_group,
                source.prep_time_index,
                source.last_active,
                source.days_since_last_active,
                source.churn_risk,
                source.life_cycle_id,
                source.last_status_id,
                source.is_churned,
                source.churned_date,
                source.batch_id,
                SYSUTCDATETIME()
            )
        OUTPUT $action INTO @merge_actions;

        SELECT 
            @rows_inserted = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
            @rows_updated  = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
        FROM @merge_actions;

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

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @rows_read = COUNT(*) FROM ods.ods_order
        WHERE (@batch_id = -1 OR batch_id = @batch_id);

        -- 6.3 Set-based MERGE for Fact Order with Dimensional Lookups and Order Lifecycle
        ;WITH OrderBase AS (
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
                o.batch_id,
                CASE 
                    WHEN o.order_timestamp < '2025-06-01' THEN 1
                    WHEN o.order_timestamp < '2025-08-01' THEN 2
                    WHEN o.order_timestamp < '2025-10-01' THEN 3
                    ELSE 4
                END AS this_period
            FROM ods.ods_order o
        ),
        CustLag AS (
            SELECT customer_id, order_date, this_period,
                   LAG(this_period) OVER (PARTITION BY customer_id ORDER BY order_date) AS last_period
            FROM (SELECT DISTINCT customer_id, order_date, this_period FROM OrderBase) d
        ),
        RestLag AS (
            SELECT restaurant_id, order_date, this_period,
                   LAG(this_period) OVER (PARTITION BY restaurant_id ORDER BY order_date) AS last_period
            FROM (SELECT DISTINCT restaurant_id, order_date, this_period FROM OrderBase) d
        ),
        DriverLag AS (
            SELECT delivery_partner_id, order_date, this_period,
                   LAG(this_period) OVER (PARTITION BY delivery_partner_id ORDER BY order_date) AS last_period
            FROM (SELECT DISTINCT delivery_partner_id, order_date, this_period FROM OrderBase WHERE delivery_partner_id IS NOT NULL) d
        ),
        SourceOrders AS (
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
                CASE 
                    WHEN cl.last_period IS NULL THEN 1
                    WHEN cl.last_period = cl.this_period OR cl.last_period + 1 = cl.this_period THEN 2
                    WHEN cl.last_period + 2 <= cl.this_period THEN 3
                    ELSE 0
                END AS cust_lc_id,
                CASE 
                    WHEN rl.last_period IS NULL THEN 1
                    WHEN rl.last_period = rl.this_period OR rl.last_period + 1 = rl.this_period THEN 2
                    WHEN rl.last_period + 2 <= rl.this_period THEN 3
                    ELSE 0
                END AS rest_lc_id,
                CASE 
                    WHEN o.delivery_partner_id IS NULL THEN NULL
                    WHEN dl.last_period IS NULL THEN 1
                    WHEN dl.last_period = dl.this_period OR dl.last_period + 1 = dl.this_period THEN 2
                    WHEN dl.last_period + 2 <= dl.this_period THEN 3
                    ELSE 0
                END AS driver_lc_id,
                o.batch_id
            FROM OrderBase o
            LEFT JOIN dwh.dim_date d
                ON d.date_key = CAST(CONVERT(VARCHAR(8), o.order_timestamp, 112) AS INT)
            LEFT JOIN dwh.dim_time t
                ON t.time_key = (DATEPART(HOUR, o.order_timestamp) * 100) + DATEPART(MINUTE, o.order_timestamp)
            LEFT JOIN dwh.dim_customer c
                ON o.customer_id = c.customer_id
            LEFT JOIN dwh.dim_restaurant r
                ON o.restaurant_id = r.restaurant_id
            LEFT JOIN dwh.dim_delivery_partner dp
                ON o.delivery_partner_id = dp.delivery_partner_id
            LEFT JOIN CustLag cl
                ON o.customer_id = cl.customer_id AND o.order_date = cl.order_date
            LEFT JOIN RestLag rl
                ON o.restaurant_id = rl.restaurant_id AND o.order_date = rl.order_date
            LEFT JOIN DriverLag dl
                ON o.delivery_partner_id = dl.delivery_partner_id AND o.order_date = dl.order_date
            WHERE (@batch_id = -1 OR o.batch_id = @batch_id)
        )
        MERGE dwh.fact_order AS target
        USING SourceOrders AS source
        ON target.order_id = source.order_id

        -- When order status or financial amounts change, update fact record
        WHEN MATCHED AND (
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
        )
        THEN UPDATE SET
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

        -- When new order, insert fact record
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
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
            VALUES
            (
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
            )
        OUTPUT $action INTO @merge_actions;

        SELECT 
            @rows_inserted = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
            @rows_updated  = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
        FROM @merge_actions;

        COMMIT TRANSACTION;

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

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @rows_read = COUNT(*) FROM ods.ods_order_item
        WHERE (@batch_id = -1 OR batch_id = @batch_id);

        -- 7.3 Set-based MERGE for Fact Order Item with Dimensional Lookups
        MERGE dwh.fact_order_item AS target
        USING (
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
            FROM ods.ods_order_item oi
            LEFT JOIN dwh.fact_order fo
                ON oi.order_id = fo.order_id
            LEFT JOIN dwh.dim_menu_item mi
                ON oi.menu_item_id = mi.menu_item_id
            WHERE (@batch_id = -1 OR oi.batch_id = @batch_id)
        ) AS source
        ON target.order_item_id = source.order_item_id

        -- When line item measures or dimensions change, update fact record
        WHEN MATCHED AND (
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
        )
        THEN UPDATE SET
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

        -- When new line item, insert fact record
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
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
            VALUES
            (
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
            )
        OUTPUT $action INTO @merge_actions;

        SELECT 
            @rows_inserted = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
            @rows_updated  = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
        FROM @merge_actions;

        COMMIT TRANSACTION;

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

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @rows_read = COUNT(*) FROM ods.ods_delivery_performance
        WHERE (@batch_id = -1 OR batch_id = @batch_id);

        -- 8.3 Set-based MERGE for Fact Delivery Performance
        MERGE dwh.fact_delivery_performance AS target
        USING (
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
            FROM ods.ods_delivery_performance dp
            LEFT JOIN dwh.fact_order fo
                ON dp.order_id = fo.order_id
            LEFT JOIN dwh.dim_restaurant dr
                ON fo.restaurant_key = dr.restaurant_key
            WHERE (@batch_id = -1 OR dp.batch_id = @batch_id)
        ) AS source
        ON target.delivery_id = source.delivery_id

        -- When operational metrics or dimensions change, update fact record
        WHEN MATCHED AND (
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
        )
        THEN UPDATE SET
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

        -- When new delivery record, insert fact record
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
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
            VALUES
            (
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
            )
        OUTPUT $action INTO @merge_actions;

        SELECT 
            @rows_inserted = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
            @rows_updated  = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
        FROM @merge_actions;

        COMMIT TRANSACTION;

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

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @rows_read = COUNT(*) FROM ods.ods_rating
        WHERE (@batch_id = -1 OR batch_id = @batch_id);

        -- 9.3 Set-based MERGE for Fact Rating with Dimensional Lookups
        MERGE dwh.fact_rating AS target
        USING (
            SELECT 
                r.rating_id,
                r.order_id,
                ISNULL(d.date_key, -1)                  AS rating_date_key,
                ISNULL(t.time_key, -1)                  AS rating_time_key,
                ISNULL(c.customer_key, -1)              AS customer_key,
                ISNULL(res.restaurant_key, -1)          AS restaurant_key,
                ISNULL(fo.delivery_partner_key, -1)     AS delivery_partner_key,
                r.rating,
                ISNULL(rt.rating_type_id, 0)            AS rating_type_id,
                r.sentiment_score,
                ISNULL(st.sentiment_type_id, 0)         AS sentiment_type_id,
                r.review_text,
                r.batch_id
            FROM ods.ods_rating r
            LEFT JOIN dwh.fact_order fo
                ON r.order_id = fo.order_id
            LEFT JOIN dwh.dim_date d
                ON d.date_key = CAST(CONVERT(VARCHAR(8), r.review_timestamp, 112) AS INT)
            LEFT JOIN dwh.dim_time t
                ON t.time_key = (DATEPART(HOUR, r.review_timestamp) * 100) + DATEPART(MINUTE, r.review_timestamp)
            LEFT JOIN dwh.dim_customer c
                ON r.customer_id = c.customer_id
            LEFT JOIN dwh.dim_restaurant res
                ON r.restaurant_id = res.restaurant_id
            LEFT JOIN dwh.dim_rating_type rt
                ON r.rating BETWEEN rt.min_score AND rt.max_score AND rt.rating_type_id <> 0
            LEFT JOIN dwh.dim_sentiment_type st
                ON r.sentiment_score BETWEEN st.min_score AND st.max_score AND st.sentiment_type_id <> 0
            WHERE (@batch_id = -1 OR r.batch_id = @batch_id)
        ) AS source
        ON target.rating_id = source.rating_id

        -- When rating attributes change, update fact record
        WHEN MATCHED AND (
            target.order_id                                       <> source.order_id
            OR target.rating_date_key                             <> source.rating_date_key
            OR target.rating_time_key                             <> source.rating_time_key
            OR target.customer_key                                <> source.customer_key
            OR target.restaurant_key                              <> source.restaurant_key
            OR target.delivery_partner_key                        <> source.delivery_partner_key
            OR ISNULL(target.rating, -1)                          <> ISNULL(source.rating, -1)
            OR ISNULL(target.rating_type_id, 255)                 <> ISNULL(source.rating_type_id, 255)
            OR ISNULL(target.sentiment_score, -99)                <> ISNULL(source.sentiment_score, -99)
            OR ISNULL(target.sentiment_type_id, 255)              <> ISNULL(source.sentiment_type_id, 255)
            OR ISNULL(target.review_text, '')                     <> ISNULL(source.review_text, '')
        )
        THEN UPDATE SET
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

        -- When new rating record, insert fact record
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
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
            VALUES
            (
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
            )
        OUTPUT $action INTO @merge_actions;

        SELECT 
            @rows_inserted = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
            @rows_updated  = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
        FROM @merge_actions;

        COMMIT TRANSACTION;

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

    DECLARE @process_name   VARCHAR(100) = 'DWH_FACT_REVIEW_ASPECT',
            @step_name      VARCHAR(100) = 'usp_load_fact_review_aspect',
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

    DECLARE @merge_actions TABLE (action_type VARCHAR(10));

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @rows_read = COUNT(*) 
        FROM dwh.fact_rating r
        JOIN ref.ref_review_aspect_cache c
            ON HASHBYTES('SHA2_256', LOWER(LTRIM(RTRIM(r.review_text)))) = CONVERT(VARBINARY(64), c.review_hash, 2)
        WHERE (@batch_id = -1 OR r.batch_id = @batch_id);

        -- 10.2 Set-based MERGE into fact_review_aspect
        MERGE dwh.fact_review_aspect AS target
        USING (
            SELECT 
                r.rating_key,
                c.aspect_id,
                c.sentiment_type_id,
                c.matched_phrase,
                r.batch_id
            FROM dwh.fact_rating r
            JOIN ref.ref_review_aspect_cache c
                ON HASHBYTES('SHA2_256', LOWER(LTRIM(RTRIM(r.review_text)))) = CONVERT(VARBINARY(64), c.review_hash, 2)
            WHERE (@batch_id = -1 OR r.batch_id = @batch_id)
        ) AS source
        ON target.rating_key = source.rating_key
           AND target.aspect_id = source.aspect_id
           AND target.sentiment_type_id = source.sentiment_type_id

        -- When attributes change, update
        WHEN MATCHED AND (
            ISNULL(target.matched_phrase, '') <> ISNULL(source.matched_phrase, '')
        )
        THEN UPDATE SET
            target.matched_phrase    = source.matched_phrase,
            target.batch_id          = source.batch_id,
            target.load_timestamp    = SYSUTCDATETIME()

        -- When new aspect extraction, insert
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
            (
                rating_key,
                aspect_id,
                sentiment_type_id,
                matched_phrase,
                batch_id,
                load_timestamp
            )
            VALUES
            (
                source.rating_key,
                source.aspect_id,
                source.sentiment_type_id,
                source.matched_phrase,
                source.batch_id,
                SYSUTCDATETIME()
            )
        OUTPUT $action INTO @merge_actions;

        SELECT 
            @rows_inserted = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
            @rows_updated  = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
        FROM @merge_actions;

        COMMIT TRANSACTION;

        -- 10.3 Update Successful Log
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
   PURPOSE  : Post-Fact Dimension Enrichment (Two-Pass Architecture).
              Calculates and updates behavioral and lifecycle metrics directly
              from dwh.fact_order into dwh.dim_customer, dwh.dim_restaurant,
              and dwh.dim_delivery_partner:
                - last_active
                - days_since_last_active
                - life_cycle_id (from fact_order at last_active date)
                - is_churned
                - churned_date
                - last_status_id
                - churn_risk
============================================================================== */

CREATE OR ALTER PROCEDURE dwh.usp_enrich_dimensions_behavioral_metrics
    @batch_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @process_name   VARCHAR(100) = 'DWH_POST_FACT_ENRICHMENT',
            @step_name      VARCHAR(200) = 'ENRICH_DIMENSIONS_BEHAVIORAL_METRICS',
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

        -- 1. Determine System-wide Reference Max Order Date
        DECLARE @max_order_date DATE;
        SELECT @max_order_date = MAX(d.full_date)
        FROM dwh.fact_order fo
        JOIN dwh.dim_date d ON fo.order_date_key = d.date_key;

        IF @max_order_date IS NULL
            SELECT @max_order_date = CAST(GETDATE() AS DATE);

        /* ----------------------------------------------------------------------
           1.1 Enrich Customer Behavioral Metrics
        ---------------------------------------------------------------------- */
        ;WITH LastOrdersCust AS (
            SELECT 
                fo.customer_key,
                MAX(d.full_date) AS last_order_date
            FROM dwh.fact_order fo
            JOIN dwh.dim_date d ON fo.order_date_key = d.date_key
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
        SET c.last_active            = COALESCE(ll.last_order_date, c.signup_date),
            c.days_since_last_active = DATEDIFF(DAY, COALESCE(ll.last_order_date, c.signup_date), @max_order_date),
            c.life_cycle_id          = ISNULL(ll.last_cust_lc_id, 0),
            c.is_churned             = CASE 
                                         WHEN COALESCE(ll.last_order_date, c.signup_date) IS NULL THEN 0
                                         WHEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, c.signup_date)) >= '2025-08-01' THEN 0
                                         WHEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, c.signup_date)) < '2025-08-01' AND ISNULL(ll.last_cust_lc_id, 0) IN (0, 1, 2) THEN 1
                                         ELSE 0
                                       END,
            c.churned_date           = CASE 
                                         WHEN (CASE 
                                                 WHEN COALESCE(ll.last_order_date, c.signup_date) IS NULL THEN 0
                                                 WHEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, c.signup_date)) >= '2025-08-01' THEN 0
                                                 WHEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, c.signup_date)) < '2025-08-01' AND ISNULL(ll.last_cust_lc_id, 0) IN (0, 1, 2) THEN 1
                                                 ELSE 0
                                               END) = 1 THEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, c.signup_date))
                                         ELSE NULL
                                       END,
            c.last_status_id         = CASE 
                                         WHEN (CASE 
                                                 WHEN COALESCE(ll.last_order_date, c.signup_date) IS NULL THEN 0
                                                 WHEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, c.signup_date)) >= '2025-08-01' THEN 0
                                                 WHEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, c.signup_date)) < '2025-08-01' AND ISNULL(ll.last_cust_lc_id, 0) IN (0, 1, 2) THEN 1
                                                 ELSE 0
                                               END) = 1 THEN 4
                                         ELSE ISNULL(ll.last_cust_lc_id, 0)
                                       END,
            c.churn_risk             = CASE 
                                         WHEN (CASE 
                                                 WHEN COALESCE(ll.last_order_date, c.signup_date) IS NULL THEN 0
                                                 WHEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, c.signup_date)) >= '2025-08-01' THEN 0
                                                 WHEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, c.signup_date)) < '2025-08-01' AND ISNULL(ll.last_cust_lc_id, 0) IN (0, 1, 2) THEN 1
                                                 ELSE 0
                                               END) = 1 THEN 'Churned'
                                         WHEN ISNULL(ll.last_cust_lc_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, c.signup_date), @max_order_date) > 45 THEN 'High'
                                         WHEN ISNULL(ll.last_cust_lc_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, c.signup_date), @max_order_date) > 30 THEN 'High'
                                         WHEN ISNULL(ll.last_cust_lc_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, c.signup_date), @max_order_date) BETWEEN 20 AND 45 THEN 'Medium'
                                         WHEN ISNULL(ll.last_cust_lc_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, c.signup_date), @max_order_date) BETWEEN 10 AND 30 THEN 'Medium'
                                         WHEN ISNULL(ll.last_cust_lc_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, c.signup_date), @max_order_date) < 20 THEN 'Low'
                                         WHEN ISNULL(ll.last_cust_lc_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, c.signup_date), @max_order_date) < 10 THEN 'Low'
                                         ELSE 'Undefined'
                                       END
        FROM dwh.dim_customer c
        LEFT JOIN LastLifecycleCust ll ON c.customer_key = ll.customer_key
        WHERE c.customer_key <> -1;

        PRINT '    - Enriched dim_customer behavioral metrics from fact_order';

        /* ----------------------------------------------------------------------
           1.2 Enrich Restaurant Behavioral Metrics
        ---------------------------------------------------------------------- */
        ;WITH LastOrdersRest AS (
            SELECT 
                fo.restaurant_key,
                MAX(d.full_date) AS last_order_date
            FROM dwh.fact_order fo
            JOIN dwh.dim_date d ON fo.order_date_key = d.date_key
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
        SET r.last_active            = COALESCE(ll.last_order_date, r.onboard_date),
            r.days_since_last_active = DATEDIFF(DAY, COALESCE(ll.last_order_date, r.onboard_date), @max_order_date),
            r.life_cycle_id          = ISNULL(ll.last_rest_lc_id, 0),
            r.is_churned             = CASE 
                                         WHEN COALESCE(ll.last_order_date, r.onboard_date) IS NULL THEN 0
                                         WHEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, r.onboard_date)) >= '2025-08-01' THEN 0
                                         WHEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, r.onboard_date)) < '2025-08-01' AND ISNULL(ll.last_rest_lc_id, 0) IN (0, 1, 2) THEN 1
                                         ELSE 0
                                       END,
            r.churned_date           = CASE 
                                         WHEN (CASE 
                                                 WHEN COALESCE(ll.last_order_date, r.onboard_date) IS NULL THEN 0
                                                 WHEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, r.onboard_date)) >= '2025-08-01' THEN 0
                                                 WHEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, r.onboard_date)) < '2025-08-01' AND ISNULL(ll.last_rest_lc_id, 0) IN (0, 1, 2) THEN 1
                                                 ELSE 0
                                               END) = 1 THEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, r.onboard_date))
                                         ELSE NULL
                                       END,
            r.last_status_id         = CASE 
                                         WHEN (CASE 
                                                 WHEN COALESCE(ll.last_order_date, r.onboard_date) IS NULL THEN 0
                                                 WHEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, r.onboard_date)) >= '2025-08-01' THEN 0
                                                 WHEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, r.onboard_date)) < '2025-08-01' AND ISNULL(ll.last_rest_lc_id, 0) IN (0, 1, 2) THEN 1
                                                 ELSE 0
                                               END) = 1 THEN 4
                                         ELSE ISNULL(ll.last_rest_lc_id, 0)
                                       END,
            r.churn_risk             = CASE 
                                         WHEN (CASE 
                                                 WHEN COALESCE(ll.last_order_date, r.onboard_date) IS NULL THEN 0
                                                 WHEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, r.onboard_date)) >= '2025-08-01' THEN 0
                                                 WHEN DATEADD(DAY, 60, COALESCE(ll.last_order_date, r.onboard_date)) < '2025-08-01' AND ISNULL(ll.last_rest_lc_id, 0) IN (0, 1, 2) THEN 1
                                                 ELSE 0
                                               END) = 1 THEN 'Churned'
                                         WHEN ISNULL(ll.last_rest_lc_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, r.onboard_date), @max_order_date) > 45 THEN 'High'
                                         WHEN ISNULL(ll.last_rest_lc_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, r.onboard_date), @max_order_date) > 21 THEN 'High'
                                         WHEN ISNULL(ll.last_rest_lc_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, r.onboard_date), @max_order_date) BETWEEN 15 AND 45 THEN 'Medium'
                                         WHEN ISNULL(ll.last_rest_lc_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, r.onboard_date), @max_order_date) BETWEEN 8 AND 21 THEN 'Medium'
                                         WHEN ISNULL(ll.last_rest_lc_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, r.onboard_date), @max_order_date) < 15 THEN 'Low'
                                         WHEN ISNULL(ll.last_rest_lc_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, r.onboard_date), @max_order_date) <= 7 THEN 'Low'
                                         ELSE 'Undefined'
                                       END
        FROM dwh.dim_restaurant r
        LEFT JOIN LastLifecycleRest ll ON r.restaurant_key = ll.restaurant_key
        WHERE r.restaurant_key <> -1;

        PRINT '    - Enriched dim_restaurant behavioral metrics from fact_order';

        /* ----------------------------------------------------------------------
           1.3 Enrich Delivery Partner Behavioral Metrics
        ---------------------------------------------------------------------- */
        ;WITH LastOrdersDriver AS (
            SELECT 
                fo.delivery_partner_key,
                MAX(d.full_date) AS last_order_date
            FROM dwh.fact_order fo
            JOIN dwh.dim_date d ON fo.order_date_key = d.date_key
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
        SET dp.last_active            = COALESCE(ll.last_order_date, dp.onboard_date),
            dp.days_since_last_active = DATEDIFF(DAY, COALESCE(ll.last_order_date, dp.onboard_date), @max_order_date),
            dp.life_cycle_id          = ISNULL(ll.last_driver_lc_id, 0),
            dp.is_churned             = CASE 
                                          WHEN COALESCE(ll.last_order_date, dp.onboard_date) IS NULL THEN 0
                                          WHEN DATEADD(DAY, 30, COALESCE(ll.last_order_date, dp.onboard_date)) >= '2025-08-01' THEN 0
                                          WHEN DATEADD(DAY, 30, COALESCE(ll.last_order_date, dp.onboard_date)) < '2025-08-01' AND ISNULL(ll.last_driver_lc_id, 0) IN (0, 1, 2) THEN 1
                                          ELSE 0
                                        END,
            dp.churned_date           = CASE 
                                          WHEN (CASE 
                                                  WHEN COALESCE(ll.last_order_date, dp.onboard_date) IS NULL THEN 0
                                                  WHEN DATEADD(DAY, 30, COALESCE(ll.last_order_date, dp.onboard_date)) >= '2025-08-01' THEN 0
                                                  WHEN DATEADD(DAY, 30, COALESCE(ll.last_order_date, dp.onboard_date)) < '2025-08-01' AND ISNULL(ll.last_driver_lc_id, 0) IN (0, 1, 2) THEN 1
                                                  ELSE 0
                                                END) = 1 THEN DATEADD(DAY, 30, COALESCE(ll.last_order_date, dp.onboard_date))
                                          ELSE NULL
                                        END,
            dp.last_status_id         = CASE 
                                          WHEN (CASE 
                                                  WHEN COALESCE(ll.last_order_date, dp.onboard_date) IS NULL THEN 0
                                                  WHEN DATEADD(DAY, 30, COALESCE(ll.last_order_date, dp.onboard_date)) >= '2025-08-01' THEN 0
                                                  WHEN DATEADD(DAY, 30, COALESCE(ll.last_order_date, dp.onboard_date)) < '2025-08-01' AND ISNULL(ll.last_driver_lc_id, 0) IN (0, 1, 2) THEN 1
                                                  ELSE 0
                                                END) = 1 THEN 4
                                         ELSE ISNULL(ll.last_driver_lc_id, 0)
                                       END,
            dp.churn_risk             = CASE 
                                         WHEN (CASE 
                                                 WHEN COALESCE(ll.last_order_date, dp.onboard_date) IS NULL THEN 0
                                                 WHEN DATEADD(DAY, 30, COALESCE(ll.last_order_date, dp.onboard_date)) >= '2025-08-01' THEN 0
                                                 WHEN DATEADD(DAY, 30, COALESCE(ll.last_order_date, dp.onboard_date)) < '2025-08-01' AND ISNULL(ll.last_driver_lc_id, 0) IN (0, 1, 2) THEN 1
                                                 ELSE 0
                                               END) = 1 THEN 'Churned'
                                         WHEN ISNULL(ll.last_driver_lc_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, dp.onboard_date), @max_order_date) > 30 THEN 'High'
                                         WHEN ISNULL(ll.last_driver_lc_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, dp.onboard_date), @max_order_date) > 15 THEN 'High'
                                         WHEN ISNULL(ll.last_driver_lc_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, dp.onboard_date), @max_order_date) BETWEEN 15 AND 30 THEN 'Medium'
                                         WHEN ISNULL(ll.last_driver_lc_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, dp.onboard_date), @max_order_date) BETWEEN 7 AND 15 THEN 'Medium'
                                         WHEN ISNULL(ll.last_driver_lc_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, dp.onboard_date), @max_order_date) < 15 THEN 'Low'
                                         WHEN ISNULL(ll.last_driver_lc_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(ll.last_order_date, dp.onboard_date), @max_order_date) < 7 THEN 'Low'
                                         ELSE 'Undefined'
                                       END
        FROM dwh.dim_delivery_partner dp
        LEFT JOIN LastLifecycleDriver ll ON dp.delivery_partner_key = ll.delivery_partner_key
        WHERE dp.delivery_partner_key <> -1;

        PRINT '    - Enriched dim_delivery_partner behavioral metrics from fact_order';

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
   12. PROCEDURE: dwh.usp_run_ods_to_dwh_pipeline
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

    IF @batch_id IS NULL OR @batch_id <= 0
        SET @batch_id = -1;

    PRINT '==============================================================================';
    PRINT 'STARTING END-TO-END ODS -> DWH PIPELINE EXECUTION (BATCH: ' + CAST(@batch_id AS VARCHAR(10)) + ')';
    PRINT '==============================================================================';

    -- Stage 0: Dimension Seeds & Unknown Members (-1)
    PRINT '>>> Step 1/11: Seeding Reference Dimensions and Unknown Members...';
    EXEC dwh.usp_seed_dimensions_and_unknowns;

    -- Stage 1: Entity Dimensions Base Profile Load
    PRINT '>>> Step 2/11: Loading dim_customer...';
    EXEC dwh.usp_load_dim_customer @batch_id = @batch_id;

    PRINT '>>> Step 3/11: Loading dim_restaurant...';
    EXEC dwh.usp_load_dim_restaurant @batch_id = @batch_id;

    PRINT '>>> Step 4/11: Loading dim_delivery_partner...';
    EXEC dwh.usp_load_dim_delivery_partner @batch_id = @batch_id;

    PRINT '>>> Step 5/11: Loading dim_menu_item...';
    EXEC dwh.usp_load_dim_menu_item @batch_id = @batch_id;

    -- Stage 2: Core Fact Order (Computes order-level lifecycles cust_lc_id, rest_lc_id, driver_lc_id)
    PRINT '>>> Step 6/11: Loading fact_order...';
    EXEC dwh.usp_load_fact_order @batch_id = @batch_id;

    -- Stage 3: Post-Fact Dimension Enrichment (Two-Pass: Enriches Dim metrics directly from fact_order)
    PRINT '>>> Step 7/11: Enriching Dimension Behavioral Metrics from fact_order...';
    EXEC dwh.usp_enrich_dimensions_behavioral_metrics @batch_id = @batch_id;

    -- Stage 4: Downstream Fact Tables
    PRINT '>>> Step 8/11: Loading fact_order_item...';
    EXEC dwh.usp_load_fact_order_item @batch_id = @batch_id;

    PRINT '>>> Step 9/11: Loading fact_delivery_performance...';
    EXEC dwh.usp_load_fact_delivery_performance @batch_id = @batch_id;

    PRINT '>>> Step 10/11: Loading fact_rating...';
    EXEC dwh.usp_load_fact_rating @batch_id = @batch_id;

    -- Stage 5: VoC Text Analytics Fact
    PRINT '>>> Step 11/11: Loading fact_review_aspect...';
    EXEC dwh.usp_load_fact_review_aspect @batch_id = @batch_id;

    PRINT '==============================================================================';
    PRINT 'END-TO-END ODS -> DWH PIPELINE COMPLETED SUCCESSFULLY (TWO-PASS ARCHITECTURE)!';
    PRINT '==============================================================================';
END;
GO
