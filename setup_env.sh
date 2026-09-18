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
# The demos use CPU tensor operations; NPU inference is provided by DXRT.
# Resolve torch/torchvision together from the CPU index before open_clip_torch.
.venv/bin/pip install --index-url https://download.pytorch.org/whl/cpu \
    -r requirements-torch.txt
.venv/bin/pip install -r requirements.txt

if dx_is_arm; then
    section "Installing PyQt5 from the system package"
    dx_install_system_pyqt5 "${REPO_ROOT}/.venv"
fi

section "Installing the DXRT python bindings (dx_engine)"
dx_install_dx_engine "${REPO_ROOT}/.venv"

echo "Environment setup complete."
