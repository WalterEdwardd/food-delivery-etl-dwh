"""
QuickBite Data Platform - Monthly Batch Ingestion Pipeline
Sequentially processes monthly batch arrivals from data/incoming/2026_01 to 2026_09,
ingesting each month via Python STG -> RAW -> ODS -> DWH, tracking SCD Type 2 lifecycles,
and logging operational audit metrics.
"""

import sys
import shutil
import time
import argparse
import subprocess
from pathlib import Path

from src.config.database import get_connection
from src.config import settings
from src.utils.logger import get_logger

logger = get_logger("monthly_pipeline")

# Paths configuration relative to src/orchestration
ORCHESTRATION_DIR = Path(__file__).resolve().parent
PYTHON_DIR = ORCHESTRATION_DIR.parents[1]
PROJECT_ROOT = PYTHON_DIR.parent
DATA_DIR = PROJECT_ROOT / "data"
INCOMING_DIR = DATA_DIR / "incoming"


def log(msg: str):
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {msg}", flush=True)


def get_latest_batch_id() -> int:
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT ISNULL(MAX(batch_id), 0) FROM control.etl_batch;")
            row = cur.fetchone()
            return int(row[0]) if row else 0
    finally:
        conn.close()


def run_sql_procedure(proc_sql: str):
    conn = get_connection()
    try:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute(proc_sql)
    finally:
        conn.close()


def query_metrics(batch_id: int) -> dict:
    conn = get_connection()
    metrics = {}
    try:
        with conn.cursor() as cur:
            # Batch record
            cur.execute("SELECT status, total_records, success_records FROM control.etl_batch WHERE batch_id = ?;", batch_id)
            row = cur.fetchone()
            if row:
                metrics['status'] = row[0]
                metrics['stg_records'] = row[1]
            
            # Cumulative orders in DWH
            cur.execute("SELECT COUNT(*) FROM dwh.fact_order;")
            row = cur.fetchone()
            metrics['dwh_orders'] = row[0] if row else 0

            # Cumulative active customers in DWH
            cur.execute("SELECT COUNT(*) FROM dwh.dim_customer WHERE is_current = 1 AND customer_key <> -1;")
            row = cur.fetchone()
            metrics['dwh_active_customers'] = row[0] if row else 0

            # SCD2 changes logged for this batch
            cur.execute("SELECT COUNT(*) FROM control.dim_change_log WHERE batch_id = ?;", batch_id)
            row = cur.fetchone()
            metrics['scd2_changes'] = row[0] if row else 0
    finally:
        conn.close()
    return metrics


def execute_month_batch(month_str: str) -> bool:
    """
    Executes a single monthly batch ingestion (e.g. '2026_01').
    Stages files from incoming/<month_str> to incoming/, runs the pipeline,
    and reports operational metrics.
    """
    month_folder = INCOMING_DIR / month_str
    if not month_folder.exists() or not month_folder.is_dir():
        log(f"Error: Month folder not found at {month_folder}")
        return False

    csv_files = list(month_folder.glob("*.csv"))
    if not csv_files:
        log(f"Error: No CSV files found in {month_folder}")
        return False

    log(f"\n=======================================================")
    log(f"   STARTING MONTHLY BATCH PIPELINE FOR: {month_str}")
    log(f"=======================================================")
    log(f"Found {len(csv_files)} files in {month_folder.name}")

    # Step 1: Copy files from subfolder directly into incoming/
    copied_files = []
    for f in csv_files:
        dest = INCOMING_DIR / f.name
        shutil.copy2(str(f), str(dest))
        copied_files.append(dest)
        log(f"  -> Staged {f.name} ({f.stat().st_size:,} bytes) into incoming/")

    start_time = time.time()

    # Step 2: Run Python STG Loader
    log("\n[1/3] Running Python STG Loader (CSV -> STG -> RAW)...")
    venv_py = PYTHON_DIR / ".venv" / "Scripts" / "python.exe"
    py_exe = str(venv_py) if venv_py.exists() else sys.executable
    res = subprocess.run(
        [py_exe, "-m", "src.ingestion.run_stg_loader"],
        cwd=PYTHON_DIR,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace"
    )
    if res.returncode != 0:
        log(f"Error during ingestion:\n{res.stdout}\n{res.stderr}")
        return False

    batch_id = get_latest_batch_id()
    log(f"STG -> RAW ingestion finished successfully. Active Batch ID: {batch_id}")

    # Step 3: Run RAW -> ODS
    log(f"\n[2/3] Triggering RAW -> ODS Upsert (ods.usp_load_raw_to_ods_batch @batch_id = {batch_id})...")
    run_sql_procedure(f"EXEC ods.usp_load_raw_to_ods_batch @batch_id = {batch_id};")
    log("RAW -> ODS upsert completed.")

    # Step 4: Run ODS -> DWH
    log(f"\n[3/3] Triggering ODS -> DWH Dimensional Load (dwh.usp_run_ods_to_dwh_pipeline @batch_id = {batch_id})...")
    run_sql_procedure(f"EXEC dwh.usp_run_ods_to_dwh_pipeline @batch_id = {batch_id};")
    log("ODS -> DWH pipeline completed.")

    elapsed = round(time.time() - start_time, 2)
    metrics = query_metrics(batch_id)

    log(f"\n--- BATCH {month_str} (Batch ID: {batch_id}) SUMMARY ---")
    log(f"  Duration              : {elapsed} seconds")
    log(f"  Batch Status          : {metrics.get('status', 'SUCCESS')}")
    log(f"  Records Ingested      : {metrics.get('stg_records', 0):,}")
    log(f"  DWH Cumulative Orders : {metrics.get('dwh_orders', 0):,}")
    log(f"  DWH Active Customers  : {metrics.get('dwh_active_customers', 0):,}")
    log(f"  SCD Type 2 Logged     : {metrics.get('scd2_changes', 0):,}")
    log(f"-------------------------------------------------------")

    return True


def main():
    parser = argparse.ArgumentParser(description="QuickBite Monthly Batch Pipeline Runner")
    parser.add_argument("--month", type=str, help="Specific month to run, e.g. '2026_01' or '01'")
    parser.add_argument("--all", action="store_true", help="Run all 9 months sequentially (2026_01 to 2026_09)")
    args = parser.parse_args()

    # Discover all monthly folders
    month_folders = sorted([d.name for d in INCOMING_DIR.iterdir() if d.is_dir() and d.name.startswith("2026_")])

    if not month_folders:
        log("No 2026_MM folders found in data/incoming/")
        sys.exit(1)

    if args.month:
        target = args.month if args.month.startswith("2026_") else f"2026_{int(args.month):02d}"
        if target not in month_folders:
            log(f"Error: Target month {target} not in available folders: {month_folders}")
            sys.exit(1)
        execute_month_batch(target)
    elif args.all:
        log(f"Starting sequential monthly batch ingestion for ALL {len(month_folders)} months: {month_folders}")
        for m in month_folders:
            success = execute_month_batch(m)
            if not success:
                log(f"Pipeline stopped due to failure at {m}")
                sys.exit(1)
        log("\n[SUCCESS] ALL 9 MONTHLY BATCHES PROCESSED SUCCESSFULLY!")
    else:
        log("Usage:")
        log("  python -m src.orchestration.monthly_pipeline --month 2026_01    # Run single month batch")
        log("  python -m src.orchestration.monthly_pipeline --all              # Run all 9 months sequentially")


if __name__ == "__main__":
    main()
