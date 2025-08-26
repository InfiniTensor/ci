# 使用官方Ubuntu镜像作为基础镜像
FROM ubuntu:latest

#安装Java和Python
RUN apt-get update && \
    apt-get install -y openjdk-11-jdk python3-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

#设置环境变量已使用Java和Python
ENV JAVA_HOME /usr/lib/jvm/java-11-openjdk-amd64
ENV PATH $PATH:$JAVA_HOME/bin
ENV PYTHONUNBUFFERED=1 

# 创建一个工作目录
WORKDIR /test

# 定义默认运行命令（例如，运行Python或Java应用）
# CMD ["python3", "your_python_script.py"] 或 CMD ["java", "-jar", "your_java_app.jar"]