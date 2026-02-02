FROM ubuntu:22.04

# 统一变量名，注意 PWD 改为 SSH_PWD 以免冲突
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

# 写入一个“保底”用的默认配置
RUN mkdir -p /etc/supervisor/conf.d
RUN echo "[supervisord]\n\
nodaemon=true\n\
user=root\n\
\n\
[program:sshd]\n\
command=/usr/sbin/sshd -D\n\
autorestart=true\n\
\n\
[program:ttyd]\n\
command=/usr/local/bin/ttyd -W bash\n\
autorestart=true" > /etc/supervisor/supervisord.conf

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22 7681

ENTRYPOINT ["/entrypoint.sh"]
# 默认命令指向 /etc 下的保底配置，这样不挂载存储也能跑
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
