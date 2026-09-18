#!/bin/bash
# Shared setup helpers, sourced by setup_env.sh and apps/paddle-ocr-web/python/
# build.sh so every venv is built from one interpreter and the system packages
# are listed in one place. Defining functions only; sourcing has no effect.

# The OCR Web demo pins gradio==5.30.0, which declares Requires-Python >=3.10.
DX_PYTHON_MIN_MINOR=10

dx_is_arm() {
    case "$(uname -m)" in
        aarch64 | arm64) return 0 ;;
        *) return 1 ;;
    esac
}

# --- System packages ---------------------------------------------------------

# "<package>|<what needs it>". Packages the vendored upstream setup checks for
# itself (libglib2.0-0, libgomp1) are left out.
dx_apt_packages() {
    cat <<'EOF'
python3-venv|creating the virtualenvs
python3-pip|installing the python packages
build-essential|building the C++ demos
cmake|building the C++ demos
libgl1|OpenGL behind the Qt GUIs
libxcb-cursor0|Qt's xcb platform plugin
git-lfs|the OCR Web example images
poppler-utils|PDF input in the OCR Web demo (pdf2image runs pdftoppm)
EOF
    if dx_is_arm; then
        cat <<'EOF'
python3-pyqt5|PyQt5 itself (PyPI has no aarch64 wheel)
python3-pyqt5.qtsvg|the launcher's SVG icons
EOF
    fi
}

dx_apt_hint() {
    dx_apt_packages |
        awk -F'|' -v want=" $* " 'index(want, " " $1 " ") { printf "  %s - %s\n", $1, $2 }'
    echo "  sudo apt-get update && sudo apt-get install -y $*"
}

# Informative only: a board may provide a dependency from outside apt, and apt
# needs root anyway.
dx_report_missing_apt() {
    command -v dpkg-query > /dev/null 2>&1 || return 0

    local pkg missing=()
    while IFS='|' read -r pkg _; do
        dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q 'ok installed' ||
            missing+=("${pkg}")
    done < <(dx_apt_packages)

    if [ ${#missing[@]} -eq 0 ]; then
        echo "All required APT packages are installed."
    else
        echo "Missing APT packages:"
        dx_apt_hint "${missing[@]}"
    fi
}

# --- Interpreter -------------------------------------------------------------

dx_py_version() {
    "$1" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null
}

dx_py_is_supported() {
    "$1" -c "import sys; raise SystemExit(0 if sys.version_info[:2] >= (3, ${DX_PYTHON_MIN_MINOR}) else 1)" \
        > /dev/null 2>&1
}

# Echoes the best interpreter candidate, which the caller still has to accept.
# Debian 11 has no python3.10+ package, so a hand-built one is the normal case.
dx_find_python() {
    local minor prefix

    if [ -n "${DX_PYTHON:-}" ]; then
        command -v "${DX_PYTHON}" 2>/dev/null || echo "${DX_PYTHON}"
        return 0
    fi
    for minor in 13 12 11 10; do
        for prefix in "" /usr/local/bin/ "/opt/python-3.${minor}/bin/"; do
            command -v "${prefix}python3.${minor}" 2>/dev/null && return 0
        done
    done
    command -v python3 2>/dev/null || true
}

# Exports DX_PYTHON, or explains what to install and fails.
dx_require_python() {
    local py
    py="$(dx_find_python)"

    if [ -n "${py}" ] && dx_py_is_supported "${py}"; then
        export DX_PYTHON="${py}"
        echo "Using Python: ${DX_PYTHON} ($(dx_py_version "${DX_PYTHON}"))"
        return 0
    fi

    echo "Error: Python 3.${DX_PYTHON_MIN_MINOR}+ is required (gradio 5.30.0 in the OCR Web demo)." >&2
    [ -n "${py}" ] && echo "  Found ${py} ($(dx_py_version "${py}" || echo "unusable"))." >&2
    echo "  Debian 11 ships no python3.11; build one with 'make altinstall' and point" >&2
    echo "  config.sh at it: export DX_PYTHON=/opt/python-3.11/bin/python3.11" >&2
    return 1
}

# --- Virtualenvs -------------------------------------------------------------

# A venv cannot be retargeted at another interpreter, so an outdated one has to
# be rebuilt rather than reused.
dx_drop_stale_venv() {
    local venv_dir="$1"
    [ -x "${venv_dir}/bin/python" ] || return 0
    dx_py_is_supported "${venv_dir}/bin/python" && return 0

    echo "${venv_dir} runs Python $(dx_py_version "${venv_dir}/bin/python"); rebuilding it."
    rm -rf "${venv_dir}"
}

# $HOME is on the small root filesystem here; one torch install fills it.
dx_setup_pip_cache() {
    export PIP_CACHE_DIR="${PIP_CACHE_DIR:-$1/.cache/pip}"
    mkdir -p "${PIP_CACHE_DIR}"
}

# --- DXRT python bindings ----------------------------------------------------

# Echoes a dx_rt checkout carrying the dx_engine sources. DX_RT in config.sh is
# the supported way to set this; the rest are the usual DEEPX SDK layouts.
dx_find_dx_rt() {
    local candidate
    for candidate in \
        "${DX_RT:-}" \
        "${DXRT_DIR:-}" \
        "${DX_ALL_SUITE_DIR:+${DX_ALL_SUITE_DIR}/dx-runtime/dx_rt}" \
        "${HOME}/dx_rt" \
        "${HOME}/dx-all-suite/dx-runtime/dx_rt" \
        "${HOME}/deepx/SDK/dx-all-suite/dx-runtime/dx_rt" \
        "${HOME}/Desktop/deepx/SDK/dx-all-suite/dx-runtime/dx_rt" \
        /opt/deepx/dx_rt; do
        if [ -n "${candidate}" ] && [ -f "${candidate}/python_package/pyproject.toml" ]; then
            echo "${candidate}"
            return 0
        fi
    done
    return 0
}

# dx_engine ships as a prebuilt wheel beside the libdxrt-bin deb, or as sources
# in a dx_rt checkout. Always through the venv's pip: a system pip refuses with
# "externally-managed-environment" (PEP 668).
dx_install_dx_engine() {
    local venv_dir="$1"
    local venv_py="${venv_dir}/bin/python"
    local venv_pip="${venv_dir}/bin/pip"
    local py_tag arch dx_rt wheel dir pat src

    # The capi module, not just the package: a binding built without a link
    # against libdxrt imports fine and then fails on the extension.
    if "${venv_py}" -c 'import dx_engine.capi._pydxrt' > /dev/null 2>&1; then
        echo "Already present: dx_engine"
        return 0
    fi

    py_tag="cp$("${venv_py}" -c 'import sys; print("%d%d" % sys.version_info[:2])')"
    arch="$(uname -m)"

    wheel=""
    for pat in "dx_engine-*-${py_tag}-*${arch}.whl" "dx_engine-*-${py_tag}-*.whl"; do
        for dir in /usr/share/libdxrt-bin/python /usr/local/share/libdxrt-bin/python; do
            [ -d "${dir}" ] || continue
            wheel="$(find "${dir}" -name "${pat}" 2>/dev/null | head -n 1)"
            [ -n "${wheel}" ] && break 2
        done
    done

    if [ -n "${wheel}" ]; then
        echo "Installing dx_engine from $(basename "${wheel}") ..."
        "${venv_pip}" install "${wheel}"
        return
    fi

    dx_rt="$(dx_find_dx_rt)"
    if [ -z "${dx_rt}" ]; then
        echo "Warning: no ${py_tag} dx_engine wheel and no dx_rt checkout to build from." >&2
        echo "         Install libdxrt-bin or set DX_RT in config.sh; demos with a" >&2
        echo "         Python NPU backend will not run without it." >&2
        return 1
    fi

    # Build from a copy: the cmake target drops _pydxrt.so back into its input
    # directory. capi/CMakeLists.txt derives DX_ROOT_DIR from the source path
    # unconditionally (-DDX_ROOT_DIR has no effect), so extern/ and lib/ have to
    # sit beside the copy for pybind11 and the DXRT headers to be found.
    echo "Building dx_engine from ${dx_rt}/python_package ..."
    src="$(mktemp -d)"
    cp -r "${dx_rt}/python_package" "${src}/dx_engine_src"
    rm -f "${src}"/dx_engine_src/src/dx_engine/capi/_pydxrt*.so
    ln -s "${dx_rt}/extern" "${src}/extern"
    ln -s "${dx_rt}/lib" "${src}/lib"

    local status=0
    "${venv_pip}" install "${src}/dx_engine_src" || status=1
    rm -rf "${src}"
    return "${status}"
}

# --- PyQt5 -------------------------------------------------------------------

# Links the distribution PyQt5 into a venv instead of building it: PyPI has no
# aarch64 wheel and the sdist compiles the whole Qt5 binding, which gets
# OOM-killed on these boards. Debian's modules are abi3, so a newer interpreter
# can load them; they just are not on a venv's path. PyQt5.sip is the one piece
# that is not abi3, and pip builds that from sdist in seconds.
dx_install_system_pyqt5() {
    local venv_dir="$1"
    local venv_py="${venv_dir}/bin/python"
    local sys_dir site

    if "${venv_py}" -c 'import PyQt5.QtWidgets' > /dev/null 2>&1; then
        echo "Already present: PyQt5"
        return 0
    fi

    # The distribution interpreter, not the venv one: PyQt5 lives in its tree.
    sys_dir="$(/usr/bin/python3 -c 'import os, PyQt5; print(os.path.dirname(PyQt5.__file__))' 2>/dev/null || true)"
    if [ -z "${sys_dir}" ]; then
        echo "Error: the system PyQt5 package is missing." >&2
        dx_apt_hint python3-pyqt5 python3-pyqt5.qtsvg >&2
        return 1
    fi
    if ! compgen -G "${sys_dir}/*.abi3.so" > /dev/null; then
        echo "Error: ${sys_dir} holds no abi3 modules, so Python $(dx_py_version "${venv_py}")" >&2
        echo "       cannot load them. Install python3-pyqt5 from the distribution." >&2
        return 1
    fi

    echo "Linking the system PyQt5 from ${sys_dir} ..."
    "${venv_dir}/bin/pip" install PyQt5-sip
    site="$("${venv_py}" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
    mkdir -p "${site}/PyQt5"
    cp -f "${sys_dir}/__init__.py" "${site}/PyQt5/"
    # Symlinks, so an apt upgrade of python3-pyqt5 applies here too. The system
    # sip.cpython-39-*.so is left out; pip just provided ours.
    ln -sf "${sys_dir}"/*.abi3.so "${site}/PyQt5/"
    [ -d "${sys_dir}/uic" ] && ln -sfn "${sys_dir}/uic" "${site}/PyQt5/uic"

    if ! "${venv_py}" -c 'import PyQt5.QtCore, PyQt5.QtGui, PyQt5.QtWidgets' > /dev/null 2>&1; then
        echo "Error: PyQt5 still fails to import after linking:" >&2
        "${venv_py}" -c 'import PyQt5.QtWidgets' >&2 || true
        return 1
    fi
    echo "PyQt5 $("${venv_py}" -c 'from PyQt5.QtCore import PYQT_VERSION_STR; print(PYQT_VERSION_STR)') linked from the system package."
}
