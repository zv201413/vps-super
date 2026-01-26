FROM ghcr.io/vevc/ubuntu:25.11.15

USER root

# 1. 安装基础工具 (确保有 pkill 所在的 procps 包)
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

# 3. 【核心修复】将别名写进系统全局配置文件 /etc/bash.bashrc
# 这样无论容器重启多少次，新容器一出生就自带这些命令
RUN echo "alias sctl='supervisorctl -c /home/zv/boot/supervisord.conf'" >> /etc/bash.bashrc && \
    echo "alias vpreboot='pkill -9 supervisord'" >> /etc/bash.bashrc && \
    echo "alias sload='supervisorctl -c /home/zv/boot/supervisord.conf reload'" >> /etc/bash.bashrc

# 4. 创建启动脚本 (稳健相对路径版)
RUN printf "#!/bin/bash\n\
# 1. 动态定义路径\n\
export USER_HOME=\"/home/\${SSH_USER:-zv}\"\n\
export BOOT_DIR=\"\${USER_HOME}/boot\"\n\
\n\
# 2. 创建必要目录\n\
mkdir -p \"\${BOOT_DIR}\" /var/run/sshd /var/log/supervisor\n\
\n\
# 3. 同步用户和密码\n\
id -u \${SSH_USER} &>/dev/null || useradd -m -s /bin/bash \${SSH_USER}\n\
echo \"\${SSH_USER}:\${SSH_PASSWORD}\" | chpasswd\n\
echo \"root:\${SSH_PASSWORD}\" | chpasswd\n\
\n\
# 4. 修复 SSH 密钥\n\
ssh-keygen -A\n\
\n\
# 5. 写入 Supervisor 配置 (使用 printf 避免 EOF 转义失败)\n\
printf \"[supervisord]\nnodaemon=true\nuser=root\nlogfile=/tmp/supervisord.log\n\n[program:sshd]\ncommand=/usr/sbin/sshd -D -p 2233 -o PermitRootLogin=yes -o PasswordAuthentication=yes\nautostart=true\nautorestart=true\n\n[include]\nfiles = \${BOOT_DIR}/*.conf\n\" > \"\${BOOT_DIR}/supervisord.conf\"\n\
\n\
# 6. 设置权限并启动\n\
chmod -R 777 \"\${USER_HOME}\"\n\
exec /bin/supervisord -c \"\${BOOT_DIR}/supervisord.conf\"\n" > /entrypoint_custom.sh && chmod +x /entrypoint_custom.sh
