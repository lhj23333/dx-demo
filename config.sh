#!/bin/bash
# dx-demos Top-Level Configuration

# Set the camera index to use for OpenCV/Python (e.g., 0, 1)
export DX_CAMERA_IDX="0"

# Set the camera device path to use for V4L2/C++ (e.g., /dev/video0, /dev/video1)
export DX_CAMERA_DEV="/dev/video${DX_CAMERA_IDX}"

# Set the PaddleOCR-deepx server endpoint used by the OCR Web demo
export DX_OCR_API_URL="http://localhost:8080/api/v1/ocr"

# Set the browser used by the web demos (empty = desktop default browser)
export DX_BROWSER="${DX_BROWSER:-}"

# Python used to create virtualenvs (must be 3.10+). Empty = auto-detect
# python3.11, including /mnt/data/opt/python-3.11/bin/python3.11
export DX_PYTHON="${DX_PYTHON:-}"

# dx_rt checkout used to build the dx_engine python binding. Empty = auto-detect
# from DX_ALL_SUITE_DIR and the usual DEEPX SDK layouts
export DX_RT="${DX_RT:-}"
