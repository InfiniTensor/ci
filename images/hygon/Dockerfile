ARG BASE_IMAGE=harbor.sourcefind.cn:5443/dcu/admin/base/custom:sglang-deepseek-v4-dev-zkjh
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
ARG http_proxy
ARG https_proxy
ARG no_proxy

# Keep the DTK-enabled PyTorch supplied by the base image when project
# dependencies are installed later in a development container.
RUN torch_version="$(python3 -m pip show torch | awk '/^Version:/ {print $2}')" && \
    test -n "$torch_version" && \
    printf 'torch==%s\n' "$torch_version" > /etc/pip-constraints.txt
ENV PIP_CONSTRAINT=/etc/pip-constraints.txt

RUN python3 -m pip install --no-cache-dir \
        janus==2.0.0 \
        libclang==18.1.1 \
        regex==2026.4.4 \
        ruff==0.15.7 \
        safetensors==0.8.0 \
        sentencepiece==0.2.1 \
        tokenizers==0.22.2 \
        transformers==5.15.0 \
        xxhash==3.6.0

ARG XMAKE_VERSION=v3.0.5
ARG XMAKE_SHA256=4075ef1b4cba7f5eb5c55a4451761ef081086bb3142e7d4b130cf9c7484e68f0
ARG XMAKE_DOWNLOAD_URL=https://github.com/xmake-io/xmake/releases/download/${XMAKE_VERSION}/xmake-bundle-${XMAKE_VERSION}.linux.x86_64
ENV XMAKE_ROOT=y
RUN curl --retry 5 --retry-all-errors -fsSL \
        "${XMAKE_DOWNLOAD_URL}" -o /usr/local/bin/xmake && \
    printf '%s  %s\n' "$XMAKE_SHA256" /usr/local/bin/xmake \
        | sha256sum --check - && \
    chmod +x /usr/local/bin/xmake

# Pin the package recipe used by the validated environment and pre-populate
# the Xmake package cache required by the InfiniLM native extensions.
ARG XMAKE_REPO_URL=https://gitee.com/crapromer/xmake-repo.git
ARG XMAKE_REPO_COMMIT=674a71c5905870e6e7e162bf689903822bbbf16e
COPY images/hygon/xmake-cache.lua /opt/xmake-cache-project/xmake.lua
RUN git clone "${XMAKE_REPO_URL}" /opt/xmake-repo && \
    git -C /opt/xmake-repo checkout "${XMAKE_REPO_COMMIT}" && \
    xmake repo --clear --global && \
    xmake repo --add --global xmake-repo /opt/xmake-repo && \
    xmake require -y -P /opt/xmake-cache-project

ENV DTK_ROOT=/opt/dtk
ENV HYGON_ARCH=gfx936
ENV CUDA_HOME=/opt/dtk/cuda/cuda
ENV PATH=/opt/dtk/cuda/cuda/bin:/root/.local/bin:${PATH}
ENV LD_LIBRARY_PATH=/opt/dtk/cuda/cuda/targets/x86_64-linux/lib:${LD_LIBRARY_PATH}

WORKDIR /workspace/run
