#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Legacy entry point: prerequisites and resource setup are documented in the root README.md."
exec bash "${SCRIPT_DIR}/build.sh" "$@"
