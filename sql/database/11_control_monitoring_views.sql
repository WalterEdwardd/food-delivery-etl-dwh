USE FoodDeliveryDW;
GO

/* ==============================================================================
   QUICKBITE DATA PLATFORM
   Food Delivery ETL & Data Warehouse

   FILE    : sql/database/11_control_monitoring_views.sql
   PURPOSE : BI Serving Layer - Dedicated Pipeline Monitoring & Data Observability
   SCHEMA  : bi
   TARGET  : Power BI Monitoring Dashboard & Data Engineering Operations

   DESIGN PRINCIPLES:
   1. Decouples Power BI from direct queries to raw control tables.
   2. Pre-calculates durations, health statuses, SLAs, throughputs, and error rates.
   3. Ready for both DirectQuery (real-time ops) and Scheduled Import modes.
   4. Covers all 5 pillars of Data Observability: Freshness, Volume, Quality,
      Lineage/Reconciliation, and Performance Bottlenecks.
============================================================================== */

-- Ensure schema bi exists
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'bi')
BEGIN
    EXEC(N'CREATE SCHEMA bi');
END;
GO


/* ==============================================================================
   VIEW 1: bi.v_monitor_pipeline_overview
   PURPOSE: Executive overview of ETL batch runs, SLAs, and pipeline health
============================================================================== */
CREATE OR ALTER VIEW bi.v_monitor_pipeline_overview AS
SELECT
    b.batch_id,
    b.pipeline_name,
    ISNULL(b.source_system, 'QuickBite Ingestion Engine') AS source_system,
    ISNULL(b.source_file_count, 0) AS source_file_count,
    b.start_time,
    b.end_time,
    
    -- Duration metrics
    DATEDIFF(SECOND, b.start_time, ISNULL(b.end_time, SYSUTCDATETIME())) AS duration_seconds,
    ROUND(CAST(DATEDIFF(SECOND, b.start_time, ISNULL(b.end_time, SYSUTCDATETIME())) AS FLOAT) / 60.0, 2) AS duration_minutes,

    -- Batch status
    b.status AS batch_status,

    -- Volume metrics
    ISNULL(b.total_records, 0) AS total_records,
    ISNULL(b.success_records, 0) AS success_records,
    ISNULL(b.error_records, 0) AS error_records,

    -- Rates
    CASE 
        WHEN ISNULL(b.total_records, 0) > 0 
        THEN ROUND((CAST(b.success_records AS FLOAT) / b.total_records) * 100.0, 2)
        ELSE 100.0
    END AS success_rate_pct,

    CASE 
        WHEN ISNULL(b.total_records, 0) > 0 
        THEN ROUND((CAST(b.error_records AS FLOAT) / b.total_records) * 100.0, 2)
        ELSE 0.0
    END AS error_rate_pct,

    -- Flags & Observability SLAs
    CASE 
        WHEN b.batch_id = (SELECT MAX(batch_id) FROM control.etl_batch) 
        THEN CAST(1 AS BIT) 
        ELSE CAST(0 AS BIT) 
    END AS is_latest_batch,

    DATEDIFF(HOUR, b.start_time, SYSUTCDATETIME()) AS hours_since_run,

    -- Dynamic Health Categorization
    CASE 
        WHEN b.status = 'SUCCESS' AND DATEDIFF(HOUR, b.start_time, SYSUTCDATETIME()) <= 24 THEN 'Healthy'
        WHEN b.status = 'RUNNING' THEN 'Running'
        WHEN b.status = 'PARTIAL' THEN 'Degraded (Partial)'
        WHEN b.status = 'FAILED' THEN 'Critical (Failed)'
        ELSE 'Warning (Stale >24h)'
    END AS pipeline_health_status,

    b.created_at
FROM control.etl_batch AS b;
GO


/* ==============================================================================
   VIEW 2: bi.v_monitor_step_performance
   PURPOSE: Execution time and record throughput per ETL step (Bottleneck detection)
============================================================================== */
CREATE OR ALTER VIEW bi.v_monitor_step_performance AS
SELECT
    l.log_id,
    l.batch_id,
    b.pipeline_name,
    l.process_name,
    l.step_name,
    l.start_time,
    l.end_time,

    -- Duration metrics
    DATEDIFF(SECOND, l.start_time, ISNULL(l.end_time, l.start_time)) AS duration_seconds,
    ROUND(CAST(DATEDIFF(SECOND, l.start_time, ISNULL(l.end_time, l.start_time)) AS FLOAT) / 60.0, 3) AS duration_minutes,

    -- Step Status
    l.status AS step_status,

    -- Processed record metrics
    ISNULL(l.rows_processed, 0) AS rows_processed,
    ISNULL(l.rows_inserted, 0) AS rows_inserted,
    ISNULL(l.rows_rejected, 0) AS rows_rejected,

    -- Rejection Rate (%)
    CASE 
        WHEN ISNULL(l.rows_processed, 0) > 0 
        THEN ROUND((CAST(l.rows_rejected AS FLOAT) / l.rows_processed) * 100.0, 2)
        ELSE 0.0
    END AS rejection_rate_pct,

    -- Throughput (Rows/sec)
    CASE 
        WHEN DATEDIFF(SECOND, l.start_time, ISNULL(l.end_time, l.start_time)) > 0 
        THEN ROUND(CAST(ISNULL(l.rows_processed, 0) AS FLOAT) / DATEDIFF(SECOND, l.start_time, ISNULL(l.end_time, l.start_time)), 0)
        ELSE ISNULL(l.rows_processed, 0)
    END AS throughput_rows_per_sec,

    l.message,
    l.created_at
FROM control.etl_log AS l
INNER JOIN control.etl_batch AS b
    ON l.batch_id = b.batch_id;
GO


/* ==============================================================================
   VIEW 3: bi.v_monitor_data_quality_errors
   PURPOSE: Quarantined error records analysis by source, table, column, and type
============================================================================== */
CREATE OR ALTER VIEW bi.v_monitor_data_quality_errors AS
SELECT
    e.error_id,
    e.batch_id,
    b.pipeline_name,
    b.status AS batch_status,
    ISNULL(e.table_name, 'UNKNOWN') AS table_name,
    ISNULL(e.column_name, 'N/A') AS column_name,
    e.error_type,
    
    -- Error Categorization for Power BI visuals
    CASE 
        WHEN e.error_type = 'MASTER_DATA_NOT_FOUND' THEN 'Referential Integrity (Orphan Record)'
        WHEN e.error_type = 'INVALID_FORMAT' THEN 'Data Type & Format Incompatibility'
        WHEN e.error_type LIKE '%NULL%' THEN 'Mandatory Field Null Violation'
        WHEN e.error_type LIKE '%DUPLICATE%' THEN 'Duplicate Business Key Violation'
        WHEN e.error_type = 'FILE_VALIDATION_ERROR' THEN 'Source File Structure & Validation'
        ELSE 'Other Data Quality Anomaly'
    END AS error_category,

    e.error_message,
    e.raw_value,
    e.source_file_name,
    e.source_row_number,
    e.error_timestamp
FROM control.etl_error AS e
LEFT JOIN control.etl_batch AS b
    ON e.batch_id = b.batch_id;
GO


/* ==============================================================================
   VIEW 4: bi.v_monitor_warnings_anomalies
   PURPOSE: Operational warnings and orphan anomaly detections
============================================================================== */
CREATE OR ALTER VIEW bi.v_monitor_warnings_anomalies AS
SELECT
    w.warning_id,
    w.batch_id,
    b.pipeline_name,
    w.step_name,
    ISNULL(w.table_name, 'N/A') AS table_name,
    w.order_id,
    w.entity_name,
    w.entity_id,
    w.warning_type,
    w.warning_message,
    w.warning_timestamp
FROM control.etl_warning AS w
LEFT JOIN control.etl_batch AS b
    ON w.batch_id = b.batch_id;
GO


/* ==============================================================================
   VIEW 5: bi.v_monitor_layer_reconciliation
   PURPOSE: End-to-end data reconciliation (RAW -> ODS -> DWH) and discrepancy audit
============================================================================== */
CREATE OR ALTER VIEW bi.v_monitor_layer_reconciliation AS
WITH entity_metrics AS
(
    SELECT 
        'Customer' AS entity_name,
        (SELECT COUNT(*) FROM raw.raw_customer) AS raw_rows,
        (SELECT COUNT(*) FROM ods.ods_customer) AS ods_rows,
        (SELECT COUNT(*) FROM dwh.dim_customer WHERE customer_key <> -1) AS dwh_rows,
        (SELECT COUNT(*) FROM control.etl_error WHERE table_name = 'customer') AS error_rows,
        (SELECT COUNT(*) FROM control.etl_warning WHERE entity_name = 'CUSTOMER') AS warning_rows
    UNION ALL
    SELECT 
        'Restaurant' AS entity_name,
        (SELECT COUNT(*) FROM raw.raw_restaurant),
        (SELECT COUNT(*) FROM ods.ods_restaurant),
        (SELECT COUNT(*) FROM dwh.dim_restaurant WHERE restaurant_key <> -1),
        (SELECT COUNT(*) FROM control.etl_error WHERE table_name = 'restaurant'),
        (SELECT COUNT(*) FROM control.etl_warning WHERE entity_name = 'RESTAURANT')
    UNION ALL
    SELECT 
        'Delivery Partner' AS entity_name,
        (SELECT COUNT(*) FROM raw.raw_delivery_partner),
        (SELECT COUNT(*) FROM ods.ods_delivery_partner),
        (SELECT COUNT(*) FROM dwh.dim_delivery_partner WHERE delivery_partner_key <> -1),
        (SELECT COUNT(*) FROM control.etl_error WHERE table_name = 'delivery_partner'),
        (SELECT COUNT(*) FROM control.etl_warning WHERE entity_name = 'DELIVERY_PARTNER')
    UNION ALL
    SELECT 
        'Menu Item' AS entity_name,
        (SELECT COUNT(*) FROM raw.raw_menu_item),
        (SELECT COUNT(*) FROM ods.ods_menu_item),
        (SELECT COUNT(*) FROM dwh.dim_menu_item WHERE menu_item_key <> -1),
        (SELECT COUNT(*) FROM control.etl_error WHERE table_name = 'menu_item'),
        (SELECT COUNT(*) FROM control.etl_warning WHERE entity_name = 'MENU_ITEM')
    UNION ALL
    SELECT 
        'Order' AS entity_name,
        (SELECT COUNT(*) FROM raw.raw_order),
        (SELECT COUNT(*) FROM ods.ods_order),
        (SELECT COUNT(*) FROM dwh.fact_order),
        (SELECT COUNT(*) FROM control.etl_error WHERE table_name = 'raw_order'),
        (SELECT COUNT(*) FROM control.etl_warning WHERE entity_name = 'ORDER')
    UNION ALL
    SELECT 
        'Order Item' AS entity_name,
        (SELECT COUNT(*) FROM raw.raw_order_item),
        (SELECT COUNT(*) FROM ods.ods_order_item),
        (SELECT COUNT(*) FROM dwh.fact_order_item),
        (SELECT COUNT(*) FROM control.etl_error WHERE table_name = 'raw_order_item'),
        (SELECT COUNT(*) FROM control.etl_warning WHERE entity_name = 'ORDER_ITEM')
    UNION ALL
    SELECT 
        'Delivery Performance' AS entity_name,
        (SELECT COUNT(*) FROM raw.raw_delivery_performance),
        (SELECT COUNT(*) FROM ods.ods_delivery_performance),
        (SELECT COUNT(*) FROM dwh.fact_delivery_performance),
        (SELECT COUNT(*) FROM control.etl_error WHERE table_name = 'raw_delivery_performance'),
        (SELECT COUNT(*) FROM control.etl_warning WHERE entity_name = 'DELIVERY_PERFORMANCE')
    UNION ALL
    SELECT 
        'Rating' AS entity_name,
        (SELECT COUNT(*) FROM raw.raw_rating),
        (SELECT COUNT(*) FROM ods.ods_rating),
        (SELECT COUNT(*) FROM dwh.fact_rating),
        (SELECT COUNT(*) FROM control.etl_error WHERE table_name = 'raw_rating'),
        (SELECT COUNT(*) FROM control.etl_warning WHERE entity_name = 'RATING')
)
SELECT
    entity_name,
    raw_rows,
    ods_rows,
    dwh_rows,
    raw_rows - ods_rows AS raw_to_ods_variance,
    ods_rows - dwh_rows AS ods_to_dwh_variance,
    error_rows AS quarantined_error_rows,
    warning_rows,
    
    -- Data Retention Rate (%)
    CASE 
        WHEN raw_rows > 0 
        THEN ROUND((CAST(dwh_rows AS FLOAT) / raw_rows) * 100.0, 2)
        ELSE 100.0
    END AS data_retention_rate_pct,

    -- Reconciliation Audit Status
    CASE 
        WHEN (raw_rows - ods_rows = 0 OR error_rows > 0) AND (ods_rows - dwh_rows = 0) 
        THEN 'RECONCILED (Valid Audit)'
        ELSE 'VARIANCE DETECTED'
    END AS audit_status
FROM entity_metrics;
GO


/* ==============================================================================
   VIEW 6: bi.v_monitor_scd2_audit
   PURPOSE: SCD Type 2 dimension historical change audit trail
============================================================================== */
CREATE OR ALTER VIEW bi.v_monitor_scd2_audit AS
SELECT
    c.change_log_id,
    c.batch_id,
    b.pipeline_name,
    c.dimension_name,
    c.business_id,
    c.surrogate_key_old,
    c.surrogate_key_new,
    c.change_type,
    c.column_name,
    c.old_value,
    c.new_value,
    c.effective_date,
    c.logged_at
FROM control.dim_change_log AS c
LEFT JOIN control.etl_batch AS b
    ON c.batch_id = b.batch_id;
GO


/* ==============================================================================
   VERIFICATION QUERY
============================================================================== */
SELECT 
    s.name AS schema_name,
    v.name AS view_name,
    v.create_date,
    v.modify_date
FROM sys.views AS v
INNER JOIN sys.schemas AS s 
    ON v.schema_id = s.schema_id
WHERE s.name = 'bi' AND v.name LIKE 'v_monitor_%'
ORDER BY v.name;
GO
