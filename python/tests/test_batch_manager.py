from unittest.mock import MagicMock, patch
import pytest

from src.orchestration.batch_context import BatchContext
from src.orchestration.batch_manager import (
    complete_batch,
    fail_batch,
    log_etl_error,
    log_etl_warning,
    start_batch,
)


@pytest.fixture(autouse=True)
def mock_db():
    """
    Mock database connection for all batch manager tests.
    Guarantees that no real database operations occur during testing.
    """
    with patch("src.orchestration.batch_manager.get_connection") as mock_get_conn:
        mock_conn = MagicMock()
        mock_cursor = MagicMock()

        # Default: return batch_id/error_id/warning_id = 1001
        mock_cursor.fetchone.return_value = (1001,)
        # Default: rowcount = 1 for successful UPDATEs
        mock_cursor.rowcount = 1

        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn

        yield {
            "get_connection": mock_get_conn,
            "connection": mock_conn,
            "cursor": mock_cursor,
        }


def test_start_batch(mock_db):
    batch_id = start_batch(
        pipeline_name="FoodDeliveryETL",
        source_system="CSV",
        source_file_count=7,
    )

    assert batch_id == 1001
    assert isinstance(batch_id, int)
    assert mock_db["cursor"].execute.called
    mock_db["connection"].commit.assert_called_once()
    mock_db["connection"].close.assert_called_once()


def test_batch_lifecycle(mock_db):
    batch_id = start_batch(
        pipeline_name="FoodDeliveryETL",
        source_system="CSV",
        source_file_count=8,
    )

    assert batch_id == 1001

    complete_batch(
        batch_id=batch_id,
        total_records=1000,
        success_records=990,
        error_records=10,
    )

    assert mock_db["cursor"].execute.called
    assert mock_db["connection"].commit.call_count == 2
    assert mock_db["connection"].close.call_count == 2


def test_batch_failure(mock_db):
    batch_id = start_batch(
        pipeline_name="FoodDeliveryETL",
        source_system="CSV",
        source_file_count=8,
    )

    assert batch_id == 1001

    fail_batch(
        batch_id=batch_id,
        total_records=1000,
        success_records=800,
        error_records=200,
    )

    assert mock_db["cursor"].execute.called
    assert mock_db["connection"].commit.call_count == 2
    assert mock_db["connection"].close.call_count == 2


def test_invalid_record_counts():
    batch_id = start_batch(
        pipeline_name="FoodDeliveryETL",
        source_system="CSV",
        source_file_count=8,
    )

    with pytest.raises(ValueError):
        complete_batch(
            batch_id=batch_id,
            total_records=1000,
            success_records=900,
            error_records=200,
        )


def test_orphan_batch_invalid_counts():
    with pytest.raises(ValueError):
        complete_batch(
            batch_id=999999,
            total_records=1000,
            success_records=900,
            error_records=200,
        )


def test_complete_non_existing_batch(mock_db):
    # Simulate batch not found or rowcount != 1
    mock_db["cursor"].rowcount = 0

    with pytest.raises(RuntimeError):
        complete_batch(
            batch_id=999999999,
            total_records=100,
            success_records=90,
            error_records=10,
        )


def test_batch_execution(mock_db):
    batch_id = start_batch(
        pipeline_name="FoodDeliveryETL",
        source_system="CSV",
        source_file_count=8,
    )

    context = BatchContext(
        batch_id=batch_id
    )

    assert context.batch_id == batch_id

    complete_batch(
        batch_id=context.batch_id,
        total_records=1000,
        success_records=990,
        error_records=10,
    )


def test_log_etl_error(mock_db):
    batch_id = start_batch(
        pipeline_name="FoodDeliveryETL_ErrorTest",
        source_system="CSV",
        source_file_count=1,
    )

    error_id = log_etl_error(
        batch_id=batch_id,
        error_type="FILE_VALIDATION_ERROR",
        error_message="Test validation error for unit test",
        source_file_name="test_customer.csv",
        table_name="customer",
    )

    assert error_id == 1001
    assert isinstance(error_id, int)

    fail_batch(
        batch_id=batch_id,
        total_records=0,
        success_records=0,
        error_records=0,
    )


def test_log_etl_warning(mock_db):
    batch_id = start_batch(
        pipeline_name="FoodDeliveryETL_WarningTest",
        source_system="CSV",
        source_file_count=1,
    )

    warning_id = log_etl_warning(
        batch_id=batch_id,
        step_name="UNIT_TEST_STEP",
        entity_name="CUSTOMER",
        entity_id="CUST_99999",
        warning_type="ORPHAN_CUSTOMER_DETECTED",
        warning_message="Unit test orphan customer warning",
    )

    assert warning_id == 1001
    assert isinstance(warning_id, int)

    fail_batch(
        batch_id=batch_id,
        total_records=0,
        success_records=0,
        error_records=0,
    )