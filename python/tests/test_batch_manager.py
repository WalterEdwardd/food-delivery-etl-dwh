from src.orchestration.batch_manager import (
    start_batch,
    complete_batch,
)


def test_batch_lifecycle():
    batch_id = start_batch(
        pipeline_name="FoodDeliveryETL",
        source_system="CSV",
        source_file_count=8,
    )

    assert batch_id is not None

    complete_batch(
        batch_id=batch_id,
        total_records=1000,
        success_records=990,
        error_records=10,
    )

from src.orchestration.batch_manager import (
    start_batch,
    fail_batch,
)


def test_batch_failure():
    batch_id = start_batch(
        pipeline_name="FoodDeliveryETL",
        source_system="CSV",
        source_file_count=8,
    )

    assert batch_id is not None

    fail_batch(
        batch_id=batch_id,
        total_records=1000,
        success_records=800,
        error_records=200,
    )

import pytest

from src.orchestration.batch_manager import complete_batch


def test_invalid_record_counts():
    with pytest.raises(ValueError):
        complete_batch(
            batch_id=999999,
            total_records=1000,
            success_records=900,
            error_records=50,
        )