# PaddleOCR Web environments / 环境说明

See the [root installation guide](../../../README.md) / [中文安装指南](../../../README.zh-CN.md) for prerequisites and the three-stage deployment flow.

```text
python/
├── build.sh
├── PP-OCRv5_Online_demo-deepx/   # Cloned UI source / UI 源码
├── PaddleOCR-deepx/             # Cloned server source / 服务端源码
│   └── deploy/fastapi/
│       ├── venv/               # Server environment / 服务端环境
│       ├── deepx_env.sh         # NPU configuration / NPU 配置
│       └── deepx/engine/model_files/
└── .venv/                      # UI environment / UI 环境
```

## Build behavior / 构建行为

1. Clone the UI and server `deepx` branches if absent; retrieve LFS example images. / 按需获取两个上游仓库及 LFS 示例图片。
2. Create/reuse the UI venv and install its requirements. Python 3.12 uses a newer binary Pillow instead of the upstream 9.5 pin; WebP support is checked. / 准备 UI 环境，处理 Python 3.12 下 Pillow wheel 兼容性，并检查 WebP。
3. Create/reuse the server venv and install its requirements directly. PaddleX supplies `opencv-contrib-python`, so the duplicate upstream headless requirement is filtered out. / 直接安装服务端依赖，过滤重复的 OpenCV wheel。
4. Unless `--cpu-only` is given, install the matching SDK's `dx_engine` binding, check its native import, and write `deepx_env.sh`. If the binding is unavailable, remove stale NPU configuration and report CPU mode. / 安装绑定并生成 NPU 配置；绑定不可用时清除旧配置并报告 CPU 模式。
5. Run the root `setup_assets.sh` separately to fetch server/mobile NPU models and dictionaries. / 单独执行根资源脚本准备模型与字典。

The shared helper uses a local compatible SDK wheel, or builds the binding from a temporary copy of `DX_RT/python_package` with the SDK headers beside it. It does not rebuild or install the system DXRT library. The upstream `local_setup.sh` and privileged `local_deepx_setup.sh` are not invoked.

共享 helper 优先使用本地兼容 SDK wheel，否则从 `DX_RT/python_package` 临时副本构建绑定，并保留配套头文件布局。不重新编译安装系统 DXRT 库，也不调用上游 `local_setup.sh` 或需要提权的 `local_deepx_setup.sh`。

From the repository root / 从仓库根目录执行：

```bash
./apps/paddle-ocr-web/python/build.sh
./setup_assets.sh
./scripts/run_ocr_web.sh
./scripts/kill_ocr_web.sh
```

| Option / 选项 | Effect / 作用 |
| --- | --- |
| `--dx_rt PATH` | Explicit binding source checkout; also accepts `DX_RT_PATH` / 指定绑定源码目录 |
| `--cpu-only` | Skip NPU binding/configuration / 跳过 NPU 绑定与配置 |
| `--clean` | Recreate both Web venvs, keep sources/resources / 重建两个环境，保留源码和资源 |

Requirements are checked again on reruns so an interrupted pip install can be repaired. Upstream branches are not commit-pinned. For old environments with multiple OpenCV providers, use `--clean`; pip does not remove packages merely because they disappeared from a requirements file.

重新运行会再次核对安装依赖，以修复中断的 pip 安装。上游分支未锁定 commit。旧环境若已有多种 OpenCV wheel，请使用 `--clean`；从 requirements 删除声明不会自动卸载旧包。
