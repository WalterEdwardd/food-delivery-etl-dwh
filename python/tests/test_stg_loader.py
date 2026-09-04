from pathlib import Path
from unittest.mock import MagicMock
import pandas as pd
import pytest

from src.config.staging_config import STAGING_CONFIG
from src.ingestion.stg_loader import (
    StagingLoader,
    StagingLoadResult,
    StagingLoadError,
)


def test_all_sources_have_staging_configuration():
    expected_sources = {
        "customer",
        "delivery_partner",
        "delivery_performance",
        "menu_item",
        "order",
        "order_item",
        "rating",
        "restaurant",
    }
    assert set(STAGING_CONFIG.keys()) == expected_sources


def test_staging_loader_rejects_invalid_chunk_size():
    with pytest.raises(ValueError, match="chunk_size"):
        StagingLoader(connection_factory=lambda: None, chunk_size=0)


def test_load_file_rejects_non_existent_file():
    loader = StagingLoader(connection_factory=lambda: None)
    with pytest.raises(FileNotFoundError, match="Source file does not exist"):
        loader.load_file(
            file_path=Path("non_existent_file.csv"),
            source_name="customer",
            batch_id=1,
        )


def test_load_file_rejects_unknown_source(tmp_path):
    dummy_file = tmp_path / "dummy.csv"
    dummy_file.write_text("col1,col2\n1,2")

    loader = StagingLoader(connection_factory=lambda: None)
    with pytest.raises(ValueError, match="Unknown source_name"):
        loader.load_file(
            file_path=dummy_file,
            source_name="unknown_source",
            batch_id=1,
        )


def test_load_file_rejects_invalid_batch_id(tmp_path):
    dummy_file = tmp_path / "customer.csv"
    dummy_file.write_text("customer_id,signup_date,city,acquisition_channel\nC1,2025-01-01,HCM,Direct")

    loader = StagingLoader(connection_factory=lambda: None)
    with pytest.raises(ValueError, match="batch_id"):
        loader.load_file(
            file_path=dummy_file,
            source_name="customer",
            batch_id=0,
        )


def test_build_insert_rows_maps_correctly():
    df = pd.DataFrame(
        {
            "customer_id": ["C1", "C2"],
            "signup_date": ["2025-01-01", "2025-01-02"],
            "city": ["HCM", "HN"],
            "acquisition_channel": ["Organic", "Ads"],
        }
    )

    rows = StagingLoader._build_insert_rows(
        chunk=df,
        source_columns=["customer_id", "signup_date", "city", "acquisition_channel"],
        batch_id=10,
        source_file_name="customer_20250930.csv",
        source_row_numbers=range(2, 4),
    )

    assert len(rows) == 2
    assert rows[0] == ("C1", "2025-01-01", "HCM", "Organic", 10, "customer_20250930.csv", 2)
    assert rows[1] == ("C2", "2025-01-02", "HN", "Ads", 10, "customer_20250930.csv", 3)


def test_load_file_success_end_to_end(tmp_path):
    csv_file = tmp_path / "customer_20250930.csv"
    csv_file.write_text("customer_id,signup_date,city,acquisition_channel\nC1,2025-01-01,HCM,Organic\nC2,2025-01-02,HN,Ads")

    mock_cursor = MagicMock()
    mock_conn = MagicMock()
    mock_conn.cursor.return_value = mock_cursor

    loader = StagingLoader(connection_factory=lambda: mock_conn, chunk_size=1000)
    result = loader.load_file(
        file_path=csv_file,
        source_name="customer",
        batch_id=1,
    )

    # 1. Verify delete called
    assert mock_cursor.execute.called
    # 2. Verify insert executemany called with 2 rows
    assert mock_cursor.executemany.called
    inserted_rows = mock_cursor.executemany.call_args[0][1]
    assert len(inserted_rows) == 2
    # 3. Verify commit & close
    mock_conn.commit.assert_called_once()
    mock_conn.close.assert_called_once()
    # 4. Verify result object
    assert isinstance(result, StagingLoadResult)
    assert result.rows_loaded == 2
    assert result.source_name == "customer"


def test_load_file_rollback_on_error(tmp_path):
    csv_file = tmp_path / "customer_20250930.csv"
    csv_file.write_text("customer_id,signup_date,city,acquisition_channel\nC1,2025-01-01,HCM,Organic")

    mock_cursor = MagicMock()
    mock_cursor.executemany.side_effect = Exception("DB Connection Lost")
    mock_conn = MagicMock()
    mock_conn.cursor.return_value = mock_cursor

    loader = StagingLoader(connection_factory=lambda: mock_conn)

    with pytest.raises(StagingLoadError, match="Failed to load source file"):
        loader.load_file(
            file_path=csv_file,
            source_name="customer",
            batch_id=1,
        )

    mock_conn.rollback.assert_called_once()
    mock_conn.close.assert_called_once()