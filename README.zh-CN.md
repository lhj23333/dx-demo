# DX Demo — DEEPX NPU 演示集合

[English](README.md) | **简体中文**

提供统一桌面启动器的 C++ / Python Demo 集合，涵盖目标检测、分割、OCR、CLIP、深度估计、手部关键点、汽车感知和设备监控。

> 依赖 **dx-as（dx-all-suite）v2.3.x API**，请使用配套的 DXRT 库、Python 绑定、驱动和固件。

## 环境要求

| 项目 | 要求 |
| --- | --- |
| 主机 | Ubuntu / Debian，`x86_64` 或 `aarch64`；启动器需要桌面会话 |
| Python | **3.10–3.12**，配套的 `venv` 和开发头文件 |
| C++ | C++17、**CMake ≥3.16**、OpenCV 和 Qt5 开发包 |
| NPU | DEEPX 硬件及配套 SDK |
| ONNX Runtime | CLIP 和 Drone 所需的原生 Linux CPU C/C++ 发行包 |
| 显示器 | **1920 × 1080** |

安装时需能访问 Python 包索引、GitHub 和 DEEPX 资源服务器。

## 快速开始

在仓库根目录按 **APT 前置依赖 → 构建 → 拉取资源 → 启动** 执行。系统软件包由管理员安装，仓库脚本使用普通用户运行。

### 1. 安装前置依赖

构建工具、Python 支持及下载工具：

```bash
sudo apt-get update
sudo apt-get install -y \
    build-essential cmake libopencv-dev qtbase5-dev zlib1g-dev \
    python3-venv python3-dev \
    git ca-certificates wget curl tar gzip unzip procps
```

Python GUI 运行库：

```bash
sudo apt-get install -y \
    libgl1 libegl1 libdbus-1-3 libfontconfig1 libgomp1 \
    libxkbcommon-x11-0 libxcb-cursor0 libxcb-icccm4 libxcb-image0 \
    libxcb-keysyms1 libxcb-render-util0 libxcb-xinerama0
```

根据系统和功能补充安装：

| 环境 / 功能 | APT 软件包 |
| --- | --- |
| Ubuntu 22.04 / Debian 12 | `libglib2.0-0` |
| Ubuntu 24.04 / Debian 13 | `libglib2.0-0t64` |
| ARM / aarch64 | `python3-pyqt5` |
| OCR Web（默认启用） | `git-lfs poppler-utils` |
| 可选：Depth X11 全屏 | `libx11-dev` |
| 可选：摄像头 / 显示诊断 | `v4l-utils x11-xserver-utils` |
| 可选：中日韩字体 / 默认浏览器发现 | `fonts-noto-cjk xdg-utils` |
| 可选：GStreamer 输入 | `gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-libav` |

例如，启用 ARM 支持与 OCR Web：

```bash
sudo apt-get install -y python3-pyqt5 git-lfs poppler-utils
```

OCR Web 和 Model Zoo 还需要桌面浏览器。使用自定义 Python 时，请提供对应版本的 venv 支持和头文件。

**SDK 与 ONNX Runtime**

准备配套的 dx-as v2.3.x SDK，按需指定路径：

```bash
export DX_RT=/path/to/dx-as-v2.3.x/dx-runtime/dx_rt
export DX_PYTHON=/usr/bin/python3.11  # 指向已准备好的 3.10–3.12 解释器
```

CLIP / Drone C++ 需要解压对应架构的 [ONNX Runtime C/C++ 发行包](https://onnxruntime.ai/docs/install/)。其根目录应包含 `include/onnxruntime_cxx_api.h` 和 `lib/libonnxruntime.so`，不能用 pip 包替代。

```bash
export ONNXRUNTIME_ROOT=/path/to/onnxruntime-linux-package
export LD_LIBRARY_PATH="$ONNXRUNTIME_ROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# 仅 SDK 安装到非标准前缀时配置：
export CMAKE_PREFIX_PATH=/path/to/dxrt-install-prefix${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}
```

### 2. 构建并安装 Python 环境

```bash
./build.sh
```

准备共享 `.venv`、`dx_engine`、OCR Web 环境及全部 C++ Demo。C++ 产物位于各应用的 `build/` 目录，可通过[构建选项](#构建选项)选择组件。

### 3. 拉取资源

```bash
./setup_assets.sh
```

下载模型和视频到 `workspace/`，包含独立的 YOLO26 深度模型；已配置 OCR Web NPU 环境时，还会准备其模型。压缩包缓存在 `.cache/`。

| 选项 / 变量 | 作用 |
| --- | --- |
| `--force` | 重新下载并覆盖受管理资源 |
| `--no-ocr-web` | 跳过 OCR Web 资源 |
| `DX_DEMOS_ASSETS_URL` | 覆盖共享资源包地址 |
| `DX_YOLO26_DEPTH_MODEL_URL` | 覆盖深度模型地址 |

默认深度模型地址带有 `2_4_0` 标记，请确认与 v2.3.x SDK 兼容，或指定配套模型地址。SFA3D 和 OCR Web 首次运行仍可能下载额外数据或模型。

### 4. 启动

```bash
./scripts/run_launcher.sh
```

在启动器中选择后端和 Demo。即使使用 C++ 推理，启动器和监控仍需共享 Python 环境。使用 `./scripts/kill_all.sh` 停止 Demo。

## 构建选项

| 选项 | 作用 |
| --- | --- |
| `--lang all` | 默认：Python + OCR Web + C++ |
| `--lang cpp` | 仅 C++，不准备启动器环境 |
| `--lang python` | 仅 Python 和 OCR Web |
| `--no-ocr-web` | 跳过 OCR Web 环境 |
| `--clean` | 清理 C++ 构建并重建 OCR Web venv；保留共享 `.venv` 和资源 |

```bash
# 跳过 OCR Web：
./build.sh --no-ocr-web
./setup_assets.sh --no-ocr-web
# 重新配置 OCR Web：
./apps/paddle-ocr-web/python/build.sh
./setup_assets.sh
# 清理 C++ 产物：
./clean_all.sh
```

各 C++ 应用也可单独运行自己的 `build.sh`。需要自定义 CMake 参数时，先配置该应用的构建目录；SFA3D 可能还需 `-DDXRT_ROOT="$DX_RT"`。

## Python 依赖

构建时自动安装[共享依赖](requirements.txt)与 [CPU Torch/TorchVision](requirements-torch.txt)。OCR Web 的 UI 和服务端使用独立 venv。

按需安装 OCR 检查与精度评估工具（`onnx`、`jiwer`）：

```bash
.venv/bin/python -m pip install -r apps/paddle-ocr/python/requirements-tools.txt
```

迁移已有环境时，请先移除旧 OpenCV 变体或重建 venv。依赖详情与验证范围见[审查记录](docs/dependency-audit.md)。

## 配置

编辑 [config.sh](config.sh)：

| 配置项 | 默认值 / 用途 |
| --- | --- |
| `DX_CAMERA_IDX` / `DX_CAMERA_DEV` | `0` / `/dev/video0` |
| `DX_OCR_API_URL` | `http://localhost:8080/api/v1/ocr` |
| `DX_BROWSER` | 留空时自动发现桌面浏览器 |
| `DX_PYTHON` | 创建 venv 的解释器 |
| `DX_RT` | 配套 SDK 源码目录 |

`DX_PYTHON`、`DX_RT`、`DX_BROWSER` 也可通过环境变量覆盖。更换已有 venv 的解释器需重建该环境。OCR Web 使用 **7860**（UI）和 **8080**（服务端）端口。

在可访问内部服务的网络中更新 Model Zoo：

```bash
./apps/model-zoo/update_modelzoo.sh
```

可通过 `DX_MODELZOO_URL` 覆盖服务地址。

## 目录结构

```text
dx-demo/
├── build.sh / setup_env.sh / python_env.sh  # 构建与 Python 环境
├── setup_assets.sh                        # 资源下载
├── requirements*.txt / config.sh          # 依赖与配置
├── launcher/ / scripts/                   # 启动器与启停脚本
├── apps/                                 # Demo 实现与应用文档
├── docs/                                 # 依赖审查记录
├── .venv/                                # 生成的 Python 环境
└── workspace/                            # 下载的模型与视频
```

## 常见问题

| 现象 | 检查方向 |
| --- | --- |
| C++ API / 头文件报错 | dx-as **v2.3.x** 配套头文件与动态库 |
| Python 包安装失败 | Python **3.10–3.12**、架构/glibc 对应 wheel、包索引网络 |
| `dx_engine` 导入失败 | SDK wheel 或 `DX_RT`、Python 头文件、动态库路径 |
| Qt `xcb` 错误 | GUI 运行库和桌面会话；使用 `QT_DEBUG_PLUGINS=1` 查看详情 |
| 缺少 CLIP / Drone 可执行文件 | 原生 ONNX Runtime 和 Qt5；缺失时 Drone 会跳过构建目标 |
| OCR Web PDF / 示例图片失败 | `poppler-utils` / `git-lfs` |
| 模型缺失或不完整 | `./setup_assets.sh --force` |
| 监控 NPU 数值为空 | DXRT 守护进程、设备权限、绑定兼容性 |
| 全屏画面裁切 | 将显示器设为 1920×1080 |

## 许可证

模型、SDK 组件和第三方库遵循各自许可证。分发前请查阅对应应用文档及 DEEPX SDK 条款。
