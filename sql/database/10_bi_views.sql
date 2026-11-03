USE FoodDeliveryDW;
GO

/* ==============================================================================
   10_bi_views.sql
   PURPOSE: BI Serving Layer (Dedicated Semantic Views for Power BI & Reporting)
   SCHEMA : bi
   
   ARCHITECTURE NOTES:
   - Schema 'bi' decouples Power BI & reporting tools from internal physical tables (dwh.*).
   - Only clean business keys, surrogate keys, measures, and calculated attributes are exposed.
   - 100% of ETL technical audit columns (batch_id, load_timestamp) are omitted.
   - SCD Type 2 metadata (valid_from, valid_to, is_current) is omitted; entity dimensions
     are pre-filtered to active versions (is_current = 1).
   - Dynamic, time-decaying metrics (days_since_last_active, is_churned, churned_date,
     last_status_id, churn_risk) are computed on-read via GETDATE().
============================================================================== */

-- Ensure schema bi exists
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'bi')
BEGIN
    EXEC(N'CREATE SCHEMA bi');
END;
GO


/* ==============================================================================
   SECTION 1: DIMENSION VIEWS (bi.dim_*)
============================================================================== */

/* 1.1 BI DIM CUSTOMER */
CREATE OR ALTER VIEW bi.dim_customer AS
SELECT
    customer_key,
    customer_id,
    signup_date,
    city,
    acquisition_channel,
    last_active,
    life_cycle_id,
    life_cycle_id AS life_cycle,
    -- Dynamic Days Since Last Active (relative to query date)
    CASE 
        WHEN customer_key = -1 THEN NULL
        ELSE DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE))
    END AS days_since_last_active,
    -- Dynamic Churn Status (> 60 days inactivity)
    CASE 
        WHEN customer_key = -1 THEN CAST(0 AS BIT)
        WHEN DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) > 60 THEN CAST(1 AS BIT)
        ELSE CAST(0 AS BIT)
    END AS is_churned,
    -- Dynamic Churned Date
    CASE 
        WHEN customer_key = -1 THEN NULL
        WHEN DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) > 60 
        THEN DATEADD(DAY, 60, COALESCE(last_active, signup_date))
        ELSE NULL
    END AS churned_date,
    -- Dynamic Last Status ID: 4 (Churned) if > 60 days, else retains transaction lifecycle (1: New, 2: Retained, 3: Reactivated)
    CASE 
        WHEN customer_key = -1 THEN CAST(0 AS TINYINT)
        WHEN DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) > 60 THEN CAST(4 AS TINYINT)
        ELSE ISNULL(life_cycle_id, CAST(0 AS TINYINT))
    END AS last_status_id,
    CASE 
        WHEN customer_key = -1 THEN CAST(0 AS TINYINT)
        WHEN DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) > 60 THEN CAST(4 AS TINYINT)
        ELSE ISNULL(life_cycle_id, CAST(0 AS TINYINT))
    END AS last_status,
    -- Dynamic Churn Risk
    CASE 
        WHEN customer_key = -1 THEN 'Unknown'
        WHEN DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) > 60 THEN 'Churned'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) > 45 THEN 'High'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) > 30 THEN 'High'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) BETWEEN 20 AND 45 THEN 'Medium'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) BETWEEN 10 AND 30 THEN 'Medium'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) < 20 THEN 'Low'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) < 10 THEN 'Low'
        ELSE 'Undefined'
    END AS churn_risk
FROM dwh.dim_customer
WHERE is_current = 1;
GO


/* 1.2 BI DIM RESTAURANT */
CREATE OR ALTER VIEW bi.dim_restaurant AS
SELECT
    restaurant_key,
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
    life_cycle_id,
    life_cycle_id AS life_cycle,
    -- Dynamic Days Since Last Active (relative to query date)
    CASE 
        WHEN restaurant_key = -1 THEN NULL
        ELSE DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE))
    END AS days_since_last_active,
    -- Dynamic Churn Status (> 60 days inactivity)
    CASE 
        WHEN restaurant_key = -1 THEN CAST(0 AS BIT)
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 60 THEN CAST(1 AS BIT)
        ELSE CAST(0 AS BIT)
    END AS is_churned,
    -- Dynamic Churned Date
    CASE 
        WHEN restaurant_key = -1 THEN NULL
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 60 
        THEN DATEADD(DAY, 60, COALESCE(last_active, onboard_date))
        ELSE NULL
    END AS churned_date,
    -- Dynamic Last Status ID: 4 (Churned) if > 60 days, else retains transaction lifecycle (1: New, 2: Retained, 3: Reactivated)
    CASE 
        WHEN restaurant_key = -1 THEN CAST(0 AS TINYINT)
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 60 THEN CAST(4 AS TINYINT)
        ELSE ISNULL(life_cycle_id, CAST(0 AS TINYINT))
    END AS last_status_id,
    CASE 
        WHEN restaurant_key = -1 THEN CAST(0 AS TINYINT)
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 60 THEN CAST(4 AS TINYINT)
        ELSE ISNULL(life_cycle_id, CAST(0 AS TINYINT))
    END AS last_status,
    -- Dynamic Churn Risk
    CASE 
        WHEN restaurant_key = -1 THEN 'Unknown'
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 60 THEN 'Churned'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 45 THEN 'High'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 21 THEN 'High'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) BETWEEN 15 AND 45 THEN 'Medium'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) BETWEEN 8 AND 21 THEN 'Medium'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) < 15 THEN 'Low'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) <= 7 THEN 'Low'
        ELSE 'Undefined'
    END AS churn_risk
FROM dwh.dim_restaurant
WHERE is_current = 1;
GO


/* 1.3 BI DIM DELIVERY PARTNER */
CREATE OR ALTER VIEW bi.dim_delivery_partner AS
SELECT
    delivery_partner_key,
    delivery_partner_id,
    onboard_date,
    partner_name,
    city,
    vehicle_type,
    employment_type,
    avg_rating,
    is_active,
    rating_type_id,
    rating_type,
    last_active,
    life_cycle_id,
    life_cycle_id AS life_cycle,
    -- Dynamic Days Since Last Active (relative to query date)
    CASE 
        WHEN delivery_partner_key = -1 THEN NULL
        ELSE DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE))
    END AS days_since_last_active,
    -- Dynamic Churn Status (> 30 days inactivity for drivers)
    CASE 
        WHEN delivery_partner_key = -1 THEN CAST(0 AS BIT)
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 30 THEN CAST(1 AS BIT)
        ELSE CAST(0 AS BIT)
    END AS is_churned,
    -- Dynamic Churned Date
    CASE 
        WHEN delivery_partner_key = -1 THEN NULL
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 30 
        THEN DATEADD(DAY, 30, COALESCE(last_active, onboard_date))
        ELSE NULL
    END AS churned_date,
    -- Dynamic Last Status ID: 4 (Churned) if > 30 days, else retains transaction lifecycle (1: New, 2: Retained, 3: Reactivated)
    CASE 
        WHEN delivery_partner_key = -1 THEN CAST(0 AS TINYINT)
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 30 THEN CAST(4 AS TINYINT)
        ELSE ISNULL(life_cycle_id, CAST(0 AS TINYINT))
    END AS last_status_id,
    CASE 
        WHEN delivery_partner_key = -1 THEN CAST(0 AS TINYINT)
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 30 THEN CAST(4 AS TINYINT)
        ELSE ISNULL(life_cycle_id, CAST(0 AS TINYINT))
    END AS last_status,
    -- Dynamic Churn Risk
    CASE 
        WHEN delivery_partner_key = -1 THEN 'Unknown'
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 30 THEN 'Churned'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 30 THEN 'High'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 15 THEN 'High'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) BETWEEN 15 AND 30 THEN 'Medium'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) BETWEEN 7 AND 15 THEN 'Medium'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) < 15 THEN 'Low'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) < 7 THEN 'Low'
        ELSE 'Undefined'
    END AS churn_risk
FROM dwh.dim_delivery_partner
WHERE is_current = 1;
GO


/* 1.4 BI DIM MENU ITEM */
CREATE OR ALTER VIEW bi.dim_menu_item AS
SELECT
    m.menu_item_key,
    m.menu_item_id,
    m.restaurant_key,
    r.restaurant_id,
    m.item_name,
    m.category,
    m.is_veg,
    m.price
FROM dwh.dim_menu_item m
LEFT JOIN dwh.dim_restaurant r ON m.restaurant_key = r.restaurant_key;
GO


/* 1.5 BI DIM DATE */
CREATE OR ALTER VIEW bi.dim_date AS
SELECT
    date_key,
    full_date,
    year,
    quarter,
    quarter_name,
    month,
    month_name,
    month_short,
    year_month,
    week_of_year,
    day_of_month,
    day_of_week,
    day_name,
    day_short,
    is_weekend,
    fiscal_year,
    fiscal_quarter,
    fiscal_quarter_number,
    fiscal_month,
    fiscal_month_number,
    period,
    period_id
FROM dwh.dim_date;
GO


/* 1.6 BI DIM TIME */
CREATE OR ALTER VIEW bi.dim_time AS
SELECT
    time_key,
    time_value,
    hour,
    minute,
    hour_12,
    am_pm,
    time_display,
    time_group,
    time_group_id,
    is_peak_hour
FROM dwh.dim_time;
GO


/* 1.7 BI DIM ASPECT */
CREATE OR ALTER VIEW bi.dim_aspect AS
SELECT
    aspect_id,
    aspect_name AS aspect,
    aspect_description
FROM dwh.dim_aspect;
GO


/* 1.8 BI DIM RATING TYPE */
CREATE OR ALTER VIEW bi.dim_rating_type AS
SELECT
    rating_type_id,
    rating_type,
    min_score,
    max_score
FROM dwh.dim_rating_type;
GO


/* 1.9 BI DIM SENTIMENT TYPE */
CREATE OR ALTER VIEW bi.dim_sentiment_type AS
SELECT
    sentiment_type_id,
    sentiment_type,
    min_score,
    max_score
FROM dwh.dim_sentiment_type;
GO


/* 1.10 BI DIM LIFE CYCLES */
CREATE OR ALTER VIEW bi.dim_life_cycles AS
SELECT
    lc_id,
    life_cycle,
    description
FROM dwh.dim_life_cycles;
GO


/* ==============================================================================
   SECTION 2: FACT VIEWS (bi.fact_*)
============================================================================== */

/* 2.1 BI FACT ORDER */
CREATE OR ALTER VIEW bi.fact_order AS
SELECT
    fo.order_key,
    fo.order_id,
    fo.order_date_key,
    TRY_CONVERT(DATE, CAST(fo.order_date_key AS VARCHAR(8)), 112) AS order_date,
    fo.order_time_key,
    CASE 
        WHEN fo.order_time_key >= 0 AND fo.order_time_key <= 2359 
        THEN TIMEFROMPARTS(fo.order_time_key / 100, fo.order_time_key % 100, 0, 0, 0) 
        ELSE NULL 
    END AS order_time,
    fo.customer_key,
    c.customer_id,
    fo.restaurant_key,
    r.restaurant_id,
    fo.delivery_partner_key,
    dp.delivery_partner_id,
    fo.subtotal_amount,
    fo.discount_amount,
    fo.delivery_fee,
    fo.total_amount,
    fo.net_order_value,
    fo.is_cod,
    fo.is_cancelled,
    fo.cust_lc_id,
    fo.rest_lc_id,
    fo.driver_lc_id
FROM dwh.fact_order fo
LEFT JOIN dwh.dim_customer c ON fo.customer_key = c.customer_key
LEFT JOIN dwh.dim_restaurant r ON fo.restaurant_key = r.restaurant_key
LEFT JOIN dwh.dim_delivery_partner dp ON fo.delivery_partner_key = dp.delivery_partner_key;
GO


/* 2.2 BI FACT ORDER ITEM */
CREATE OR ALTER VIEW bi.fact_order_item AS
SELECT
    foi.order_item_key,
    foi.order_item_id,
    foi.order_id,
    foi.order_date_key,
    foi.customer_key,
    foi.restaurant_key,
    foi.menu_item_key,
    m.menu_item_id,
    foi.quantity,
    foi.unit_price,
    foi.gross_line_total,
    foi.item_discount,
    foi.net_line_total
FROM dwh.fact_order_item foi
LEFT JOIN dwh.dim_menu_item m ON foi.menu_item_key = m.menu_item_key;
GO


/* 2.3 BI FACT DELIVERY PERFORMANCE */
CREATE OR ALTER VIEW bi.fact_delivery_performance AS
SELECT
    fdp.delivery_key,
    fdp.delivery_id,
    fdp.order_id,
    fdp.delivery_date_key,
    TRY_CONVERT(DATE, CAST(fdp.delivery_date_key AS VARCHAR(8)), 112) AS delivery_date,
    fdp.customer_key,
    c.customer_id,
    fdp.restaurant_key,
    r.restaurant_id,
    fdp.delivery_partner_key,
    dp.delivery_partner_id,
    fdp.order_item,
    fdp.delivery_item,
    fdp.is_infull,
    fdp.prep_time,
    fdp.rider_wait_time,
    fdp.travel_time,
    fdp.expected_delivery_time_min,
    fdp.actual_delivery_time_min,
    fdp.delivery_delay_min,
    fdp.is_ontime,
    fdp.late_time,
    fdp.prep_late_time,
    fdp.late_reason,
    fdp.is_otif,
    fdp.distance_km,
    fdp.distance_bins,
    fdp.travel_bins,
    fdp.prep_time_bins,
    fdp.actual_bins
FROM dwh.fact_delivery_performance fdp
LEFT JOIN dwh.dim_customer c ON fdp.customer_key = c.customer_key
LEFT JOIN dwh.dim_restaurant r ON fdp.restaurant_key = r.restaurant_key
LEFT JOIN dwh.dim_delivery_partner dp ON fdp.delivery_partner_key = dp.delivery_partner_key;
GO


/* 2.4 BI FACT RATING */
CREATE OR ALTER VIEW bi.fact_rating AS
SELECT
    fr.rating_key,
    fr.rating_id,
    fr.order_id,
    fr.rating_date_key,
    TRY_CONVERT(DATE, CAST(fr.rating_date_key AS VARCHAR(8)), 112) AS review_date,
    fr.rating_time_key,
    CASE 
        WHEN fr.rating_time_key >= 0 AND fr.rating_time_key <= 2359 
        THEN TIMEFROMPARTS(fr.rating_time_key / 100, fr.rating_time_key % 100, 0, 0, 0) 
        ELSE NULL 
    END AS review_time,
    fr.customer_key,
    c.customer_id,
    fr.restaurant_key,
    r.restaurant_id,
    fr.delivery_partner_key,
    dp.delivery_partner_id,
    fr.rating,
    fr.rating_type_id,
    fr.sentiment_score,
    fr.sentiment_type_id,
    fr.review_text
FROM dwh.fact_rating fr
LEFT JOIN dwh.dim_customer c ON fr.customer_key = c.customer_key
LEFT JOIN dwh.dim_restaurant r ON fr.restaurant_key = r.restaurant_key
LEFT JOIN dwh.dim_delivery_partner dp ON fr.delivery_partner_key = dp.delivery_partner_key;
GO


/* 2.5 BI FACT REVIEW ASPECT */
CREATE OR ALTER VIEW bi.fact_review_aspect AS
SELECT
    fra.review_aspect_key,
    r.rating_id,
    fra.aspect_id,
    fra.sentiment_type_id AS sentiment_id,
    fra.sentiment_type_id,
    TRY_CONVERT(DATE, CAST(r.rating_date_key AS VARCHAR(8)), 112) AS review_date,
    fra.matched_phrase
FROM dwh.fact_review_aspect fra
LEFT JOIN dwh.fact_rating r ON fra.rating_key = r.rating_key;
GO


/* ==============================================================================
   SECTION 3: VERIFICATION SUMMARY
============================================================================== */
SELECT 
    s.name AS schema_name,
    v.name AS view_name,
    v.create_date,
    v.modify_date
FROM sys.views v
JOIN sys.schemas s ON v.schema_id = s.schema_id
WHERE s.name = 'bi'
ORDER BY v.name;
GO
