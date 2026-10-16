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
    menu_item_key,
    menu_item_id,
    restaurant_key,
    item_name,
    category,
    is_veg,
    price
FROM dwh.dim_menu_item;
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
    aspect_name,
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
    order_key,
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
    driver_lc_id
FROM dwh.fact_order;
GO


/* 2.2 BI FACT ORDER ITEM */
CREATE OR ALTER VIEW bi.fact_order_item AS
SELECT
    order_item_key,
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
    net_line_total
FROM dwh.fact_order_item;
GO


/* 2.3 BI FACT DELIVERY PERFORMANCE */
CREATE OR ALTER VIEW bi.fact_delivery_performance AS
SELECT
    delivery_key,
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
    actual_bins
FROM dwh.fact_delivery_performance;
GO


/* 2.4 BI FACT RATING */
CREATE OR ALTER VIEW bi.fact_rating AS
SELECT
    rating_key,
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
    review_text
FROM dwh.fact_rating;
GO


/* 2.5 BI FACT REVIEW ASPECT */
CREATE OR ALTER VIEW bi.fact_review_aspect AS
SELECT
    review_aspect_key,
    rating_key,
    aspect_id,
    sentiment_type_id,
    matched_phrase
FROM dwh.fact_review_aspect;
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
