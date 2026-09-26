import os
from pathlib import Path
from dotenv import load_dotenv

# Search for .env in python directory or project root
_CURRENT_DIR = Path(__file__).resolve().parent
_PYTHON_DIR = _CURRENT_DIR.parents[1]
_ROOT_DIR = _CURRENT_DIR.parents[2]

for _env_candidate in (_PYTHON_DIR / ".env", _ROOT_DIR / ".env"):
    if _env_candidate.is_file():
        load_dotenv(dotenv_path=_env_candidate)
        break
else:
    load_dotenv()

# Database Connection Parameters with safe production defaults
DB_SERVER = os.getenv("DB_SERVER", r"localhost\SQLEXPRESS")
DB_DATABASE = os.getenv("DB_DATABASE", "FoodDeliveryDW")
DB_DRIVER = os.getenv("DB_DRIVER", "ODBC Driver 17 for SQL Server")
DB_PORT = os.getenv("DB_PORT", "")

# Authentication parameters
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_TRUSTED_CONNECTION = os.getenv("DB_TRUSTED_CONNECTION", "yes")
DB_TRUST_SERVER_CERTIFICATE = os.getenv("DB_TRUST_SERVER_CERTIFICATE", "yes")

# Timeout in seconds
try:
    DB_TIMEOUT = int(os.getenv("DB_TIMEOUT", "30"))
except ValueError:
    DB_TIMEOUT = 30