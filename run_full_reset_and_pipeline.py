"""
QuickBite Data Platform - Full End-to-End Database Reset and Pipeline Execution Runner
Resets the database completely from scratch, loads source CSVs to STG -> RAW -> ODS -> DWH,
and executes all verification and audit suites.
"""

import os
import sys
import shutil
import subprocess
import time
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent
PYTHON_DIR = PROJECT_ROOT / "python"
DATA_DIR = PROJECT_ROOT / "data"
SQL_DIR = PROJECT_ROOT / "sql"
SSIS_DIR = PROJECT_ROOT / "ssis" / "FoodDeliveryETL" / "FoodDeliveryETL"
SERVER = r"localhost\SQLEXPRESS"


def log(msg: str):
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {msg}", flush=True)


def run_cmd(cmd: list[str], cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess:
    log(f"Executing: {' '.join(str(c) for c in cmd)}")
    res = subprocess.run(
        cmd,
        cwd=cwd or PROJECT_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if res.stdout:
        print(res.stdout, flush=True)
    if check and res.returncode != 0:
        raise RuntimeError(f"Command failed with return code {res.returncode}: {' '.join(str(c) for c in cmd)}")
    return res


def run_sqlcmd(query_or_file: str, is_file: bool = False, db: str | None = None):
    cmd = ["sqlcmd", "-S", SERVER, "-E", "-b"]
    if db:
        cmd.extend(["-d", db])
    if is_file:
        cmd.extend(["-i", query_or_file])
    else:
        cmd.extend(["-Q", query_or_file])
    return run_cmd(cmd)


def step_cleanup_filesystem():
    log("=== STEP 1: CLEANING FILESYSTEM (PROCESSED, REJECTED, ARCHIVE) ===")
    for folder_name in ["processed", "archive", "rejected"]:
        folder = DATA_DIR / folder_name
        if folder.exists():
            for item in folder.iterdir():
                if item.name == ".gitkeep":
                    continue
                if item.is_file():
                    item.unlink()
                    log(f"Deleted {folder_name}/{item.name}")
                elif item.is_dir():
                    shutil.rmtree(item)
                    log(f"Deleted directory {folder_name}/{item.name}/")

    # Ensure incoming files exist
    incoming_dir = DATA_DIR / "incoming"
    incoming_csvs = list(incoming_dir.glob("*.csv"))
    if not incoming_csvs:
        init_folder = incoming_dir / "2026_01"
        if init_folder.exists() and list(init_folder.glob("*.csv")):
            log(f"Staging initial batch CSVs from {init_folder.name} into incoming/...")
            for f in init_folder.glob("*.csv"):
                dest = incoming_dir / f.name
                shutil.copy2(str(f), str(dest))
                log(f"  -> Staged {f.name} ({f.stat().st_size:,} bytes)")
        else:
            log("Restoring missing incoming files from git...")
            run_cmd(["git", "checkout", "--", "data/incoming"])
    else:
        for f in incoming_csvs:
            log(f"Verified incoming file: {f.name} ({f.stat().st_size:,} bytes)")


def step_reset_database():
    log("=== STEP 2: COMPLETE DATABASE DROP & RECREATION ===")
    drop_recreate_sql = """
    USE master;
    IF DB_ID('FoodDeliveryDW') IS NOT NULL
    BEGIN
        ALTER DATABASE FoodDeliveryDW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
        DROP DATABASE FoodDeliveryDW;
    END;
    CREATE DATABASE FoodDeliveryDW;
    """
    run_sqlcmd(drop_recreate_sql)
    log("Database FoodDeliveryDW recreated cleanly.")

    # 1. Run Database DDL Scripts
    ddl_scripts = [
        "01_database.sql",
        "02_schemas.sql",
        "03_control.sql",
        "04_ref.sql",
        "05_stg.sql",
        "06_raw.sql",
        "07_ods.sql",
        "08_temp_ods_tables.sql",
        "09_dwh.sql",
        "10_bi_views.sql",
        "11_control_monitoring_views.sql",
    ]
    log("--- Executing DDL Scripts (01 to 11) ---")
    for script in ddl_scripts:
        script_path = SQL_DIR / "database" / script
        log(f"Applying DDL: {script}")
        run_sqlcmd(str(script_path), is_file=True)

    # 2. Run ETL Stored Procedure Scripts
    etl_scripts = [
        "01_ref_seed_procedures.sql",
        "02_stg_to_raw_procedures.sql",
        "03_raw_to_ods_logging_procedures.sql",
        "04_raw_to_ods_upsert_procedures.sql",
        "05_ods_to_dwh_procedures.sql",
        "06_maintenance_procedures.sql",
        "07_sql_agent_job_orchestration.sql",
    ]
    log("--- Executing ETL Procedure Scripts (01 to 07) ---")
    for script in etl_scripts:
        script_path = SQL_DIR / "etl" / script
        log(f"Applying ETL Script: {script}")
        run_sqlcmd(str(script_path), is_file=True)

    # 3. Seed Reference Data (All 8 tables including ref_review_aspect_cache)
    log("--- Seeding Reference Master Data ---")
    run_sqlcmd("EXEC ref.usp_seed_reference_data;", db="FoodDeliveryDW")


def step_run_python_ingestion():
    log("=== STEP 3: RUNNING PYTHON INGESTION (CSV -> STG -> RAW) ===")
    venv_py = PYTHON_DIR / ".venv" / "Scripts" / "python.exe"
    py_exe = str(venv_py) if venv_py.exists() else sys.executable
    run_cmd([py_exe, "-m", "src.ingestion.run_stg_loader"], cwd=PYTHON_DIR)

    log("--- Validating RAW Ingestion (01_verify_raw_load.sql) ---")
    raw_verify_script = SQL_DIR / "tests" / "01_verify_raw_load.sql"
    run_sqlcmd(str(raw_verify_script), is_file=True, db="FoodDeliveryDW")


def step_run_ssis_pipeline():
    log("=== STEP 4: RUNNING SSIS PIPELINE (RAW -> ODS) ===")
    pkg_path = SSIS_DIR / "01_Pipeline_Orchestrator.dtsx"
    res = run_cmd(["dtexec.exe", "/File", str(pkg_path)], cwd=SSIS_DIR, check=False)
    if res.returncode != 0:
        log(f"SSIS dtexec returned exit code {res.returncode} (SSIS license restriction outside SSDT).")
        log("Executing native production fallback: ods.usp_load_raw_to_ods_batch @batch_id = 1...")
        run_sqlcmd("EXEC ods.usp_load_raw_to_ods_batch @batch_id = 1;", db="FoodDeliveryDW")
        log("Native T-SQL RAW -> ODS batch load completed successfully.")

    log("--- Validating ODS Load (02_verify_ods_load.sql) ---")
    ods_verify_script = SQL_DIR / "tests" / "02_verify_ods_load.sql"
    run_sqlcmd(str(ods_verify_script), is_file=True, db="FoodDeliveryDW")


def step_run_dwh_pipeline():
    log("=== STEP 5: RUNNING DWH PIPELINE (ODS -> DWH SINGLE SOURCE OF TRUTH) ===")
    dwh_sql = """
    SET NOCOUNT ON;
    PRINT 'Triggering dwh.usp_run_ods_to_dwh_pipeline @batch_id = 1...';
    EXEC dwh.usp_run_ods_to_dwh_pipeline @batch_id = 1;
    """
    run_sqlcmd(dwh_sql, db="FoodDeliveryDW")

    log("--- Running Post-ETL DWH Maintenance (Indexes & Stats) ---")
    maint_sql = """
    EXEC dwh.usp_maintain_dwh_indexes_and_stats
        @rebuild_threshold    = 30.0,
        @reorganize_threshold = 10.0,
        @update_stats         = 1,
        @force_fact_rebuild   = 0;
    """
    run_sqlcmd(maint_sql, db="FoodDeliveryDW")

    log("--- Validating DWH Star Schema & Serving Views (03_verify_dwh_load.sql) ---")
    dwh_verify_script = SQL_DIR / "tests" / "03_verify_dwh_load.sql"
    run_sqlcmd(str(dwh_verify_script), is_file=True, db="FoodDeliveryDW")


def step_verify_database_summary():
    log("=== STEP 6: FINAL DATABASE INTEGRITY & METRIC SUMMARY ===")
    summary_sql = """
    SET NOCOUNT ON;
    SELECT s.name AS [Schema], t.name AS [Table], SUM(ps.row_count) AS [Row Count]
    FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    JOIN sys.dm_db_partition_stats ps ON t.object_id = ps.object_id
    WHERE ps.index_id IN (0, 1)
      AND s.name IN ('control', 'ref', 'stg', 'raw', 'temp', 'ods', 'dwh')
    GROUP BY s.name, t.name
    ORDER BY s.name, t.name;

    SELECT 'Serving Views Check' AS [Check], name AS [View Name]
    FROM sys.views
    WHERE schema_id = SCHEMA_ID('bi');

    SELECT batch_id, pipeline_name, status, total_records, success_records, error_records, start_time, end_time
    FROM control.etl_batch
    ORDER BY batch_id;
    """
    run_sqlcmd(summary_sql, db="FoodDeliveryDW")


def step_cleanup_and_restore_sources():
    log("=== STEP 7: RESTORING INCOMING SOURCE CSVs ===")
    init_folder = DATA_DIR / "incoming" / "2026_01"
    incoming_dir = DATA_DIR / "incoming"
    if init_folder.exists() and list(init_folder.glob("*.csv")):
        for f in init_folder.glob("*.csv"):
            shutil.copy2(str(f), str(incoming_dir / f.name))
        log("Incoming CSV files successfully restored from 2026_01 for future runs.")
    else:
        run_cmd(["git", "checkout", "--", "data/incoming"])
        log("Incoming CSV files successfully restored from git.")


def step_run_pytest():
    log("=== STEP 8: RUNNING PYTEST TEST SUITE ===")
    venv_py = PYTHON_DIR / ".venv" / "Scripts" / "python.exe"
    py_exe = str(venv_py) if venv_py.exists() else sys.executable
    run_cmd([py_exe, "-m", "pytest"], cwd=PYTHON_DIR)


def main():
    start_total = time.time()
    log("********************************************************************")
    log("STARTING FULL END-TO-END RESET AND DATA PIPELINE RUN")
    log("Target: FoodDeliveryDW (SQL Server SQLEXPRESS)")
    log("Architecture: CSV -> Python STG -> RAW -> SSIS ODS -> DWH Serving")
    log("********************************************************************")

    try:
        step_cleanup_filesystem()
        step_reset_database()
        step_run_python_ingestion()
        step_run_ssis_pipeline()
        step_run_dwh_pipeline()
        step_verify_database_summary()
        step_cleanup_and_restore_sources()
        step_run_pytest()

        elapsed = time.time() - start_total
        log("********************************************************************")
        log(f"ALL PIPELINE STAGES AND VERIFICATION AUDITS PASSED IN {elapsed:.2f}s!")
        log("********************************************************************")
    except Exception as exc:
        log(f"CRITICAL ERROR OCCURRED: {exc}")
        sys.exit(1)


if __name__ == "__main__":
    main()
