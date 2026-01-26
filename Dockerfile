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

# 4. 创建启动脚本 (集成 SSH 到 Supervisor)
RUN echo '#!/bin/bash\n\
USER_HOME="/home/${SSH_USER}"\n\
BOOT_DIR="${USER_HOME}/boot"\n\
mkdir -p ${BOOT_DIR}\n\
# 确保用户存在并同步密码\n\
id -u ${SSH_USER} &>/dev/null || useradd -m -s /bin/bash ${SSH_USER}\n\
echo "${SSH_USER}:${SSH_PASSWORD}" | chpasswd\n\
echo "root:${SSH_PASSWORD}" | chpasswd\n\
\n\
# 动态生成 supervisord 配置\n\
cat <<EOF > ${BOOT_DIR}/supervisord.conf\n\
[supervisord]\n\
nodaemon=true\n\
logfile=/tmp/supervisord.log\n\
pidfile=/tmp/supervisord.pid\n\
\n\
[program:sshd]\n\
# -D 保证前台运行，-p 2233 避开端口劫持\n\
command=/usr/sbin/sshd -D -p 2233 -o "PermitRootLogin=yes" -o "PasswordAuthentication=yes"\n\
autostart=true\n\
autorestart=true\n\
stdout_logfile=/tmp/sshd.log\n\
stderr_logfile=/tmp/sshd.err.log\n\
\n\
[unix_http_server]\n\
file=/tmp/supervisor.sock\n\
chmod=0700\n\
\n\
[rpcinterface:supervisor]\n\
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface\n\
\n\
[supervisorctl]\n\
serverurl=unix:///tmp/supervisor.sock\n\
\n\
[include]\n\
# 允许加载其他业务配置（如 xray）\n\
files = ${BOOT_DIR}/*.conf\n\
EOF\n\
\n\
# 准备 SSH 运行环境\n\
mkdir -p /var/run/sshd\n\
chmod 0755 /var/run/sshd\n\
chmod -R 777 ${USER_HOME}\n\
\n\
# 启动进程管理器\n\
exec supervisord -c ${BOOT_DIR}/supervisord.conf' > /entrypoint_custom.sh && chmod +x /entrypoint_custom.sh
