#!/bin/bash
# Local/dev helper: mirrors ENV in images/metax/Dockerfile.deploy.
# Image builds do not source this file; variables are baked in via ENV.

export XMAKE_ROOT=y
export INFINI_ROOT=/root/.infini
export PATH="${PATH}:${INFINI_ROOT}/bin"
export MACA_HOME=/opt/maca
export MACA_PATH="${MACA_HOME}"

_conda_lib=/opt/conda/lib
_torch_lib=/opt/conda/lib/python3.10/site-packages/torch/lib
export LD_LIBRARY_PATH="${INFINI_ROOT}/lib:${MACA_PATH}/lib:${_conda_lib}:${_torch_lib}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

export CPATH="${MACA_PATH}/tools/cu-bridge/include:${MACA_PATH}/include/common:${MACA_PATH}/include/mcblas:${MACA_PATH}/include/mcsolver:${MACA_PATH}/include/mcsparse:${MACA_PATH}/include/mcr:${MACA_PATH}/include:/opt/conda/include/python3.10:/opt/conda/include:/opt/conda/lib/python3.10/site-packages/pybind11/include:${CPATH:-}"
export CPLUS_INCLUDE_PATH="${CPATH}"
export C_INCLUDE_PATH="${CPATH}"

if compgen -G /opt/conda/lib/python3.10/site-packages/flash_attn_2_cuda*.so >/dev/null; then
  export FLASH_ATTN_2_CUDA_SO="$(ls -1 /opt/conda/lib/python3.10/site-packages/flash_attn_2_cuda*.so | head -n 1)"
fi

export PYTHONPATH="/workspace/InfiniLM/python:/workspace/InfiniCore/python:${PYTHONPATH:-}"
