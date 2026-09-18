# DX Demo — DEEPX NPU demos

**English** | [简体中文](README.zh-CN.md)

C++ and Python demos with a shared desktop launcher, covering detection, segmentation, OCR, CLIP, depth estimation, hand landmarks, automotive perception, and device monitoring.

> Requires the **dx-as (dx-all-suite) v2.3.x API** and matching DXRT libraries, Python binding, driver, and firmware.

## Requirements

| Item | Requirement |
| --- | --- |
| Host | Ubuntu / Debian, `x86_64` or `aarch64`; desktop session for the launcher |
| Python | **3.10–3.12**, with matching `venv` support and development headers |
| C++ | C++17, **CMake ≥3.16**, OpenCV and Qt5 development packages |
| NPU | DEEPX hardware and the matching SDK |
| ONNX Runtime | Native Linux CPU C/C++ package for CLIP and Drone |
| Display | **1920 × 1080** |

Setup requires access to Python package indexes, GitHub, and DEEPX asset servers.

## Quick start

Run from the repository root: **APT prerequisites → build → resources → launch**. Have an administrator install system packages; run the repository scripts as a normal user.

### 1. Install prerequisites

Build tools, Python support, and download utilities:

```bash
sudo apt-get update
sudo apt-get install -y \
    build-essential cmake libopencv-dev qtbase5-dev zlib1g-dev \
    python3-venv python3-dev \
    git ca-certificates wget curl tar gzip unzip procps
```

Python GUI runtime libraries:

```bash
sudo apt-get install -y \
    libgl1 libegl1 libdbus-1-3 libfontconfig1 libgomp1 \
    libxkbcommon-x11-0 libxcb-cursor0 libxcb-icccm4 libxcb-image0 \
    libxcb-keysyms1 libxcb-render-util0 libxcb-xinerama0
```

Install the additional packages for your environment:

| Environment / feature | APT packages |
| --- | --- |
| Ubuntu 22.04 / Debian 12 | `libglib2.0-0` |
| Ubuntu 24.04 / Debian 13 | `libglib2.0-0t64` |
| ARM / aarch64 | `python3-pyqt5` |
| OCR Web (enabled by default) | `git-lfs poppler-utils` |
| Optional: Depth X11 fullscreen | `libx11-dev` |
| Optional: camera / display diagnostics | `v4l-utils x11-xserver-utils` |
| Optional: CJK fonts / default browser discovery | `fonts-noto-cjk xdg-utils` |
| Optional: GStreamer inputs | `gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-libav` |

For example, enable ARM support and OCR Web:

```bash
sudo apt-get install -y python3-pyqt5 git-lfs poppler-utils
```

OCR Web and Model Zoo also require a desktop browser. For a custom Python installation, provide its matching venv support and headers.

**SDK and ONNX Runtime**

Prepare the matching dx-as v2.3.x SDK. Set these paths as needed:

```bash
export DX_RT=/path/to/dx-as-v2.3.x/dx-runtime/dx_rt
export DX_PYTHON=/usr/bin/python3.11  # use an existing 3.10–3.12 interpreter
```

For CLIP / Drone C++, unpack the matching [ONNX Runtime C/C++ package](https://onnxruntime.ai/docs/install/). Its root must contain `include/onnxruntime_cxx_api.h` and `lib/libonnxruntime.so`; the pip package does not replace it.

```bash
export ONNXRUNTIME_ROOT=/path/to/onnxruntime-linux-package
export LD_LIBRARY_PATH="$ONNXRUNTIME_ROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# Only for a nonstandard SDK install prefix:
export CMAKE_PREFIX_PATH=/path/to/dxrt-install-prefix${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}
```

### 2. Build and prepare Python environments

```bash
./build.sh
```

Prepares the shared `.venv`, `dx_engine`, OCR Web environments, and all C++ demos. Native outputs are stored in each app's `build/` directory. See [build options](#build-options) to select components.

### 3. Download resources

```bash
./setup_assets.sh
```

Downloads models and videos into `workspace/`, including the separate YOLO26 depth model. Also prepares OCR Web NPU models when its environment is configured. Archives are cached in `.cache/`.

| Option / variable | Use |
| --- | --- |
| `--force` | Re-download and overwrite managed assets |
| `--no-ocr-web` | Skip OCR Web assets |
| `DX_DEMOS_ASSETS_URL` | Override the shared archive URL |
| `DX_YOLO26_DEPTH_MODEL_URL` | Override the depth model URL |

The default depth URL is labelled `2_4_0`; confirm compatibility with your v2.3.x SDK or supply a matching model URL. SFA3D and OCR Web may download additional data/models on first use.

### 4. Launch

```bash
./scripts/run_launcher.sh
```

Select the backend and demo in the launcher. The launcher and monitor require the shared Python environment even with C++ inference. Stop demos with `./scripts/kill_all.sh`.

## Build options

| Option | Effect |
| --- | --- |
| `--lang all` | Default: Python + OCR Web + C++ |
| `--lang cpp` | C++ only; does not prepare the launcher environment |
| `--lang python` | Python and OCR Web only |
| `--no-ocr-web` | Skip OCR Web setup |
| `--clean` | Clean C++ builds and recreate OCR Web venvs; keep shared `.venv` and resources |

```bash
# Skip OCR Web:
./build.sh --no-ocr-web
./setup_assets.sh --no-ocr-web
# Reconfigure OCR Web:
./apps/paddle-ocr-web/python/build.sh
./setup_assets.sh
# Remove C++ outputs:
./clean_all.sh
```

Each C++ app also has its own `build.sh`. For custom CMake settings, configure that app's build directory first. SFA3D may additionally need `-DDXRT_ROOT="$DX_RT"`.

## Python dependencies

The build installs [shared requirements](requirements.txt) and [CPU Torch/TorchVision](requirements-torch.txt). OCR Web uses separate UI and server venvs.

Optional OCR inspection and accuracy tools (`onnx`, `jiwer`):

```bash
.venv/bin/python -m pip install -r apps/paddle-ocr/python/requirements-tools.txt
```

For existing environments, remove old OpenCV variants or recreate the venv before migrating. Dependency details and validation limits are in the [audit](docs/dependency-audit.md).

## Configuration

Edit [config.sh](config.sh):

| Setting | Default / use |
| --- | --- |
| `DX_CAMERA_IDX` / `DX_CAMERA_DEV` | `0` / `/dev/video0` |
| `DX_OCR_API_URL` | `http://localhost:8080/api/v1/ocr` |
| `DX_BROWSER` | Empty: discover the desktop browser |
| `DX_PYTHON` | Interpreter for new venvs |
| `DX_RT` | Matching SDK source checkout |

`DX_PYTHON`, `DX_RT`, and `DX_BROWSER` also accept environment overrides. Recreate an existing venv to change its interpreter. OCR Web uses ports **7860** (UI) and **8080** (server).

Update Model Zoo from a network with access to the internal endpoint:

```bash
./apps/model-zoo/update_modelzoo.sh
```

Use `DX_MODELZOO_URL` to override the endpoint.

## Project structure

```text
dx-demo/
├── build.sh / setup_env.sh / python_env.sh  # Build and Python setup
├── setup_assets.sh                        # Resource downloads
├── requirements*.txt / config.sh          # Dependencies and settings
├── launcher/ / scripts/                   # Launcher and run/stop helpers
├── apps/                                 # Demo implementations and app docs
├── docs/                                 # Dependency audit
├── .venv/                                # Generated Python environment
└── workspace/                            # Downloaded models and videos
```

## Troubleshooting

| Symptom | Check |
| --- | --- |
| C++ API / header errors | Matching dx-as **v2.3.x** headers and libraries |
| Python package installation fails | Python **3.10–3.12**, architecture/glibc wheel support, index access |
| `dx_engine` import fails | SDK wheel or `DX_RT`, Python headers, library search path |
| Qt `xcb` error | GUI runtime libraries and desktop session; use `QT_DEBUG_PLUGINS=1` |
| CLIP / Drone executable missing | Native ONNX Runtime and Qt5; Drone skips its target when these are absent |
| OCR Web PDF / example images fail | `poppler-utils` / `git-lfs` |
| Models missing or incomplete | `./setup_assets.sh --force` |
| Monitor NPU values are empty | DXRT daemon, device permissions, binding compatibility |
| Fullscreen view is cropped | Set the display to 1920×1080 |

## Licenses

Models, SDK components, and third-party libraries retain their own licenses. Consult the relevant app documentation and DEEPX SDK terms before redistribution.
