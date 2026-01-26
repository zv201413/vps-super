FROM ghcr.io/vevc/ubuntu:25.11.15

USER root

# 1. 安装基础工具 (包含 passwd 以支持 chpasswd)
RUN apt-get update && apt-get install -y \
    supervisor \
    procps \
    wget \
    curl \
    passwd \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# 2. 固化环境变量
ENV SSH_USER=zv
ENV SSH_PASSWORD=105106

# 3. 固化全局别名 (确保每个登录 Shell 都能直接使用 sctl)
RUN echo "alias sctl='supervisorctl -c /home/zv/boot/supervisord.conf'" >> /etc/bash.bashrc && \
    echo "alias vpreboot='pkill -9 supervisord'" >> /etc/bash.bashrc && \
    echo "alias sload='supervisorctl -c /home/zv/boot/supervisord.conf reload'" >> /etc/bash.bashrc

# 4. 创建启动脚本 (包含完整的 Supervisor 控制区块)
RUN printf "#!/bin/bash\n\
export USER_HOME=\"/home/\${SSH_USER:-zv}\"\n\
export BOOT_DIR=\"\${USER_HOME}/boot\"\n\
\n\
mkdir -p \"\${BOOT_DIR}\" /var/run/sshd /var/log/supervisor\n\
\n\
# 设置用户和密码\n\
id -u \${SSH_USER} &>/dev/null || useradd -m -s /bin/bash \${SSH_USER}\n\
echo \"\${SSH_USER}:\${SSH_PASSWORD}\" | chpasswd\n\
echo \"root:\${SSH_PASSWORD}\" | chpasswd\n\
\n\
# 准备 SSH 主机密钥\n\
ssh-keygen -A\n\
\n\
# 写入完整的 Supervisor 配置\n\
printf \"[supervisord]\n\
nodaemon=true\n\
user=root\n\
logfile=/tmp/supervisord.log\n\
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
[program:sshd]\n\
command=/usr/sbin/sshd -D -p 2233 -o PermitRootLogin=yes -o PasswordAuthentication=yes\n\
autostart=true\n\
autorestart=true\n\
\n\
[include]\n\
files = \${BOOT_DIR}/*.conf\n\
\" > \"\${BOOT_DIR}/supervisord.conf\"\n\
\n\
chmod -R 777 \"\${USER_HOME}\"\n\
\n\
# 启动进程管理器\n\
exec /bin/supervisord -c \"\${BOOT_DIR}/supervisord.conf\"\n" > /entrypoint_custom.sh && chmod +x /entrypoint_custom.sh

# 5. 设置入口点
ENTRYPOINT ["/bin/bash", "/entrypoint_custom.sh"]
