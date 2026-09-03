from pathlib import Path

import pandas as pd
import pytest

from src.config.staging_config import STAGING_CONFIG
from src.ingestion.stg_loader import StagingLoader


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
        StagingLoader(
            connection_factory=lambda: None,
            chunk_size=0,
        )


def test_validate_chunk_columns_accepts_expected_columns():
    chunk = pd.DataFrame(
        columns=[
            "customer_id",
            "signup_date",
            "city",
            "acquisition_channel",
        ]
    )

    StagingLoader._validate_chunk_columns(
        chunk=chunk,
        expected_columns=[
            "customer_id",
            "signup_date",
            "city",
            "acquisition_channel",
        ],
        source_file_name="customer_20250930.csv",
    )


def test_validate_chunk_columns_rejects_wrong_columns():
    chunk = pd.DataFrame(
        columns=[
            "customer_id",
            "signup_date",
            "wrong_column",
            "acquisition_channel",
        ]
    )

    with pytest.raises(
        ValueError,
        match="CSV columns do not match staging contract",
    ):
        StagingLoader._validate_chunk_columns(
            chunk=chunk,
            expected_columns=[
                "customer_id",
                "signup_date",
                "city",
                "acquisition_channel",
            ],
            source_file_name="customer_20250930.csv",
        )


def test_load_file_rejects_unknown_source():
    loader = StagingLoader(
        connection_factory=lambda: None
    )

    with pytest.raises(FileNotFoundError):
        loader.load_file(
            file_path=Path("does_not_exist.csv"),
            source_name="unknown",
            batch_id=1,
        )