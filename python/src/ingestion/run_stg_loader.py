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

    total_records = 0
    success_records = 0
    error_records = 0
    has_critical_failure = False

    loader = StagingLoader()

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
            # Di chuyển file lỗi sang thư mục rejected
            shutil.move(str(file_path), str(rejected_dir / file_path.name))
            error_records += 1
            continue

        # Nếu file hợp lệ -> Nạp vào STG
        try:
            load_result = loader.load_file(
                file_path=file_path,
                source_name=result.source_name,
                batch_id=batch_id,
            )
            total_records += load_result.rows_loaded
            success_records += load_result.rows_loaded

            # Nạp thành công -> Di chuyển sang thư mục processed
            shutil.move(str(file_path), str(processed_dir / file_path.name))
            logger.info("Archived %s to processed directory", file_path.name)

        except StagingLoadError as exc:
            has_critical_failure = True
            logger.error("Failed to load %s into staging: %s", file_path.name, exc)
            # Di chuyển sang rejected
            shutil.move(str(file_path), str(rejected_dir / file_path.name))

    # 4. Đóng Batch trong bảng control.etl_batch
    if has_critical_failure:
        fail_batch(
            batch_id=batch_id,
            total_records=total_records + error_records,
            success_records=success_records,
            error_records=error_records + (total_records - success_records),
        )
        logger.error("Batch %s finished with errors.", batch_id)
    else:
        complete_batch(
            batch_id=batch_id,
            total_records=total_records + error_records,
            success_records=success_records,
            error_records=error_records,
        )
        logger.info("Batch %s completed successfully.", batch_id)


if __name__ == "__main__":
    BASE_DIR = Path(__file__).resolve().parents[3]
    run_staging_ingestion(
        incoming_dir=BASE_DIR / "data" / "incoming",
        processed_dir=BASE_DIR / "data" / "processed",
        rejected_dir=BASE_DIR / "data" / "rejected",
    )