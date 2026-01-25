FROM ghcr.io/vevc/ubuntu:25.11.15

USER root

# 1. 安装基础工具
RUN apt-get update && apt-get install -y \
    supervisor \
    wget \
    curl \
    vim \
    unzip \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# 2. 默认环境变量
ENV SSH_USER=zv
ENV SSH_PASSWORD=105106

# 3. 创建自定义启动脚本
# 这个脚本会：创建用户、设置密码、生成配置、启动SSH、启动Supervisor
RUN echo '#!/bin/bash\n\
# 动态创建用户主目录\n\
USER_HOME="/home/${SSH_USER}"\n\
BOOT_DIR="${USER_HOME}/boot"\n\
mkdir -p ${BOOT_DIR}\n\
\n\
# 设置系统用户和密码 (支持动态变量)\n\
id -u ${SSH_USER} &>/dev/null || useradd -m -s /bin/bash ${SSH_USER}\n\
echo "${SSH_USER}:${SSH_PASSWORD}" | chpasswd\n\
\n\
# 生成 supervisord 配置\n\
cat <<EOF > ${BOOT_DIR}/supervisord.conf\n\
[supervisord]\n\
nodaemon=true\n\
logfile=/tmp/supervisord.log\n\
pidfile=/tmp/supervisord.pid\n\
\n\
[unix_http_server]\n\
file=/tmp/supervisor.sock\n\
\n\
[rpcinterface:supervisor]\n\
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface\n\
\n\
[supervisorctl]\n\
serverurl=unix:///tmp/supervisor.sock\n\
EOF\n\
\n\
# 权限归属\n\
chmod -R 777 ${USER_HOME}\n\
\n\
# 启动 SSH 服务 (手动启动以确保 SSH 可用)\n\
mkdir -p /var/run/sshd\n\
/usr/sbin/sshd\n\
\n\
# 启动 Supervisor (作为前台主进程)\n\
echo "Starting Supervisor with config at ${BOOT_DIR}/supervisord.conf..."\n\
exec supervisord -c ${BOOT_DIR}/supervisord.conf' > /entrypoint_custom.sh

RUN chmod +x /entrypoint_custom.sh

# 4. 暴露端口
EXPOSE 22 2222

# 指向我们完全接管的入口
ENTRYPOINT ["/entrypoint_custom.sh"]
ENTRYPOINT ["/entrypoint_custom.sh"]
