FROM ghcr.io/vevc/ubuntu:25.11.15

USER root

# 1. 安装基础工具 + Cloudflared (针对 Linux AMD64 架构)
RUN apt-get update && apt-get install -y \
    supervisor procps wget curl passwd sudo openssh-server && \
    curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb && \
    dpkg -i cloudflared.deb && \
    rm cloudflared.deb && \
    rm -rf /var/lib/apt/lists/*

# 2. 设置默认环境变量
# 用户名和密码可以在 cf push 时通过 -e 修改，Token 必须在部署时传入
ENV SSH_USER=zv
ENV SSH_PASSWORD=105106
ENV CF_TUNNEL_TOKEN=""

# 3. 固化全局别名 (适配动态用户名)
RUN echo "alias sctl='supervisorctl -c /home/\${SSH_USER:-zv}/boot/supervisord.conf'" >> /etc/bash.bashrc && \
    echo "alias vpreboot='pkill -9 supervisord'" >> /etc/bash.bashrc

# 4. 编写入口启动脚本
RUN printf "#!/bin/bash\n\
export USER_HOME=\"/home/\${SSH_USER:-zv}\"\n\
export BOOT_DIR=\"\${USER_HOME}/boot\"\n\
mkdir -p \"\${BOOT_DIR}\" /var/run/sshd /var/log/supervisor\n\
\n\
# 配置权限：让 sudo 组免密\n\
echo \"%%sudo ALL=(ALL:ALL) NOPASSWD: ALL\" >> /etc/sudoers\n\
\n\
# 创建用户并加入 sudo 组\n\
if ! id \"\${SSH_USER}\" &>/dev/null; then\n\
    useradd -m -s /bin/bash \"\${SSH_USER}\"\n\
fi\n\
adduser \"\${SSH_USER}\" sudo\n\
\n\
# 设置密码\n\
echo \"\${SSH_USER}:\${SSH_PASSWORD}\" | chpasswd\n\
echo \"root:\${SSH_PASSWORD}\" | chpasswd\n\
\n\
# 生成 SSH 主机密钥\n\
ssh-keygen -A\n\
\n\
# 动态生成 Supervisor 配置\n\
printf \"[supervisord]\n\
nodaemon=true\n\
user=root\n\
\n\
[program:sshd]\n\
command=/usr/sbin/sshd -D -p 22\n\
autostart=true\n\
autorestart=true\n\
\n\
[program:cloudflared]\n\
command=/usr/bin/cloudflared tunnel --no-autoupdate run --token \${CF_TUNNEL_TOKEN}\n\
autostart=true\n\
autorestart=true\n\
\" > \"\${BOOT_DIR}/supervisord.conf\"\n\
\n\
# 启动进程管理\n\
exec /usr/bin/supervisord -c \"\${BOOT_DIR}/supervisord.conf\"\n" > /entrypoint.sh && chmod +x /entrypoint.sh

# 5. 设置启动入口
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
