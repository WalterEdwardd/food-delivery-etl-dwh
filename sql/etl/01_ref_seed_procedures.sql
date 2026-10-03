/*
================================================================================
PROJECT : Food Delivery ETL & Data Warehouse
FILE    : 01_ref_seed_procedures.sql
PURPOSE : Production Stored Procedure to Seed & Synchronize Reference Data (ref.*)
DATABASE: FoodDeliveryDW
SCHEMA  : ref
PLATFORM: Microsoft SQL Server 2019+
================================================================================
ARCHITECTURE & DESIGN PRINCIPLES:
================================================================================
1. Zero External Dependency:
   - Replaces SSIS package 01_Load_Master.dtsx and Excel source files.
   - Eliminates Microsoft Access Database Engine (ACE OLEDB 32/64-bit) driver conflicts.
   - Self-contained T-SQL script ready for CI/CD, migration runners, and SQL Agent Jobs.

2. Idempotency (Replayability):
   - Uses set-based MERGE statements with change detection.
   - Running the procedure multiple times produces identical, error-free results.
   - Inserts new entries, updates existing entries if attributes change, preserves unchanged.

3. Granular Transaction & Error Handling:
   - Wrapped in TRY...CATCH with BEGIN TRANSACTION / COMMIT / ROLLBACK.
   - Captures detailed merge actions (INSERTED, UPDATED) for audit reporting.
   - Prints clear execution metrics and validation summary.

4. Reference Tables Seeded (7 Master Tables):
   - ref.ref_city                 (20 records)
   - ref.ref_acquisition_channel  (5 records)
   - ref.ref_vehicle_type         (10 records)
   - ref.ref_employment_type      (3 records)
   - ref.ref_category             (24 records)
   - ref.ref_cuisine_type         (14 records)
   - ref.ref_partner_type         (3 records)
================================================================================
*/

USE FoodDeliveryDW;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO


/* ==============================================================================
   STORED PROCEDURE: ref.usp_seed_reference_data
============================================================================== */

CREATE OR ALTER PROCEDURE ref.usp_seed_reference_data
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @start_time DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @merge_results TABLE
    (
        table_name  VARCHAR(50),
        action_type VARCHAR(10)
    );

    PRINT '====================================================================';
    PRINT 'STARTING REFERENCE DATA SEEDING: ref.usp_seed_reference_data';
    PRINT 'Timestamp (UTC): ' + CONVERT(VARCHAR(30), @start_time, 120);
    PRINT '====================================================================';

    BEGIN TRY
        BEGIN TRANSACTION;

        /* ----------------------------------------------------------------------
           1. SEED: ref.ref_city (20 rows)
        ---------------------------------------------------------------------- */
        PRINT '--> Seeding ref.ref_city...';

        MERGE ref.ref_city AS target
        USING
        (
            VALUES
                ('AHMEDABAD',     'Ahmedabad',     1),
                ('BENGALURU',     'Bengaluru',     1),
                ('BHOPAL',        'Bhopal',        1),
                ('CHANDIGARH',    'Chandigarh',    1),
                ('CHENNAI',       'Chennai',       1),
                ('COIMBATORE',    'Coimbatore',    1),
                ('DELHI',         'Delhi',         1),
                ('GURUGRAM',      'Gurugram',      1),
                ('HYDERABAD',     'Hyderabad',     1),
                ('INDORE',        'Indore',        1),
                ('JAIPUR',        'Jaipur',        1),
                ('KOCHI',         'Kochi',         1),
                ('KOLKATA',       'Kolkata',       1),
                ('LUCKNOW',       'Lucknow',       1),
                ('MUMBAI',        'Mumbai',        1),
                ('NAGPUR',        'Nagpur',        1),
                ('NOIDA',         'Noida',         1),
                ('PUNE',          'Pune',          1),
                ('SURAT',         'Surat',         1),
                ('VISAKHAPATNAM', 'Visakhapatnam', 1)
        ) AS source (city_code, city_name, is_active)
        ON (target.city_code = source.city_code)
        WHEN MATCHED AND
        (
            target.city_name <> source.city_name
            OR target.is_active <> source.is_active
        )
        THEN
            UPDATE SET
                target.city_name  = source.city_name,
                target.is_active  = source.is_active
        WHEN NOT MATCHED BY TARGET
        THEN
            INSERT (city_code, city_name, is_active)
            VALUES (source.city_code, source.city_name, source.is_active)
        OUTPUT 'ref_city', $action INTO @merge_results (table_name, action_type);


        /* ----------------------------------------------------------------------
           2. SEED: ref.ref_acquisition_channel (5 rows)
        ---------------------------------------------------------------------- */
        PRINT '--> Seeding ref.ref_acquisition_channel...';

        MERGE ref.ref_acquisition_channel AS target
        USING
        (
            VALUES
                ('DIRECT',   'Direct',   1),
                ('ORGANIC',  'Organic',  1),
                ('PAID',     'Paid',     1),
                ('REFERRAL', 'Referral', 1),
                ('SOCIAL',   'Social',   1)
        ) AS source (acquisition_channel_code, acquisition_channel_name, is_active)
        ON (target.acquisition_channel_code = source.acquisition_channel_code)
        WHEN MATCHED AND
        (
            target.acquisition_channel_name <> source.acquisition_channel_name
            OR target.is_active <> source.is_active
        )
        THEN
            UPDATE SET
                target.acquisition_channel_name = source.acquisition_channel_name,
                target.is_active                = source.is_active
        WHEN NOT MATCHED BY TARGET
        THEN
            INSERT (acquisition_channel_code, acquisition_channel_name, is_active)
            VALUES (source.acquisition_channel_code, source.acquisition_channel_name, source.is_active)
        OUTPUT 'ref_acquisition_channel', $action INTO @merge_results (table_name, action_type);


        /* ----------------------------------------------------------------------
           3. SEED: ref.ref_vehicle_type (10 rows)
        ---------------------------------------------------------------------- */
        PRINT '--> Seeding ref.ref_vehicle_type...';

        MERGE ref.ref_vehicle_type AS target
        USING
        (
            VALUES
                ('3 WHEELER',     '3-Wheeler',          1),
                ('BIKE',          'Bike',               1),
                ('CAR',           'Car',                1),
                ('CYCLE',         'Cycle',              1),
                ('EV 3 WHEELER',  'Electric 3-Wheeler', 1),
                ('EV BIKE',       'Electric Bike',      1),
                ('EV CYCLE',      'Electric Cycle',     1),
                ('EV SCOOTER',    'Electric Scooter',   1),
                ('SCOOTER',       'Scooter',            1),
                ('VAN',           'Van',                1)
        ) AS source (vehicle_type_code, vehicle_type_name, is_active)
        ON (target.vehicle_type_code = source.vehicle_type_code)
        WHEN MATCHED AND
        (
            target.vehicle_type_name <> source.vehicle_type_name
            OR target.is_active <> source.is_active
        )
        THEN
            UPDATE SET
                target.vehicle_type_name = source.vehicle_type_name,
                target.is_active         = source.is_active
        WHEN NOT MATCHED BY TARGET
        THEN
            INSERT (vehicle_type_code, vehicle_type_name, is_active)
            VALUES (source.vehicle_type_code, source.vehicle_type_name, source.is_active)
        OUTPUT 'ref_vehicle_type', $action INTO @merge_results (table_name, action_type);


        /* ----------------------------------------------------------------------
           4. SEED: ref.ref_employment_type (3 rows)
        ---------------------------------------------------------------------- */
        PRINT '--> Seeding ref.ref_employment_type...';

        MERGE ref.ref_employment_type AS target
        USING
        (
            VALUES
                ('CONTRACT',  'Contract',  1),
                ('FULL-TIME', 'Full-Time', 1),
                ('PART-TIME', 'Part-Time', 1)
        ) AS source (employment_type_code, employment_type_name, is_active)
        ON (target.employment_type_code = source.employment_type_code)
        WHEN MATCHED AND
        (
            target.employment_type_name <> source.employment_type_name
            OR target.is_active <> source.is_active
        )
        THEN
            UPDATE SET
                target.employment_type_name = source.employment_type_name,
                target.is_active            = source.is_active
        WHEN NOT MATCHED BY TARGET
        THEN
            INSERT (employment_type_code, employment_type_name, is_active)
            VALUES (source.employment_type_code, source.employment_type_name, source.is_active)
        OUTPUT 'ref_employment_type', $action INTO @merge_results (table_name, action_type);


        /* ----------------------------------------------------------------------
           5. SEED: ref.ref_category (24 rows)
        ---------------------------------------------------------------------- */
        PRINT '--> Seeding ref.ref_category...';

        MERGE ref.ref_category AS target
        USING
        (
            VALUES
                ('BEVERAGES',    'Beverages',              1),
                ('BIRYANI',      'Biryani',                1),
                ('BOWLS',        'Bowls',                  1),
                ('BREADS',       'Breads',                 1),
                ('BURGERS',      'Burgers',                1),
                ('CURRIES',      'Curries',                1),
                ('DESSERTS',     'Desserts',               1),
                ('DOSA',         'Dosa',                   1),
                ('FRIED RICE',   'Fried Rice',             1),
                ('FRIES',        'Fries',                  1),
                ('IDLI',         'Idli',                   1),
                ('JUICES',       'Juices',                 1),
                ('MOMOS',        'Momos',                  1),
                ('NOODLES',      'Noodles',                1),
                ('PIZZA',        'Pizza',                  1),
                ('RICE',         'Rice',                   1),
                ('SALADS',       'Salads',                 1),
                ('SHAKES',       'Milkshakes & Smoothies', 1),
                ('SIDES',        'Sides',                  1),
                ('SNACKS',       'Snacks',                 1),
                ('SOUPS',        'Soups',                  1),
                ('STARTERS',     'Starters',               1),
                ('TIKKA KEBAB',  'Tikka & Kebabs',         1),
                ('WRAPS',        'Wraps',                  1)
        ) AS source (category_code, category_name, is_active)
        ON (target.category_code = source.category_code)
        WHEN MATCHED AND
        (
            target.category_name <> source.category_name
            OR target.is_active <> source.is_active
        )
        THEN
            UPDATE SET
                target.category_name = source.category_name,
                target.is_active     = source.is_active
        WHEN NOT MATCHED BY TARGET
        THEN
            INSERT (category_code, category_name, is_active)
            VALUES (source.category_code, source.category_name, source.is_active)
        OUTPUT 'ref_category', $action INTO @merge_results (table_name, action_type);


        /* ----------------------------------------------------------------------
           6. SEED: ref.ref_cuisine_type (14 rows)
        ---------------------------------------------------------------------- */
        PRINT '--> Seeding ref.ref_cuisine_type...';

        MERGE ref.ref_cuisine_type AS target
        USING
        (
            VALUES
                ('BENGALI',       'Bengali',       1),
                ('BIRYANI',       'Biryani',       1),
                ('CHINESE',       'Chinese',       1),
                ('DESSERTS',      'Desserts',      1),
                ('FAST FOOD',     'Fast Food',     1),
                ('GOAN',          'Goan',          1),
                ('GUJARATI',      'Gujarati',      1),
                ('HEALTHY',       'Healthy',       1),
                ('INDO-CHINESE',  'Indo-Chinese',  1),
                ('ITALIAN',       'Italian',       1),
                ('MAHARASHTRIAN', 'Maharashtrian', 1),
                ('NORTH INDIAN',  'North Indian',  1),
                ('PIZZA',         'Pizza',         1),
                ('SOUTH INDIAN',  'South Indian',  1)
        ) AS source (cuisine_type_code, cuisine_type_name, is_active)
        ON (target.cuisine_type_code = source.cuisine_type_code)
        WHEN MATCHED AND
        (
            target.cuisine_type_name <> source.cuisine_type_name
            OR target.is_active <> source.is_active
        )
        THEN
            UPDATE SET
                target.cuisine_type_name = source.cuisine_type_name,
                target.is_active         = source.is_active
        WHEN NOT MATCHED BY TARGET
        THEN
            INSERT (cuisine_type_code, cuisine_type_name, is_active)
            VALUES (source.cuisine_type_code, source.cuisine_type_name, source.is_active)
        OUTPUT 'ref_cuisine_type', $action INTO @merge_results (table_name, action_type);


        /* ----------------------------------------------------------------------
           7. SEED: ref.ref_partner_type (3 rows)
        ---------------------------------------------------------------------- */
        PRINT '--> Seeding ref.ref_partner_type...';

        MERGE ref.ref_partner_type AS target
        USING
        (
            VALUES
                ('CLOUD KITCHEN', 'Cloud Kitchen', 1),
                ('HOME CHEF',     'Home Chef',     1),
                ('RESTAURANT',    'Restaurant',    1)
        ) AS source (partner_type_code, partner_type_name, is_active)
        ON (target.partner_type_code = source.partner_type_code)
        WHEN MATCHED AND
        (
            target.partner_type_name <> source.partner_type_name
            OR target.is_active <> source.is_active
        )
        THEN
            UPDATE SET
                target.partner_type_name = source.partner_type_name,
                target.is_active         = source.is_active
        WHEN NOT MATCHED BY TARGET
        THEN
            INSERT (partner_type_code, partner_type_name, is_active)
            VALUES (source.partner_type_code, source.partner_type_name, source.is_active)
        OUTPUT 'ref_partner_type', $action INTO @merge_results (table_name, action_type);


        COMMIT TRANSACTION;

        DECLARE @end_time DATETIME2(3) = SYSUTCDATETIME();
        DECLARE @duration_ms INT = DATEDIFF(MILLISECOND, @start_time, @end_time);

        PRINT '====================================================================';
        PRINT 'REFERENCE DATA SEED COMPLETED SUCCESSFULLY';
        PRINT 'Duration: ' + CAST(@duration_ms AS VARCHAR(10)) + ' ms';
        PRINT '====================================================================';

        /* ----------------------------------------------------------------------
           AUDIT SUMMARY REPORT
        ---------------------------------------------------------------------- */
        SELECT
            t.table_name,
            ISNULL(SUM(CASE WHEN r.action_type = 'INSERT' THEN 1 ELSE 0 END), 0) AS rows_inserted,
            ISNULL(SUM(CASE WHEN r.action_type = 'UPDATE' THEN 1 ELSE 0 END), 0) AS rows_updated,
            c.total_current_rows,
            CASE 
                WHEN c.total_current_rows > 0 THEN 'PASS'
                ELSE 'FAIL (EMPTY)'
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
        ) AS t(table_name)
        LEFT JOIN @merge_results AS r
            ON t.table_name = r.table_name
        CROSS APPLY
        (
            SELECT CASE t.table_name
                WHEN 'ref_city'                THEN (SELECT COUNT(*) FROM ref.ref_city)
                WHEN 'ref_acquisition_channel' THEN (SELECT COUNT(*) FROM ref.ref_acquisition_channel)
                WHEN 'ref_vehicle_type'        THEN (SELECT COUNT(*) FROM ref.ref_vehicle_type)
                WHEN 'ref_employment_type'     THEN (SELECT COUNT(*) FROM ref.ref_employment_type)
                WHEN 'ref_category'            THEN (SELECT COUNT(*) FROM ref.ref_category)
                WHEN 'ref_cuisine_type'        THEN (SELECT COUNT(*) FROM ref.ref_cuisine_type)
                WHEN 'ref_partner_type'        THEN (SELECT COUNT(*) FROM ref.ref_partner_type)
            END AS total_current_rows
        ) AS c
        GROUP BY
            t.table_name,
            c.total_current_rows
        ORDER BY
            t.table_name;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        DECLARE
            @error_number   INT            = ERROR_NUMBER(),
            @error_message  NVARCHAR(4000) = ERROR_MESSAGE(),
            @error_line     INT            = ERROR_LINE(),
            @error_proc     SYSNAME        = ISNULL(ERROR_PROCEDURE(), 'ref.usp_seed_reference_data');

        PRINT '====================================================================';
        PRINT 'ERROR OCCURRED DURING REFERENCE DATA SEEDING!';
        PRINT 'Procedure: ' + @error_proc;
        PRINT 'Line     : ' + CAST(@error_line AS VARCHAR(10));
        PRINT 'Message  : ' + @error_message;
        PRINT '====================================================================';

        THROW 50000, @error_message, 1;
    END CATCH;
END;
GO
