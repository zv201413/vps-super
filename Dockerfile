FROM ghcr.io/vevc/ubuntu:25.11.15

USER root

# 1. 安装基础工具 + Cloudflared + Xray
RUN apt-get update && apt-get install -y \
    supervisor procps wget curl passwd sudo openssh-server unzip && \
    # 安装 Cloudflared
    curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb && \
    dpkg -i cloudflared.deb && rm cloudflared.deb && \
    # 安装 Xray 核心 (最新版)
    mkdir -p /usr/local/share/xray && \
    curl -L -o /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip && \
    unzip /tmp/xray.zip -d /usr/local/bin/ xray geosite.dat geoip.dat && \
    rm /tmp/xray.zip && \
    rm -rf /var/lib/apt/lists/*

# 2. 默认环境变量
ENV SSH_USER=zv
ENV SSH_PASSWORD=105106
ENV CF_TUNNEL_TOKEN=""

# 3. 别名与工具路径
RUN echo "alias sctl='supervisorctl -c /home/\${SSH_USER:-zv}/boot/supervisord.conf'" >> /etc/bash.bashrc

# 4. 入口脚本 (集成 Xray 配置生成)
RUN printf "#!/bin/bash\n\
export USER_HOME=\"/home/\${SSH_USER:-zv}\"\n\
export BOOT_DIR=\"\${USER_HOME}/boot\"\n\
mkdir -p \"\${BOOT_DIR}\" /var/run/sshd /var/log/supervisor /usr/local/etc/xray\n\
\n\
# 用户与权限配置\n\
if ! id \"\${SSH_USER}\" &>/dev/null; then useradd -m -s /bin/bash \"\${SSH_USER}\"; fi\n\
echo \"\${SSH_USER} ALL=(ALL:ALL) NOPASSWD: ALL\" >> /etc/sudoers\n\
echo \"\${SSH_USER}:\${SSH_PASSWORD}\" | chpasswd\n\
echo \"root:\${SSH_PASSWORD}\" | chpasswd\n\
ssh-keygen -A\n\
\n\
# 动态生成 Xray 配置 (集成 WARP 出站)\n\
printf \"{ \n\
  \\\"log\\\": {\\\"loglevel\\\": \\\"none\\\"}, \n\
  \\\"inbounds\\\": [{ \n\
    \\\"port\\\": 13457, \\\"protocol\\\": \\\"vmess\\\", \n\
    \\\"settings\\\": {\\\"clients\\\": [{\\\"id\\\": \\\"47e28d60-7c95-4400-912c-ae99a69700c1\\\"}]}, \n\
    \\\"streamSettings\\\": {\\\"network\\\": \\\"ws\\\", \\\"wsSettings\\\": {\\\"path\\\": \\\"/47e28d60-7c95-4400-912c-ae99a69700c1-vm\\\"}} \n\
  }], \n\
  \\\"outbounds\\\": [ \n\
    {\\\"protocol\\\": \\\"freedom\\\", \\\"tag\\\": \\\"direct\\\"}, \n\
    { \n\
      \\\"tag\\\": \\\"x-warp-out\\\", \\\"protocol\\\": \\\"wireguard\\\", \n\
      \\\"settings\\\": { \n\
        \\\"secretKey\\\": \\\"n6Qylf7mA98snl43oHOqvFyMBb/Jpv//zj+6ZJMhxrc=\\\", \n\
        \\\"address\\\": [\\\"172.16.0.2/32\\\", \\\"2606:4700:110:8a9e:cd99:bea6:27eb:5a51/128\\\"], \n\
        \\\"peers\\\": [{\\\"publicKey\\\": \\\"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyw=\\\", \\\"endpoint\\\": \\\"162.159.193.10:500\\\"}], \n\
        \\\"reserved\\\": [60, 220, 81], \\\"mtu\\\": 1280 \n\
      } \n\
    } \n\
  ], \n\
  \\\"routing\\\": { \n\
    \\\"rules\\\": [ \n\
      {\\\"type\\\": \\\"field\\\", \\\"outboundTag\\\": \\\"x-warp-out\\\", \\\"domain\\\": [\\\"geosite:openai\\\", \\\"domain:ip.gs\\\"]}, \n\
      {\\\"type\\\": \\\"field\\\", \\\"outboundTag\\\": \\\"direct\\\", \\\"network\\\": \\\"tcp,udp\\\"} \n\
    ] \n\
  } \n\
}\" > /usr/local/etc/xray/config.json\n\
\n\
# 动态生成 Supervisor 配置\n\
printf \"[supervisord]\nnodaemon=true\nuser=root\n\n\
[program:sshd]\ncommand=/usr/sbin/sshd -D\n\n\
[program:cloudflared]\ncommand=/usr/bin/cloudflared tunnel --no-autoupdate run --token \${CF_TUNNEL_TOKEN}\n\n\
[program:xray]\ncommand=/usr/local/bin/xray -c /usr/local/etc/xray/config.json\n\" > \"\${BOOT_DIR}/supervisord.conf\"\n\
\n\
exec /usr/bin/supervisord -c \"\${BOOT_DIR}/supervisord.conf\"\n" > /entrypoint.sh && chmod +x /entrypoint.sh

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
