#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "${REPO_ROOT}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/config.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/python_env.sh"

section() {
    echo "========================================"
    echo "$*"
    echo "========================================"
}

section "Checking the Python interpreter"
dx_require_python

section "Checking the APT dependencies"
dx_report_missing_apt

section "Setting up the Python virtual environment"
dx_setup_pip_cache "${REPO_ROOT}"
dx_drop_stale_venv "${REPO_ROOT}/.venv"
if [ -d .venv ] && [ ! -x .venv/bin/python ]; then
    echo "Existing .venv is incomplete; recreating it."
    rm -rf .venv
fi
if [ -d .venv ]; then
    echo "Already present: .venv ($(dx_py_version .venv/bin/python))"
else
    # No --system-site-packages: with a hand-built interpreter the system
    # dist-packages tree belongs to another version and would shadow pip's
    # packages. PyQt5 is linked in explicitly below instead.
    "${DX_PYTHON}" -m venv .venv
    echo "Created .venv ($(dx_py_version .venv/bin/python))"
fi

section "Installing the Python requirements"
.venv/bin/pip install --upgrade pip
if dx_is_arm; then
    # PyQt5 has no aarch64 wheel; pip would build the sdist and get OOM-killed.
    filtered="$(mktemp)"
    trap 'rm -f "${filtered}"' EXIT
    grep -v -i "^pyqt5" requirements.txt > "${filtered}"
    .venv/bin/pip install -r "${filtered}"
else
    .venv/bin/pip install -r requirements.txt
fi

if dx_is_arm; then
    section "Installing PyQt5 from the system package"
    dx_install_system_pyqt5 "${REPO_ROOT}/.venv"
fi

section "Installing the DXRT python bindings (dx_engine)"
# Not fatal: the C++ demos and the OCR Web UI run without the bindings.
dx_install_dx_engine "${REPO_ROOT}/.venv" || true

echo "Environment setup complete."
