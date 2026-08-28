/* =========================================================
   QUICKBITE DATA PLATFORM
   Food Delivery ETL & Data Warehouse

   PART 2 - SQL Server Database Setup

   Purpose:
   Create and validate the FoodDeliveryDW database
   used for the food delivery ETL and data warehouse project.

   Database : FoodDeliveryDW
   Platform : Microsoft SQL Server
   ========================================================= */


-- 1. CREATE DATABASE

IF DB_ID(N'FoodDeliveryDW') IS NULL
BEGIN
    CREATE DATABASE FoodDeliveryDW;
END;
GO


-- 2. VALIDATE DATABASE

SELECT
    name,
    database_id,
    state_desc,
    recovery_model_desc
FROM sys.databases
WHERE name = N'FoodDeliveryDW';
GO