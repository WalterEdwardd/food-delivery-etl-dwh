"""Database connection provider with dynamic configuration and driver fallback."""

import pyodbc

from src.config import settings
from src.utils.logger import get_logger

logger = get_logger(__name__)


def resolve_odbc_driver(preferred_driver: str | None = None) -> str:
    """
    Resolve a compatible ODBC driver installed on the current host.
    Falls back gracefully if the preferred driver is not installed.
    """
    available_drivers = pyodbc.drivers()
    preferred = preferred_driver or settings.DB_DRIVER

    if preferred and preferred in available_drivers:
        return preferred

    candidates = [
        "ODBC Driver 17 for SQL Server",
        "ODBC Driver 18 for SQL Server",
        "SQL Server Native Client 11.0",
        "SQL Server",
    ]

    for candidate in candidates:
        if candidate in available_drivers:
            logger.warning(
                "Preferred ODBC driver '%s' not found. Falling back to '%s'. Available: %s",
                preferred,
                candidate,
                available_drivers,
            )
            return candidate

    logger.error("No compatible SQL Server ODBC driver found in: %s", available_drivers)
    return preferred or "ODBC Driver 17 for SQL Server"


def get_connection_string() -> str:
    """Build connection string dynamically from configuration settings."""
    driver = resolve_odbc_driver(settings.DB_DRIVER)
    server = settings.DB_SERVER
    if settings.DB_PORT:
        server = f"{server},{settings.DB_PORT}"

    parts = [
        f"DRIVER={{{driver}}}",
        f"SERVER={server}",
        f"DATABASE={settings.DB_DATABASE}",
    ]

    # Authentication mode selection
    if settings.DB_USER and settings.DB_PASSWORD:
        parts.append(f"UID={settings.DB_USER}")
        parts.append(f"PWD={settings.DB_PASSWORD}")
    else:
        parts.append(f"Trusted_Connection={settings.DB_TRUSTED_CONNECTION}")

    if settings.DB_TRUST_SERVER_CERTIFICATE:
        parts.append(f"TrustServerCertificate={settings.DB_TRUST_SERVER_CERTIFICATE}")

    return ";".join(parts) + ";"


def get_connection() -> pyodbc.Connection:
    """Create and return a database connection using dynamic configuration."""
    conn_str = get_connection_string()
    try:
        return pyodbc.connect(conn_str, timeout=settings.DB_TIMEOUT)
    except pyodbc.Error as exc:
        logger.exception("Failed to connect to database with connection string: %s", conn_str)
        raise exc
