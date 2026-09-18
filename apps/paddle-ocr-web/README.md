# PaddleOCR Web

[English deployment guide](../../README.md) · [中文部署指南](../../README.zh-CN.md)

PP-OCRv5 document OCR through a Gradio UI and a FastAPI server. This app uses Python for both launcher backend selections. The camera OCR demo is in `apps/paddle-ocr/`.

PP-OCRv5 文档 OCR 演示，由 Gradio UI 和 FastAPI 服务组成。启动器选择任一后端时，此应用均使用 Python。摄像头 OCR Demo 位于 `apps/paddle-ocr/`。

| Component / 组件 | Source / 源码 | Port / 端口 |
| --- | --- | --- |
| Gradio UI | [PP-OCRv5_Online_demo-deepx](https://github.com/DEEPX-AI/PP-OCRv5_Online_demo-deepx), `deepx` branch, `app.py` | 7860 |
| FastAPI server | [PaddleOCR-deepx](https://github.com/DEEPX-AI/PaddleOCR-deepx), `deepx` branch, `deploy/fastapi/ocr_service.py` | 8080 |

## Setup / 安装

Prepare the root README prerequisites first, including the matching dx-as v2.3.x SDK, Python 3.10–3.12, `git-lfs`, `curl`, and Poppler for PDF input. Run the following from the **repository root** as a normal user:

先按根 README 准备前置依赖，包括配套的 dx-as v2.3.x SDK、Python 3.10–3.12、`git-lfs`、`curl` 和 PDF 所需 Poppler。然后以普通用户在**仓库根目录**执行：

```bash
./apps/paddle-ocr-web/build.sh
./setup_assets.sh
./scripts/run_ocr_web.sh
```

The root `./build.sh` includes this environment by default; `--no-ocr-web` skips it. Build creates environments and NPU configuration; `setup_assets.sh` prepares NPU models separately. The launcher can prepare a missing Web environment, but missing NPU assets require the resource step. CPU/Paddle models may download on first use.

根目录 `./build.sh` 默认包含此环境，`--no-ocr-web` 可跳过。构建阶段准备环境和 NPU 配置，`setup_assets.sh` 单独准备 NPU 模型。启动器可以补建缺失的 Web 环境，但缺少 NPU 模型时仍需执行资源步骤。CPU/Paddle 模型可能在首次使用时下载。

```bash
./apps/paddle-ocr-web/build.sh --dx_rt /path/to/matching/dx_rt
./apps/paddle-ocr-web/build.sh --cpu-only
./apps/paddle-ocr-web/build.sh --clean
./scripts/kill_ocr_web.sh
```

`--cpu-only` removes NPU configuration; `--clean` recreates the two Web venvs. These scripts do not provision the system SDK. See [environment details](python/README.md).

`--cpu-only` 移除 NPU 配置，`--clean` 重建两个 Web venv。脚本不负责系统 SDK 安装。详见[环境说明](python/README.md)。

## Run configuration / 运行配置

- `config.sh`: `DX_OCR_API_URL` defaults to `http://localhost:8080/api/v1/ocr`; `DX_BROWSER` selects the browser. / 配置 API 地址和浏览器。
- The launcher waits for `/health` before opening the UI in a normal browser window. / 启动器等待服务健康检查通过后，以普通浏览器窗口打开 UI。
- Upstream `run.sh` reads `deepx_env.sh` to select NPU mode; otherwise it starts in CPU mode. / 上游根据 `deepx_env.sh` 是否存在选择 NPU 模式。
- The current UI fixes its port at 7860. / 当前 UI 端口固定为 7860。

To run only the local server / 仅启动本地服务端：

```bash
cd apps/paddle-ocr-web/python/PaddleOCR-deepx/deploy/fastapi
./run.sh
```

This deployment revision has only been statically reviewed; no installation, build, or inference result is claimed. / 本次调整仅经过静态审查，不声明已通过安装、构建或推理验证。
