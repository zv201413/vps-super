FROM ubuntu:22.04

# 1. 基础环境设置
#    SSH_PWD 是镜像内置的默认口令。镜像公开, 故此值等同公开 ——
#    sshd 的 22 端口在 CF 上不对外路由(只有 $PORT 走公网), 所以实际暴露面有限;
#    但若给 22 配了 TCP Proxy, 就必须在部署时用环境变量覆盖掉它。
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    SSH_USER=zv \
    SSH_PWD=pwd123

# 2. 安装必要软件包
#    python3 是 supervisor 的依赖, 本来就会被拉进来; 这里显式写出, 因为
#    打洞脚本 (sweep.py / etaddr.py / punchd.sh 里的解析) 直接依赖它
RUN apt-get update && apt-get install -y \
    openssh-server supervisor python3 curl wget sudo ca-certificates openssl \
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

# 拷贝 UDP 打洞工具 (仅在设了 PUNCH 时才由 entrypoint 拉起, 平时不占资源)
#   etaddr.py —— STUN 自测本节点 UDP 出口 IP/映射端口, 供广播与 mapped-listeners
#   sweep.py  —— 全端口预授权扫射, 与 docker-ocr-mesh 里的同一份, 改动请两边同步
#   punchd.sh —— 守护: 缺 UDP 就做「停 ET → 扫射 → 起 ET」的授权接力
COPY etaddr.py sweep.py punchd.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/etaddr.py /usr/local/bin/sweep.py /usr/local/bin/punchd.sh

# 移除系统默认配置，确保只走持久化卷里的配置
RUN rm -f /etc/supervisor/supervisord.conf

# 6. 运行身份
USER root

# 执行 entrypoint.sh 进行动态替换和权限修正
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
