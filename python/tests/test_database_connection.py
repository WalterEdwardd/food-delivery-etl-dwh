from unittest.mock import patch

from src.config.database import (
    get_connection,
    get_connection_string,
    resolve_odbc_driver,
)


def test_database_connection():
    connection = get_connection()
    cursor = connection.cursor()
    cursor.execute("SELECT DB_NAME()")
    database_name = cursor.fetchone()[0]
    connection.close()

    assert database_name == "FoodDeliveryDW"


def test_resolve_odbc_driver_returns_installed_driver():
    driver = resolve_odbc_driver("ODBC Driver 17 for SQL Server")
    assert driver == "ODBC Driver 17 for SQL Server"


def test_resolve_odbc_driver_fallback_when_preferred_missing():
    with patch("pyodbc.drivers", return_value=["ODBC Driver 17 for SQL Server"]):
        driver = resolve_odbc_driver("NonExistentDriver")
        assert driver == "ODBC Driver 17 for SQL Server"


def test_get_connection_string_structure():
    conn_str = get_connection_string()
    assert "DRIVER=" in conn_str
    assert "SERVER=" in conn_str
    assert "DATABASE=" in conn_str