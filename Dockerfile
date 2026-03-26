# 使用官方Ubuntu镜像作为基础镜像
FROM ubuntu:latest

#安装Java、Python和Git
RUN apt-get update && \
    apt-get install -y openjdk-11-jdk python3-pip python3-venv git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

#设置环境变量已使用Java和Python
ENV JAVA_HOME /usr/lib/jvm/java-11-openjdk-amd64
ENV PATH $PATH:$JAVA_HOME/bin
ENV PYTHONUNBUFFERED=1

# 创建一个工作目录
WORKDIR /test

# 将项目代码拷贝进镜像
COPY . /test

# 创建并激活虚拟环境，安装 Python 依赖（如果 requirements.txt 不存在则忽略错误）
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir --upgrade pip && \
    if [ -f requirements.txt ]; then /opt/venv/bin/pip install --no-cache-dir -r requirements.txt; fi

# 将虚拟环境加入 PATH
ENV PATH="/opt/venv/bin:/test/allure-2.35.1/bin:$PATH"

# 确保启动脚本可执行
RUN chmod +x /test/start.sh

# 定义默认运行命令（根据实际需要调整）
# CMD ["python3", "your_python_script.py"] 或 CMD ["java", "-jar", "your_java_app.jar"]