/* =========================================================
   QUICKBITE DATA PLATFORM
   Food Delivery ETL & Data Warehouse

   PART 5 - RAW LAYER SETUP

   Purpose:
   Create and validate the RAW tables
   used for raw source data ingestion.

   Database : FoodDeliveryDW
   Schema   : raw
   Platform : Microsoft SQL Server
   ========================================================= */


-- 1. CHECK DATABASE

USE FoodDeliveryDW;
GO

SELECT
    DB_NAME() AS current_database;
GO

SET NOCOUNT ON;
GO


-- 2. CREATE RAW TABLES

-- 2.1 RAW CUSTOMER

IF OBJECT_ID(N'raw.raw_customer', N'U') IS NULL
BEGIN
    CREATE TABLE raw.raw_customer
    (
        customer_id           VARCHAR(100) NULL,
        signup_date           VARCHAR(50) NULL,
        city                  VARCHAR(100) NULL,
        acquisition_channel   VARCHAR(100) NULL,

        batch_id              BIGINT NOT NULL,
        source_file_name      VARCHAR(200) NOT NULL,
        source_row_number     INT NOT NULL,
        load_timestamp         DATETIME2(3) NOT NULL
            CONSTRAINT DF_raw_customer_load_timestamp
            DEFAULT SYSUTCDATETIME()
    );
END;
GO


-- 2.2 RAW RESTAURANT

IF OBJECT_ID(N'raw.raw_restaurant', N'U') IS NULL
BEGIN
    CREATE TABLE raw.raw_restaurant
    (
        restaurant_id        VARCHAR(100) NULL,
        restaurant_name      VARCHAR(200) NULL,
        city                 VARCHAR(100) NULL,
        cuisine_type         VARCHAR(100) NULL,
        partner_type         VARCHAR(100) NULL,
        avg_prep_time_min    VARCHAR(50) NULL,
        is_active             VARCHAR(50) NULL,

        batch_id              BIGINT NOT NULL,
        source_file_name      VARCHAR(200) NOT NULL,
        source_row_number     INT NOT NULL,
        load_timestamp         DATETIME2(3) NOT NULL
            CONSTRAINT DF_raw_restaurant_load_timestamp
            DEFAULT SYSUTCDATETIME()
    );
END;
GO


-- 2.3 RAW MENU ITEM

IF OBJECT_ID(N'raw.raw_menu_item', N'U') IS NULL
BEGIN
    CREATE TABLE raw.raw_menu_item
    (
        menu_item_id          VARCHAR(100) NULL,
        restaurant_id         VARCHAR(100) NULL,
        item_name             VARCHAR(200) NULL,
        category              VARCHAR(100) NULL,
        is_veg                VARCHAR(50) NULL,
        price                 VARCHAR(100) NULL,

        batch_id              BIGINT NOT NULL,
        source_file_name      VARCHAR(200) NOT NULL,
        source_row_number     INT NOT NULL,
        load_timestamp         DATETIME2(3) NOT NULL
            CONSTRAINT DF_raw_menu_item_load_timestamp
            DEFAULT SYSUTCDATETIME()
    );
END;
GO


-- 2.4 RAW DELIVERY PARTNER

IF OBJECT_ID(N'raw.raw_delivery_partner', N'U') IS NULL
BEGIN
    CREATE TABLE raw.raw_delivery_partner
    (
        delivery_partner_id   VARCHAR(100) NULL,
        partner_name          VARCHAR(200) NULL,
        city                  VARCHAR(100) NULL,
        vehicle_type          VARCHAR(100) NULL,
        employment_type       VARCHAR(100) NULL,
        avg_rating            VARCHAR(50) NULL,
        is_active              VARCHAR(50) NULL,

        batch_id              BIGINT NOT NULL,
        source_file_name      VARCHAR(200) NOT NULL,
        source_row_number     INT NOT NULL,
        load_timestamp         DATETIME2(3) NOT NULL
            CONSTRAINT DF_raw_delivery_partner_load_timestamp
            DEFAULT SYSUTCDATETIME()
    );
END;
GO


-- 2.5 RAW ORDER

IF OBJECT_ID(N'raw.raw_order', N'U') IS NULL
BEGIN
    CREATE TABLE raw.raw_order
    (
        order_id               VARCHAR(100) NULL,
        customer_id            VARCHAR(100) NULL,
        restaurant_id          VARCHAR(100) NULL,
        delivery_partner_id    VARCHAR(100) NULL,
        order_timestamp        VARCHAR(100) NULL,
        subtotal_amount        VARCHAR(100) NULL,
        discount_amount        VARCHAR(100) NULL,
        delivery_fee           VARCHAR(100) NULL,
        total_amount           VARCHAR(100) NULL,
        is_cod                 VARCHAR(50) NULL,
        is_cancelled           VARCHAR(50) NULL,

        batch_id               BIGINT NOT NULL,
        source_file_name       VARCHAR(200) NOT NULL,
        source_row_number      INT NOT NULL,
        load_timestamp         DATETIME2(3) NOT NULL
            CONSTRAINT DF_raw_order_load_timestamp
            DEFAULT SYSUTCDATETIME()
    );
END;
GO


-- 2.6 RAW ORDER ITEM

IF OBJECT_ID(N'raw.raw_order_item', N'U') IS NULL
BEGIN
    CREATE TABLE raw.raw_order_item
    (
        order_line_id          VARCHAR(100) NULL,
        order_id               VARCHAR(100) NULL,
        menu_item_id           VARCHAR(100) NULL,
        restaurant_id          VARCHAR(100) NULL,
        quantity               VARCHAR(100) NULL,
        unit_price             VARCHAR(100) NULL,
        item_discount          VARCHAR(100) NULL,
        line_total             VARCHAR(100) NULL,

        batch_id               BIGINT NOT NULL,
        source_file_name       VARCHAR(200) NOT NULL,
        source_row_number      INT NOT NULL,
        load_timestamp         DATETIME2(3) NOT NULL
            CONSTRAINT DF_raw_order_item_load_timestamp
            DEFAULT SYSUTCDATETIME()
    );
END;
GO


-- 2.7 RAW DELIVERY PERFORMANCE

IF OBJECT_ID(N'raw.raw_delivery_performance', N'U') IS NULL
BEGIN
    CREATE TABLE raw.raw_delivery_performance
    (
        delivery_id                    VARCHAR(100) NULL,
        order_id                       VARCHAR(100) NULL,
        order_item                     VARCHAR(100) NULL,
        expected_delivery_time_min     VARCHAR(100) NULL,
        actual_delivery_time_min       VARCHAR(100) NULL,
        delivery_item                  VARCHAR(100) NULL,
        distance_km                    VARCHAR(100) NULL,

        batch_id                       BIGINT NOT NULL,
        source_file_name               VARCHAR(200) NOT NULL,
        source_row_number              INT NOT NULL,
        load_timestamp                 DATETIME2(3) NOT NULL
            CONSTRAINT DF_raw_delivery_performance_load_timestamp
            DEFAULT SYSUTCDATETIME()
    );
END;
GO


-- 2.8 RAW RATING

IF OBJECT_ID(N'raw.raw_rating', N'U') IS NULL
BEGIN
    CREATE TABLE raw.raw_rating
    (
        rating_id            VARCHAR(100) NULL,
        order_id             VARCHAR(100) NULL,
        customer_id          VARCHAR(100) NULL,
        restaurant_id        VARCHAR(100) NULL,
        rating               VARCHAR(50) NULL,
        review_text          VARCHAR(MAX) NULL,
        review_timestamp     VARCHAR(100) NULL,
        sentiment_score      VARCHAR(50) NULL,

        batch_id             BIGINT NOT NULL,
        source_file_name     VARCHAR(200) NOT NULL,
        source_row_number    INT NOT NULL,
        load_timestamp        DATETIME2(3) NOT NULL
            CONSTRAINT DF_raw_rating_load_timestamp
            DEFAULT SYSUTCDATETIME()
    );
END;
GO


-- 3. VALIDATE RAW TABLES

USE FoodDeliveryDW;
GO


-- 3.1 Validate RAW table existence

SELECT
    s.name AS schema_name,
    t.name AS table_name
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'raw'
ORDER BY
    t.name;
GO


-- 3.2 Verify column count for each RAW table

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    COUNT(*) AS column_count
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
INNER JOIN sys.columns AS c
    ON t.object_id = c.object_id
WHERE s.name = N'raw'
GROUP BY
    s.name,
    t.name
ORDER BY
    t.name;
GO


-- 3.3 Verify column name, column order,
-- data types, length, precision,
-- scale, and nullability

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    c.column_id,
    c.name AS column_name,
    ty.name AS data_type,
	CASE
		WHEN ty.name IN (N'varchar', N'char', N'varbinary', N'binary')
			THEN c.max_length
		ELSE NULL
	END AS max_length,
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
WHERE s.name = N'raw'
ORDER BY
    t.name,
    c.column_id;
GO


-- 3.4 Verify RAW metadata columns

SELECT
    t.name AS table_name,
	c.column_id,
    c.name AS column_name,
    ty.name AS data_type,
	c.max_length,
	c.precision,
	c.scale,
    c.is_nullable
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
INNER JOIN sys.columns AS c
    ON t.object_id = c.object_id
INNER JOIN sys.types AS ty
    ON c.user_type_id = ty.user_type_id
WHERE s.name = N'raw'
  AND c.name IN
  (
      N'batch_id',
      N'source_file_name',
      N'source_row_number',
      N'load_timestamp'
  )
ORDER BY
    t.name,
    c.column_id;
GO


-- 3.5 Verify RAW tables have no data

SELECT 'raw_customer' AS table_name, COUNT(*) AS row_count
FROM raw.raw_customer

UNION ALL

SELECT 'raw_restaurant', COUNT(*)
FROM raw.raw_restaurant

UNION ALL

SELECT 'raw_menu_item', COUNT(*)
FROM raw.raw_menu_item

UNION ALL

SELECT 'raw_delivery_partner', COUNT(*)
FROM raw.raw_delivery_partner

UNION ALL

SELECT 'raw_order', COUNT(*)
FROM raw.raw_order

UNION ALL

SELECT 'raw_order_item', COUNT(*)
FROM raw.raw_order_item

UNION ALL

SELECT 'raw_delivery_performance', COUNT(*)
FROM raw.raw_delivery_performance

UNION ALL

SELECT 'raw_rating', COUNT(*)
FROM raw.raw_rating;
GO


-- 3.6 Verify RAW naming convention

SELECT
    s.name AS schema_name,
    t.name AS table_name
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'raw'
  AND t.name NOT LIKE N'raw[_]%'
ORDER BY t.name;
GO


-- 3.7 Verify DEFAULT constraints

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    c.name AS column_name,
    dc.name AS constraint_name,
    dc.definition AS default_definition
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
INNER JOIN sys.columns AS c
    ON t.object_id = c.object_id
INNER JOIN sys.default_constraints AS dc
    ON c.default_object_id = dc.object_id
WHERE s.name = N'raw'
ORDER BY
    t.name,
    c.column_id;
GO


-- 3.8 Verify RAW metadata structure

SELECT
    t.name AS table_name,
    CASE
        WHEN
			MAX(
				CASE
					WHEN c.name = N'batch_id'
					AND ty.name = N'bigint'
					AND c.is_nullable = 0
					THEN 1
					ELSE 0
				END
			) = 1

         AND MAX(
				CASE
					WHEN c.name = N'source_file_name'
					AND ty.name = N'varchar'
					AND c.max_length = 200
					AND c.is_nullable = 0
					THEN 1
					ELSE 0
				END
			) = 1

		AND MAX(
				CASE
					WHEN c.name = N'source_row_number'
					AND ty.name = N'int'
					AND c.is_nullable = 0
					THEN 1
					ELSE 0
				END
			) = 1

		AND MAX(
				CASE
					WHEN c.name = N'load_timestamp'
					AND ty.name = N'dateitme2'
					AND c.is_nullable = 0
					THEN 1
					ELSE 0
				END
			) = 1

        THEN 'PASS'
        ELSE 'FAIL'
    END AS metadata_validation
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
INNER JOIN sys.columns AS c
    ON t.object_id = c.object_id
INNER JOIN sys.types AS ty
    ON c.user_type_id = ty.user_type_id
WHERE s.name = N'raw'
GROUP BY
    t.name
ORDER BY
    t.name;
GO