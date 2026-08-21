FROM ubuntu:22.04

# 1. 基础环境设置 (保持默认值 zv/105106)
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    SSH_USER=zv \
    SSH_PWD=105106

# 2. 安装必要软件包
RUN apt-get update && apt-get install -y \
    openssh-server supervisor curl wget sudo ca-certificates openssl \
    tzdata vim net-tools unzip iputils-ping telnet git iproute2 \
    && rm -rf /var/lib/apt/lists/*

# 3. 安装工具 (cloudflared & ttyd)
RUN curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
    && dpkg -i cloudflared.deb \
    && rm cloudflared.deb \
    && curl -L https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64 -o /usr/local/bin/ttyd \
    && chmod +x /usr/local/bin/ttyd \
    && curl -L https://github.com/aptible/supercronic/releases/download/v0.2.44/supercronic-linux-amd64 -o /usr/local/bin/sc \
    && chmod +x /usr/local/bin/sc

# 3c. 安装 sing-box 核心 (alpha 版本，支持原生 realm 打洞)
RUN curl -L https://github.com/SagerNet/sing-box/releases/download/v1.14.0-alpha.24/sing-box-1.14.0-alpha.24-linux-amd64.tar.gz \
        -o /tmp/sb.tar.gz \
    && tar -xzf /tmp/sb.tar.gz -C /tmp \
    && mv /tmp/sing-box-*/sing-box /usr/local/bin/sing-box \
    && rm -rf /tmp/sing-box-* /tmp/sb.tar.gz \
    && chmod 755 /usr/local/bin/sing-box
RUN curl -L https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64 \
        -o /usr/local/bin/hysteria \
    && chmod +x /usr/local/bin/hysteria

# 3c-2. 安装 EasyTier 核心 (异地组网: UDP 打洞 P2P, TCP/WS/WSS 兜底)
RUN curl -L https://github.com/EasyTier/EasyTier/releases/download/v2.6.4/easytier-linux-x86_64-v2.6.4.zip \
        -o /tmp/et.zip \
    && unzip -q /tmp/et.zip -d /tmp/et \
    && find /tmp/et -name 'easytier-core' -exec mv {} /usr/local/bin/ \; \
    && find /tmp/et -name 'easytier-cli'  -exec mv {} /usr/local/bin/ \; \
    && chmod +x /usr/local/bin/easytier-core /usr/local/bin/easytier-cli \
    && rm -rf /tmp/et /tmp/et.zip

# 3d. 安装 opencode CLI
RUN curl -fsSL https://opencode.ai/install.sh | bash

# 4. SSH 环境预处理
RUN mkdir -p /run/sshd && ssh-keygen -A \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
EXPOSE 7681

# 5. 配置文件与脚本处理
RUN mkdir -p /usr/local/etc

# 拷贝包含 {SSH_USER} 占位符的配置文件
COPY supervisord.conf /usr/local/etc/supervisord.conf.template

# 拷贝独立片段模板
COPY fragments /usr/local/etc/fragments

# 拷贝动态处理逻辑的启动脚本
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 移除系统默认配置，确保只走持久化卷里的配置
RUN rm -f /etc/supervisor/supervisord.conf

# 6. 运行身份
USER root

# 执行 entrypoint.sh 进行动态替换和权限修正
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
