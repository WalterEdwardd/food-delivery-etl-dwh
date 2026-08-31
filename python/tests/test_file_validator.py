from pathlib import Path

from src.config.source_schema import SOURCE_SCHEMA
from src.validation.file_validator import identify_source

# Test Identify Customer Source
def test_identify_customer_source():

    file_path = Path(
        "customer_20250930.csv"
    )

    result = identify_source(
        file_path,
        SOURCE_SCHEMA,
    )

    assert result == "customer"

# Test Invalid File Name
def test_invalid_filename():

    file_path = Path(
        "customer_test.csv"
    )

    result = identify_source(
        file_path,
        SOURCE_SCHEMA,
    )

    assert result is None

# Test Missing Requireed Column
def test_missing_required_column(tmp_path):

    file_path = (
        tmp_path /
        "customer_20251201.csv"
    )

    file_path.write_text(
        "signup_date,city,acquisition_channel\n"
        "2025-12-01,Hanoi,Organic\n",
        encoding="utf-8",
    )

    from src.validation.file_validator import (
        validate_file,
    )

    result = validate_file(
        file_path,
        SOURCE_SCHEMA,
    )

    assert result.is_valid is False

    assert any(
        "customer_id" in error
        for error in result.errors
    )

# Test Optional Column
def test_optional_column_can_be_missing(tmp_path):

    file_path = (
        tmp_path /
        "customer_20251201.csv"
    )

    file_path.write_text(
        "customer_id,signup_date,city\n"
        "C001,2025-12-01,Hanoi\n",
        encoding="utf-8",
    )

    from src.validation.file_validator import (
        validate_file,
    )

    result = validate_file(
        file_path,
        SOURCE_SCHEMA,
    )

    assert result.is_valid is True

# Test Unexpected Column
def test_unexpected_column(tmp_path):

    file_path = (
        tmp_path /
        "customer_20251201.csv"
    )

    file_path.write_text(
        "customer_id,signup_date,city,"
        "acquisition_channel,country\n"
        "C001,2025-12-01,Hanoi,"
        "Organic,Vietnam\n",
        encoding="utf-8",
    )

    from src.validation.file_validator import (
        validate_file,
    )

    result = validate_file(
        file_path,
        SOURCE_SCHEMA,
    )

    assert result.is_valid is False

    assert any(
        "country" in error
        for error in result.errors
    )

# Test Column Order
def test_column_order_does_not_matter(tmp_path):

    file_path = (
        tmp_path /
        "customer_20251201.csv"
    )

    file_path.write_text(
        "city,customer_id,signup_date,"
        "acquisition_channel\n"
        "Hanoi,C001,2025-12-01,Organic\n",
        encoding="utf-8",
    )

    from src.validation.file_validator import (
        validate_file,
    )

    result = validate_file(
        file_path,
        SOURCE_SCHEMA,
    )

    assert result.is_valid is True