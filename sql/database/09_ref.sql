/* =========================================================
   Food Delivery ETL & Data Warehouse

   PART 6 - REFERENCE LAYER SETUP

   Purpose:
       Create and validate the REFERENCE tables
       used for standardizing business reference data.

   Database : FoodDeliveryDW
   Schema   : ref
   Platform : Microsoft SQL Server

   Reference Tables:
       1. ref_city
       2. ref_acquisition_channel
       3. ref_vehicle_type
       4. ref_employment_type
       5. ref_category
       6. ref_cuisine_type
       7. ref_partner_type
   ========================================================= */


/* =========================================================
   1. CHECK DATABASE
   ========================================================= */

USE FoodDeliveryDW;
GO

SELECT
    DB_NAME() AS current_database;
GO


/* =========================================================
   2. VERIFY REFERENCE SCHEMA
   ========================================================= */

SELECT
    name AS schema_name
FROM sys.schemas
WHERE name = N'ref';
GO


/* =========================================================
   3. CREATE REFERENCE TABLES
   ========================================================= */


/* ---------------------------------------------------------
   3.1 REFERENCE CITY
   --------------------------------------------------------- */

DROP TABLE IF EXISTS ref.ref_city;
GO

CREATE TABLE ref.ref_city
(
    city_code VARCHAR(100) NOT NULL,
    city_name VARCHAR(100) NOT NULL,
    is_active BIT NOT NULL
        CONSTRAINT DF_ref_city_is_active DEFAULT 1,

    CONSTRAINT PK_ref_city
        PRIMARY KEY (city_code),

    CONSTRAINT UQ_ref_city_city_name
        UNIQUE (city_name)
);
GO


/* ---------------------------------------------------------
   3.2 REFERENCE ACQUISITION CHANNEL
   --------------------------------------------------------- */

DROP TABLE IF EXISTS ref.ref_acquisition_channel;
GO

CREATE TABLE ref.ref_acquisition_channel
(
    acquisition_channel_code VARCHAR(100) NOT NULL,
    acquisition_channel_name VARCHAR(100) NOT NULL,
    is_active BIT NOT NULL
        CONSTRAINT DF_ref_acquisition_channel_is_active DEFAULT 1,

    CONSTRAINT PK_ref_acquisition_channel
        PRIMARY KEY (acquisition_channel_code),

    CONSTRAINT UQ_ref_acquisition_channel_name
        UNIQUE (acquisition_channel_name)
);
GO


/* ---------------------------------------------------------
   3.3 REFERENCE VEHICLE TYPE
   --------------------------------------------------------- */

DROP TABLE IF EXISTS ref.ref_vehicle_type;
GO

CREATE TABLE ref.ref_vehicle_type
(
    vehicle_type_code VARCHAR(100) NOT NULL,
    vehicle_type_name VARCHAR(100) NOT NULL,
    is_active BIT NOT NULL
        CONSTRAINT DF_ref_vehicle_type_is_active DEFAULT 1,

    CONSTRAINT PK_ref_vehicle_type
        PRIMARY KEY (vehicle_type_code),

    CONSTRAINT UQ_ref_vehicle_type_name
        UNIQUE (vehicle_type_name)
);
GO


/* ---------------------------------------------------------
   3.4 REFERENCE EMPLOYMENT TYPE
   --------------------------------------------------------- */

DROP TABLE IF EXISTS ref.ref_employment_type;
GO

CREATE TABLE ref.ref_employment_type
(
    employment_type_code VARCHAR(100) NOT NULL,
    employment_type_name VARCHAR(100) NOT NULL,
    is_active BIT NOT NULL
        CONSTRAINT DF_ref_employment_type_is_active DEFAULT 1,

    CONSTRAINT PK_ref_employment_type
        PRIMARY KEY (employment_type_code),

    CONSTRAINT UQ_ref_employment_type_name
        UNIQUE (employment_type_name)
);
GO


/* ---------------------------------------------------------
   3.5 REFERENCE CATEGORY
   --------------------------------------------------------- */

DROP TABLE IF EXISTS ref.ref_category;
GO

CREATE TABLE ref.ref_category
(
    category_code VARCHAR(100) NOT NULL,
    category_name VARCHAR(100) NOT NULL,
    is_active BIT NOT NULL
        CONSTRAINT DF_ref_category_is_active DEFAULT 1,

    CONSTRAINT PK_ref_category
        PRIMARY KEY (category_code),

    CONSTRAINT UQ_ref_category_name
        UNIQUE (category_name)
);
GO


/* ---------------------------------------------------------
   3.6 REFERENCE CUISINE TYPE
   --------------------------------------------------------- */

DROP TABLE IF EXISTS ref.ref_cuisine_type;
GO

CREATE TABLE ref.ref_cuisine_type
(
    cuisine_type_code VARCHAR(100) NOT NULL,
    cuisine_type_name VARCHAR(100) NOT NULL,
    is_active BIT NOT NULL
        CONSTRAINT DF_ref_cuisine_type_is_active DEFAULT 1,

    CONSTRAINT PK_ref_cuisine_type
        PRIMARY KEY (cuisine_type_code),

    CONSTRAINT UQ_ref_cuisine_type_name
        UNIQUE (cuisine_type_name)
);
GO


/* ---------------------------------------------------------
   3.7 REFERENCE PARTNER TYPE
   --------------------------------------------------------- */

DROP TABLE IF EXISTS ref.ref_partner_type;
GO

CREATE TABLE ref.ref_partner_type
(
    partner_type_code VARCHAR(100) NOT NULL,
    partner_type_name VARCHAR(100) NOT NULL,
    is_active BIT NOT NULL
        CONSTRAINT DF_ref_partner_type_is_active DEFAULT 1,

    CONSTRAINT PK_ref_partner_type
        PRIMARY KEY (partner_type_code),

    CONSTRAINT UQ_ref_partner_type_name
        UNIQUE (partner_type_name)
);
GO


/* =========================================================
   4. VERIFY REFERENCE TABLES
   ========================================================= */


/* ---------------------------------------------------------
   4.1 VERIFY TABLE EXISTENCE
   --------------------------------------------------------- */

SELECT
    s.name AS schema_name,
    t.name AS table_name
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'ref'
ORDER BY
    t.name;
GO


/* ---------------------------------------------------------
   4.2 VERIFY EXPECTED TABLE COUNT
   --------------------------------------------------------- */

SELECT
    COUNT(*) AS actual_table_count,
    7 AS expected_table_count,
    CASE
        WHEN COUNT(*) = 7 THEN 'PASS'
        ELSE 'FAIL'
    END AS validation_status
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'ref';
GO


/* ---------------------------------------------------------
   4.3 VERIFY TABLE STRUCTURE
   --------------------------------------------------------- */

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    c.column_id,
    c.name AS column_name,
    ty.name AS data_type,
    CASE
        WHEN ty.name IN ('varchar', 'char', 'nvarchar', 'nchar')
            THEN c.max_length
        ELSE NULL
    END AS max_length,
    c.is_nullable,
    c.is_identity
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
INNER JOIN sys.columns AS c
    ON t.object_id = c.object_id
INNER JOIN sys.types AS ty
    ON c.user_type_id = ty.user_type_id
WHERE s.name = N'ref'
ORDER BY
    t.name,
    c.column_id;
GO


/* ---------------------------------------------------------
   4.4 VERIFY PRIMARY KEYS
   --------------------------------------------------------- */

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    kc.name AS constraint_name,
    c.name AS column_name
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
INNER JOIN sys.key_constraints AS kc
    ON t.object_id = kc.parent_object_id
INNER JOIN sys.index_columns AS ic
    ON kc.parent_object_id = ic.object_id
    AND kc.unique_index_id = ic.index_id
INNER JOIN sys.columns AS c
    ON ic.object_id = c.object_id
    AND ic.column_id = c.column_id
WHERE s.name = N'ref'
    AND kc.type = 'PK'
ORDER BY
    t.name;
GO


/* ---------------------------------------------------------
   4.5 VERIFY UNIQUE CONSTRAINTS
   --------------------------------------------------------- */

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    kc.name AS constraint_name,
    c.name AS column_name
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
INNER JOIN sys.key_constraints AS kc
    ON t.object_id = kc.parent_object_id
INNER JOIN sys.index_columns AS ic
    ON kc.parent_object_id = ic.object_id
    AND kc.unique_index_id = ic.index_id
INNER JOIN sys.columns AS c
    ON ic.object_id = c.object_id
    AND ic.column_id = c.column_id
WHERE s.name = N'ref'
    AND kc.type = 'UQ'
ORDER BY
    t.name;
GO


/* ---------------------------------------------------------
   4.6 VERIFY DEFAULT CONSTRAINTS
   --------------------------------------------------------- */

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    c.name AS column_name,
    dc.name AS default_constraint_name,
    dc.definition AS default_definition
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
INNER JOIN sys.columns AS c
    ON t.object_id = c.object_id
INNER JOIN sys.default_constraints AS dc
    ON c.object_id = dc.parent_object_id
    AND c.column_id = dc.parent_column_id
WHERE s.name = N'ref'
ORDER BY
    t.name,
    c.column_id;
GO


/* ---------------------------------------------------------
   4.7 VERIFY NULLABILITY
   --------------------------------------------------------- */

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    c.name AS column_name,
    c.is_nullable
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
INNER JOIN sys.columns AS c
    ON t.object_id = c.object_id
WHERE s.name = N'ref'
ORDER BY
    t.name,
    c.column_id;
GO


/* ---------------------------------------------------------
   4.8 VERIFY IS_ACTIVE COLUMN
   --------------------------------------------------------- */

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    c.name AS column_name,
    ty.name AS data_type,
    c.is_nullable
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
INNER JOIN sys.columns AS c
    ON t.object_id = c.object_id
INNER JOIN sys.types AS ty
    ON c.user_type_id = ty.user_type_id
WHERE s.name = N'ref'
    AND c.name = N'is_active'
ORDER BY
    t.name;
GO


/* =========================================================
   5. VALIDATION SUMMARY
   ========================================================= */


/* ---------------------------------------------------------
   5.1 VALIDATE REQUIRED REFERENCE TABLES
   --------------------------------------------------------- */

SELECT
    v.expected_table_name,
    CASE
        WHEN t.object_id IS NOT NULL THEN 'PASS'
        ELSE 'FAIL'
    END AS validation_status
FROM
(
    VALUES
        ('ref_city'),
        ('ref_acquisition_channel'),
        ('ref_vehicle_type'),
        ('ref_employment_type'),
        ('ref_category'),
        ('ref_cuisine_type'),
        ('ref_partner_type')
) AS v(expected_table_name)
LEFT JOIN sys.tables AS t
    ON t.name = v.expected_table_name
LEFT JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
    AND s.name = N'ref'
ORDER BY
    v.expected_table_name;
GO


/* ---------------------------------------------------------
   5.2 VALIDATE PRIMARY KEY COUNT
   --------------------------------------------------------- */

SELECT
    COUNT(*) AS primary_key_count,
    7 AS expected_primary_key_count,
    CASE
        WHEN COUNT(*) = 7 THEN 'PASS'
        ELSE 'FAIL'
    END AS validation_status
FROM sys.key_constraints AS kc
INNER JOIN sys.tables AS t
    ON kc.parent_object_id = t.object_id
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'ref'
    AND kc.type = 'PK';
GO


/* ---------------------------------------------------------
   5.3 VALIDATE UNIQUE CONSTRAINT COUNT
   --------------------------------------------------------- */

SELECT
    COUNT(*) AS unique_constraint_count,
    7 AS expected_unique_constraint_count,
    CASE
        WHEN COUNT(*) = 7 THEN 'PASS'
        ELSE 'FAIL'
    END AS validation_status
FROM sys.key_constraints AS kc
INNER JOIN sys.tables AS t
    ON kc.parent_object_id = t.object_id
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'ref'
    AND kc.type = 'UQ';
GO


/* ---------------------------------------------------------
   5.4 VALIDATE DEFAULT CONSTRAINT COUNT
   --------------------------------------------------------- */

SELECT
    COUNT(*) AS default_constraint_count,
    7 AS expected_default_constraint_count,
    CASE
        WHEN COUNT(*) = 7 THEN 'PASS'
        ELSE 'FAIL'
    END AS validation_status
FROM sys.default_constraints AS dc
INNER JOIN sys.tables AS t
    ON dc.parent_object_id = t.object_id
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'ref';
GO


/* =========================================================
   6. VERIFY REFERENCE DATA
   ========================================================= */


/* ---------------------------------------------------------
   6.1 CHECK CURRENT ROW COUNTS
   --------------------------------------------------------- */

SELECT
    'ref_city' AS table_name,
    COUNT(*) AS row_count
FROM ref.ref_city

UNION ALL

SELECT
    'ref_acquisition_channel',
    COUNT(*)
FROM ref.ref_acquisition_channel

UNION ALL

SELECT
    'ref_vehicle_type',
    COUNT(*)
FROM ref.ref_vehicle_type

UNION ALL

SELECT
    'ref_employment_type',
    COUNT(*)
FROM ref.ref_employment_type

UNION ALL

SELECT
    'ref_category',
    COUNT(*)
FROM ref.ref_category

UNION ALL

SELECT
    'ref_cuisine_type',
    COUNT(*)
FROM ref.ref_cuisine_type

UNION ALL

SELECT
    'ref_partner_type',
    COUNT(*)
FROM ref.ref_partner_type

ORDER BY
    table_name;
GO


/* ---------------------------------------------------------
   6.2 CHECK ACTIVE / INACTIVE DISTRIBUTION
   --------------------------------------------------------- */

SELECT
    'ref_city' AS table_name,
    is_active,
    COUNT(*) AS row_count
FROM ref.ref_city
GROUP BY is_active

UNION ALL

SELECT
    'ref_acquisition_channel',
    is_active,
    COUNT(*)
FROM ref.ref_acquisition_channel
GROUP BY is_active

UNION ALL

SELECT
    'ref_vehicle_type',
    is_active,
    COUNT(*)
FROM ref.ref_vehicle_type
GROUP BY is_active

UNION ALL

SELECT
    'ref_employment_type',
    is_active,
    COUNT(*)
FROM ref.ref_employment_type
GROUP BY is_active

UNION ALL

SELECT
    'ref_category',
    is_active,
    COUNT(*)
FROM ref.ref_category
GROUP BY is_active

UNION ALL

SELECT
    'ref_cuisine_type',
    is_active,
    COUNT(*)
FROM ref.ref_cuisine_type
GROUP BY is_active

UNION ALL

SELECT
    'ref_partner_type',
    is_active,
    COUNT(*)
FROM ref.ref_partner_type
GROUP BY is_active

ORDER BY
    table_name,
    is_active;
GO


/* =========================================================
   7. FINAL STATUS
   ========================================================= */

SELECT
    'PART 6 - REFERENCE LAYER SETUP' AS validation_scope,
    'REFERENCE TABLE STRUCTURE CREATED AND VALIDATED' AS status,
    GETDATE() AS validation_timestamp;
GO
