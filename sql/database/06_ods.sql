/*
============================================================
PART 12.5 - ODS LAYER
Database : FoodDeliveryDW
Schema   : ods

Purpose:
    Create Operational Data Store tables.

Architecture:
    RAW
      ↓
    ODS
      ↓
    DWH

ODS responsibilities:
    - Typed data
    - Cleaned data
    - Standardized data
    - Validated data
    - Preserve source/business entity structure
    - Preserve audit and lineage metadata

IMPORTANT:
    ODS does NOT contain dimensional modeling.
    ODS does NOT contain business aggregations.
============================================================
*/

USE FoodDeliveryDW;
GO


/* =========================================================
   1. CREATE ODS SCHEMA
   ========================================================= */

IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = 'ods'
)
BEGIN
    EXEC('CREATE SCHEMA ods');
END;
GO


/* =========================================================
   2. ODS CUSTOMER
   ========================================================= */

DROP TABLE IF EXISTS ods.ods_customer;
GO

CREATE TABLE ods.ods_customer
(
    customer_id				VARCHAR(50)    NOT NULL,
    signup_date				DATE           NULL,
    city					VARCHAR(100)  NULL,
    acquisition_channel		VARCHAR(100)  NULL,

    batch_id             BIGINT        NOT NULL,
    source_file_name     VARCHAR(200)   NOT NULL,
    source_row_number    INT           NOT NULL,
    load_timestamp       DATETIME2(3)   NOT NULL
        CONSTRAINT DF_ods_customer_load_timestamp
        DEFAULT SYSUTCDATETIME()
);
GO


/* =========================================================
   3. ODS RESTAURANT
   ========================================================= */

DROP TABLE IF EXISTS ods.ods_restaurant;
GO

CREATE TABLE ods.ods_restaurant
(
    restaurant_id		VARCHAR(50)    NOT NULL,
    restaurant_name		VARCHAR(200)  NULL,
    city				VARCHAR(100)  NULL,
    cuisine_type		VARCHAR(100)  NULL,
    partner_type		VARCHAR(100)  NULL,
    avg_prep_time_min	INT            NULL,
    is_active			BIT            NULL,

    batch_id             BIGINT        NOT NULL,
    source_file_name     VARCHAR(200)   NOT NULL,
    source_row_number    INT           NOT NULL,
    load_timestamp       DATETIME2(3)   NOT NULL
        CONSTRAINT DF_ods_restaurant_load_timestamp
        DEFAULT SYSUTCDATETIME()
);
GO


/* =========================================================
   4. ODS MENU ITEM
   ========================================================= */

DROP TABLE IF EXISTS ods.ods_menu_item;
GO

CREATE TABLE ods.ods_menu_item
(
    menu_item_id		VARCHAR(50)     NOT NULL,
    restaurant_id		VARCHAR(50)     NOT NULL,
    item_name			VARCHAR(200)   NULL,
    category			VARCHAR(100)   NULL,
    is_veg				BIT             NULL,
    price				DECIMAL(18,2)   NULL,

    batch_id			BIGINT        NOT NULL,
    source_file_name	VARCHAR(200)   NOT NULL,
    source_row_number	INT           NOT NULL,
    load_timestamp		DATETIME2(3)   NOT NULL
        CONSTRAINT DF_ods_menu_item_load_timestamp
        DEFAULT SYSUTCDATETIME()
);
GO


/* =========================================================
   5. ODS DELIVERY PARTNER
   ========================================================= */

DROP TABLE IF EXISTS ods.ods_delivery_partner;
GO

CREATE TABLE ods.ods_delivery_partner
(
    delivery_partner_id	VARCHAR(50)     NOT NULL,
    partner_name		VARCHAR(200)   NULL,
    city				VARCHAR(100)   NULL,
    vehicle_type		VARCHAR(100)   NULL,
    employment_type		VARCHAR(100)   NULL,
    avg_rating			DECIMAL(5,2)    NULL,
    is_active			BIT             NULL,

    batch_id			BIGINT        NOT NULL,
    source_file_name	VARCHAR(200)   NOT NULL,
    source_row_number	INT           NOT NULL,
    load_timestamp		DATETIME2(3)   NOT NULL
        CONSTRAINT DF_ods_delivery_partner_load_timestamp
        DEFAULT SYSUTCDATETIME()
);
GO


/* =========================================================
   6. ODS ORDER
   ========================================================= */

DROP TABLE IF EXISTS ods.ods_order;
GO

CREATE TABLE ods.ods_order
(
    order_id             VARCHAR(50)     NOT NULL,
    customer_id          VARCHAR(50)     NOT NULL,
    restaurant_id        VARCHAR(50)     NOT NULL,
    delivery_partner_id  VARCHAR(50)     NULL,

    order_timestamp      DATETIME2(3)    NULL,

    subtotal_amount      DECIMAL(18,2)   NULL,
    discount_amount      DECIMAL(18,2)   NULL,
    delivery_fee         DECIMAL(18,2)   NULL,
    total_amount         DECIMAL(18,2)   NULL,

    is_cod               BIT             NULL,
    is_cancelled         BIT             NULL,

    batch_id             BIGINT        NOT NULL,
    source_file_name     VARCHAR(200)   NOT NULL,
    source_row_number    INT           NOT NULL,
    load_timestamp       DATETIME2(3)   NOT NULL
        CONSTRAINT DF_ods_order_load_timestamp
        DEFAULT SYSUTCDATETIME()
);
GO


/* =========================================================
   7. ODS ORDER ITEM
   ========================================================= */

DROP TABLE IF EXISTS ods.ods_order_item;
GO

CREATE TABLE ods.ods_order_item
(
    order_line_id		VARCHAR(50)     NOT NULL,
    order_id			VARCHAR(50)     NOT NULL,
    menu_item_id		VARCHAR(50)     NOT NULL,
    restaurant_id		VARCHAR(50)     NOT NULL,

    quantity			INT             NULL,

    unit_price			DECIMAL(18,2)   NULL,
    item_discount		DECIMAL(18,2)   NULL,
    line_total			DECIMAL(18,2)   NULL,

    batch_id			BIGINT        NOT NULL,
    source_file_name	VARCHAR(200)   NOT NULL,
    source_row_number	INT           NOT NULL,
    load_timestamp		DATETIME2(3)   NOT NULL
        CONSTRAINT DF_ods_order_item_load_timestamp
        DEFAULT SYSUTCDATETIME()
);
GO


/* =========================================================
   8. ODS DELIVERY PERFORMANCE
   ========================================================= */

DROP TABLE IF EXISTS ods.ods_delivery_performance;
GO

CREATE TABLE ods.ods_delivery_performance
(
    delivery_id						VARCHAR(50)    NOT NULL,
    order_id						VARCHAR(50)    NOT NULL,

    order_item						INT            NULL,
    expected_delivery_time_min		INT            NULL,
    actual_delivery_time_min		INT            NULL,
    delivery_item					INT            NULL,

    distance_km						DECIMAL(10,2)  NULL,

    batch_id						BIGINT        NOT NULL,
    source_file_name				VARCHAR(200)   NOT NULL,
    source_row_number				INT           NOT NULL,
    load_timestamp					DATETIME2(3)   NOT NULL
        CONSTRAINT DF_ods_delivery_performance_load_timestamp
        DEFAULT SYSUTCDATETIME()
);
GO


/* =========================================================
   9. ODS RATING
   ========================================================= */

DROP TABLE IF EXISTS ods.ods_rating;
GO

CREATE TABLE ods.ods_rating
(
    rating_id			VARCHAR(50)     NOT NULL,
    order_id			VARCHAR(50)     NOT NULL,
    customer_id			VARCHAR(50)     NOT NULL,
    restaurant_id		VARCHAR(50)     NOT NULL,

    rating				DECIMAL(3,2)    NULL,
    review_text			VARCHAR(2000)  NULL,
    review_timestamp	DATETIME2(3)    NULL,
    sentiment_score		DECIMAL(5,4)    NULL,

    batch_id			BIGINT        NOT NULL,
    source_file_name	VARCHAR(200)   NOT NULL,
    source_row_number	INT           NOT NULL,
    load_timestamp		DATETIME2(3)   NOT NULL
        CONSTRAINT DF_ods_rating_load_timestamp
        DEFAULT SYSUTCDATETIME()
);
GO


/* =========================================================
   10. VERIFICATION
   ========================================================= */

SELECT
    s.name AS schema_name,
    t.name AS table_name
FROM sys.tables t
JOIN sys.schemas s
    ON t.schema_id = s.schema_id
WHERE s.name = 'ods'
ORDER BY t.name;
GO


/* =========================================================
   11. TABLE ROW COUNT
   ========================================================= */

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    SUM(p.rows) AS row_count
FROM sys.tables t
JOIN sys.schemas s
    ON t.schema_id = s.schema_id
JOIN sys.partitions p
    ON t.object_id = p.object_id
WHERE s.name = 'ods'
  AND p.index_id IN (0, 1)
GROUP BY
    s.name,
    t.name
ORDER BY
    t.name;
GO