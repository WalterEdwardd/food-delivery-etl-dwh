"""Orchestrator script to validate, ingest incoming files to STG, sync to RAW, and manage batch status."""

import shutil
from pathlib import Path

from src.config.database import get_connection
from src.config.source_schema import SOURCE_SCHEMA
from src.ingestion.stg_loader import StagingLoader, StagingLoadError
from src.orchestration.batch_manager import (
    complete_batch,
    fail_batch,
    log_etl_error,
    start_batch,
)
from src.utils.logger import get_logger
from src.validation.file_validator import validate_all_files

logger = get_logger(__name__)


def _safe_move(src: Path, dst: Path) -> bool:
    """Move *src* to *dst*, logging a warning on failure. Returns True if succeeded."""
    try:
        shutil.move(str(src), str(dst))
        return True
    except Exception as exc:  # noqa: BLE001
        logger.warning(
            "Could not move file | src=%s | dst=%s | reason=%s",
            src.name,
            dst,
            exc,
        )
        return False


def truncate_staging_tables(connection_factory=get_connection) -> None:
    """Truncate all transient staging tables before batch ingestion."""
    logger.info("Truncating transient staging tables (stg.usp_truncate_stg_tables)...")
    conn = connection_factory()
    try:
        conn.autocommit = True
        with conn.cursor() as cursor:
            cursor.execute("EXEC stg.usp_truncate_stg_tables;")
        logger.info("Transient staging tables truncated successfully.")
    finally:
        conn.close()


def load_stg_to_raw(batch_id: int, connection_factory=get_connection) -> dict:
    """
    Execute the T-SQL orchestration stored procedure dbo.usp_load_raw_batch.
    Loads data from STG to RAW for the given batch_id, with full audit logging.
    """
    logger.info("Executing STG -> RAW batch load | batch_id=%s", batch_id)
    conn = connection_factory()
    try:
        conn.autocommit = True
        summary = {}
        with conn.cursor() as cursor:
            cursor.execute("EXEC dbo.usp_load_raw_batch @batch_id = ?;", batch_id)
            while cursor.description:
                rows = cursor.fetchall()
                if rows:
                    columns = [col[0] for col in cursor.description]
                    summary = dict(zip(columns, rows[0]))
                if not cursor.nextset():
                    break
        logger.info(
            "STG -> RAW batch load succeeded | batch_id=%s | summary=%s",
            batch_id,
            summary,
        )
        return summary
    except Exception as exc:
        logger.exception("STG -> RAW batch load failed | batch_id=%s | error=%s", batch_id, exc)
        raise
    finally:
        conn.close()


def run_staging_ingestion(
    incoming_dir: Path,
    processed_dir: Path,
    rejected_dir: Path,
    pipeline_name: str = "CSV_to_RAW_Pipeline",
    source_system: str = "Source_CSV",
):
    incoming_dir.mkdir(parents=True, exist_ok=True)
    processed_dir.mkdir(parents=True, exist_ok=True)
    rejected_dir.mkdir(parents=True, exist_ok=True)

    # 1. Validate tất cả các file trong thư mục incoming
    logger.info("Scanning and validating incoming files in %s", incoming_dir)
    validation_results = validate_all_files(incoming_dir, SOURCE_SCHEMA)

    if not validation_results:
        logger.info("No files found in incoming directory. Ingestion skipped.")
        return

    # 2. Khởi tạo Batch trong bảng control.etl_batch
    batch_id = start_batch(
        pipeline_name=pipeline_name,
        source_system=source_system,
        source_file_count=len(validation_results),
    )

    rows_loaded = 0         # tổng số rows load thành công vào DB
    files_ok = 0            # số file load DB thành công
    files_rejected = 0      # số file bị reject (validation fail hoặc DB fail)
    has_critical_failure = False
    files_to_archive: list[tuple[Path, Path]] = []

    loader = StagingLoader()

    try:
        # 3. Truncate staging tables để chuẩn bị nạp batch mới
        truncate_staging_tables()

        # 4. Lặp qua các file và thực hiện nạp dữ liệu vào STG
        for result in validation_results:
            file_path = result.file_path

            # Nếu file không hợp lệ theo schema/cấu trúc
            if not result.is_valid or not result.source_name:
                err_msg = "; ".join(result.errors) if result.errors else "Unknown validation error"
                logger.warning(
                    "File validation failed: %s | Errors: %s",
                    file_path.name,
                    result.errors,
                )
                log_etl_error(
                    batch_id=batch_id,
                    error_type="FILE_VALIDATION_ERROR",
                    error_message=err_msg,
                    source_file_name=file_path.name,
                    table_name=result.source_name or "UNKNOWN",
                )
                _safe_move(
                    src=file_path,
                    dst=rejected_dir / f"{file_path.stem}_batch{batch_id}{file_path.suffix}",
                )
                files_rejected += 1
                continue

            # Nếu file hợp lệ -> Nạp vào STG
            try:
                load_result = loader.load_file(
                    file_path=file_path,
                    source_name=result.source_name,
                    batch_id=batch_id,
                )
                rows_loaded += load_result.rows_loaded
                files_ok += 1

                # Ghi nhận file cần lưu trữ sau khi toàn bộ quy trình STG -> RAW hoàn tất (2-phase commit)
                target_archive_path = processed_dir / f"{file_path.stem}_batch{batch_id}{file_path.suffix}"
                files_to_archive.append((file_path, target_archive_path))

            except StagingLoadError as exc:
                has_critical_failure = True
                files_rejected += 1
                logger.error("Failed to load %s into staging: %s", file_path.name, exc)
                log_etl_error(
                    batch_id=batch_id,
                    error_type="STAGING_LOAD_ERROR",
                    error_message=str(exc),
                    source_file_name=file_path.name,
                    table_name=result.source_name,
                )
                _safe_move(
                    src=file_path,
                    dst=rejected_dir / f"{file_path.stem}_batch{batch_id}{file_path.suffix}",
                )

        # 5. Nếu nạp STG thành công cho các file hợp lệ -> Kích hoạt STG -> RAW
        if not has_critical_failure and files_ok > 0:
            try:
                load_stg_to_raw(batch_id=batch_id)

                # Nạp RAW thành công -> Thực hiện archive các file hợp lệ sang processed
                for src_file, dst_file in files_to_archive:
                    _safe_move(src=src_file, dst=dst_file)
                    logger.info("Archived %s to processed directory", src_file.name)

                # Dọn dẹp STG sau khi đã lưu an toàn vào RAW
                truncate_staging_tables()

            except Exception as raw_exc:
                has_critical_failure = True
                logger.error("STG -> RAW execution failed for batch %s: %s", batch_id, raw_exc)
                log_etl_error(
                    batch_id=batch_id,
                    error_type="RAW_LOAD_ERROR",
                    error_message=str(raw_exc),
                    table_name="RAW_BATCH_LOAD",
                )

    except KeyboardInterrupt:
        logger.warning("Ingestion interrupted by user. Marking batch %s as failed.", batch_id)
        fail_batch(
            batch_id=batch_id,
            total_records=rows_loaded,
            success_records=0,
            error_records=rows_loaded,
        )
        raise

    # 6. Đóng Batch trong bảng control.etl_batch
    logger.info(
        "Ingestion summary | batch_id=%s | files_ok=%d | files_rejected=%d | rows_loaded=%d",
        batch_id,
        files_ok,
        files_rejected,
        rows_loaded,
    )

    if has_critical_failure:
        fail_batch(
            batch_id=batch_id,
            total_records=rows_loaded,
            success_records=0,
            error_records=rows_loaded,
        )
        logger.error("Batch %s finished with errors.", batch_id)
    else:
        complete_batch(
            batch_id=batch_id,
            total_records=rows_loaded,
            success_records=rows_loaded,
            error_records=0,
        )
        logger.info("Batch %s (CSV -> STG -> RAW) completed successfully.", batch_id)


if __name__ == "__main__":
    BASE_DIR = Path(__file__).resolve().parents[3]
    run_staging_ingestion(
        incoming_dir=BASE_DIR / "data" / "incoming",
        processed_dir=BASE_DIR / "data" / "processed",
        rejected_dir=BASE_DIR / "data" / "rejected",
    )