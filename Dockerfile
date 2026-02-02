FROM ubuntu:22.04

# 统一变量名，使用 SSH_PWD 避免冲突
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    SSH_USER=zv \
    SSH_PWD=105106

RUN apt-get update && apt-get install -y \
    openssh-server supervisor curl wget sudo ca-certificates \
    tzdata vim net-tools unzip iputils-ping telnet git iproute2 \
    && rm -rf /var/lib/apt/lists/*

# 安装 cloudflared 和 ttyd
RUN curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
    && dpkg -i cloudflared.deb \
    && rm cloudflared.deb \
    && curl -L https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64 -o /usr/local/bin/ttyd \
    && chmod +x /usr/local/bin/ttyd

# 准备 SSH 运行环境
RUN mkdir -p /run/sshd && ssh-keygen -A \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# --- 核心改进：注入满血版模板 ---
# 这个模板包含了 unix_http_server 和 rpcinterface，确保 sctl 进场就能用
RUN mkdir -p /usr/local/etc && printf "[unix_http_server]\n\
file=/var/run/supervisor.sock\n\
chmod=0700\n\n\
[supervisord]\n\
nodaemon=true\n\
user=root\n\
logfile=/var/log/supervisor/supervisord.log\n\
pidfile=/var/run/supervisord.pid\n\n\
[rpcinterface:supervisor]\n\
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface\n\n\
[supervisorctl]\n\
serverurl=unix:///var/run/supervisor.sock\n\n\
[program:sshd]\n\
command=/usr/sbin/sshd -D\n\
autostart=true\n\
autorestart=true\n\n\
[program:ttyd]\n\
command=/usr/local/bin/ttyd -W bash\n\
autostart=true\n\
autorestart=true\n\n\
[program:cloudflare]\n\
command=cloudflared tunnel --no-autoupdate run --token %%(ENV_CF_TOKEN)s\n\
autostart=true\n\
autorestart=true\n" > /usr/local/etc/supervisord.conf.template

# 默认的保底配置也同步更新为支持 sctl 的版本
RUN cp /usr/local/etc/supervisord.conf.template /etc/supervisor/supervisord.conf

# 拷贝并处理智能脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22 7681

# 注意：这里不再指定 CMD 的具体参数，全部交给 entrypoint.sh 处理逻辑分流
ENTRYPOINT ["/entrypoint.sh"]
