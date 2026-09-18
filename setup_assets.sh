#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$REPO_ROOT/workspace"
ASSETS_URL="${DX_DEMOS_ASSETS_URL:-https://cs.deepx.ai/_deepx_fae_archive/demo_assets.tar.gz}"
CACHE_DIR="$REPO_ROOT/.cache"
FASTAPI_DIR="$REPO_ROOT/apps/paddle-ocr-web/python/PaddleOCR-deepx/deploy/fastapi"
# shellcheck source=scripts/asset_helpers.sh
source "$REPO_ROOT/scripts/asset_helpers.sh"

usage() {
    echo "Usage: $0 [--force] [--no-ocr-web] [--help]"
    echo "Prepare workspace models/videos, YOLO26 depth, and configured OCR Web NPU assets."
    echo "  --force        Re-download and overwrite managed assets"
    echo "  --no-ocr-web   Skip OCR Web assets even if its NPU environment exists"
}

FORCE=false
setup_ocr_web=true
while (( $# )); do
    case "$1" in
        --force) FORCE=true; shift;;
        --no-ocr-web) setup_ocr_web=false; shift;;
        --help|-h) usage; exit 0;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1;;
    esac
done

if [ "$FORCE" = false ] && [ -d "$WORKSPACE_DIR/models" ] && [ -d "$WORKSPACE_DIR/videos" ]; then
    echo "Workspace assets already exist. Use --force to overwrite."
else
    dx_unpack_asset "$ASSETS_URL" "$CACHE_DIR/demo_assets.tar.gz" "$WORKSPACE_DIR" workspace "$FORCE"
fi

force_args=()
[ "$FORCE" = false ] || force_args=(--force)
bash "$REPO_ROOT/scripts/fetch_yolo26_depth_model.sh" "${force_args[@]}"

# Use the same archives as upstream deepx/setup.sh without invoking its
# interactive helpers, which can install system packages or elevate.
if [ "$setup_ocr_web" = true ] && [ -f "$FASTAPI_DIR/deepx_env.sh" ]; then
    models_dir="$FASTAPI_DIR/deepx/engine/model_files"
    for variant in server mobile; do
        if [ "$FORCE" = false ] && [ -n "$(find -L "$models_dir/$variant" -type f -name '*.dxnn' -print -quit 2>/dev/null)" ]; then
            echo "OCR Web $variant models already exist."
        else
            dx_unpack_asset \
                "https://sdk.deepx.ai/res/assets/dx_baidu_PPOCR/$variant.tar.gz" \
                "$CACHE_DIR/ocr-web-$variant.tar.gz" "$models_dir/$variant" "$variant" "$FORCE"
        fi
    done
    # The engine resolves dictionaries one level above the server models.
    for dictionary in "$models_dir/server/"*.txt; do
        [ ! -f "$dictionary" ] || cp "$dictionary" "$models_dir/"
    done
else
    echo "Skipping OCR Web NPU assets (not configured or --no-ocr-web)."
fi

echo "Demo assets are ready. Run ./scripts/run_launcher.sh"
