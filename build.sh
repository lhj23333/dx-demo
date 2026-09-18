#!/bin/bash
set -e

REPO_ROOT=$(cd "$(dirname "$0")" && pwd)
clean_args=()
lang=all
setup_ocr_web=true

usage() {
    echo "Usage: $0 [--clean] [--lang cpp|python|all] [--no-ocr-web]"
    echo "  --clean        Clean build the C++ demos and recreate the OCR Web venvs"
    echo "  --lang         What to prepare (default: all)"
    echo "  --no-ocr-web   Skip the OCR Web setup (heavy: clones two repos, creates"
    echo "                 two venvs, installs paddlepaddle)"
}

while (( $# )); do
    case "$1" in
        --clean) clean_args=(--clean); shift;;
        --lang) lang="$2"; shift 2;;
        --no-ocr-web) setup_ocr_web=false; shift;;
        --help|-h) usage; exit 0;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 1;;
    esac
done

case "${lang}" in
    cpp | python | all) ;;
    *) echo "Unknown lang: ${lang}. Use cpp, python, or all." >&2; exit 1;;
esac

section() {
    echo "========================================"
    echo "$*"
    echo "========================================"
}

ocr_web_failed=false
passed=()
failed=()

if [ "${lang}" != cpp ]; then
    section "Setting up Python Environment"
    bash "${REPO_ROOT}/setup_env.sh"
    echo

    if [ "${setup_ocr_web}" = true ]; then
        section "Setting up OCR Web Environment"
        # Network-bound and slow. A failure here must not abort the C++ build,
        # so it is collected and reported at the end.
        if bash "${REPO_ROOT}/apps/paddle-ocr-web/build.sh" "${clean_args[@]}"; then
            echo "  OK   apps/paddle-ocr-web"
        else
            ocr_web_failed=true
            echo "FAILED: apps/paddle-ocr-web" >&2
        fi
    else
        echo "Skipping the OCR Web environment setup (--no-ocr-web)."
    fi
    echo
fi

if [ "${lang}" != python ]; then
    section "Building C++ Projects"
    mapfile -t build_scripts < <(
        find "${REPO_ROOT}/apps" -mindepth 3 -maxdepth 4 -name build.sh | grep "/cpp/" | sort
    )
    echo "Found ${#build_scripts[@]} build target(s)."
    echo

    for script in "${build_scripts[@]}"; do
        rel="${script#"${REPO_ROOT}/"}"
        section "Building: ${rel}"
        if (cd "$(dirname "${script}")" && ./build.sh "${clean_args[@]}"); then
            passed+=("${rel}")
        else
            failed+=("${rel}")
        fi
        echo
    done

    section "Build summary (${#passed[@]}/${#build_scripts[@]} succeeded)"
    [ ${#passed[@]} -gt 0 ] && printf '  OK   %s\n' "${passed[@]}"
    [ ${#failed[@]} -gt 0 ] && printf '  FAIL %s\n' "${failed[@]}"
fi

if [ "${ocr_web_failed}" = true ]; then
    echo "  FAIL apps/paddle-ocr-web - the OCR Web demo will not start." >&2
    echo "       Retry with apps/paddle-ocr-web/python/build.sh" >&2
fi

if [ ${#failed[@]} -gt 0 ] || [ "${ocr_web_failed}" = true ]; then
    exit 1
fi
