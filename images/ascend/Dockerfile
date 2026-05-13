ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
ARG http_proxy
ARG https_proxy
ARG no_proxy
ARG PIP_INDEX_URL=https://pypi.org/simple

RUN missing=0; \
    for tool in git cmake ninja curl gcc g++ clang; do \
        if ! command -v "$tool" >/dev/null 2>&1; then missing=1; fi; \
    done; \
    if [ "$missing" = "0" ]; then \
        echo "Required system tools are already present"; \
    elif command -v apt-get >/dev/null 2>&1; then \
        export DEBIAN_FRONTEND=noninteractive; \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            git \
            cmake \
            ninja-build \
            coreutils \
            curl \
            libclang-dev && \
        rm -rf /var/lib/apt/lists/*; \
    elif command -v dnf >/dev/null 2>&1; then \
        dnf install -y \
            git \
            cmake \
            ninja-build \
            coreutils \
            curl \
            gcc \
            gcc-c++ \
            clang-devel && \
        dnf clean all; \
    elif command -v yum >/dev/null 2>&1; then \
        yum install -y \
            git \
            cmake \
            ninja-build \
            coreutils \
            curl \
            clang-devel && \
        yum clean all; \
    else \
        echo "No supported package manager found" >&2; \
        exit 1; \
    fi

ARG PRIVATE_SDK_URL
RUN if [ -n "$PRIVATE_SDK_URL" ]; then \
        curl -fSL "$PRIVATE_SDK_URL" -o /tmp/sdk.run && \
        chmod +x /tmp/sdk.run && /tmp/sdk.run --quiet && \
        rm /tmp/sdk.run; \
    fi

RUN python3 -m pip install --no-cache-dir \
    scikit-build-core \
    pybind11 \
    libclang \
    pytest \
    pytest-cov \
    pytest-xdist \
    pyyaml

ENV ASCEND_TOOLKIT_HOME=/usr/local/Ascend/ascend-toolkit/latest
ENV LD_LIBRARY_PATH=${ASCEND_TOOLKIT_HOME}/lib64:${ASCEND_TOOLKIT_HOME}/lib64/plugin/opskernel:${ASCEND_TOOLKIT_HOME}/lib64/plugin/nnengine:${ASCEND_TOOLKIT_HOME}/opp/built-in/op_impl/ai_core/tbe/op_tiling/lib/linux/aarch64:${LD_LIBRARY_PATH}
ENV PYTHONPATH=${ASCEND_TOOLKIT_HOME}/python/site-packages:${ASCEND_TOOLKIT_HOME}/opp/built-in/op_impl/ai_core/tbe:${PYTHONPATH}
ENV PATH=${ASCEND_TOOLKIT_HOME}/bin:${ASCEND_TOOLKIT_HOME}/compiler/ccec_compiler/bin:${PATH}
ENV ASCEND_AICPU_PATH=${ASCEND_TOOLKIT_HOME}
ENV ASCEND_OPP_PATH=${ASCEND_TOOLKIT_HOME}/opp
ENV TOOLCHAIN_HOME=${ASCEND_TOOLKIT_HOME}/toolkit

WORKDIR /workspace
