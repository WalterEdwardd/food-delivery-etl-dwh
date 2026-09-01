from src.orchestration.batch_context import BatchContext


def test_batch_context():
    context = BatchContext(
        batch_id=1001
    )

    assert context.batch_id == 1001