/* =========================================================
   QUICKBITE DATA PLATFORM
   Food Delivery ETL & Data Warehouse

   PART 4 - STAGING LAYER SETUP

   Purpose:
   Create and validate the STG tables
   used for source data ingestion.

   Database : FoodDeliveryDW
   Schema   : stg
   Platform : Microsoft SQL Server
   ========================================================= */


-- 1. CHECK DATABASE

USE FoodDeliveryDW;
GO

SELECT
    DB_NAME() AS current_database;
GO


-- 2. CREATE STAGING TABLES

-- 2.1 STG CUSTOMER

DROP TABLE IF EXISTS stg.stg_customer;
CREATE TABLE stg.stg_customer
    (
        customer_id            VARCHAR(100),
        signup_date            VARCHAR(50),
        city                   VARCHAR(100),
        acquisition_channel    VARCHAR(100),

        batch_id               BIGINT,
        source_file_name       VARCHAR(200),
        source_row_number      INT,
        load_timestamp         DATETIME2(3)
    );
GO


-- 2.2 STG RESTAURANT

DROP TABLE IF EXISTS stg.stg_restaurant;
CREATE TABLE stg.stg_restaurant
    (
        restaurant_id          VARCHAR(100),
        restaurant_name        VARCHAR(200),
        city                   VARCHAR(100),
        cuisine_type           VARCHAR(100),
        partner_type           VARCHAR(100),
        avg_prep_time_min      VARCHAR(50),
        is_active              VARCHAR(50),

        batch_id               BIGINT,
        source_file_name       VARCHAR(200),
        source_row_number      INT,
        load_timestamp         DATETIME2(3)
    );
GO


-- 2.3 STG MENU ITEM

DROP TABLE IF EXISTS stg.stg_menu_item;
CREATE TABLE stg.stg_menu_item
    (
        menu_item_id           VARCHAR(100),
        restaurant_id          VARCHAR(100),
        item_name              VARCHAR(200),
        category               VARCHAR(100),
        is_veg                 VARCHAR(50),
        price                  VARCHAR(100),

        batch_id               BIGINT,
        source_file_name       VARCHAR(200),
        source_row_number      INT,
        load_timestamp         DATETIME2(3)
    );
GO


-- 2.4 STG DELIVERY PARTNER

DROP TABLE IF EXISTS stg.stg_delivery_partner;
CREATE TABLE stg.stg_delivery_partner
    (
        delivery_partner_id    VARCHAR(100),
        partner_name           VARCHAR(200),
        city                   VARCHAR(100),
        vehicle_type           VARCHAR(100),
        employment_type        VARCHAR(100),
        avg_rating             VARCHAR(50),
        is_active              VARCHAR(50),

        batch_id               BIGINT,
        source_file_name       VARCHAR(200),
        source_row_number      INT,
        load_timestamp         DATETIME2(3)
    );
GO


-- 2.5 STG ORDER

DROP TABLE IF EXISTS stg.stg_order;
CREATE TABLE stg.stg_order
    (
        order_id               VARCHAR(100),
        customer_id            VARCHAR(100),
        restaurant_id          VARCHAR(100),
        delivery_partner_id    VARCHAR(100),
        order_timestamp        VARCHAR(100),
        subtotal_amount        VARCHAR(100),
        discount_amount        VARCHAR(100),
        delivery_fee           VARCHAR(100),
        total_amount            VARCHAR(100),
        is_cod                 VARCHAR(50),
        is_cancelled           VARCHAR(50),

        batch_id               BIGINT,
        source_file_name       VARCHAR(200),
        source_row_number      INT,
        load_timestamp         DATETIME2(3)
    );
GO


-- 2.6 STG ORDER ITEM

DROP TABLE IF EXISTS stg.stg_order_item;
CREATE TABLE stg.stg_order_item
    (
        order_line_id          VARCHAR(100),
        order_id               VARCHAR(100),
        menu_item_id           VARCHAR(100),
        restaurant_id          VARCHAR(100),
        quantity               VARCHAR(100),
        unit_price             VARCHAR(100),
        item_discount          VARCHAR(100),
        line_total             VARCHAR(100),

        batch_id               BIGINT,
        source_file_name       VARCHAR(200),
        source_row_number      INT,
        load_timestamp          DATETIME2(3)
    );
GO


-- 2.7 STG DELIVERY PERFORMANCE

DROP TABLE IF EXISTS stg.stg_delivery_performance;
CREATE TABLE stg.stg_delivery_performance
    (
        delivery_id                    VARCHAR(100),
        order_id                       VARCHAR(100),
        order_item                     VARCHAR(100),
        delivery_item                  VARCHAR(100),
        expected_delivery_time_min     VARCHAR(100),
        actual_delivery_time_min       VARCHAR(100),
        distance_km                    VARCHAR(100),

        batch_id                       BIGINT,
        source_file_name               VARCHAR(200),
        source_row_number              INT,
        load_timestamp                 DATETIME2(3)
    );
GO


-- 2.8 STG RATING

DROP TABLE IF EXISTS stg.stg_rating;
CREATE TABLE stg.stg_rating
    (
        rating_id				VARCHAR(100),
        order_id				VARCHAR(100),
        customer_id				VARCHAR(100),
        restaurant_id			VARCHAR(100),
		rating					VARCHAR(50),
        sentiment_score			VARCHAR(50),
        review_text				VARCHAR(MAX),
        review_timestamp		VARCHAR(100),

        batch_id				BIGINT,
        source_file_name		VARCHAR(200),
        source_row_number		INT,
        load_timestamp			DATETIME2(3)
    );
GO


-- 3. VALIDATE STAGING TABLES

USE FoodDeliveryDW;
GO

-- 3.1 Validate STG table existence

SELECT
    s.name AS schema_name,
    t.name AS table_name
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'stg'
ORDER BY
    t.name;
GO


-- 3.2 Verify column count for each STG table

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    COUNT(*) AS column_count
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
INNER JOIN sys.columns AS c
    ON t.object_id = c.object_id
WHERE s.name = N'stg'
GROUP BY
    s.name,
    t.name
ORDER BY
    t.name;
GO


-- 3.3 Verify column name, column order, column data types, and nullability

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    c.column_id,
    c.name AS column_name,
    ty.name AS data_type,
    c.max_length,
    c.precision,
    c.scale,
    CASE
        WHEN c.is_nullable = 1 THEN 'YES'
        ELSE 'NO'
    END AS is_nullable
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
INNER JOIN sys.columns AS c
    ON t.object_id = c.object_id
INNER JOIN sys.types AS ty
    ON c.user_type_id = ty.user_type_id
WHERE s.name = N'stg'
ORDER BY
    t.name,
    c.column_id;
GO