#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${ROOT_DIR}/apps/paddle-ocr-web"
PY_DIR="${APP_DIR}/python"
WEB_DIR="${PY_DIR}/PP-OCRv5_Online_demo-deepx"
VENV_DIR="${PY_DIR}/.venv"
SERVER_DIR="${PY_DIR}/PaddleOCR-deepx"
FASTAPI_DIR="${SERVER_DIR}/deploy/fastapi"
BROWSER_PID_FILE="${APP_DIR}/.browser.pid"

# Load top-level configuration.
if [ -f "${ROOT_DIR}/config.sh" ]; then
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/config.sh"
fi

OCR_API_URL="${DX_OCR_API_URL:-http://localhost:8080/api/v1/ocr}"
OCR_HEALTH_URL="${OCR_API_URL%/api/v1/ocr}/health"
# app.py pins server_port=7860 in demo.launch(), so the port is not configurable.
WEB_URL="http://localhost:7860"

OCR_SERVER_PID=""
WEB_UI_PID=""
BROWSER_PID=""

process_is_running() {
    [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}

wait_for_http() {
    local url="$1"
    local timeout_seconds="$2"
    local watched_pid="${3:-}"
    local deadline=$((SECONDS + timeout_seconds))

    while (( SECONDS < deadline )); do
        if curl -sf -m 2 "${url}" > /dev/null 2>&1; then
            return 0
        fi
        if [ -n "${watched_pid}" ] && ! process_is_running "${watched_pid}"; then
            return 1
        fi
        sleep 1
    done
    return 1
}

wait_for_old_stack_to_stop() {
    local deadline=$((SECONDS + 15))

    while (( SECONDS < deadline )); do
        if ! pgrep -f 'PP-OCRv5_Online_demo-deepx/app\.py' > /dev/null 2>&1 &&
           ! pgrep -f 'deploy/fastapi/ocr_service\.py' > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done

    echo "Warning: the previous OCR Web stack did not stop cleanly; forcing shutdown."
    pkill -KILL -f 'PP-OCRv5_Online_demo-deepx/app\.py' 2>/dev/null || true
    pkill -KILL -f 'deploy/fastapi/ocr_service\.py' 2>/dev/null || true
}

terminate_process() {
    local pid="${1:-}"
    if process_is_running "${pid}"; then
        kill -TERM "${pid}" 2>/dev/null || true
    fi
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM HUP

    # The OCR server is launched through run.sh, so terminate its Python child
    # before terminating the wrapper. PIDs are scoped to this invocation and
    # cannot affect another app with a similar command line.
    if process_is_running "${OCR_SERVER_PID}"; then
        pkill -TERM -P "${OCR_SERVER_PID}" 2>/dev/null || true
        terminate_process "${OCR_SERVER_PID}"
    fi
    terminate_process "${WEB_UI_PID}"
    terminate_process "${BROWSER_PID}"

    if [ -n "${BROWSER_PID}" ] && [ -f "${BROWSER_PID_FILE}" ] &&
       [ "$(cat "${BROWSER_PID_FILE}" 2>/dev/null)" = "${BROWSER_PID}" ]; then
        rm -f "${BROWSER_PID_FILE}"
    fi

    wait "${WEB_UI_PID}" 2>/dev/null || true
    wait "${OCR_SERVER_PID}" 2>/dev/null || true
    wait "${BROWSER_PID}" 2>/dev/null || true
    exit "${status}"
}

trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# Stop an earlier launch first. kill_ocr_web.sh sends TERM; wait here so its
# still-exiting backend cannot pass the health check and disappear afterwards.
"${ROOT_DIR}"/scripts/kill_ocr_web.sh
wait_for_old_stack_to_stop

# Auto-setup on first run: build.sh clones the repos and creates both venvs.
if [ ! -f "${WEB_DIR}/app.py" ] || [ ! -x "${VENV_DIR}/bin/python" ]; then
    echo "Web demo environment not found. Running python/build.sh ..."
    if ! "${PY_DIR}"/build.sh; then
        echo "Error: setup failed. See apps/paddle-ocr-web/python/README.md"
        exit 1
    fi
fi

# The UI is only a front-end; do not expose it until the OCR API is healthy.
if curl -sf -m 2 "${OCR_HEALTH_URL}" > /dev/null 2>&1; then
    echo "OCR server already running at ${OCR_API_URL}"
elif [ -x "${FASTAPI_DIR}/run.sh" ] && [ -x "${FASTAPI_DIR}/venv/bin/python" ]; then
    echo "Starting OCR server ..."
    # Keep the wrapper as a tracked child of this script. Do not put '&' inside
    # the subshell: that detached the server and let the subshell exit at once.
    (cd "${FASTAPI_DIR}" && exec ./run.sh) &
    OCR_SERVER_PID=$!

    echo "Waiting for the OCR server at ${OCR_HEALTH_URL} ..."
    if ! wait_for_http "${OCR_HEALTH_URL}" 300 "${OCR_SERVER_PID}"; then
        if process_is_running "${OCR_SERVER_PID}"; then
            echo "Error: OCR server did not become healthy within 300 seconds."
        else
            wait "${OCR_SERVER_PID}" 2>/dev/null
            echo "Error: OCR server exited before becoming healthy."
        fi
        exit 1
    fi
else
    echo "Error: no healthy OCR server at ${OCR_API_URL} and no local server setup."
    echo "       See apps/paddle-ocr-web/README.md."
    exit 1
fi

echo "Starting OCR Web UI ..."
# The absolute app.py path keeps stop-script matching unambiguous. exec makes
# WEB_UI_PID the Python process rather than a short-lived subshell.
(cd "${WEB_DIR}" && \
    API_URL="${OCR_API_URL}" exec "${VENV_DIR}"/bin/python "${WEB_DIR}"/app.py) &
WEB_UI_PID=$!

echo "Waiting for the Web UI at ${WEB_URL} ..."
if ! wait_for_http "${WEB_URL}" 120 "${WEB_UI_PID}"; then
    if process_is_running "${WEB_UI_PID}"; then
        echo "Error: Web UI did not become ready within 120 seconds."
    else
        wait "${WEB_UI_PID}" 2>/dev/null
        echo "Error: Web UI exited before becoming ready."
    fi
    exit 1
fi

# Re-check the dependency immediately before declaring the whole stack ready.
if ! curl -sf -m 2 "${OCR_HEALTH_URL}" > /dev/null 2>&1; then
    echo "Error: OCR server became unavailable while the Web UI was starting."
    exit 1
fi

"${ROOT_DIR}"/scripts/open_browser.sh --no-fullscreen "${WEB_URL}" &
# open_browser.sh execs the browser, so $! is the browser itself.
BROWSER_PID=$!
echo "${BROWSER_PID}" > "${BROWSER_PID_FILE}"

# Let the launcher end its "Wait" only after both services are healthy.
if [ -n "${DX_LAUNCHER_READY_FILE:-}" ]; then
    : > "${DX_LAUNCHER_READY_FILE}"
fi

echo "OCR Web is ready: ${WEB_URL}"

# Couple the local backend and UI lifetimes. If either one exits, cleanup stops
# the other one and the browser. With an externally managed API, only wait for
# the UI because this script does not own the OCR server.
if [ -n "${OCR_SERVER_PID}" ]; then
    wait -n "${OCR_SERVER_PID}" "${WEB_UI_PID}"
    runtime_status=$?
    if process_is_running "${WEB_UI_PID}" && ! process_is_running "${OCR_SERVER_PID}"; then
        echo "Error: OCR server stopped; shutting down the Web UI."
    fi
    exit "${runtime_status}"
fi

wait "${WEB_UI_PID}"
