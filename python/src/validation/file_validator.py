from dataclasses import dataclass
from pathlib import Path
import re

import pandas as pd

# Validation Result
@dataclass
class FileValidationResult:
    file_path: Path
    is_valid: bool
    source_name: str | None
    errors: list[str]

# File Discovery
def discover_files(input_dir: Path) -> list[Path]:
    """ 
    Find all CSV files in the incoming directory
    """
    files = []

    for file_path in input_dir.iterdir():

        if file_path.is_file() and file_path.suffix.lower() == ".csv":
            files.append(file_path)

    return sorted(files)

# Identify Source
def identify_source(
    file_path: Path,
    source_schema: dict,
) -> str | None:
    """ 
    Identity source entity from filename
    """

    file_name = file_path.name

    for source_name, config in source_schema.items():

        pattern = config["file_pattern"]

        if re.fullmatch(pattern, file_name):
            return source_name

    return None

# Validate File Existence
def validate_file_exists(
    file_path: Path,        
) -> list[str]:
    """ 
    Validate file exists and basic filesystem state.    
    """
    errors = []

    if not file_path.exists():
        errors.append(
            "File does not exist"
        )
        return errors

    if not file_path.is_file():
        errors.append(
            "Path is not a file"
        )
        return errors

    if file_path.stat().st_size == 0:
        errors.append(
            "Files is empty"
        )

    return errors


# Validate CSV Readability
def validate_csv_readability(
    file_path: Path,
) -> list[str]:
    """ 
    Validate that the CSV can be read.
    """
    try:
        pd.read_csv(
            file_path,
            nrows=0,
            )

    except Exception as exc:
        return [
            f"Unable to read CSV: {exc}"
        ]

    return []

# Validate Empty Data File
def validate_has_data(
    file_path: Path,
) -> list[str]:
    """ 
    Validate that the CSV contains at least one data row.
    """
    try:
        sample = pd.read_csv(
            file_path,
            nrows = 1,
        )

        if sample.empty:
            return [
                "CSV file contains no data rows"
            ]

    except Exception as exc:
        return [
            f"Unable to inspect CSV data: {exc}"
        ]

    return []

# Validate Colums
def validate_columns(
    file_path: Path,
    source_config: dict,
) -> list[str]:
    """ 
    Validate CSV columns against source schema.
    """
    errors = []

    try:
        actual_columns = pd.read_csv(
            file_path,
            nrows=0,
        ).columns.to_list()

    except Exception as exc:
        return [
            f"Unable to read CSV header: {exc}"
        ]

    column_metadata = source_config["columns"]

    expected_columns = list(
        column_metadata.keys()
    )

    required_columns = [
        column_name
        for column_name, metadata
        in column_metadata.items()
        if metadata["required"]
    ]

    missing_required = [
        column_name
        for column_name in required_columns
        if column_name not in actual_columns
    ]

    unexpected_columns = [
        column_name
        for column_name in actual_columns
        if column_name not in expected_columns
    ]

    if missing_required:
        errors.append(
            "Missing required columns: "
            f"{missing_required}"
        )

    if unexpected_columns:
        errors.append(
            "Unexpected columns: "
            f"{unexpected_columns}"
        )

    return errors

# Main Validate File
def validate_file(
    file_path: Path,
    source_schema: dict,
) -> FileValidationResult:

    errors = []

    source_name = identify_source(
        file_path,
        source_schema,
    )

    if source_name is None:
        errors.append(
            f"Invalid filename: {file_path.name}"
        )

        return FileValidationResult(
            file_path=file_path,
            is_valid=False,
            source_name=None,
            errors=errors,
        )
    
    errors.extend(
        validate_file_exists(file_path)
    )

    if errors:
        return FileValidationResult(
            file_path=file_path,
            is_valid=False,
            source_name=source_name,
            errors=errors,
        )

    errors.extend(
        validate_csv_readability(file_path)
    )

    if errors:
        return FileValidationResult(
            file_path=file_path,
            is_valid=False,
            source_name=source_name,
            errors=errors,
        )

    source_config = source_schema[
        source_name
    ]

    errors.extend(
        validate_columns(
            file_path,
            source_config,
        )
    )

    errors.extend(
        validate_has_data(file_path)
    )

    return FileValidationResult(
        file_path=file_path,
        is_valid=len(errors) == 0,
        source_name=source_name,
        errors=errors,
    )

# Validate all files in incoming folder
def validate_all_files(
        input_dir: Path,
        source_schema: dict,
) -> list[FileValidationResult]:

    files = discover_files(
        input_dir
    )

    results = []

    for file_path in files:

        result = validate_file(
            file_path,
            source_schema,
        )

        results.append(result)

    return results

# Validation Summary
def summarize_results(
    results: list[FileValidationResult],
) -> dict:

    total_files = len(results)

    valid_files = sum(
        result.is_valid
        for result in results
    )

    invalid_files = (
        total_files - valid_files
    )

    return {
        "total_files": total_files,
        "valid_files": valid_files,
        "invalid_files": invalid_files
    }
