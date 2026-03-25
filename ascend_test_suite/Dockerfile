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
    docker.io \
    tini \
    npm \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# 安装 Node.js 20 LTS（包含 npm）
# RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
#     apt-get update && apt-get install -y nodejs && \
#     rm -rf /var/lib/apt/lists/*

# 创建 .ssh 目录
RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh

# 拷贝私钥
COPY id_rsa /root/.ssh/id_rsa

# 设置权限
RUN chmod 600 /root/.ssh/id_rsa

# 创建一个工作目录
WORKDIR /CI_Workspace

# 将项目代码拷贝进镜像
COPY entrypoint.sh /CI_Workspace
COPY requirements.txt /CI_Workspace

RUN pip3 install --no-cache-dir -r requirements.txt

ARG JMETER_VERSION=5.6.3
RUN wget -q https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz && \
    tar -xzf apache-jmeter-${JMETER_VERSION}.tgz -C /opt && \
    ln -s /opt/apache-jmeter-${JMETER_VERSION} /opt/jmeter && \
    rm apache-jmeter-${JMETER_VERSION}.tgz

ENV JMETER_HOME=/opt/jmeter
ENV PATH=$JMETER_HOME/bin:$PATH

RUN chmod +x /CI_Workspace/entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/CI_Workspace/entrypoint.sh"]
