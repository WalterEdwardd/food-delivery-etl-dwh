# test start_batch
from src.orchestration.batch_manager import start_batch
def test_start_batch():
    batch_id = start_batch(
    pipeline_name = "FoodDeliveryETL",
    source_system = "CSV",
    source_file_count = 7,
    )

    assert batch_id is not None
    assert isinstance(batch_id, int)


# test complete
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


# test fail
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



# test invalid counters
import pytest
from src.orchestration.batch_manager import (
    start_batch,
    complete_batch
)
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


# test orphan running batch
def test_invalid_record_counts():
    with pytest.raises(ValueError):
        complete_batch(
            batch_id=999999,
            total_records=1000,
            success_records=900,
            error_records=200,
        )


# test batch not exists
def test_complete_non_existing_batch():
    with pytest.raises(RuntimeError):
        complete_batch(
            batch_id=999999999,
            total_records=100,
            success_records=90,
            error_records=10,
        )


# test lifecycle
from src.orchestration.batch_context import BatchContext

from src.orchestration.batch_manager import (
    start_batch,
    complete_batch,
)

def test_batch_execution():
    batch_id = start_batch(
        pipeline_name = "FoodDeliveryETL",
        source_system = "CSV",
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