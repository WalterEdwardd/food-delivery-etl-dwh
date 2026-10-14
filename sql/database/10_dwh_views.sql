USE FoodDeliveryDW;
GO

/* ==============================================================================
   10_dwh_views.sql
   PURPOSE: DWH Serving Layer (Semantic Views for Power BI, Analytics & Reporting).
   
   ARCHITECTURE NOTES:
   - Physical DWH tables (dwh.dim_*) store immutable and SCD Type 2 descriptive
     attributes along with baseline event dates (last_active, life_cycle_id).
   - This Serving Layer decouples physical storage from dynamic, time-decaying
     behavioral metrics (days_since_last_active, is_churned, churned_date,
     last_status_id, churn_risk).
   - Metrics are computed on-read using current system date (GETDATE()), ensuring:
       1. Zero-latency reporting accuracy without data freezing.
       2. Zero transaction log bloat from periodic mass-UPDATE sweeps.
       3. Automatic scoping to active SCD Type 2 versions (is_current = 1).
============================================================================== */

/* ==============================================================================
   1. SERVING VIEW: dwh.v_dim_customer
   Consumes: dwh.dim_customer
   Grain   : 1 row per active customer (is_current = 1)
============================================================================== */
CREATE OR ALTER VIEW dwh.v_dim_customer AS
SELECT
    customer_key,
    customer_id,
    signup_date,
    city,
    acquisition_channel,
    last_active,
    life_cycle_id,
    -- Dynamic Days Since Last Active (relative to query date)
    DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) AS days_since_last_active,
    -- Dynamic Churn Status (> 60 days inactivity)
    CASE 
        WHEN DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) > 60 THEN CAST(1 AS BIT)
        ELSE CAST(0 AS BIT)
    END AS is_churned,
    -- Dynamic Churned Date
    CASE 
        WHEN DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) > 60 
        THEN DATEADD(DAY, 60, COALESCE(last_active, signup_date))
        ELSE NULL
    END AS churned_date,
    -- Dynamic Last Status ID: 4 (Churned) if > 60 days, else retains transaction lifecycle (1: New, 2: Retained, 3: Reactivated)
    CASE 
        WHEN DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) > 60 THEN CAST(4 AS TINYINT)
        ELSE ISNULL(life_cycle_id, CAST(0 AS TINYINT))
    END AS last_status_id,
    -- Dynamic Churn Risk
    CASE 
        WHEN DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) > 60 THEN 'Churned'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) > 45 THEN 'High'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) > 30 THEN 'High'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) BETWEEN 20 AND 45 THEN 'Medium'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) BETWEEN 10 AND 30 THEN 'Medium'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) < 20 THEN 'Low'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, signup_date), CAST(GETDATE() AS DATE)) < 10 THEN 'Low'
        ELSE 'Undefined'
    END AS churn_risk,
    valid_from,
    valid_to,
    is_current,
    batch_id,
    load_timestamp
FROM dwh.dim_customer
WHERE customer_key <> -1 AND is_current = 1;
GO

/* ==============================================================================
   2. SERVING VIEW: dwh.v_dim_restaurant
   Consumes: dwh.dim_restaurant
   Grain   : 1 row per active restaurant (is_current = 1)
============================================================================== */
CREATE OR ALTER VIEW dwh.v_dim_restaurant AS
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
    DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) AS days_since_last_active,
    -- Dynamic Churn Status (> 60 days inactivity)
    CASE 
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 60 THEN CAST(1 AS BIT)
        ELSE CAST(0 AS BIT)
    END AS is_churned,
    -- Dynamic Churned Date
    CASE 
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 60 
        THEN DATEADD(DAY, 60, COALESCE(last_active, onboard_date))
        ELSE NULL
    END AS churned_date,
    -- Dynamic Last Status ID: 4 (Churned) if > 60 days, else retains transaction lifecycle (1: New, 2: Retained, 3: Reactivated)
    CASE 
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 60 THEN CAST(4 AS TINYINT)
        ELSE ISNULL(life_cycle_id, CAST(0 AS TINYINT))
    END AS last_status_id,
    -- Dynamic Churn Risk
    CASE 
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 60 THEN 'Churned'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 45 THEN 'High'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 21 THEN 'High'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) BETWEEN 15 AND 45 THEN 'Medium'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) BETWEEN 8 AND 21 THEN 'Medium'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) < 15 THEN 'Low'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) <= 7 THEN 'Low'
        ELSE 'Undefined'
    END AS churn_risk,
    valid_from,
    valid_to,
    is_current,
    batch_id,
    load_timestamp
FROM dwh.dim_restaurant
WHERE restaurant_key <> -1 AND is_current = 1;
GO

/* ==============================================================================
   3. SERVING VIEW: dwh.v_dim_delivery_partner
   Consumes: dwh.dim_delivery_partner
   Grain   : 1 row per active delivery partner (is_current = 1)
============================================================================== */
CREATE OR ALTER VIEW dwh.v_dim_delivery_partner AS
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
    DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) AS days_since_last_active,
    -- Dynamic Churn Status (> 30 days inactivity for drivers)
    CASE 
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 30 THEN CAST(1 AS BIT)
        ELSE CAST(0 AS BIT)
    END AS is_churned,
    -- Dynamic Churned Date
    CASE 
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 30 
        THEN DATEADD(DAY, 30, COALESCE(last_active, onboard_date))
        ELSE NULL
    END AS churned_date,
    -- Dynamic Last Status ID: 4 (Churned) if > 30 days, else retains transaction lifecycle (1: New, 2: Retained, 3: Reactivated)
    CASE 
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 30 THEN CAST(4 AS TINYINT)
        ELSE ISNULL(life_cycle_id, CAST(0 AS TINYINT))
    END AS last_status_id,
    -- Dynamic Churn Risk
    CASE 
        WHEN DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 30 THEN 'Churned'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 30 THEN 'High'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) > 15 THEN 'High'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) BETWEEN 15 AND 30 THEN 'Medium'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) BETWEEN 7 AND 15 THEN 'Medium'
        WHEN ISNULL(life_cycle_id, 0) = 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) < 15 THEN 'Low'
        WHEN ISNULL(life_cycle_id, 0) <> 2 AND DATEDIFF(DAY, COALESCE(last_active, onboard_date), CAST(GETDATE() AS DATE)) < 7 THEN 'Low'
        ELSE 'Undefined'
    END AS churn_risk,
    valid_from,
    valid_to,
    is_current,
    batch_id,
    load_timestamp
FROM dwh.dim_delivery_partner
WHERE delivery_partner_key <> -1 AND is_current = 1;
GO

/* ==============================================================================
   4. VERIFICATION
============================================================================== */
SELECT 
    s.name AS schema_name,
    v.name AS view_name,
    v.create_date,
    v.modify_date
FROM sys.views v
JOIN sys.schemas s ON v.schema_id = s.schema_id
WHERE s.name = 'dwh'
ORDER BY v.name;
GO
