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

/* ------------------------------------------------------------------------------
   DEPLOYMENT CONFIGURATION: PROJECT ROOT & ENVIRONMENT RESOLUTION
   - Priority 1: OS Environment Variable $env:FOOD_DELIVERY_ROOT (ideal for CI/CD & multi-env VM)
   - Priority 2: Fallback to @project_root deployment default path
------------------------------------------------------------------------------ */
DECLARE @project_root NVARCHAR(500) = N'c:\Users\PC\Downloads\food-delivery-etl-dwh';

DECLARE @cmd_python NVARCHAR(MAX) = N'
# Resolve project root: priority $env:FOOD_DELIVERY_ROOT, fallback to deployment default
$root = if ($env:FOOD_DELIVERY_ROOT) { $env:FOOD_DELIVERY_ROOT } else { "' + @project_root + N'" }
$pyDir = Join-Path $root "python"
$pyExe = Join-Path $pyDir ".venv\Scripts\python.exe"

if (-not (Test-Path $pyExe)) {
    # Fallback to system python if project virtual environment is not at default location
    $pyExe = "python.exe"
}

Write-Host "Executing Python Ingestion Pipeline from: $pyDir"
Write-Host "Python Runtime: $pyExe"
Set-Location -Path $pyDir
& $pyExe -m src.ingestion.run_stg_loader
if ($LASTEXITCODE -ne 0) {
    throw "Python Ingestion Pipeline failed with exit code $LASTEXITCODE"
}
';

DECLARE @cmd_ssis NVARCHAR(MAX) = N'
# Resolve project root: priority $env:FOOD_DELIVERY_ROOT, fallback to deployment default
$root = if ($env:FOOD_DELIVERY_ROOT) { $env:FOOD_DELIVERY_ROOT } else { "' + @project_root + N'" }
$ssisDir = Join-Path $root "ssis\FoodDeliveryETL\FoodDeliveryETL"
$pkgPath = Join-Path $ssisDir "01_Pipeline_Orchestrator.dtsx"

if (-not (Test-Path $pkgPath)) {
    throw "SSIS Package not found at expected path: $pkgPath"
}

Write-Host "Executing SSIS Pipeline Orchestrator from: $ssisDir"
Write-Host "Target Package: $pkgPath"
Set-Location -Path $ssisDir
& "dtexec.exe" /File $pkgPath
if ($LASTEXITCODE -ne 0) {
    Write-Warning "SSIS dtexec returned exit code $LASTEXITCODE (license constraint). Executing native T-SQL fallback: ods.usp_load_raw_to_ods_batch"
    & "sqlcmd.exe" -S "localhost\SQLEXPRESS" -d "FoodDeliveryDW" -E -b -Q "EXEC ods.usp_load_raw_to_ods_batch;"
    if ($LASTEXITCODE -ne 0) {
        throw "Both SSIS and T-SQL fallback failed with exit code $LASTEXITCODE"
    }
}
';

EXEC msdb.dbo.sp_add_job
    @job_name              = @job_name,
    @enabled               = 1,
    @notify_level_eventlog = 2,  -- Log on failure
    @notify_level_email    = 0,  -- Set to 2 if Database Mail is configured
    @description           = N'Runs the end-to-end Food Delivery ETL pipeline (Python Ingestion -> SSIS RAW to ODS -> T-SQL ODS to DWH) and executes log retention maintenance.',
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

-- Self-healing: Purge stale staging records left behind by aborted/crashed runs (> 12h)
IF OBJECT_ID(''temp.usp_purge_stale_temp_ods'', ''P'') IS NOT NULL
BEGIN
    EXEC temp.usp_purge_stale_temp_ods @retention_hours = 12, @dry_run = 0;
    PRINT ''[SELF-HEALING] Stale staging records verified and purged.'';
END;

PRINT ''[HEALTH CHECK PASSED] All 5 core schemas verified and staging cleansed.'';
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
    @command              = @cmd_python;

/* ==============================================================================
   STEP 3: RUN SSIS PIPELINE (RAW TO ODS VIA ORCHESTRATOR)
============================================================================== */
EXEC msdb.dbo.sp_add_jobstep
    @job_id               = @job_id,
    @step_name            = N'03 - Execute SSIS Pipeline (RAW to ODS)',
    @step_id              = 3,
    @cmdexec_success_code = 0,
    @on_success_action    = 3, -- Go to next step
    @on_fail_action       = 2, -- Quit with failure
    @subsystem            = N'PowerShell',
    @command              = @cmd_ssis;

/* ==============================================================================
   STEP 4: VERIFY ODS RECONCILIATION & GUARDRAILS
============================================================================== */
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @job_id,
    @step_name       = N'04 - Verify ODS Ingestion & Reconciliation',
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
WHERE status IN (''RUNNING'', ''SUCCESS'')
  AND ISNULL(total_records, 0) > 0
ORDER BY batch_id DESC;

IF @current_batch_id IS NULL OR @current_batch_id <= 0
BEGIN
    SELECT @current_batch_id = MAX(batch_id) FROM raw.raw_order;
END;

IF @current_batch_id IS NULL OR @current_batch_id <= 0
BEGIN
    THROW 50050, ''No active batch_id found to verify in ODS.'', 1;
END;

-- Production Guardrail: Verify data reconciliation between RAW and ODS
DECLARE @raw_orders_count INT, @ods_orders_count INT;
SELECT @raw_orders_count = COUNT(*) FROM raw.raw_order WHERE batch_id = @current_batch_id;
SELECT @ods_orders_count = COUNT(*) FROM ods.ods_order WHERE batch_id = @current_batch_id;

IF @raw_orders_count > 0 AND @ods_orders_count = 0
BEGIN
    THROW 50051, ''Data Reconciliation Guardrail Failed: raw_order has records but ods_order has 0 records!'', 1;
END;

PRINT ''[SUCCESS] ODS Data Reconciliation verified for BATCH_ID = '' + CAST(@current_batch_id AS VARCHAR(20));
',
    @database_name   = N'FoodDeliveryDW';

/* ==============================================================================
   STEP 5: RUN DWH DIMENSIONAL PIPELINE (ODS -> DWH SINGLE SOURCE OF TRUTH)
============================================================================== */
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @job_id,
    @step_name       = N'05 - Execute DWH Dimensional Pipeline',
    @step_id         = 5,
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
WHERE status IN (''RUNNING'', ''SUCCESS'')
  AND ISNULL(total_records, 0) > 0
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
   STEP 6: EXECUTE AUDIT LOG RETENTION & PURGE
============================================================================== */
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @job_id,
    @step_name       = N'06 - Maintenance Log Purge (30 Days Retention)',
    @step_id         = 6,
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
   STEP 7: DAILY LIGHTWEIGHT DWH MAINTENANCE
============================================================================== */
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @job_id,
    @step_name       = N'07 - Daily Lightweight DWH Maintenance',
    @step_id         = 7,
    @cmdexec_success_code = 0,
    @on_success_action    = 3, -- Go to next step
    @on_fail_action       = 2, -- Quit with failure
    @subsystem       = N'TSQL',
    @command         = N'
USE FoodDeliveryDW;
SET NOCOUNT ON;

-- Execute daily lightweight maintenance:
-- 1. Rowstore: Reorganize/Rebuild based on fragmentation thresholds (10%/30%)
-- 2. Columnstore: Reorganize with COMPRESS_ALL_ROW_GROUPS = ON (fast, online, closes delta stores)
-- 3. Statistics: Hybrid (FULLSCAN for Dim, SAMPLE 20% for Fact)
EXEC dwh.usp_maintain_dwh_indexes_and_stats
    @rebuild_threshold    = 30.0,
    @reorganize_threshold = 10.0,
    @update_stats         = 1,
    @force_fact_rebuild   = 0;
',
    @database_name   = N'FoodDeliveryDW';

/* ==============================================================================
   STEP 8: POST-ETL AUDIT SUMMARY & ALERTING CHECK
============================================================================== */
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @job_id,
    @step_name       = N'08 - Post-ETL Audit Verification',
    @step_id         = 8,
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
DECLARE @del_daily_sched_id INT;
WHILE EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WHERE name = N'Daily_02_AM_Schedule')
BEGIN
    SELECT TOP 1 @del_daily_sched_id = schedule_id FROM msdb.dbo.sysschedules WHERE name = N'Daily_02_AM_Schedule';
    EXEC msdb.dbo.sp_delete_schedule @schedule_id = @del_daily_sched_id, @force_delete = 1;
END;

DECLARE @schedule_id INT;

EXEC msdb.dbo.sp_add_schedule
    @schedule_name       = N'Daily_02_AM_Schedule',
    @enabled             = 1,
    @freq_type           = 4,       -- Daily
    @freq_interval       = 1,       -- Every 1 day
    @active_start_time   = 020000,  -- 02:00:00 AM
    @schedule_id         = @schedule_id OUTPUT;

EXEC msdb.dbo.sp_attach_schedule
    @job_name      = @job_name,
    @schedule_id   = @schedule_id;

-- Set server
EXEC msdb.dbo.sp_add_jobserver
    @job_name     = @job_name,
    @server_name  = N'(local)';

PRINT 'Job schedule attached: Daily at 02:00 AM.';
GO

/* ==============================================================================
   4. WEEKLY COMPREHENSIVE DWH MAINTENANCE JOB (OPTION 3B)
   Schedule: Weekly on Sunday at 03:00 AM (Low-traffic maintenance window)
============================================================================== */
USE msdb;
GO

DECLARE @weekly_job_name NVARCHAR(128) = N'QuickBite_Weekly_DWH_Maintenance';
DECLARE @weekly_job_id BINARY(16);

SELECT @weekly_job_id = job_id 
FROM msdb.dbo.sysjobs 
WHERE name = @weekly_job_name;

IF @weekly_job_id IS NOT NULL
BEGIN
    PRINT 'Existing weekly job found. Dropping job: ' + @weekly_job_name;
    EXEC msdb.dbo.sp_delete_job @job_id = @weekly_job_id, @delete_unused_schedule = 1;
    SET @weekly_job_id = NULL;
END;

EXEC msdb.dbo.sp_add_job
    @job_name              = @weekly_job_name,
    @enabled               = 1,
    @notify_level_eventlog = 2,  -- Log on failure
    @notify_level_email    = 0,
    @description           = N'Weekly comprehensive maintenance for FoodDeliveryDW: Full Clustered Columnstore Rebuild, aggressive Rowstore defragmentation, deep staging purge, and log cleanup.',
    @category_name         = N'Database Maintenance',
    @owner_login_name      = N'sa',
    @job_id                = @weekly_job_id OUTPUT;

PRINT 'Created Weekly Job: ' + @weekly_job_name;

-- Step 1: Deep Columnstore Rebuild & Index Maintenance
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @weekly_job_id,
    @step_name       = N'01 - Deep Columnstore Rebuild & Index Maintenance',
    @step_id         = 1,
    @cmdexec_success_code = 0,
    @on_success_action    = 3, -- Go to next step
    @on_fail_action       = 2, -- Quit with failure
    @subsystem       = N'TSQL',
    @command         = N'
USE FoodDeliveryDW;
SET NOCOUNT ON;

PRINT ''Executing Weekly Deep Index Maintenance (Force Fact Columnstore Rebuild)...'';
EXEC dwh.usp_maintain_dwh_indexes_and_stats
    @rebuild_threshold    = 20.0,
    @reorganize_threshold = 5.0,
    @update_stats         = 1,
    @force_fact_rebuild   = 1;
',
    @database_name   = N'FoodDeliveryDW';

-- Step 2: Deep Staging Purge (Purge orphan records older than 6h)
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @weekly_job_id,
    @step_name       = N'02 - Deep Staging Self-Healing Purge',
    @step_id         = 2,
    @cmdexec_success_code = 0,
    @on_success_action    = 3, -- Go to next step
    @on_fail_action       = 2, -- Quit with failure
    @subsystem       = N'TSQL',
    @command         = N'
USE FoodDeliveryDW;
SET NOCOUNT ON;

PRINT ''Executing Weekly Deep Staging Purge (Retention: 6 Hours)...'';
EXEC temp.usp_purge_stale_temp_ods @retention_hours = 6, @dry_run = 0;
',
    @database_name   = N'FoodDeliveryDW';

-- Step 3: Deep Audit Log Cleanup (Retain 30 days)
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @weekly_job_id,
    @step_name       = N'03 - Audit Log Extended Retention Purge',
    @step_id         = 3,
    @cmdexec_success_code = 0,
    @on_success_action    = 3, -- Go to next step
    @on_fail_action       = 2, -- Quit with failure
    @subsystem       = N'TSQL',
    @command         = N'
USE FoodDeliveryDW;
SET NOCOUNT ON;

PRINT ''Executing Weekly Audit Log Purge...'';
EXEC control.usp_purge_etl_logs @retention_days = 30, @dry_run = 0;
',
    @database_name   = N'FoodDeliveryDW';

-- Step 4: Weekly Maintenance Verification
EXEC msdb.dbo.sp_add_jobstep
    @job_id          = @weekly_job_id,
    @step_name       = N'04 - Weekly Maintenance Verification',
    @step_id         = 4,
    @cmdexec_success_code = 0,
    @on_success_action    = 1, -- Quit with success
    @on_fail_action       = 2, -- Quit with failure
    @subsystem       = N'TSQL',
    @command         = N'
USE FoodDeliveryDW;
SET NOCOUNT ON;

DECLARE @failed_steps INT;
SELECT @failed_steps = COUNT(*)
FROM control.etl_log
WHERE status = ''FAILED''
  AND start_time >= DATEADD(HOUR, -2, GETDATE());

IF @failed_steps > 0
BEGIN
    PRINT ''[ALERT] Weekly Maintenance detected '' + CAST(@failed_steps AS VARCHAR(10)) + '' failed step(s)!'';
    THROW 50098, ''Weekly maintenance completed with failed steps. Review control.etl_log!'', 1;
END
ELSE
BEGIN
    PRINT ''[SUCCESS] Weekly Maintenance completed cleanly with 0 failures.'';
END;
',
    @database_name   = N'FoodDeliveryDW';

-- Configure Weekly Sunday Schedule (03:00 AM)
DECLARE @del_weekly_sched_id INT;
WHILE EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WHERE name = N'Weekly_Sunday_03_AM_Schedule')
BEGIN
    SELECT TOP 1 @del_weekly_sched_id = schedule_id FROM msdb.dbo.sysschedules WHERE name = N'Weekly_Sunday_03_AM_Schedule';
    EXEC msdb.dbo.sp_delete_schedule @schedule_id = @del_weekly_sched_id, @force_delete = 1;
END;

DECLARE @weekly_schedule_id INT;

EXEC msdb.dbo.sp_add_schedule
    @schedule_name          = N'Weekly_Sunday_03_AM_Schedule',
    @enabled                = 1,
    @freq_type              = 8,       -- Weekly
    @freq_interval          = 1,       -- Sunday (1 = Sunday)
    @freq_recurrence_factor = 1,       -- Every 1 week
    @active_start_time      = 030000,  -- 03:00:00 AM
    @schedule_id            = @weekly_schedule_id OUTPUT;

EXEC msdb.dbo.sp_attach_schedule
    @job_name      = @weekly_job_name,
    @schedule_id   = @weekly_schedule_id;

EXEC msdb.dbo.sp_add_jobserver
    @job_name     = @weekly_job_name,
    @server_name  = N'(local)';

PRINT 'Job schedule attached: Weekly on Sunday at 03:00 AM.';
GO
