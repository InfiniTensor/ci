FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# 安装必要的系统工具和运行环境
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    wget \
    git \
    vim \
    jq \
    net-tools \
    iputils-ping \
    dnsutils \
    procps \
    lsof \
    unzip \
    zip \
    python3 \
    python3-pip \
    python3-venv \
    npm \
    && rm -rf /var/lib/apt/lists/*

# 创建一个工作目录
WORKDIR /workspace

# 将项目代码拷贝进镜像
COPY deamon.sh /workspace
COPY requirements.txt /workspace

RUN pip3 install --no-cache-dir -r requirements.txt

RUN chmod +x /workspace/deamon.sh

ENTRYPOINT ["/workspace/deamon.sh"]
