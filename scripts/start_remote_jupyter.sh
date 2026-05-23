#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_PYTHON="$ROOT_DIR/.venv/bin/python"
HOST="${JUPYTER_HOST:-127.0.0.1}"
PORT="${JUPYTER_PORT:-8888}"
LOG_FILE="${JUPYTER_LOG_FILE:-/tmp/deep-learning-study-jupyter.log}"
PID_FILE="${JUPYTER_PID_FILE:-/tmp/deep-learning-study-jupyter.pid}"
STARTUP_TIMEOUT_SECONDS="${JUPYTER_STARTUP_TIMEOUT_SECONDS:-20}"

if [[ ! -x "$VENV_PYTHON" ]]; then
  echo "Missing .venv python. Run: python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt" >&2
  exit 1
fi

if [[ -f "$PID_FILE" ]]; then
  EXISTING_PID="$(cat "$PID_FILE" || true)"
  if [[ -n "${EXISTING_PID}" ]] && kill -0 "${EXISTING_PID}" 2>/dev/null && lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN | grep -q "${EXISTING_PID}"; then
    echo "Jupyter is already running with PID ${EXISTING_PID}."
    echo "Open: http://${HOST}:${PORT}"
    exit 0
  fi

  rm -f "$PID_FILE"
fi

if lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port ${PORT} is already in use. Stop the existing Jupyter process or choose another JUPYTER_PORT." >&2
  exit 1
fi

cd "$ROOT_DIR"

"$VENV_PYTHON" - <<'PY'
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

root_dir = Path.cwd()
host = os.environ.get("JUPYTER_HOST", "127.0.0.1")
port = os.environ.get("JUPYTER_PORT", "8888")
log_file = Path(os.environ.get("JUPYTER_LOG_FILE", "/tmp/deep-learning-study-jupyter.log"))
pid_file = Path(os.environ.get("JUPYTER_PID_FILE", "/tmp/deep-learning-study-jupyter.pid"))
startup_timeout_seconds = float(os.environ.get("JUPYTER_STARTUP_TIMEOUT_SECONDS", "20"))
python = root_dir / ".venv" / "bin" / "python"

log_file.parent.mkdir(parents=True, exist_ok=True)
with log_file.open("ab", buffering=0) as log:
    process = subprocess.Popen(
        [
            str(python),
            "-m",
            "jupyterlab",
            "--no-browser",
            f"--ip={host}",
            f"--port={port}",
            "--ServerApp.port_retries=0",
        ],
        cwd=root_dir,
        stdin=subprocess.DEVNULL,
        stdout=log,
        stderr=log,
        start_new_session=True,
    )

deadline = time.monotonic() + startup_timeout_seconds

while time.monotonic() < deadline:
    if process.poll() is not None:
        print("Jupyter exited before it started listening. Check the log file for details.", file=sys.stderr)
        sys.exit(1)

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.2)
        if sock.connect_ex((host, int(port))) == 0:
            pid_file.write_text(f"{process.pid}\n")
            print(process.pid)
            sys.exit(0)

    time.sleep(0.25)

process.terminate()
print(
    f"Jupyter did not start listening within {startup_timeout_seconds:.0f} seconds. "
    "Check the log file for details or increase JUPYTER_STARTUP_TIMEOUT_SECONDS.",
    file=sys.stderr,
)
sys.exit(1)
PY

echo "Jupyter started."
echo "PID file: ${PID_FILE}"
echo "Log file: ${LOG_FILE}"
echo "Open after tunneling: http://${HOST}:${PORT}"
