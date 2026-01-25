# 基础镜像：继承 vevc 的 Ubuntu 模拟器
FROM ghcr.io/vevc/ubuntu:25.11.15

# 切换为 root 进行环境构建
USER root

# 1. 安装基础工具和 supervisor
RUN apt-get update && apt-get install -y \
    supervisor \
    wget \
    curl \
    vim \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# 2. 默认环境变量 (用户可通过 cf set-env 覆盖)
ENV SSH_USER=zv
ENV SSH_PASSWORD=105106

# 3. 动态入口脚本：实现 /home/用户名/boot 的逻辑
RUN echo '#!/bin/bash\n\
USER_HOME="/home/${SSH_USER}"\n\
BOOT_DIR="${USER_HOME}/boot"\n\
mkdir -p ${BOOT_DIR}\n\
\n\
# 生成默认配置 (如果不存在)\n\
IF_CONF="${BOOT_DIR}/supervisord.conf"\n\
if [ ! -f "$IF_CONF" ]; then\n\
  echo -e "[supervisord]\\nnodaemon=true\\nlogfile=/tmp/supervisord.log\\npidfile=/tmp/supervisord.pid\\n" > "$IF_CONF"\n\
  echo -e "[unix_http_server]\\nfile=/tmp/supervisor.sock\\n" >> "$IF_CONF"\n\
  echo -e "[rpcinterface:supervisor]\\nsupervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface\\n" >> "$IF_CONF"\n\
  echo -e "[supervisorctl]\\nserverurl=unix:///tmp/supervisor.sock" >> "$IF_CONF"\n\
fi\n\
\n\
# 赋予权限\n\
chmod -R 777 ${USER_HOME}\n\
\n\
# 设置启动命令并交给原有入口执行\n\
export START_CMD="supervisord -c ${BOOT_DIR}/supervisord.conf"\n\
exec /usr/local/bin/entrypoint.sh' > /entrypoint_custom.sh

RUN chmod +x /entrypoint_custom.sh

# 4. 只暴露 SSH 端口
EXPOSE 22 2222

# 指向自定义入口
ENTRYPOINT ["/entrypoint_custom.sh"]
