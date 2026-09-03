/* =========================================================
   QUICKBITE DATA PLATFORM
   Food Delivery ETL & Data Warehouse

   PART 2 - SQL Server Database Setup

   Purpose:
   Create and validate the database schemas
   used for the food delivery ETL and data warehouse project.

   Database : FoodDeliveryDW
   Platform : Microsoft SQL Server
   ========================================================= */


-- 1. CHECK DATABASE

USE FoodDeliveryDW;
GO

SELECT
    DB_NAME() AS current_database;
GO


-- 2. CREATE SCHEMAS

IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = N'stg'
)
BEGIN
    EXEC(N'CREATE SCHEMA stg');
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = N'raw'
)
BEGIN
    EXEC(N'CREATE SCHEMA raw');
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = N'ods'
)
BEGIN
    EXEC(N'CREATE SCHEMA ods');
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = N'dwh'
)
BEGIN
    EXEC(N'CREATE SCHEMA dwh');
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = N'mart'
)
BEGIN
    EXEC(N'CREATE SCHEMA mart');
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = N'control'
)
BEGIN
    EXEC(N'CREATE SCHEMA control');
END;
GO


-- 3. VERIFY SCHEMAS

USE FoodDeliveryDW;
GO

SELECT
    schema_id,
    name
FROM sys.schemas
WHERE name IN
(
    N'stg',
    N'raw',
    N'ods',
    N'dwh',
    N'mart',
    N'control'
)
ORDER BY
    name;
GO


-- 4. CHECK DATABASE OBJECTS

USE FoodDeliveryDW;
GO

SELECT
    s.name AS schema_name,
    COUNT(o.object_id) AS object_count
FROM sys.schemas AS s
LEFT JOIN sys.objects AS o
    ON s.schema_id = o.schema_id
WHERE s.name IN
(
    N'stg',
    N'raw',
    N'ods',
    N'dwh',
    N'mart',
    N'control'
)
GROUP BY
    s.name
ORDER BY
    s.name;
GO