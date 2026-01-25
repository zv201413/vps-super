FROM ghcr.io/vevc/ubuntu:25.11.15

USER root

# 1. 安装基础工具 (确保有 pkill 所在的 procps 包)
RUN apt-get update && apt-get install -y \
    supervisor \
    procps \
    wget \
    curl \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# 2. 固化环境变量
ENV SSH_USER=zv
ENV SSH_PASSWORD=105106

# 3. 【核心修复】将别名写进系统全局配置文件 /etc/bash.bashrc
# 这样无论容器重启多少次，新容器一出生就自带这些命令
RUN echo "alias sctl='supervisorctl -c /home/zv/boot/supervisord.conf'" >> /etc/bash.bashrc && \
    echo "alias vpreboot='pkill -9 supervisord'" >> /etc/bash.bashrc && \
    echo "alias sload='supervisorctl -c /home/zv/boot/supervisord.conf reload'" >> /etc/bash.bashrc

# 4. 创建启动脚本 (保持之前的逻辑)
RUN echo '#!/bin/bash\n\
USER_HOME="/home/${SSH_USER}"\n\
BOOT_DIR="${USER_HOME}/boot"\n\
mkdir -p ${BOOT_DIR}\n\
id -u ${SSH_USER} &>/dev/null || useradd -m -s /bin/bash ${SSH_USER}\n\
echo "${SSH_USER}:${SSH_PASSWORD}" | chpasswd\n\
cat <<EOF > ${BOOT_DIR}/supervisord.conf\n\
[supervisord]\n\
nodaemon=true\n\
logfile=/tmp/supervisord.log\n\
pidfile=/tmp/supervisord.pid\n\
[unix_http_server]\n\
file=/tmp/supervisor.sock\n\
chmod=0700\n\
[rpcinterface:supervisor]\n\
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface\n\
[supervisorctl]\n\
serverurl=unix:///tmp/supervisor.sock\n\
[include]\n\
files = ${BOOT_DIR}/*.conf\n\
EOF\n\
chmod -R 777 ${USER_HOME}\n\
mkdir -p /var/run/sshd\n\
/usr/sbin/sshd\n\
exec supervisord -c ${BOOT_DIR}/supervisord.conf' > /entrypoint_custom.sh && chmod +x /entrypoint_custom.sh

EXPOSE 22 2222
ENTRYPOINT ["/entrypoint_custom.sh"]
