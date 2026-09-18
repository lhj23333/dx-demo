#!/bin/bash
set -e

# Sets up the PP-OCRv5 web demo: Gradio UI (:7860) + PaddleOCR-deepx OCR server
# (:8080). Reuses checkouts and venvs; rechecks package requirements on reruns.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../../.." && pwd)

# shellcheck disable=SC1091
source "${REPO_ROOT}/config.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/python_env.sh"

WEB_REPO="https://github.com/DEEPX-AI/PP-OCRv5_Online_demo-deepx.git"
SERVER_REPO="https://github.com/DEEPX-AI/PaddleOCR-deepx.git"
REPO_BRANCH="deepx"

WEB_DIR="${SCRIPT_DIR}/PP-OCRv5_Online_demo-deepx"
SERVER_DIR="${SCRIPT_DIR}/PaddleOCR-deepx"
FASTAPI_DIR="${SERVER_DIR}/deploy/fastapi"
VENV_DIR="${SCRIPT_DIR}/.venv"

DX_RT_PATH="${DX_RT_PATH:-}"
cpu_only=false
clean_build=false

usage() {
    echo "Usage: $0 [--dx_rt PATH] [--cpu-only] [--clean]"
    echo "  --dx_rt PATH   dx_rt checkout used to build the dx_engine python binding"
    echo "                 (auto-detected when omitted; DX_RT_PATH env also works)"
    echo "  --cpu-only     Skip the NPU binding and configuration"
    echo "  --clean        Remove the venvs first"
}

while (( $# )); do
    case "$1" in
        --dx_rt)
            [ $# -ge 2 ] || { echo "Missing value for --dx_rt" >&2; exit 1; }
            DX_RT_PATH="$2"; shift 2;;
        --cpu-only) cpu_only=true; shift;;
        --clean) clean_build=true; shift;;
        --help|-h) usage; exit 0;;
        *) echo "Unknown argument: $1"; usage; exit 1;;
    esac
done

if [ "$clean_build" = true ]; then
    echo "Removing existing environments ..."
    rm -rf "${VENV_DIR}" "${FASTAPI_DIR}/venv"
fi

dx_require_python
dx_setup_pip_cache "${REPO_ROOT}"

# --- Sources -----------------------------------------------------------------

clone_if_missing() {
    local dir="$1" repo="$2"
    if [ -d "${dir}/.git" ]; then
        echo "Already cloned: $(basename "${dir}")"
    else
        echo "Cloning ${repo} ..."
        git clone --depth 1 --branch "${REPO_BRANCH}" "${repo}" "${dir}"
    fi
}

# Without git-lfs a clone leaves the LFS-tracked example images as pointer
# stubs, and Gradio's example gallery dies on them with UnidentifiedImageError.
fix_lfs_examples() {
    grep -q "filter=lfs" "${WEB_DIR}/.gitattributes" 2>/dev/null || return 0
    grep -rlI "^version https://git-lfs.github.com/spec/v1" "${WEB_DIR}/examples" \
        2>/dev/null | grep -q . || return 0

    if ! command -v git-lfs > /dev/null 2>&1; then
        echo "Warning: the example images are git-lfs pointers and git-lfs is missing." >&2
        echo "         See the OCR Web prerequisites in the root README.md." >&2
        return 1
    fi
    echo "Fetching the git-lfs example images ..."
    (cd "${WEB_DIR}" && git lfs pull)
}

clone_if_missing "${WEB_DIR}" "${WEB_REPO}"
clone_if_missing "${SERVER_DIR}" "${SERVER_REPO}"
# A broken example gallery does not stop the demo from working.
fix_lfs_examples || true

# --- Web UI venv -------------------------------------------------------------
# Kept apart from the repository .venv because gradio 5.30.0 is pinned.

# The upstream pin (pillow==9.5.0) has no wheel for python 3.12+, and its sdist
# quietly builds a Pillow without the WebP encoder unless libwebp-dev is around.
# Refuse that source build and drop the pin instead.
install_web_requirements() (
    set -e
    local req="${WEB_DIR}/requirements.txt" filtered
    if "${VENV_DIR}/bin/python" -c 'import sys; raise SystemExit(sys.version_info[:2] >= (3, 12))'; then
        "${VENV_DIR}/bin/python" -m pip install --only-binary=Pillow -r "${req}"
    else
        filtered="$(mktemp "${WEB_DIR}/.requirements.XXXXXX")"
        trap 'rm -f "${filtered}"' EXIT
        grep -viE '^[[:space:]]*pillow([[:space:]]*[<>=!~]|$)' "${req}" > "${filtered}"
        echo 'pillow>=10.4,<12.0' >> "${filtered}"
        "${VENV_DIR}/bin/python" -m pip install --only-binary=Pillow -r "${filtered}"
    fi
)

# gradio's Gallery writes WebP, so a Pillow without that encoder makes every
# render die with KeyError: 'WEBP' after a successful inference. Checked on
# every run, which also covers venvs this script did not create.
ensure_pillow_webp() {
    local check='from PIL import features; raise SystemExit(0 if features.check("webp") else 1)'

    if "${VENV_DIR}"/bin/python -c "${check}" > /dev/null 2>&1; then
        echo "Already present: Pillow with WebP support"
        return
    fi

    echo "Pillow has no WebP encoder; installing a binary wheel ..."
    # --force-reinstall, not --upgrade: a source-built Pillow satisfies the
    # version range, so pip would skip it as "already satisfied".
    "${VENV_DIR}"/bin/pip install --force-reinstall --only-binary=:all: 'pillow>=10.4,<12.0'
    if ! "${VENV_DIR}"/bin/python -c "${check}" > /dev/null 2>&1; then
        echo "Error: Pillow still has no WebP support; the Gradio gallery will fail." >&2
        exit 1
    fi
}

dx_drop_stale_venv "${VENV_DIR}"
if [ -x "${VENV_DIR}/bin/python" ]; then
    echo "Already present: web UI venv ($(dx_py_version "${VENV_DIR}/bin/python"))"
else
    echo "Creating the web UI venv ..."
    "${DX_PYTHON}" -m venv "${VENV_DIR}"
    "${VENV_DIR}"/bin/pip install --upgrade pip
fi
install_web_requirements
ensure_pillow_webp

# --- OCR server venv ---------------------------------------------------------

dx_drop_stale_venv "${FASTAPI_DIR}/venv"
if [ ! -x "${FASTAPI_DIR}/venv/bin/python" ]; then
    echo "Creating the OCR server venv ..."
    "${DX_PYTHON}" -m venv "${FASTAPI_DIR}/venv"
fi
# Install directly into the venv: upstream local_setup.sh mixes package
# installation, interactive system-package checks, and model downloads.
# PaddleOCR 3.3.x -> PaddleX[ocr-core] already requires opencv-contrib-python;
# remove upstream's extra headless wheel so cv2 has a single provider.
install_server_requirements() (
    set -e
    local filtered
    filtered="$(mktemp "${FASTAPI_DIR}/.requirements.XXXXXX")"
    trap 'rm -f "${filtered}"' EXIT
    grep -viE '^[[:space:]]*opencv-python-headless([[:space:]]*[<>=!~]|$)' \
        "${FASTAPI_DIR}/requirements.txt" > "${filtered}"
    "${FASTAPI_DIR}/venv/bin/python" -m pip install --upgrade pip
    "${FASTAPI_DIR}/venv/bin/python" -m pip install -r "${filtered}"
)
install_server_requirements
"${FASTAPI_DIR}/venv/bin/python" -c 'import paddleocr, fastapi, uvicorn, pdf2image'

# --- NPU support -------------------------------------------------------------
# Only the dx_engine python binding is set up here; DX-RT itself is expected to
# be installed already (that is what makes upstream local_deepx_setup.sh need
# sudo, and it is unnecessary for the demo).

write_deepx_env() {
    # run.sh sources this file and enables SETUP_NPU when it exists.
    local defaults=(
        CUSTOM_INTER_OP_THREADS_COUNT=1
        CUSTOM_INTRA_OP_THREADS_COUNT=2
        DXRT_DYNAMIC_CPU_THREAD=1
        DXRT_TASK_MAX_LOAD=3
        NFH_INPUT_WORKER_THREADS=2
        NFH_OUTPUT_WORKER_THREADS=4
    )
    # shellcheck disable=SC1091
    [ -f "${FASTAPI_DIR}/.env.deepx" ] && source "${FASTAPI_DIR}/.env.deepx"

    local entry name
    {
        echo "#!/bin/bash"
        echo "# Written by build.sh from .env.deepx; sourced by run.sh."
        for entry in "${defaults[@]}"; do
            name="${entry%%=*}"
            echo "export ${name}=${!name:-${entry#*=}}"
        done
    } > "${FASTAPI_DIR}/deepx_env.sh"
    chmod +x "${FASTAPI_DIR}/deepx_env.sh"
    echo "Wrote deepx_env.sh"
}

setup_npu() {
    # --dx_rt feeds the shared lookup, which otherwise tries DX_RT from
    # config.sh and the usual SDK layouts.
    if ! DX_RT="${DX_RT_PATH:-${DX_RT:-}}" dx_install_dx_engine "${FASTAPI_DIR}/venv"; then
        echo "Skipping NPU setup: dx_engine is unavailable."
        rm -f "${FASTAPI_DIR}/deepx_env.sh"
        return
    fi

    write_deepx_env

    # Fonts for the OCR overlays the server renders
    mkdir -p "${FASTAPI_DIR}/deepx/engine/fonts"
    cp "${SERVER_DIR}"/doc/fonts/*.ttf "${FASTAPI_DIR}/deepx/engine/fonts/" 2>/dev/null || true
}

if [ "$cpu_only" = true ]; then
    echo "Skipping NPU setup (--cpu-only); removing deepx_env.sh so run.sh stays on CPU."
    rm -f "${FASTAPI_DIR}/deepx_env.sh"
else
    setup_npu
fi

# --- Summary -----------------------------------------------------------------

echo
echo "Setup complete."
echo "  Web UI      : ${WEB_DIR}"
echo "  OCR server  : ${FASTAPI_DIR}"
if [ -f "${FASTAPI_DIR}/deepx_env.sh" ]; then
    echo "  Inference   : NPU (deepx_env.sh present)"
else
    echo "  Inference   : CPU only"
fi
# pdf2image only wraps poppler's pdftoppm, which pip cannot provide. Reported
# last so a long build does not scroll it out of sight.
if command -v pdftoppm > /dev/null 2>&1; then
    echo "  PDF input   : available (pdftoppm)"
else
    echo "  PDF input   : UNAVAILABLE - PDF uploads will fail without pdftoppm"
    echo "                See the OCR Web prerequisites in the root README.md."
fi
echo
echo "Next: run ${REPO_ROOT}/setup_assets.sh, then ${REPO_ROOT}/scripts/run_ocr_web.sh"
