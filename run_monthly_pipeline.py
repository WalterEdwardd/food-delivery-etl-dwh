"""
QuickBite Data Platform - Root CLI Entrypoint for Monthly Batch Pipeline
Delegates execution to src.orchestration.monthly_pipeline using the project virtual environment.
"""

import sys
import subprocess
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent
PYTHON_DIR = PROJECT_ROOT / "python"

VENV_PY = PYTHON_DIR / ".venv" / "Scripts" / "python.exe"
PY_EXE = str(VENV_PY) if VENV_PY.exists() else sys.executable

if __name__ == "__main__":
    cmd = [PY_EXE, "-m", "src.orchestration.monthly_pipeline"] + sys.argv[1:]
    res = subprocess.run(cmd, cwd=str(PYTHON_DIR))
    sys.exit(res.returncode)
