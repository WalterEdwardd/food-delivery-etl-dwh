"""Load validated CSV source files into SQL Server staging tables."""

from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import pandas as pd
import pyodbc

from src.config.staging_config import STAGING_CONFIG
from src.config.database import get_connection


@dataclass(frozen=True)
class StagingLoadResult:
    """Summary returned after a staging load completes successfully."""

    source_name: str
    source_file_name: str
    target_table: str
    batch_id: int
    rows_loaded: int


class StagingLoadError(Exception):
    """Raised when a source file cannot be loaded into staging."""


class StagingLoader:
    """Load validated CSV files into SQL Server STG tables."""

    def __init__(
        self,
        connection_factory: Callable[[], pyodbc.Connection],
        chunk_size: int = 10_000,
    ) -> None:
        if chunk_size <= 0:
            raise ValueError("chunk_size must be greater than 0.")

        self.connection_factory = connection_factory
        self.chunk_size = chunk_size

    def load_file(
        self,
        file_path: Path,
        source_name: str,
        batch_id: int,
    ) -> StagingLoadResult:
        """
        Load one validated CSV file into its configured staging table.

        The whole file is processed in one database transaction.
        Existing rows for the same batch and source file are removed
        before reload to support idempotent retry.
        """

        file_path = Path(file_path)

        if not file_path.exists():
            raise FileNotFoundError(
                f"Source file does not exist: {file_path}"
            )

        if source_name not in STAGING_CONFIG:
            raise ValueError(
                f"Unknown source_name: {source_name}"
            )

        if batch_id <= 0:
            raise ValueError("batch_id must be greater than 0.")

        config = STAGING_CONFIG[source_name]

        target_table = config["table"]
        source_columns = config["columns"]
        source_file_name = file_path.name

        connection = None
        rows_loaded = 0

        try:
            connection = self.connection_factory()
            connection.autocommit = False

            cursor = connection.cursor()

            self._delete_existing_file_rows(
                cursor=cursor,
                target_table=target_table,
                batch_id=batch_id,
                source_file_name=source_file_name,
            )

            reader = pd.read_csv(
                file_path,
                dtype=str,
                keep_default_na=False,
                na_filter=False,
                encoding="utf-8-sig",
                chunksize=self.chunk_size,
            )

            next_source_row_number = 2

            for chunk in reader:
                self._validate_chunk_columns(
                    chunk=chunk,
                    expected_columns=source_columns,
                    source_file_name=source_file_name,
                )

                chunk_row_count = len(chunk)

                if chunk_row_count == 0:
                    continue

                source_row_numbers = range(
                    next_source_row_number,
                    next_source_row_number + chunk_row_count,
                )

                rows = self._build_insert_rows(
                    chunk=chunk,
                    source_columns=source_columns,
                    batch_id=batch_id,
                    source_file_name=source_file_name,
                    source_row_numbers=source_row_numbers,
                )

                self._insert_rows(
                    cursor=cursor,
                    target_table=target_table,
                    source_columns=source_columns,
                    rows=rows,
                )

                rows_loaded += chunk_row_count

                next_source_row_number += chunk_row_count

            connection.commit()

            return StagingLoadResult(
                source_name=source_name,
                source_file_name=source_file_name,
                target_table=target_table,
                batch_id=batch_id,
                rows_loaded=rows_loaded,
            )

        except Exception as exc:
            if connection is not None:
                connection.rollback()

            raise StagingLoadError(
                "Failed to load source file into staging. "
                f"source={source_name}, "
                f"file={file_path.name}, "
                f"batch_id={batch_id}. "
                f"Reason: {exc}"
            ) from exc

        finally:
            if connection is not None:
                connection.close()

    @staticmethod
    def _delete_existing_file_rows(
        cursor: pyodbc.Cursor,
        target_table: str,
        batch_id: int,
        source_file_name: str,
    ) -> None:
        """Remove rows from a previous attempt of the same file/batch."""

        sql = f"""
            DELETE FROM {target_table}
            WHERE batch_id = ?
              AND source_file_name = ?;
        """

        cursor.execute(
            sql,
            batch_id,
            source_file_name,
        )

    @staticmethod
    def _validate_chunk_columns(
        chunk: pd.DataFrame,
        expected_columns: list[str],
        source_file_name: str,
    ) -> None:
        """Defensive validation before inserting a CSV chunk."""

        actual_columns = list(chunk.columns)

        if actual_columns != expected_columns:
            raise ValueError(
                "CSV columns do not match staging contract. "
                f"file={source_file_name}, "
                f"expected={expected_columns}, "
                f"actual={actual_columns}"
            )

    @staticmethod
    def _build_insert_rows(
        chunk: pd.DataFrame,
        source_columns: list[str],
        batch_id: int,
        source_file_name: str,
        source_row_numbers,
    ) -> list[tuple]:
        """Build parameter tuples for pyodbc.executemany()."""

        rows = []

        source_values = chunk[source_columns].itertuples(
            index=False,
            name=None,
        )

        for values, row_number in zip(
            source_values,
            source_row_numbers,
        ):
            rows.append(
                (
                    *values,
                    batch_id,
                    source_file_name,
                    row_number,
                )
            )

        return rows

    @staticmethod
    def _insert_rows(
        cursor: pyodbc.Cursor,
        target_table: str,
        source_columns: list[str],
        rows: list[tuple],
    ) -> None:
        """Insert one chunk into the target staging table."""

        if not rows:
            return

        insert_columns = [
            *source_columns,
            "batch_id",
            "source_file_name",
            "source_row_number",
        ]

        column_sql = ", ".join(insert_columns)

        parameter_count = len(insert_columns)
        placeholders = ", ".join(["?"] * parameter_count)

        sql = f"""
            INSERT INTO {target_table}
            (
                {column_sql},
                load_timestamp
            )
            VALUES
            (
                {placeholders},
                SYSUTCDATETIME()
            );
        """

        cursor.fast_executemany = True
        cursor.executemany(sql, rows)