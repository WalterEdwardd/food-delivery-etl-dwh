from src.config.database import get_connection
from src.utils.logger import get_logger


logger = get_logger(__name__)


def start_batch(
    pipeline_name,
    source_system,
    source_file_count,
):
    logger.info(
        "Starting ETL batch | pipeline=%s | source=%s | files=%s",
        pipeline_name,
        source_system,
        source_file_count,
    )

    connection = get_connection()

    try:
        cursor = connection.cursor()

        cursor.execute(
            """
            INSERT INTO control.etl_batch
            (
                pipeline_name,
                source_system,
                source_file_count,
                start_time,
                status,
                total_records,
                success_records,
                error_records
            )
            OUTPUT INSERTED.batch_id
            VALUES
            (
                ?,
                ?,
                ?,
                SYSUTCDATETIME(),
                ?,
                0,
                0,
                0
            );
            """,
            pipeline_name,
            source_system,
            source_file_count,
            "RUNNING",
        )

        batch_id = cursor.fetchone()[0]

        connection.commit()

        logger.info(
            "ETL batch started successfully | batch_id=%s",
            batch_id,
        )

        return batch_id

    except Exception:
        connection.rollback()

        logger.exception(
            "Failed to start ETL batch"
        )

        raise

    finally:
        connection.close()


def _validate_record_counts(
        total_records,
        success_records,
        error_records,
):
    if total_records <0:
        raise ValueError("total_records cannot be negative")

    if success_records <0:
        raise ValueError("success_records cannot be negative")

    if error_records <0:
        raise ValueError("error_records cannot be nagative")

    if success_records + error_records != total_records:
        raise ValueError(
            "success_records + error_records "
            "must equal total_records"
        )


def complete_batch(
    batch_id,
    total_records,
    success_records,
    error_records,
):
    _validate_record_counts(
        total_records,
        success_records,
        error_records,
    )

    logger.info(
        "Completing ETL batch | batch_id=%s",
        batch_id,
    )

    connection = get_connection()

    try:
        cursor = connection.cursor()

        cursor.execute(
            """
            UPDATE control.etl_batch
            SET
                end_time = SYSUTCDATETIME(),
                status = ?,
                total_records = ?,
                success_records = ?,
                error_records = ?
            WHERE batch_id = ?
                AND status = 'RUNNING';
            """,
            "SUCCESS",
            total_records,
            success_records,
            error_records,
            batch_id,
        )

        if cursor.rowcount != 1:
            raise RuntimeError(
                f"Batch not found or multiple rows affected: "
                f"batch_id={batch_id}"
            )

        connection.commit()

        logger.info(
            "ETL batch completed successfully | "
            "batch_id=%s | total=%s | success=%s | error=%s",
            batch_id,
            total_records,
            success_records,
            error_records,
        )

    except Exception:
        connection.rollback()

        logger.exception(
            "Failed to complete ETL batch | batch_id=%s",
            batch_id,
        )

        raise

    finally:
        connection.close()


def fail_batch(
    batch_id,
    total_records=0,
    success_records=0,
    error_records=0,
):
    _validate_record_counts(
        total_records,
        success_records,
        error_records,
    )

    logger.error(
        "Failing ETL batch | batch_id=%s",
        batch_id,
    )

    connection = get_connection()

    try:
        cursor = connection.cursor()

        cursor.execute(
            """
            UPDATE control.etl_batch
            SET
                end_time = SYSUTCDATETIME(),
                status = ?,
                total_records = ?,
                success_records = ?,
                error_records = ?
            WHERE batch_id = ?
                AND status = 'RUNNING';
            """,
            "FAILED",
            total_records,
            success_records,
            error_records,
            batch_id,
        )

        if cursor.rowcount != 1:
            raise RuntimeError(
                f"Batch not found or multiple rows affected: "
                f"batch_id={batch_id}"
            )

        connection.commit()

        logger.error(
            "ETL batch marked as FAILED | batch_id=%s",
            batch_id,
        )

    except Exception:
        connection.rollback()

        logger.exception(
            "Failed to mark batch as FAILED | batch_id=%s",
            batch_id,
        )

        raise

    finally:
        connection.close()


def log_etl_error(
    batch_id: int,
    error_type: str,
    error_message: str,
    source_file_name: str | None = None,
    source_row_number: int | None = None,
    table_name: str | None = None,
    column_name: str | None = None,
    raw_value: str | None = None,
) -> int | None:
    """
    Log an error entry into control.etl_error.
    Returns the generated error_id or None if logging failed.
    """
    logger.warning(
        "Logging ETL error | batch_id=%s | type=%s | file=%s | msg=%s",
        batch_id,
        error_type,
        source_file_name,
        error_message,
    )
    connection = None
    try:
        connection = get_connection()
        cursor = connection.cursor()
        cursor.execute(
            """
            INSERT INTO control.etl_error
            (
                batch_id,
                source_file_name,
                source_row_number,
                table_name,
                column_name,
                error_type,
                error_message,
                raw_value,
                error_timestamp
            )
            OUTPUT INSERTED.error_id
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, SYSUTCDATETIME());
            """,
            batch_id,
            source_file_name,
            source_row_number,
            table_name,
            column_name,
            error_type,
            error_message[:4000] if error_message else "Unknown error",
            raw_value[:4000] if raw_value else None,
        )
        error_id = cursor.fetchone()[0]
        connection.commit()
        return error_id
    except Exception:
        if connection:
            connection.rollback()
        logger.exception("Failed to write entry to control.etl_error | batch_id=%s", batch_id)
        return None
    finally:
        if connection:
            connection.close()