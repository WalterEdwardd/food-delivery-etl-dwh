/* ==============================================================================
   QUICKBITE DATA PLATFORM
   Food Delivery ETL & Data Warehouse

   ORCHESTRATION & AUTOMATION: SQL SERVER AGENT JOB SETUP
   
   Database : FoodDeliveryDW / msdb
   File     : sql/etl/07_sql_agent_job_orchestration.sql
   Purpose  : Automate the end-to-end execution of the Food Delivery ETL Pipeline
              and periodic maintenance tasks via SQL Server Agent.
============================================================================== */

USE msdb;
GO

/* ==============================================================================
   1. CLEANUP PREVIOUS JOB (IF EXISTS)
============================================================================== */
DECLARE @job_name NVARCHAR(128) = N'QuickBite_Daily_ETL_Pipeline';
DECLARE @job_id BINARY(16);

SELECT @job_id = job_id 
FROM msdb.dbo.sysjobs 
WHERE name = @job_name;

IF @job_id IS NOT NULL
BEGIN
    PRINT 'Existing job found. Dropping job: ' + @job_name;
    EXEC msdb.dbo.sp_delete_job @job_id = @job_id, @delete_unused_schedule = 1;
END;
GO

/* ==============================================================================
   2. CREATE SQL SERVER AGENT JOB
============================================================================== */
DECLARE @job_name NVARCHAR(128) = N'QuickBite_Daily_ETL_Pipeline';
DECLARE @job_id BINARY(16);

EXEC msdb.dbo.sp_add_job
    @job_name              = @job_name,
    @enabled               = 1,
    @notify_level_eventlog = 2,  -- Log on failure
    @notify_level_email    = 0,  -- Set to 2 if Database Mail is configured
    @description           = N'Runs the end-to-end Food Delivery ETL pipeline (RAW to ODS Incremental Upsert) and executes log retention maintenance.',
    @category_name         = N'Data Collector',
    @owner_login_name      = N'sa',
    @job_id                = @job_id OUTPUT;

PRINT 'Created Job: ' + @job_name;

/* ==============================================================================
   STEP 1: PRE-CHECK & INITIALIZE BATCH
============================================================================== */
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @job_id,
    @step_name       = N'01 - Pre-ETL Health Check & Schema Validation',
    @step_id         = 1,
    @cmdexec_success_code = 0,
    @on_success_action    = 3, -- Go to next step
    @on_fail_action       = 2, -- Quit with failure
    @subsystem       = N'TSQL',
    @command         = N'
USE FoodDeliveryDW;
SET NOCOUNT ON;

-- Verify all required schemas exist
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''control'')
    THROW 50001, ''Schema control does not exist!'', 1;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''stg'')
    THROW 50002, ''Schema stg does not exist!'', 1;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''raw'')
    THROW 50003, ''Schema raw does not exist!'', 1;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''temp'')
    THROW 50004, ''Schema temp does not exist!'', 1;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''ods'')
    THROW 50005, ''Schema ods does not exist!'', 1;

PRINT ''[HEALTH CHECK PASSED] All 5 core schemas verified.'';
',
    @database_name   = N'FoodDeliveryDW';

/* ==============================================================================
   STEP 2: RUN INGESTION PIPELINE (PYTHON: CSV -> STG -> RAW)
============================================================================== */
EXEC msdb.dbo.sp_add_jobstep
    @job_id               = @job_id,
    @step_name            = N'02 - Ingest CSV to RAW (Python Pipeline)',
    @step_id              = 2,
    @cmdexec_success_code = 0,
    @on_success_action    = 3, -- Go to next step
    @on_fail_action       = 2, -- Quit with failure
    @subsystem            = N'PowerShell',
    @command              = N'
Set-Location -Path "c:\Users\PC\Downloads\food-delivery-etl-dwh\python"
& ".\.venv\Scripts\python.exe" -m src.ingestion.run_stg_loader
if ($LASTEXITCODE -ne 0) {
    throw "Python Ingestion Pipeline failed with exit code $LASTEXITCODE"
}
';

/* ==============================================================================
   STEP 3: RUN ODS INCREMENTAL UPSERT & SYNCHRONIZATION
============================================================================== */
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @job_id,
    @step_name       = N'03 - Execute ODS Upsert & Synchronization',
    @step_id         = 3,
    @cmdexec_success_code = 0,
    @on_success_action    = 3, -- Go to next step
    @on_fail_action       = 2, -- Quit with failure
    @subsystem       = N'TSQL',
    @command         = N'
USE FoodDeliveryDW;
SET NOCOUNT ON;

DECLARE @current_batch_id BIGINT;

-- 1. Identify active completed batch from Step 2 (Python Ingestion)
SELECT TOP 1 @current_batch_id = batch_id
FROM control.etl_batch
WHERE status = ''COMPLETED''
ORDER BY batch_id DESC;

-- Fallback to raw.raw_order if control.etl_batch has no completed entries
IF @current_batch_id IS NULL OR @current_batch_id <= 0
BEGIN
    SELECT @current_batch_id = MAX(batch_id) FROM raw.raw_order;
END;

IF @current_batch_id IS NULL OR @current_batch_id <= 0
BEGIN
    THROW 50050, ''No active batch_id found to load into ODS. Ingestion pipeline aborted.'', 1;
END;

PRINT ''Starting RAW to ODS Master Ingestion & Validation for BATCH_ID = '' + CAST(@current_batch_id AS VARCHAR(20));

-- 2. Execute RAW -> ODS Master Ingestion & Cleansing
EXEC ods.usp_load_raw_to_ods_batch @batch_id = @current_batch_id;

-- 3. Production Guardrail: Verify data reconciliation between RAW and ODS
DECLARE @raw_orders_count INT, @ods_orders_count INT;
SELECT @raw_orders_count = COUNT(*) FROM raw.raw_order WHERE batch_id = @current_batch_id;
SELECT @ods_orders_count = COUNT(*) FROM ods.ods_order WHERE batch_id = @current_batch_id;

IF @raw_orders_count > 0 AND @ods_orders_count = 0
BEGIN
    THROW 50051, ''Data Reconciliation Guardrail Failed: raw_order has records but ods_order has 0 records!'', 1;
END;

PRINT ''[SUCCESS] ODS Master Ingestion completed successfully for BATCH_ID = '' + CAST(@current_batch_id AS VARCHAR(20));
',
    @database_name   = N'FoodDeliveryDW';

/* ==============================================================================
   STEP 4: RUN DWH DIMENSIONAL PIPELINE (ODS -> DWH SINGLE SOURCE OF TRUTH)
============================================================================== */
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @job_id,
    @step_name       = N'04 - Execute DWH Dimensional Pipeline',
    @step_id         = 4,
    @cmdexec_success_code = 0,
    @on_success_action    = 3, -- Go to next step
    @on_fail_action       = 2, -- Quit with failure
    @subsystem       = N'TSQL',
    @command         = N'
USE FoodDeliveryDW;
SET NOCOUNT ON;

DECLARE @current_batch_id BIGINT;

SELECT TOP 1 @current_batch_id = batch_id
FROM control.etl_batch
WHERE status = ''COMPLETED''
ORDER BY batch_id DESC;

IF @current_batch_id IS NULL OR @current_batch_id <= 0
BEGIN
    SELECT @current_batch_id = MAX(batch_id) FROM ods.ods_order;
END;

PRINT ''Executing ODS to DWH Dimensional Pipeline for BATCH_ID = '' + CAST(ISNULL(@current_batch_id, -1) AS VARCHAR(20));
EXEC dwh.usp_run_ods_to_dwh_pipeline @batch_id = @current_batch_id;
PRINT ''[SUCCESS] DWH Dimensional Pipeline completed.'';
',
    @database_name   = N'FoodDeliveryDW';

/* ==============================================================================
   STEP 5: EXECUTE AUDIT LOG RETENTION & PURGE
============================================================================== */
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @job_id,
    @step_name       = N'05 - Maintenance Log Purge (30 Days Retention)',
    @step_id         = 5,
    @cmdexec_success_code = 0,
    @on_success_action    = 3, -- Go to next step
    @on_fail_action       = 2, -- Quit with failure
    @subsystem       = N'TSQL',
    @command         = N'
USE FoodDeliveryDW;
SET NOCOUNT ON;

-- Purge logs older than 30 days
EXEC control.usp_purge_etl_logs @retention_days = 30, @dry_run = 0;
',
    @database_name   = N'FoodDeliveryDW';

/* ==============================================================================
   STEP 6: POST-ETL AUDIT SUMMARY & ALERTING CHECK
============================================================================== */
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @job_id,
    @step_name       = N'06 - Post-ETL Audit Verification',
    @step_id         = 6,
    @cmdexec_success_code = 0,
    @on_success_action    = 1, -- Quit with success
    @on_fail_action       = 2, -- Quit with failure
    @subsystem       = N'TSQL',
    @command         = N'
USE FoodDeliveryDW;
SET NOCOUNT ON;

-- Audit check: verify if any step in the current run failed
DECLARE @failed_steps INT;
SELECT @failed_steps = COUNT(*)
FROM control.etl_log
WHERE status = ''FAILED''
  AND start_time >= DATEADD(HOUR, -2, GETDATE());

IF @failed_steps > 0
BEGIN
    PRINT ''[ALERT] Detected '' + CAST(@failed_steps AS VARCHAR(10)) + '' failed ETL step(s) in the last 2 hours!'';
    -- In production, trigger Database Mail (sp_send_dbmail) here
    THROW 50099, ''Pipeline completed with failed steps. Review control.etl_log!'', 1;
END
ELSE
BEGIN
    PRINT ''[SUCCESS] All ETL steps completed cleanly with 0 failures.'';
END;
',
    @database_name   = N'FoodDeliveryDW';

/* ==============================================================================
   3. CONFIGURE RECURRING DAILY SCHEDULE (02:00 AM)
============================================================================== */
DECLARE @schedule_id INT;

EXEC msdb.dbo.sp_add_schedule
    @schedule_name       = N'Daily_02_AM_Schedule',
    @enabled             = 1,
    @freq_type           = 4,       -- Daily
    @freq_interval       = 1,       -- Every 1 day
    @active_start_time   = 020000,  -- 02:00:00 AM
    @schedule_id         = @schedule_id OUTPUT;

EXEC msdb.dbo.sp_attach_schedule
    @job_name     = @job_name,
    @schedule_name = N'Daily_02_AM_Schedule';

-- Set server
EXEC msdb.dbo.sp_add_jobserver
    @job_name     = @job_name,
    @server_name  = N'(local)';

PRINT 'Job schedule attached: Daily at 02:00 AM.';
GO
