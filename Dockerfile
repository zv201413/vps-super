FROM ubuntu:22.04

# 1. 基础环境设置
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    SSH_USER=zv \
    SSH_PWD=105106

# 2. 安装必要软件包
RUN apt-get update && apt-get install -y \
    openssh-server supervisor curl wget sudo ca-certificates \
    tzdata vim net-tools unzip iputils-ping telnet git iproute2 \
    && rm -rf /var/lib/apt/lists/*

# 3. 安装工具 (cloudflared & ttyd)
RUN curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
    && dpkg -i cloudflared.deb \
    && rm cloudflared.deb \
    && curl -L https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64 -o /usr/local/bin/ttyd \
    && chmod +x /usr/local/bin/ttyd

# 4. SSH 环境预处理
RUN mkdir -p /run/sshd && ssh-keygen -A \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 5. 配置文件与脚本处理 (关键修复区)
# 创建模板存放目录
RUN mkdir -p /usr/local/etc

# 直接从仓库拷贝配置文件，彻底避开 echo 导致的 exit code 2 报错
COPY supervisord.conf /usr/local/etc/supervisord.conf.template

# 处理启动脚本
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 移除系统默认配置以防冲突
RUN rm -f /etc/supervisor/supervisord.conf

# 6. 运行身份设置
# 必须以 root 启动以处理 Zeabur 挂载存储后的 chown 权限问题
USER root

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
