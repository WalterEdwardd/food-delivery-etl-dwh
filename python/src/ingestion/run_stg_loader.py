"""Orchestrator script to validate, ingest incoming files to STG, and manage batch status."""

import shutil
from pathlib import Path

from src.config.source_schema import SOURCE_SCHEMA
from src.ingestion.stg_loader import StagingLoader, StagingLoadError
from src.orchestration.batch_manager import (
    complete_batch,
    fail_batch,
    start_batch,
)
from src.utils.logger import get_logger
from src.validation.file_validator import validate_all_files

logger = get_logger(__name__)


def _safe_move(src: Path, dst: Path) -> None:
    """Move *src* to *dst*, logging a warning instead of raising on failure."""
    try:
        shutil.move(str(src), str(dst))
    except Exception as exc:  # noqa: BLE001
        logger.warning(
            "Could not move file | src=%s | dst=%s | reason=%s",
            src.name,
            dst,
            exc,
        )


def run_staging_ingestion(
    incoming_dir: Path,
    processed_dir: Path,
    rejected_dir: Path,
    pipeline_name: str = "CSV_to_STG_Pipeline",
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

    rows_loaded = 0       # tổng số rows load thành công vào DB
    files_ok = 0          # số file load DB thành công
    files_rejected = 0    # số file bị reject (validation fail hoặc DB fail)
    has_critical_failure = False

    loader = StagingLoader()

    try:
        # 3. Lặp qua các file và thực hiện nạp dữ liệu
        for result in validation_results:
            file_path = result.file_path

            # Nếu file không hợp lệ theo schema/cấu trúc
            if not result.is_valid or not result.source_name:
                logger.warning(
                    "File validation failed: %s | Errors: %s",
                    file_path.name,
                    result.errors,
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

                # Nạp thành công -> Di chuyển sang thư mục processed
                # Thêm batch_id vào tên để tránh conflict khi retry
                _safe_move(
                    src=file_path,
                    dst=processed_dir / f"{file_path.stem}_batch{batch_id}{file_path.suffix}",
                )
                logger.info("Archived %s to processed directory", file_path.name)

            except StagingLoadError as exc:
                has_critical_failure = True
                files_rejected += 1
                logger.error("Failed to load %s into staging: %s", file_path.name, exc)
                _safe_move(
                    src=file_path,
                    dst=rejected_dir / f"{file_path.stem}_batch{batch_id}{file_path.suffix}",
                )

    except KeyboardInterrupt:
        logger.warning("Ingestion interrupted by user. Marking batch %s as failed.", batch_id)
        fail_batch(
            batch_id=batch_id,
            total_records=rows_loaded + files_rejected,
            success_records=rows_loaded,
            error_records=files_rejected,
        )
        raise

    # 4. Đóng Batch trong bảng control.etl_batch
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
            total_records=rows_loaded + files_rejected,
            success_records=rows_loaded,
            error_records=files_rejected,
        )
        logger.error("Batch %s finished with errors.", batch_id)
    else:
        complete_batch(
            batch_id=batch_id,
            total_records=rows_loaded + files_rejected,
            success_records=rows_loaded,
            error_records=files_rejected,
        )
        logger.info("Batch %s completed successfully.", batch_id)


if __name__ == "__main__":
    BASE_DIR = Path(__file__).resolve().parents[3]
    run_staging_ingestion(
        incoming_dir=BASE_DIR / "data" / "incoming",
        processed_dir=BASE_DIR / "data" / "processed",
        rejected_dir=BASE_DIR / "data" / "rejected",
    )