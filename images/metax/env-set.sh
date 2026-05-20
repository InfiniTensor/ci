#! /bin/bash
echo "------------------------ env-set.sh ----------------------"

# xmake in our dev container runs as root; allow it explicitly.
export XMAKE_ROOT=y

# INFINI_ROOT
export INFINI_ROOT=/root/.infini
export PATH=${PATH}:${INFINI_ROOT}/bin

# MACA
export MACA_HOME=/opt/maca
export MACA_PATH=${MACA_HOME}

# Loader order: Infini install first (correct libinfinicore_cpp_api), then MACA, then the
# Conda toolchain lib (must precede system /lib so we do not load two different libstdc++.so.6),
# then Torch's bundled libs.
# Avoid a leading ":" when LD_LIBRARY_PATH was unset — that makes ld.so search CWD first.
_conda_lib=/opt/conda/lib
_torch_lib=/opt/conda/lib/python3.10/site-packages/torch/lib
export LD_LIBRARY_PATH="${INFINI_ROOT}/lib:${MACA_PATH}/lib:${_conda_lib}:${_torch_lib}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# cu-bridge + MACA headers for ATen builds (Torch expects cuda_runtime_api.h; cu-bridge provides it)
# `cu-bridge/include/cuComplex.h` includes `mcComplex.h` which lives under `include/common` in MACA.
export CPATH=${MACA_PATH}/tools/cu-bridge/include:${MACA_PATH}/include/common:${MACA_PATH}/include/mcblas:${MACA_PATH}/include/mcsolver:${MACA_PATH}/include/mcsparse:${MACA_PATH}/include/mcr:${MACA_PATH}/include:${CPATH:-}
export CPLUS_INCLUDE_PATH=${MACA_PATH}/tools/cu-bridge/include:${MACA_PATH}/include/common:${MACA_PATH}/include/mcblas:${MACA_PATH}/include/mcsolver:${MACA_PATH}/include/mcsparse:${MACA_PATH}/include/mcr:${MACA_PATH}/include:${CPLUS_INCLUDE_PATH:-}
export C_INCLUDE_PATH=${MACA_PATH}/tools/cu-bridge/include:${MACA_PATH}/include/common:${MACA_PATH}/include/mcblas:${MACA_PATH}/include/mcsolver:${MACA_PATH}/include/mcsparse:${MACA_PATH}/include/mcr:${MACA_PATH}/include:${C_INCLUDE_PATH:-}

# Optional: only set if it exists in this image
if [[ -f /opt/conda/lib/python3.10/site-packages/flash_attn_2_cuda*.so ]]; then
  export FLASH_ATTN_2_CUDA_SO="$(ls -1 /opt/conda/lib/python3.10/site-packages/flash_attn_2_cuda*.so | head -n 1)"
fi


echo "------------------------ env-set.sh success ----------------------"
