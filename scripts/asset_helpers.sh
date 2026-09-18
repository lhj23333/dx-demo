#!/bin/bash
# Sourced by setup_assets.sh; no downloads happen when this file is sourced.

# Validate downloads before replacing cached archives. Extract completely
# before copying, so an extraction failure does not create ready-looking dirs.
dx_unpack_asset() (
    set -euo pipefail
    local url="$1" archive="$2" dest="$3" wrapper="$4" force="$5"
    local partial="" staging="" entries top
    trap 'rm -f "${partial}"; [ -z "${staging}" ] || rm -rf "${staging}"' EXIT

    mkdir -p "$(dirname "${archive}")"
    if [ "${force}" = true ] || [ ! -f "${archive}" ]; then
        partial="$(mktemp "${archive}.partial.XXXXXX")"
        echo "Downloading ${url} ..."
        if command -v wget > /dev/null 2>&1; then
            wget -O "${partial}" "${url}"
        elif command -v curl > /dev/null 2>&1; then
            curl -fL -o "${partial}" "${url}"
        else
            echo "Error: no downloader available. See README.md prerequisites." >&2
            exit 1
        fi
        tar -tzf "${partial}" > /dev/null
        mv "${partial}" "${archive}"
    fi

    entries="$(tar -tzf "${archive}")"
    top="$(printf '%s\n' "${entries}" | sed 's|^\./||; /^$/d' | cut -d/ -f1 | sort -u)"
    staging="$(mktemp -d "$(dirname "${archive}")/extract.XXXXXX")"
    # Select the wrapper after extraction to handle both wrapper/... and
    # ./wrapper/... without strip-components ambiguity.
    tar -xzf "${archive}" -C "${staging}" --no-same-owner
    local source="${staging}"
    if [ -d "${staging}/${top}" ]; then
        if [ "${wrapper}" != workspace ] || [ "${top}" = workspace ]; then
            source="${staging}/${top}"
        fi
    fi
    if [ "${wrapper}" = workspace ]; then
        [ -d "${source}/models" ] && [ -d "${source}/videos" ] || {
            echo "Error: archive must contain models/ and videos/." >&2
            exit 1
        }
    else
        [ -n "$(find "${source}" -name '*.dxnn' -type f -print -quit)" ] || {
            echo "Error: ${wrapper} archive contains no .dxnn models." >&2
            exit 1
        }
    fi
    mkdir -p "${dest}"
    cp -a "${source}/." "${dest}/"
)
