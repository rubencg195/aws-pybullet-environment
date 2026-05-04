#!/usr/bin/env bash
# Default: run the given command (or bash) with PyBullet venv on PATH.
# START_CODE_SERVER=1 → VS Code in the browser (code-server on CODE_SERVER_PORT, default 8080).
# Set PASSWORD when using --auth password (code-server default for this entrypoint).

set -euo pipefail

if [[ "${START_CODE_SERVER:-0}" == "1" ]]; then
  # code-server reads login password from PASSWORD when --auth password
  exec code-server \
    --bind-addr "0.0.0.0:${CODE_SERVER_PORT:-8080}" \
    --auth "${CODE_SERVER_AUTH:-password}" \
    "${WORKSPACE:-/workspace}"
fi

exec "$@"
