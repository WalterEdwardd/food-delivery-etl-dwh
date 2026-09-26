/* =========================================================
   QUICKBITE DATA PLATFORM
   Food Delivery ETL & Data Warehouse

   PART 12.6 - TEMPORARY ODS TABLES & CONSTRAINTS SETUP
   Database : FoodDeliveryDW
   Schemas  : ods, temp
   Platform : Microsoft SQL Server

   Purpose  :
   1. Create Primary Key & Index constraints on main ODS tables to optimize MERGE.
   2. Create staging tables under schema 'temp' to support Incremental Load (Upsert).
   ========================================================= */

USE FoodDeliveryDW;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO


/* =========================================================
   1. ODS CUSTOMER
   ========================================================= */

-- 1.1 Primary Key & Index on ods.ods_customer
IF NOT EXISTS (
    SELECT 1 FROM sys.key_constraints 
    WHERE [type] = 'PK' AND parent_object_id = OBJECT_ID('ods.ods_customer')
)
BEGIN
    ALTER TABLE ods.ods_customer
    ADD CONSTRAINT PK_ods_customer PRIMARY KEY CLUSTERED (customer_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = ON);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_ods_customer_batch_id' AND object_id = OBJECT_ID('ods.ods_customer')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_ods_customer_batch_id 
    ON ods.ods_customer(batch_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = ON);
END;
GO

-- 1.2 Temp Table: temp.ods_customer
DROP TABLE IF EXISTS temp.ods_customer;
GO

CREATE TABLE temp.ods_customer
(
    customer_id         VARCHAR(50)   NOT NULL,
    signup_date         DATE          NULL,
    city                VARCHAR(100)  NULL,
    acquisition_channel VARCHAR(100)  NULL,

    batch_id            BIGINT        NOT NULL,
    source_file_name    VARCHAR(200)  NOT NULL,
    source_row_number   INT           NOT NULL,
    load_timestamp      DATETIME2(3)  NOT NULL
        CONSTRAINT DF_temp_ods_customer_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_temp_ods_customer PRIMARY KEY CLUSTERED (customer_id)
);
GO


/* =========================================================
   2. ODS RESTAURANT
   ========================================================= */

-- 2.1 Primary Key & Index on ods.ods_restaurant
IF NOT EXISTS (
    SELECT 1 FROM sys.key_constraints 
    WHERE [type] = 'PK' AND parent_object_id = OBJECT_ID('ods.ods_restaurant')
)
BEGIN
    ALTER TABLE ods.ods_restaurant
    ADD CONSTRAINT PK_ods_restaurant PRIMARY KEY CLUSTERED (restaurant_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = ON);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_ods_restaurant_batch_id' AND object_id = OBJECT_ID('ods.ods_restaurant')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_ods_restaurant_batch_id 
    ON ods.ods_restaurant(batch_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = ON);
END;
GO

-- 2.2 Temp Table: temp.ods_restaurant
DROP TABLE IF EXISTS temp.ods_restaurant;
GO

CREATE TABLE temp.ods_restaurant
(
    restaurant_id       VARCHAR(50)   NOT NULL,
    restaurant_name     VARCHAR(200)  NULL,
    city                VARCHAR(100)  NULL,
    cuisine_type        VARCHAR(100)  NULL,
    partner_type        VARCHAR(100)  NULL,
    avg_prep_time_min   VARCHAR(50)   NULL,
    is_active           BIT           NULL,

    batch_id            BIGINT        NOT NULL,
    source_file_name    VARCHAR(200)  NOT NULL,
    source_row_number   INT           NOT NULL,
    load_timestamp      DATETIME2(3)  NOT NULL
        CONSTRAINT DF_temp_ods_restaurant_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_temp_ods_restaurant PRIMARY KEY CLUSTERED (restaurant_id)
);
GO


/* =========================================================
   3. ODS MENU ITEM
   ========================================================= */

-- 3.1 Primary Key & Index on ods.ods_menu_item
IF NOT EXISTS (
    SELECT 1 FROM sys.key_constraints 
    WHERE [type] = 'PK' AND parent_object_id = OBJECT_ID('ods.ods_menu_item')
)
BEGIN
    ALTER TABLE ods.ods_menu_item
    ADD CONSTRAINT PK_ods_menu_item PRIMARY KEY CLUSTERED (menu_item_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = ON);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_ods_menu_item_batch_id' AND object_id = OBJECT_ID('ods.ods_menu_item')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_ods_menu_item_batch_id 
    ON ods.ods_menu_item(batch_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = ON);
END;
GO

-- 3.2 Temp Table: temp.ods_menu_item
DROP TABLE IF EXISTS temp.ods_menu_item;
GO

CREATE TABLE temp.ods_menu_item
(
    menu_item_id        VARCHAR(50)    NOT NULL,
    restaurant_id       VARCHAR(50)    NOT NULL,
    item_name           VARCHAR(200)   NULL,
    category            VARCHAR(100)   NULL,
    is_veg              BIT            NULL,
    price               DECIMAL(18,2)  NULL,

    batch_id            BIGINT         NOT NULL,
    source_file_name    VARCHAR(200)   NOT NULL,
    source_row_number   INT            NOT NULL,
    load_timestamp      DATETIME2(3)   NOT NULL
        CONSTRAINT DF_temp_ods_menu_item_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_temp_ods_menu_item PRIMARY KEY CLUSTERED (menu_item_id)
);
GO


/* =========================================================
   4. ODS DELIVERY PARTNER
   ========================================================= */

-- 4.1 Primary Key & Index on ods.ods_delivery_partner
IF NOT EXISTS (
    SELECT 1 FROM sys.key_constraints 
    WHERE [type] = 'PK' AND parent_object_id = OBJECT_ID('ods.ods_delivery_partner')
)
BEGIN
    ALTER TABLE ods.ods_delivery_partner
    ADD CONSTRAINT PK_ods_delivery_partner PRIMARY KEY CLUSTERED (delivery_partner_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = ON);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_ods_delivery_partner_batch_id' AND object_id = OBJECT_ID('ods.ods_delivery_partner')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_ods_delivery_partner_batch_id 
    ON ods.ods_delivery_partner(batch_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = ON);
END;
GO

-- 4.2 Temp Table: temp.ods_delivery_partner
DROP TABLE IF EXISTS temp.ods_delivery_partner;
GO

CREATE TABLE temp.ods_delivery_partner
(
    delivery_partner_id VARCHAR(50)    NOT NULL,
    partner_name        VARCHAR(200)   NULL,
    city                VARCHAR(100)   NULL,
    vehicle_type        VARCHAR(100)   NULL,
    employment_type     VARCHAR(100)   NULL,
    avg_rating          DECIMAL(5,2)   NULL,
    is_active           BIT            NULL,

    batch_id            BIGINT         NOT NULL,
    source_file_name    VARCHAR(200)   NOT NULL,
    source_row_number   INT            NOT NULL,
    load_timestamp      DATETIME2(3)   NOT NULL
        CONSTRAINT DF_temp_ods_delivery_partner_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_temp_ods_delivery_partner PRIMARY KEY CLUSTERED (delivery_partner_id)
);
GO


/* =========================================================
   5. ODS ORDER
   ========================================================= */

-- 5.1 Primary Key & Index on ods.ods_order
IF NOT EXISTS (
    SELECT 1 FROM sys.key_constraints 
    WHERE [type] = 'PK' AND parent_object_id = OBJECT_ID('ods.ods_order')
)
BEGIN
    ALTER TABLE ods.ods_order
    ADD CONSTRAINT PK_ods_order PRIMARY KEY CLUSTERED (order_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = ON);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_ods_order_batch_id' AND object_id = OBJECT_ID('ods.ods_order')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_ods_order_batch_id 
    ON ods.ods_order(batch_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = ON);
END;
GO

-- 5.2 Temp Table: temp.ods_order
DROP TABLE IF EXISTS temp.ods_order;
GO

CREATE TABLE temp.ods_order
(
    order_id             VARCHAR(50)    NOT NULL,
    customer_id          VARCHAR(50)    NOT NULL,
    restaurant_id        VARCHAR(50)    NOT NULL,
    delivery_partner_id  VARCHAR(50)    NULL,

    order_timestamp      DATETIME2(3)   NULL,

    subtotal_amount      DECIMAL(18,2)  NULL,
    discount_amount      DECIMAL(18,2)  NULL,
    delivery_fee         DECIMAL(18,2)  NULL,
    total_amount         DECIMAL(18,2)  NULL,

    is_cod               BIT            NULL,
    is_cancelled         BIT            NULL,

    batch_id             BIGINT         NOT NULL,
    source_file_name     VARCHAR(200)   NOT NULL,
    source_row_number    INT            NOT NULL,
    load_timestamp       DATETIME2(3)   NOT NULL
        CONSTRAINT DF_temp_ods_order_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_temp_ods_order PRIMARY KEY CLUSTERED (order_id)
);
GO


/* =========================================================
   6. ODS ORDER ITEM
   ========================================================= */

-- 6.1 Primary Key & Index on ods.ods_order_item
IF NOT EXISTS (
    SELECT 1 FROM sys.key_constraints 
    WHERE [type] = 'PK' AND parent_object_id = OBJECT_ID('ods.ods_order_item')
)
BEGIN
    ALTER TABLE ods.ods_order_item
    ADD CONSTRAINT PK_ods_order_item PRIMARY KEY CLUSTERED (order_line_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = ON);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_ods_order_item_batch_id' AND object_id = OBJECT_ID('ods.ods_order_item')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_ods_order_item_batch_id 
    ON ods.ods_order_item(batch_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = ON);
END;
GO

-- 6.2 Temp Table: temp.ods_order_item
DROP TABLE IF EXISTS temp.ods_order_item;
GO

CREATE TABLE temp.ods_order_item
(
    order_line_id       VARCHAR(50)    NOT NULL,
    order_id            VARCHAR(50)    NOT NULL,
    menu_item_id        VARCHAR(50)    NOT NULL,

    quantity            INT            NULL,

    unit_price          DECIMAL(18,2)  NULL,
    item_discount       DECIMAL(18,2)  NULL,
    line_total          DECIMAL(18,2)  NULL,

    batch_id            BIGINT         NOT NULL,
    source_file_name    VARCHAR(200)   NOT NULL,
    source_row_number   INT            NOT NULL,
    load_timestamp      DATETIME2(3)   NOT NULL
        CONSTRAINT DF_temp_ods_order_item_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_temp_ods_order_item PRIMARY KEY CLUSTERED (order_line_id)
);
GO


/* =========================================================
   7. ODS DELIVERY PERFORMANCE
   ========================================================= */

-- 7.1 Primary Key & Index on ods.ods_delivery_performance
IF NOT EXISTS (
    SELECT 1 FROM sys.key_constraints 
    WHERE [type] = 'PK' AND parent_object_id = OBJECT_ID('ods.ods_delivery_performance')
)
BEGIN
    ALTER TABLE ods.ods_delivery_performance
    ADD CONSTRAINT PK_ods_delivery_performance PRIMARY KEY CLUSTERED (delivery_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = ON);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_ods_delivery_performance_batch_id' AND object_id = OBJECT_ID('ods.ods_delivery_performance')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_ods_delivery_performance_batch_id 
    ON ods.ods_delivery_performance(batch_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = ON);
END;
GO

-- 7.2 Temp Table: temp.ods_delivery_performance
DROP TABLE IF EXISTS temp.ods_delivery_performance;
GO

CREATE TABLE temp.ods_delivery_performance
(
    delivery_id                 VARCHAR(50)    NOT NULL,
    order_id                    VARCHAR(50)    NOT NULL,

    order_item                  INT            NULL,
    expected_delivery_time_min  INT            NULL,
    actual_delivery_time_min    INT            NULL,
    delivery_item               INT            NULL,

    distance_km                 DECIMAL(10,2)  NULL,

    batch_id                    BIGINT         NOT NULL,
    source_file_name            VARCHAR(200)   NOT NULL,
    source_row_number           INT            NOT NULL,
    load_timestamp              DATETIME2(3)   NOT NULL
        CONSTRAINT DF_temp_ods_delivery_performance_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_temp_ods_delivery_performance PRIMARY KEY CLUSTERED (delivery_id)
);
GO


/* =========================================================
   8. ODS RATING
   ========================================================= */

-- 8.1 Primary Key & Index on ods.ods_rating
IF NOT EXISTS (
    SELECT 1 FROM sys.key_constraints 
    WHERE [type] = 'PK' AND parent_object_id = OBJECT_ID('ods.ods_rating')
)
BEGIN
    ALTER TABLE ods.ods_rating
    ADD CONSTRAINT PK_ods_rating PRIMARY KEY CLUSTERED (rating_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = ON);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_ods_rating_batch_id' AND object_id = OBJECT_ID('ods.ods_rating')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_ods_rating_batch_id 
    ON ods.ods_rating(batch_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = ON);
END;
GO

-- 8.2 Temp Table: temp.ods_rating
DROP TABLE IF EXISTS temp.ods_rating;
GO

CREATE TABLE temp.ods_rating
(
    rating_id           VARCHAR(50)    NOT NULL,
    order_id            VARCHAR(50)    NOT NULL,
    customer_id         VARCHAR(50)    NOT NULL,
    restaurant_id       VARCHAR(50)    NOT NULL,

    rating              DECIMAL(3,2)   NULL,
    review_text         VARCHAR(2000)  NULL,
    review_timestamp    DATETIME2(3)   NULL,
    sentiment_score     DECIMAL(5,4)   NULL,

    batch_id            BIGINT         NOT NULL,
    source_file_name    VARCHAR(200)   NOT NULL,
    source_row_number   INT            NOT NULL,
    load_timestamp      DATETIME2(3)   NOT NULL
        CONSTRAINT DF_temp_ods_rating_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_temp_ods_rating PRIMARY KEY CLUSTERED (rating_id)
);
GO


/* =========================================================
   9. VERIFICATION
   ========================================================= */

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    k.name AS pk_name
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id
LEFT JOIN sys.key_constraints k ON t.object_id = k.parent_object_id AND k.[type] = 'PK'
WHERE s.name IN ('ods', 'temp')
ORDER BY s.name, t.name;
GO
