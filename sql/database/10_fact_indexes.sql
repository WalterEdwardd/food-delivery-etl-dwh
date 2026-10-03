/* ==============================================================================
   QUICKBITE DATA PLATFORM
   Food Delivery ETL & Data Warehouse

   PERFORMANCE OPTIMIZATION: FOREIGN KEY NON-CLUSTERED INDEXES
   
   Database : FoodDeliveryDW
   Schema   : dwh
   File     : sql/database/10_fact_indexes.sql
   Purpose  : Create non-clustered indexes on all Foreign Key and relationship
              columns across all DWH Fact tables to accelerate Star Schema JOINs,
              serving view aggregations, and Power BI analytical queries.
============================================================================== */

USE FoodDeliveryDW;
GO

PRINT '==============================================================================';
PRINT 'CREATING NON-CLUSTERED INDEXES ON FACT TABLES (FOREIGN KEYS & RELATIONSHIPS)';
PRINT '==============================================================================';

/* ------------------------------------------------------------------------------
   1. FACT ORDER INDEXES
------------------------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_order_order_date_key' AND object_id = OBJECT_ID('dwh.fact_order'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_order_order_date_key
        ON dwh.fact_order (order_date_key);
    PRINT '  - Created IX_fact_order_order_date_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_order_order_time_key' AND object_id = OBJECT_ID('dwh.fact_order'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_order_order_time_key
        ON dwh.fact_order (order_time_key);
    PRINT '  - Created IX_fact_order_order_time_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_order_customer_key' AND object_id = OBJECT_ID('dwh.fact_order'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_order_customer_key
        ON dwh.fact_order (customer_key);
    PRINT '  - Created IX_fact_order_customer_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_order_restaurant_key' AND object_id = OBJECT_ID('dwh.fact_order'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_order_restaurant_key
        ON dwh.fact_order (restaurant_key);
    PRINT '  - Created IX_fact_order_restaurant_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_order_delivery_partner_key' AND object_id = OBJECT_ID('dwh.fact_order'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_order_delivery_partner_key
        ON dwh.fact_order (delivery_partner_key);
    PRINT '  - Created IX_fact_order_delivery_partner_key';
END;


/* ------------------------------------------------------------------------------
   2. FACT ORDER ITEM INDEXES
------------------------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_order_item_order_date_key' AND object_id = OBJECT_ID('dwh.fact_order_item'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_order_item_order_date_key
        ON dwh.fact_order_item (order_date_key);
    PRINT '  - Created IX_fact_order_item_order_date_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_order_item_customer_key' AND object_id = OBJECT_ID('dwh.fact_order_item'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_order_item_customer_key
        ON dwh.fact_order_item (customer_key);
    PRINT '  - Created IX_fact_order_item_customer_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_order_item_restaurant_key' AND object_id = OBJECT_ID('dwh.fact_order_item'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_order_item_restaurant_key
        ON dwh.fact_order_item (restaurant_key);
    PRINT '  - Created IX_fact_order_item_restaurant_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_order_item_menu_item_key' AND object_id = OBJECT_ID('dwh.fact_order_item'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_order_item_menu_item_key
        ON dwh.fact_order_item (menu_item_key);
    PRINT '  - Created IX_fact_order_item_menu_item_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_order_item_order_id' AND object_id = OBJECT_ID('dwh.fact_order_item'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_order_item_order_id
        ON dwh.fact_order_item (order_id);
    PRINT '  - Created IX_fact_order_item_order_id';
END;


/* ------------------------------------------------------------------------------
   3. FACT DELIVERY PERFORMANCE INDEXES
------------------------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_delivery_performance_delivery_date_key' AND object_id = OBJECT_ID('dwh.fact_delivery_performance'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_delivery_performance_delivery_date_key
        ON dwh.fact_delivery_performance (delivery_date_key);
    PRINT '  - Created IX_fact_delivery_performance_delivery_date_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_delivery_performance_customer_key' AND object_id = OBJECT_ID('dwh.fact_delivery_performance'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_delivery_performance_customer_key
        ON dwh.fact_delivery_performance (customer_key);
    PRINT '  - Created IX_fact_delivery_performance_customer_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_delivery_performance_restaurant_key' AND object_id = OBJECT_ID('dwh.fact_delivery_performance'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_delivery_performance_restaurant_key
        ON dwh.fact_delivery_performance (restaurant_key);
    PRINT '  - Created IX_fact_delivery_performance_restaurant_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_delivery_performance_delivery_partner_key' AND object_id = OBJECT_ID('dwh.fact_delivery_performance'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_delivery_performance_delivery_partner_key
        ON dwh.fact_delivery_performance (delivery_partner_key);
    PRINT '  - Created IX_fact_delivery_performance_delivery_partner_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_delivery_performance_order_id' AND object_id = OBJECT_ID('dwh.fact_delivery_performance'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_delivery_performance_order_id
        ON dwh.fact_delivery_performance (order_id);
    PRINT '  - Created IX_fact_delivery_performance_order_id';
END;


/* ------------------------------------------------------------------------------
   4. FACT RATING INDEXES
------------------------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_rating_rating_date_key' AND object_id = OBJECT_ID('dwh.fact_rating'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_rating_rating_date_key
        ON dwh.fact_rating (rating_date_key);
    PRINT '  - Created IX_fact_rating_rating_date_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_rating_rating_time_key' AND object_id = OBJECT_ID('dwh.fact_rating'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_rating_rating_time_key
        ON dwh.fact_rating (rating_time_key);
    PRINT '  - Created IX_fact_rating_rating_time_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_rating_customer_key' AND object_id = OBJECT_ID('dwh.fact_rating'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_rating_customer_key
        ON dwh.fact_rating (customer_key);
    PRINT '  - Created IX_fact_rating_customer_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_rating_restaurant_key' AND object_id = OBJECT_ID('dwh.fact_rating'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_rating_restaurant_key
        ON dwh.fact_rating (restaurant_key);
    PRINT '  - Created IX_fact_rating_restaurant_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_rating_delivery_partner_key' AND object_id = OBJECT_ID('dwh.fact_rating'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_rating_delivery_partner_key
        ON dwh.fact_rating (delivery_partner_key);
    PRINT '  - Created IX_fact_rating_delivery_partner_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_rating_rating_type_id' AND object_id = OBJECT_ID('dwh.fact_rating'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_rating_rating_type_id
        ON dwh.fact_rating (rating_type_id);
    PRINT '  - Created IX_fact_rating_rating_type_id';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_rating_sentiment_type_id' AND object_id = OBJECT_ID('dwh.fact_rating'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_rating_sentiment_type_id
        ON dwh.fact_rating (sentiment_type_id);
    PRINT '  - Created IX_fact_rating_sentiment_type_id';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_rating_order_id' AND object_id = OBJECT_ID('dwh.fact_rating'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_rating_order_id
        ON dwh.fact_rating (order_id);
    PRINT '  - Created IX_fact_rating_order_id';
END;


/* ------------------------------------------------------------------------------
   5. FACT REVIEW ASPECT ADDITIONAL INDEXES
------------------------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_review_aspect_rating_key' AND object_id = OBJECT_ID('dwh.fact_review_aspect'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_review_aspect_rating_key
        ON dwh.fact_review_aspect (rating_key);
    PRINT '  - Created IX_fact_review_aspect_rating_key';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_review_aspect_aspect_id' AND object_id = OBJECT_ID('dwh.fact_review_aspect'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_review_aspect_aspect_id
        ON dwh.fact_review_aspect (aspect_id);
    PRINT '  - Created IX_fact_review_aspect_aspect_id';
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_review_aspect_sentiment_type_id' AND object_id = OBJECT_ID('dwh.fact_review_aspect'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_fact_review_aspect_sentiment_type_id
        ON dwh.fact_review_aspect (sentiment_type_id);
    PRINT '  - Created IX_fact_review_aspect_sentiment_type_id';
END;

PRINT '==============================================================================';
PRINT '[SUCCESS] All Fact Table Foreign Key Non-Clustered Indexes Created!';
PRINT '==============================================================================';
GO
