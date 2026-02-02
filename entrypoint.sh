#!/usr/bin/env sh
set -e

# 1. 基础环境初始化
if ! id -u "$SSH_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$SSH_USER"
fi

# 同步密码（root 和自定义用户）
echo "root:$SSH_PWD" | chpasswd
echo "$SSH_USER:$SSH_PWD" | chpasswd
echo "$SSH_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/init-users

# 2. 硬核注入 sctl (比别名更稳，全系统即刻生效)
ln -sf /usr/bin/supervisorctl /usr/local/bin/sctl

# 3. 智能配置文件定位与初始化
BOOT_CONF="/home/zv/boot/supervisord.conf"
TEMPLATE="/usr/local/etc/supervisord.conf.template"

# 如果挂载了卷但没文件，自动从镜像模板初始化
if [ ! -f "$BOOT_CONF" ] && [ -f "$TEMPLATE" ]; then
    echo "检测到持久化目录为空，正在初始化满血版配置..."
    mkdir -p /home/zv/boot
    cp "$TEMPLATE" "$BOOT_CONF"
fi

# 确定最终使用的配置文件路径
# 优先使用持久化目录下的文件，否则退回系统默认路径
FINAL_CONF="/etc/supervisor/supervisord.conf"
[ -f "$BOOT_CONF" ] && FINAL_CONF="$BOOT_CONF"

# 4. 动态 CF 探测 (只有没 Token 时才在配置里屏蔽 cloudflare)
if [ -z "$CF_TOKEN" ] && [ -f "$FINAL_CONF" ]; then
    echo "未检测到 CF_TOKEN，正在配置中禁用 Cloudflare 进程..."
    # 屏蔽进程标题和启动命令
    sed -i '/\[program:cloudflare\]/s/^/;/' "$FINAL_CONF"
    sed -i '/command=cloudflared/s/^/;/' "$FINAL_CONF"
fi

# 5. 启动逻辑分流
if [ -n "$SSH_CMD" ]; then
    echo "检测到自定义启动指令: $SSH_CMD"
    # 使用 sh -c 运行以支持复杂的变量解析或多命令执行
    exec /bin/sh -c "$SSH_CMD"
else
    echo "按默认配置启动进程管理器..."
    exec /usr/bin/supervisord -n -c "$FINAL_CONF"
fi
