#!/bin/bash
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BUILD_DIR="${SCRIPT_DIR}/build"

clean_build=false

while (( $# )); do
    case "$1" in
        --clean) clean_build=true; shift;;
        *) echo "Unknown argument: $1"; echo "Usage: $0 [--clean]"; exit 1;;
    esac
done

if [ "$clean_build" = true ]; then
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake_args=(-DCMAKE_BUILD_TYPE=Release)
if [ -n "${ONNXRUNTIME_ROOT:-}" ]; then
    cmake_args+=("-DONNXRUNTIME_ROOT=${ONNXRUNTIME_ROOT}")
fi
cmake .. "${cmake_args[@]}"
make -j"$(nproc)"
