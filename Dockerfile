FROM ghcr.io/vevc/ubuntu:25.11.15

USER root

# 1. 安装基础工具
RUN apt-get update && apt-get install -y \
    supervisor \
    wget \
    curl \
    vim \
    unzip \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# 2. 默认环境变量
ENV SSH_USER=zv
ENV SSH_PASSWORD=105106

# 3. 配置全局别名 (参考维客工坊建议)
# 写入 /etc/bash.bashrc 确保所有用户登录都能直接使用 sctl
RUN echo "alias sctl='supervisorctl'" >> /etc/bash.bashrc && \
    echo "alias sstat='supervisorctl status'" >> /etc/bash.bashrc

# 4. 创建自定义启动脚本
RUN echo '#!/bin/bash\n\
USER_HOME="/home/${SSH_USER}"\n\
BOOT_DIR="${USER_HOME}/boot"\n\
mkdir -p ${BOOT_DIR}\n\
\n\
# 动态创建用户并设置密码\n\
id -u ${SSH_USER} &>/dev/null || useradd -m -s /bin/bash ${SSH_USER}\n\
echo "${SSH_USER}:${SSH_PASSWORD}" | chpasswd\n\
\n\
# 生成符合 supervisorctl 通讯要求的配置\n\
cat <<EOF > ${BOOT_DIR}/supervisord.conf\n\
[supervisord]\n\
nodaemon=true\n\
logfile=/tmp/supervisord.log\n\
pidfile=/tmp/supervisord.pid\n\
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
files = ${BOOT_DIR}/*.conf\n\
EOF\n\
\n\
# 权限修正\n\
chmod -R 777 ${USER_HOME}\n\
\n\
# 启动 SSH 服务\n\
mkdir -p /var/run/sshd\n\
/usr/sbin/sshd\n\
\n\
# 启动 Supervisor 主进程\n\
echo "Cloud VPS is starting..."\n\
exec supervisord -c ${BOOT_DIR}/supervisord.conf' > /entrypoint_custom.sh

RUN chmod +x /entrypoint_custom.sh

# 5. 暴露端口
EXPOSE 22 2222

# 指向接管入口
ENTRYPOINT ["/entrypoint_custom.sh"]
